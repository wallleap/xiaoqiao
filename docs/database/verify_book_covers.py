"""V10 tests; disposable in-memory databases only, never device data."""
import sqlite3
import re
import json
from pathlib import Path
import verify_schema as schema_tests
import unittest
from verify_account_details import AccountDetailsTests, statements


class BookCoverTests(unittest.TestCase):
    def setUp(self):
        fixture = AccountDetailsTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        fixture.migrate()
        self.db = fixture.db

    def migrate(self):
        for sql in statements('BookCoverSchema.ets'):
            self.db.execute(sql)

    def test_migration_preserves_books_balances_accounts_and_history(self):
        old = [r[1] for r in self.db.execute('PRAGMA table_info(books)')]
        query = 'SELECT ' + ','.join(old) + ' FROM books ORDER BY id'
        before = self.db.execute(query).fetchall()
        money = self.db.execute('SELECT * FROM v_effective_movements ORDER BY id').fetchall()
        accounts = self.db.execute('SELECT * FROM accounts ORDER BY id').fetchall()
        self.db.execute('BEGIN')
        self.migrate()
        self.db.execute('COMMIT')
        self.assertEqual(before, self.db.execute(query).fetchall())
        self.assertEqual(money, self.db.execute('SELECT * FROM v_effective_movements ORDER BY id').fetchall())
        self.assertEqual(accounts, self.db.execute('SELECT * FROM accounts ORDER BY id').fetchall())
        self.assertEqual([], self.db.execute('PRAGMA foreign_key_check').fetchall())
        self.assertEqual('ok', self.db.execute('PRAGMA quick_check').fetchone()[0])
        self.assertEqual([('butter', 'lucide_notebook_text1')], self.db.execute('SELECT DISTINCT cover_palette,cover_icon FROM books').fetchall())

    def test_rollback_removes_new_columns(self):
        self.db.execute('BEGIN')
        self.migrate()
        self.db.execute('ROLLBACK')
        self.assertNotIn('cover_palette', [r[1] for r in self.db.execute('PRAGMA table_info(books)')])

    def test_invalid_keys_rejected(self):
        self.migrate()
        for column, value in [('cover_palette','unknown'), ('cover_icon','file://private'), ('cover_icon','lucide_../../bad')]:
            with self.assertRaises(sqlite3.IntegrityError):
                self.db.execute(f'UPDATE books SET {column}=?', (value,))

    def test_styles_survive_full_database_backup(self):
        self.migrate()
        self.db.execute("UPDATE books SET cover_palette='lagoon',cover_icon='lucide_plane1',revision=revision+1")
        target = sqlite3.connect(':memory:')
        self.addCleanup(target.close)
        self.db.backup(target)
        self.assertEqual(self.db.execute('SELECT * FROM books ORDER BY id').fetchall(), target.execute('SELECT * FROM books ORDER BY id').fetchall())
        self.assertEqual(self.db.execute('SELECT * FROM v_effective_movements ORDER BY id').fetchall(), target.execute('SELECT * FROM v_effective_movements ORDER BY id').fetchall())

    def test_production_book_counts_include_only_effective_transactions(self):
        self.migrate()
        helper = schema_tests.SchemaTests()
        helper.db = self.db
        helper.expense(id='count-expense')
        helper.tx(id='count-draft')
        helper.tx(id='count-income', kind='income', category_id='b1income', include_in_budget=0)
        helper.move(id='count-income-m', tx='count-income', leg='income', delta=2800)
        helper.post('count-income')
        helper.tx(id='count-transfer', kind='transfer', category_id=None, include_in_budget=0)
        helper.move(id='count-out', tx='count-transfer', leg='transfer_out', delta=-2800)
        helper.move(id='count-in', tx='count-transfer', account='bank', leg='transfer_in', delta=2800)
        helper.post('count-transfer')
        source = (Path(__file__).resolve().parents[2] / 'entry/src/main/ets/data/rdb/LedgerWorkspace.ets').read_text()
        body = source.split('async books():', 1)[1].split('async selectBook', 1)[0]
        parts = re.search(r'db.querySql\("([^"\n]+)" \+ LEDGER_USAGE_ROWS_SQL \+ "([^"\n]+)"\)', body)
        usage_source = (Path(__file__).resolve().parents[2] / 'entry/src/main/ets/data/rdb/LedgerUsageQuery.ets').read_text()
        usage_sql = json.loads(usage_source.split('string = ', 1)[1].strip().rstrip(';'))
        sql = parts.group(1) + usage_sql + parts.group(2)
        result = {row[0]: row[6] for row in self.db.execute(sql)}
        self.assertEqual({'b1': '3', 'b2': '0'}, result)
        self.db.execute("UPDATE transactions SET deleted_at_ms=99 WHERE id='count-expense'")
        result = {row[0]: row[6] for row in self.db.execute(sql)}
        self.assertEqual('2', result['b1'])
        self.db.execute("UPDATE books SET archived_at_ms=99 WHERE id='b1'")
        self.assertEqual('2', {row[0]: row[6] for row in self.db.execute(sql)}['b1'])

    def test_personal_total_equals_sum_of_book_counts_with_prepayments(self):
        self.migrate()
        helper = schema_tests.SchemaTests()
        helper.db = self.db
        helper.expense(id='unified-expense')
        for project, book, date in [('p1','b1','2025-01-01'),('p2','b2','2024-01-01')]:
            helper.put('prepaid_projects', id=project, book_id=book, name=project, currency_id='CNY', created_at_ms=1, updated_at_ms=1)
            helper.put('prepaid_events', id=project+'fund', project_id=project, sequence_no=1, kind='fund', amount_minor=100,
                       book_minor=100, account_id='cash', account_currency_id='CNY', cash_minor=100, cash_book_minor=100,
                       local_date=date, occurred_at_ms=1, offset_minutes=480, created_at_ms=1)
            self.db.execute("UPDATE prepaid_events SET posting_state='posted' WHERE id=?", (project+'fund',))
        helper.put('prepaid_events', id='p1refund', project_id='p1', sequence_no=2, kind='refund', amount_minor=20,
                   book_minor=20, account_id='cash', account_currency_id='CNY', cash_minor=20, cash_book_minor=20,
                   local_date='2025-02-01', occurred_at_ms=2, offset_minutes=480, created_at_ms=2)
        helper.put('prepaid_allocations', event_id='p1refund', fund_id='p1fund', amount_minor=20, book_minor=20)
        self.db.execute("UPDATE prepaid_events SET posting_state='posted' WHERE id='p1refund'")
        helper.put('prepaid_events', id='draft-fund', project_id='p1', sequence_no=3, kind='fund', amount_minor=10,
                   book_minor=10, account_id='cash', account_currency_id='CNY', cash_minor=10, cash_book_minor=10,
                   local_date='2023-01-01', occurred_at_ms=3, offset_minutes=480, created_at_ms=3)
        folder = Path(__file__).resolve().parents[2] / 'entry/src/main/ets/data/rdb'
        usage_sql = json.loads((folder/'LedgerUsageQuery.ets').read_text().split('string = ',1)[1].strip().rstrip(';'))
        source = (folder/'LedgerWorkspace.ets').read_text()
        body = source.split('async books():',1)[1].split('async selectBook',1)[0]
        parts = re.search(r'db.querySql\("([^"\n]+)" \+ LEDGER_USAGE_ROWS_SQL \+ "([^"\n]+)"\)',body)
        books_sql = parts.group(1)+usage_sql+parts.group(2)
        total_sql = "SELECT MIN(local_day),COUNT(*) FROM ("+usage_sql+")"
        def check(expected, first):
            counts = {r[0]:int(r[6]) for r in self.db.execute(books_sql)}
            summary = self.db.execute(total_sql).fetchone()
            self.assertEqual(expected, summary[1])
            self.assertEqual(sum(counts.values()), summary[1])
            self.assertEqual(first, summary[0])
        check(4,'2024-01-01')
        self.db.execute("UPDATE books SET archived_at_ms=9 WHERE id='b2'")
        check(4,'2024-01-01')
        self.db.execute("UPDATE books SET deleted_at_ms=10 WHERE id='b2'")
        check(3,'2025-01-01')

    def test_legacy_backup_can_upgrade_to_current_schema(self):
        legacy = sqlite3.connect(':memory:', isolation_level=None)
        self.addCleanup(legacy.close)
        self.db.backup(legacy)
        self.migrate()
        for sql in statements('BookCoverSchema.ets'):
            legacy.execute(sql)
        schema = "SELECT name,sql FROM sqlite_master WHERE type IN ('table','view','trigger') ORDER BY name"
        self.assertEqual(self.db.execute(schema).fetchall(), legacy.execute(schema).fetchall())


if __name__ == '__main__':
    unittest.main()
