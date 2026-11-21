"""V11 migration checks on temporary/in-memory SQLite only. Never opens device data."""
import sqlite3
import unittest
import verify_book_covers as covers
from verify_account_details import statements
import verify_schema

class BookSettingsTests(unittest.TestCase):
    def setUp(self):
        fixture = covers.BookCoverTests(); fixture.setUp(); fixture.migrate()
        self.addCleanup(fixture.doCleanups); self.db = fixture.db
        self.helper = verify_schema.SchemaTests(); self.helper.db = self.db

    def migrate(self):
        for sql in statements('BookSettingsSchema.ets'): self.db.execute(sql)

    def test_defaults_preserve_all_history_and_balances(self):
        tables = ['books','transactions','account_movements','accounts','budgets','prepaid_events','fx_snapshots']
        before = {t:list(self.db.execute('SELECT * FROM '+t)) for t in tables}
        self.db.execute('BEGIN'); self.migrate(); self.db.execute('COMMIT')
        for t in tables:
            after = list(self.db.execute('SELECT * FROM '+t))
            if t == 'books': after = [r[:-1] for r in after]
            self.assertEqual(before[t], after)
        self.assertEqual([(1,)], list(self.db.execute('SELECT DISTINCT month_start_day FROM books')))
        self.assertEqual([], list(self.db.execute('PRAGMA foreign_key_check')))
        self.assertEqual(('ok',), self.db.execute('PRAGMA quick_check').fetchone())

    def test_rollback_and_backup_restore(self):
        backup = sqlite3.connect(':memory:'); self.addCleanup(backup.close); self.db.backup(backup)
        self.db.execute('BEGIN'); self.migrate()
        with self.assertRaises(sqlite3.IntegrityError): self.db.execute('UPDATE books SET month_start_day=32')
        self.db.execute('ROLLBACK')
        self.assertNotIn('month_start_day', [r[1] for r in self.db.execute('PRAGMA table_info(books)')])
        self.migrate(); self.db.execute("UPDATE books SET month_start_day=31,base_currency_id='USD' WHERE id='b2'")
        current = sqlite3.connect(':memory:'); self.addCleanup(current.close); self.db.backup(current)
        backup.backup(self.db); self.migrate(); current.backup(self.db)
        self.assertEqual(('USD',31),self.db.execute("SELECT base_currency_id,month_start_day FROM books WHERE id='b2'").fetchone())

    def test_currency_lock_transactions_budgets_and_prepaid(self):
        self.migrate(); self.db.execute("UPDATE books SET base_currency_id='USD' WHERE id='b2'")
        self.helper.tx(id='usd-t', book_id='b2', category_id='b2expense', currency_id='USD', book_currency_id='USD')
        with self.assertRaisesRegex(sqlite3.IntegrityError,'book currency is in use'):
            self.db.execute("UPDATE books SET base_currency_id='CNY' WHERE id='b2'")
        self.helper.put('prepaid_projects', id='p',book_id='b1',name='P',currency_id='CNY',created_at_ms=1,updated_at_ms=1)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'book currency is in use'):
            self.db.execute("UPDATE books SET base_currency_id='USD' WHERE id='b1'")
        self.db.execute("UPDATE books SET month_start_day=25 WHERE id='b1'")

    def test_budget_dates_and_amounts_are_not_moved(self):
        self.helper.put('budgets',id='budget',book_id='b1',currency_id='CNY',period_start_date='2026-11-01',period_end_date_exclusive='2026-12-01',total_minor=12345,created_at_ms=1,updated_at_ms=1)
        self.migrate(); self.db.execute("UPDATE books SET month_start_day=25 WHERE id='b1'")
        self.assertEqual(('2026-11-01','2026-12-01',12345),self.db.execute('SELECT period_start_date,period_end_date_exclusive,total_minor FROM budgets').fetchone())
        with self.assertRaisesRegex(sqlite3.IntegrityError,'book currency is in use'):
            self.db.execute("UPDATE books SET base_currency_id='USD' WHERE id='b1'")

    def test_usd_prepaid_consumption(self):
        self.migrate(); self.db.execute("UPDATE books SET base_currency_id='USD' WHERE id='b2'")
        h=self.helper
        h.put('prepaid_projects',id='p',book_id='b2',name='P',currency_id='USD',created_at_ms=1,updated_at_ms=1)
        h.put('prepaid_events',id='fund',project_id='p',sequence_no=1,kind='fund',amount_minor=1000,book_minor=1000,account_id='usd',account_currency_id='USD',cash_minor=1000,cash_book_minor=1000,local_date='2026-11-25',occurred_at_ms=1,offset_minutes=0,created_at_ms=1)
        self.db.execute("UPDATE prepaid_events SET posting_state='posted' WHERE id='fund'")
        h.tx(id='consume-t',book_id='b2',category_id='b2expense',currency_id='USD',book_currency_id='USD',gross_minor=300,paid_minor=300,book_minor=300,include_in_assets=0)
        self.db.execute("UPDATE transactions SET posting_state='posted' WHERE id='consume-t'")
        h.put('prepaid_events',id='consume',project_id='p',sequence_no=2,kind='consume',amount_minor=300,book_minor=300,account_currency_id='USD',transaction_id='consume-t',local_date='2026-11-25',occurred_at_ms=1,offset_minutes=0,created_at_ms=1)
        h.put('prepaid_allocations',event_id='consume',fund_id='fund',amount_minor=300,book_minor=300)
        self.db.execute("UPDATE prepaid_events SET posting_state='posted' WHERE id='consume'")
        self.assertEqual((700,700),self.db.execute("SELECT remaining_minor,remaining_book_minor FROM v_prepaid_balances WHERE id='p'").fetchone())

if __name__ == '__main__': unittest.main()
