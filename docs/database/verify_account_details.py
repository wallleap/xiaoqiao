"""V9 regression checks using disposable in-memory databases only."""
from pathlib import Path
import json
import sqlite3
import unittest
import verify_schema as schema_tests

ROOT = Path(__file__).resolve().parents[2]


def statements(name):
    text = (ROOT / 'entry/src/main/ets/data/rdb' / name).read_text()
    return json.loads(text.split('STATEMENTS: string[] = ', 1)[1].strip().rstrip(';'))


class AccountDetailsTests(unittest.TestCase):
    def setUp(self):
        fixture = schema_tests.SchemaTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.db = fixture.db
        self.db.execute("UPDATE accounts SET icon_key='cash' WHERE id='cash'")
        self.db.execute("UPDATE accounts SET icon_key='credit_card' WHERE id='credit'")
        fixture.adjust(id='opening-a', account='cash', after=12345)
        fixture.adjust(id='opening-c', account='credit', after=-4321)
        for schema in ['TransferSchema.ets', 'SpendingNatureSchema.ets', 'BudgetNatureSchema.ets',
                       'RecoverySchema.ets', 'NatureColorSchema.ets', 'MulticurrencySchema.ets', 'PrepaidSchema.ets']:
            for sql in statements(schema):
                self.db.execute(sql)

    def migrate(self):
        for sql in statements('AccountDetailsSchema.ets'):
            self.db.execute(sql)

    def test_preserves_legacy_accounts_and_all_money(self):
        columns = [r[1] for r in self.db.execute('PRAGMA table_info(accounts)')]
        query = 'SELECT ' + ','.join(columns) + ' FROM accounts ORDER BY id'
        before = self.db.execute(query).fetchall()
        balances = self.db.execute('SELECT * FROM v_effective_movements ORDER BY id').fetchall()
        self.db.execute('BEGIN')
        self.migrate()
        self.db.execute('COMMIT')
        self.assertEqual(before, self.db.execute(query).fetchall())
        self.assertEqual(balances, self.db.execute('SELECT * FROM v_effective_movements ORDER BY id').fetchall())
        self.assertEqual('cash', self.db.execute("SELECT account_type FROM accounts WHERE id='cash'").fetchone()[0])
        self.assertEqual('credit_card', self.db.execute("SELECT account_type FROM accounts WHERE id='credit'").fetchone()[0])
        self.assertEqual('other_asset', self.db.execute("SELECT account_type FROM accounts WHERE id='bank'").fetchone()[0])
        self.assertEqual([], self.db.execute('PRAGMA foreign_key_check').fetchall())
        self.assertEqual('ok', self.db.execute('PRAGMA quick_check').fetchone()[0])

    def test_rollback_removes_partial_metadata_columns(self):
        before = self.db.execute('PRAGMA table_info(accounts)').fetchall()
        self.db.execute('BEGIN')
        self.migrate()
        self.db.execute('ROLLBACK')
        self.assertEqual(before, self.db.execute('PRAGMA table_info(accounts)').fetchall())

    def test_recognized_bank_and_credit_products_keep_issuer(self):
        self.db.execute("UPDATE accounts SET icon_key='icbk_color' WHERE id='bank'")
        self.db.execute("UPDATE accounts SET icon_key='huabei_color' WHERE id='credit'")
        self.migrate()
        self.assertEqual(('debit_card', 'icbk'), self.db.execute("SELECT account_type,issuer_key FROM accounts WHERE id='bank'").fetchone())
        self.assertEqual(('huabei', ''), self.db.execute("SELECT account_type,issuer_key FROM accounts WHERE id='credit'").fetchone())

    def test_metadata_constraints_and_backup_round_trip(self):
        self.migrate()
        self.db.execute("UPDATE accounts SET account_type='debit_card',issuer_key='icbk',card_tail='1234',note='工资卡' WHERE id='bank'")
        for invalid in ['123', '12345', '12a4', '１２３４']:
            with self.assertRaises(sqlite3.IntegrityError):
                self.db.execute("UPDATE accounts SET card_tail=? WHERE id='bank'", (invalid,))
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE accounts SET note=? WHERE id='bank'", ('a' * 501,))
        copy = sqlite3.connect(':memory:')
        self.addCleanup(copy.close)
        self.db.backup(copy)
        row = copy.execute("SELECT account_type,issuer_key,card_tail,note FROM accounts WHERE id='bank'").fetchone()
        self.assertEqual(('debit_card', 'icbk', '1234', '工资卡'), row)

    def test_edit_type_keeps_identity_name_currency_and_movements(self):
        self.migrate()
        before = self.db.execute("SELECT id,name,kind,currency_id FROM accounts WHERE id='cash'").fetchone()
        movements = self.db.execute('SELECT * FROM v_effective_movements ORDER BY id').fetchall()
        self.db.execute("UPDATE accounts SET account_type='debit_card',issuer_key='icbk',card_tail='1234',note='工资卡',revision=revision+1 WHERE id='cash' AND kind='asset' AND currency_id='CNY' AND revision=1")
        self.assertEqual(before, self.db.execute("SELECT id,name,kind,currency_id FROM accounts WHERE id='cash'").fetchone())
        self.assertEqual(movements, self.db.execute('SELECT * FROM v_effective_movements ORDER BY id').fetchall())
        self.assertEqual(('debit_card', 'icbk', '1234', '工资卡', 2), self.db.execute("SELECT account_type,issuer_key,card_tail,note,revision FROM accounts WHERE id='cash'").fetchone())


if __name__ == '__main__':
    unittest.main()
