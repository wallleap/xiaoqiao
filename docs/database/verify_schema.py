"""Executable design checks. Uses only sqlite3 :memory:, never an application DB."""
from pathlib import Path
import sqlite3
import unittest

DDL = Path(__file__).with_name('schema-v1.sql').read_text()


class SchemaTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:', isolation_level=None)
        self.addCleanup(self.db.close)
        self.db.executescript(DDL)
        for code, unit in [('CNY', 2), ('USD', 2), ('JPY', 0), ('KWD', 3)]:
            self.put('currencies', id=code, code=code, name=code, symbol=code,
                     minor_unit=unit, valid_from='2026-01-01', source_version='TEST FIXTURE')
        for book in ['b1', 'b2']:
            self.put('books', id=book, name=book, base_currency_id='CNY', timezone='Asia/Shanghai',
                     created_at_ms=1, updated_at_ms=1)
            for kind in ['expense', 'income']:
                self.category(book + kind, book=book, kind=kind)
        for account, currency, kind in [('cash', 'CNY', 'asset'), ('bank', 'CNY', 'asset'),
                                        ('usd', 'USD', 'asset'), ('credit', 'CNY', 'liability')]:
            self.put('accounts', id=account, name=account, kind=kind, currency_id=currency,
                     created_at_ms=1, updated_at_ms=1)

    def put(self, table, **values):
        # Table/column identifiers below are fixed test code, never file/user input.
        self.db.execute(f'INSERT INTO {table} ({",".join(values)}) VALUES ({",".join("?" for _ in values)})',
                        tuple(values.values()))

    def category(self, id, book='b1', kind='expense', parent=None, name=None):
        self.put('categories', id=id, book_id=book, kind=kind, parent_id=parent,
                 name=name or id, name_key=name or id, created_at_ms=1, updated_at_ms=1)

    def tx(self, id='t', **overrides):
        v = dict(id=id, book_id='b1', kind='expense', category_id='b1expense', currency_id='CNY',
                 gross_minor=2800, discount_minor=0, paid_minor=2800, book_currency_id='CNY', book_minor=2800,
                 include_in_budget=1, occurred_at_ms=1790830800000, occurred_local_date='2026-10-01',
                 occurred_timezone='Asia/Shanghai', occurred_offset_minutes=480, created_at_ms=1, updated_at_ms=1)
        v.update(overrides)
        self.put('transactions', **v)

    def move(self, id='m', tx='t', account='cash', currency='CNY', delta=-2800, leg='expense', adjustment=None, occurred_at_ms=None):
        if occurred_at_ms is None:
            table, source = ('transactions', tx) if tx else ('balance_adjustments', adjustment)
            occurred_at_ms = self.db.execute(f'SELECT occurred_at_ms FROM {table} WHERE id=?', (source,)).fetchone()[0]
        self.put('account_movements', id=id, transaction_id=tx, adjustment_id=adjustment,
                 account_id=account, currency_id=currency, delta_minor=delta, leg=leg, occurred_at_ms=occurred_at_ms)

    def post(self, tx='t'):
        self.db.execute("UPDATE transactions SET posting_state='posted' WHERE id=?", (tx,))

    def expense(self, id='t', account='cash', **values):
        self.tx(id, **values)
        if account is not None:
            self.move(id + 'm', tx=id, account=account, delta=-values.get('paid_minor', 2800))
        self.post(id)

    def adjust(self, id='a', account='cash', before=0, after=1000000, kind='opening', publish=True, **values):
        self.put('balance_adjustments', id=id, account_id=account, kind=kind, before_minor=before,
                 after_minor=after, delta_minor=after-before, reason='TEST', occurred_at_ms=1,
                 created_at_ms=1, **values)
        currency = self.db.execute('SELECT currency_id FROM accounts WHERE id=?', (account,)).fetchone()[0]
        self.move(id+'m', tx=None, account=account, currency=currency, delta=after-before,
                  leg='adjustment', adjustment=id)
        if publish:
            self.db.execute("UPDATE balance_adjustments SET posting_state='posted' WHERE id=?", (id,))

    def balance(self, account='cash'):
        return self.db.execute('SELECT balance_minor FROM v_account_balances WHERE account_id=?', (account,)).fetchone()[0]

    def fx(self, id, tx='t', role='book', movement=None, src='USD', dst='CNY', from_minor=10000,
           to_minor=71980, rate='7.198', **values):
        self.put('fx_snapshots', id=id, transaction_id=tx, role=role, account_movement_id=movement,
                 from_currency_id=src, to_currency_id=dst, from_minor=from_minor, to_minor=to_minor,
                 rate_decimal=rate, rate_source='TEST ACTUAL', rate_time_ms=1, rounding_mode='ACTUAL',
                 calculation_version=1, **values)

    def batch(self, id='batch', mode='preserve', duplicate=False):
        self.put('import_batches', id=id, book_id='b1', file_sha256='TEST', file_name='TEST.csv',
                 header_row=1, profile_snapshot_json='{}', balance_mode=mode, status='validated',
                 total_count=1, selected_count=1, skipped_count=0, confirmed_at_ms=1, created_at_ms=1)
        self.put('import_rows', id=id+'row', batch_id=id, row_number=1, raw_json='{}',
                 validation_status='duplicate' if duplicate else 'valid', selected=1)

    def imported(self, id='t', batch='batch', mode='preserve', **values):
        self.expense(id, import_batch_id=batch, import_row_id=batch+'row', balance_mode=mode, **values)

    def commit_batch(self, id='batch'):
        self.db.execute("UPDATE import_batches SET status='committed',committed_at_ms=2 WHERE id=?", (id,))

    def budget(self):
        self.put('budgets', id='budget', book_id='b1', currency_id='CNY', period_start_date='2026-10-01',
                 period_end_date_exclusive='2026-11-01', total_minor=300000, created_at_ms=1, updated_at_ms=1)

    def test_schema_foreign_keys(self):
        self.assertEqual(self.db.execute('PRAGMA foreign_keys').fetchone()[0], 1)
        self.assertEqual(self.db.execute('PRAGMA foreign_key_check').fetchall(), [])

    def test_global_account_across_books(self):
        self.adjust()
        self.expense('t1')
        self.expense('t2', book_id='b2', category_id='b2expense')
        self.assertEqual(self.balance(), 994400)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM v_book_totals').fetchone()[0], 2)

    def test_discount_paid_amount_only_once(self):
        self.adjust()
        self.expense(gross_minor=3000, discount_minor=200)
        self.assertEqual(self.balance(), 997200)
        self.assertEqual(self.db.execute('SELECT expense_minor FROM v_book_totals').fetchone()[0], 2800)

    def test_bad_discount_equation(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.tx(gross_minor=3000, discount_minor=200, paid_minor=3000)

    def test_float_and_out_of_safe_range_rejected(self):
        for value in [28.5, '28.50', 9007199254740992, 0, -1]:
            with self.subTest(value=value), self.assertRaises(sqlite3.IntegrityError):
                self.tx(str(value), gross_minor=value, paid_minor=value, book_minor=value)

    def test_income_sign(self):
        self.tx(kind='income', category_id='b1income', include_in_budget=0)
        self.move(delta=2800, leg='income')
        self.post()
        self.assertEqual(self.balance(), 2800)
        self.assertEqual(self.db.execute('SELECT income_minor FROM v_book_totals').fetchone()[0], 2800)

    def test_income_cannot_consume_budget(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.tx(kind='income', category_id='b1income', include_in_budget=1)

    def test_no_account_expense_still_in_statistics(self):
        self.expense(account=None)
        self.assertEqual(self.balance(), 0)
        self.assertEqual(self.db.execute('SELECT expense_minor FROM v_book_totals').fetchone()[0], 2800)

    def test_assets_off_budget_on(self):
        self.budget()
        self.expense(include_in_assets=0)
        self.assertEqual(self.balance(), 0)
        self.assertEqual(self.db.execute('SELECT used_minor FROM v_budget_usage').fetchone()[0], 2800)

    def test_budget_off_assets_on(self):
        self.adjust()
        self.budget()
        self.expense(include_in_budget=0)
        self.assertEqual(self.balance(), 997200)
        self.assertEqual(self.db.execute('SELECT used_minor FROM v_budget_usage').fetchone()[0], 0)

    def test_pending_reimbursement_does_not_create_income(self):
        self.expense(reimbursement_status='pending')
        self.assertEqual(self.db.execute('SELECT expense_minor,income_minor FROM v_book_totals').fetchone(), (2800, 0))

    def test_same_currency_transfer_not_income_or_expense(self):
        self.adjust()
        self.tx(kind='transfer', category_id=None, include_in_budget=0, gross_minor=10000, paid_minor=10000, book_minor=10000)
        self.move('out', delta=-10000, leg='transfer_out')
        self.move('in', account='bank', delta=10000, leg='transfer_in')
        self.post()
        self.assertEqual((self.balance(), self.balance('bank')), (990000, 10000))
        self.assertEqual(self.db.execute('SELECT expense_minor,income_minor FROM v_book_totals').fetchone(), (0, 0))

    def test_transfer_one_side_rejected(self):
        self.tx(kind='transfer', category_id=None, include_in_budget=0)
        self.move(leg='transfer_out')
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'incomplete transfer'):
            self.post()

    def test_transfer_same_account_rejected(self):
        self.tx(kind='transfer', category_id=None, include_in_budget=0)
        self.move('out', leg='transfer_out')
        self.move('in', delta=2800, leg='transfer_in')
        with self.assertRaises(sqlite3.IntegrityError):
            self.post()

    def test_same_currency_transfer_mismatch_rejected(self):
        self.tx(kind='transfer', category_id=None, include_in_budget=0)
        self.move('out', leg='transfer_out')
        self.move('in', account='bank', delta=2700, leg='transfer_in')
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'same currency settlement'):
            self.post()

    def test_cross_currency_transfer_and_fee(self):
        self.adjust('open-usd', account='usd', after=100000)
        self.tx(kind='transfer', category_id=None, include_in_budget=0, currency_id='USD',
                gross_minor=10000, paid_minor=10000, book_minor=71980, group_id='g')
        self.move('out', account='usd', currency='USD', delta=-10000, leg='transfer_out')
        self.move('in', delta=71980, leg='transfer_in')
        self.fx('base')
        self.fx('settle', role='settlement', movement='in')
        self.post()
        self.tx('fee', gross_minor=720, paid_minor=720, book_minor=720, group_id='g')
        self.move('fee-m', tx='fee', delta=-720)
        self.post('fee')
        self.assertEqual(self.balance('usd'), 90000)
        self.assertEqual(self.balance(), 71260)
        self.assertEqual(self.db.execute('SELECT expense_minor,income_minor FROM v_book_totals').fetchone(), (720, 0))

    def test_transfer_does_not_require_unused_book_currency_quote(self):
        self.put('accounts', id='jpy', name='JPY cash', kind='asset', currency_id='JPY', created_at_ms=1, updated_at_ms=1)
        self.tx(kind='transfer', category_id=None, include_in_budget=0, currency_id='USD',
                gross_minor=10000, paid_minor=10000, book_minor=None)
        self.move('out', account='usd', currency='USD', delta=-10000, leg='transfer_out')
        self.move('in', account='jpy', currency='JPY', delta=15000, leg='transfer_in')
        self.fx('settle', role='settlement', movement='in', dst='JPY', to_minor=15000, rate='150')
        self.post()
        self.assertEqual(self.balance('jpy'), 15000)
        self.assertEqual(self.balance('usd'), -10000)
        self.assertEqual(self.db.execute('SELECT expense_minor,income_minor FROM v_book_totals').fetchone(), (0, 0))

    def test_foreign_expense_requires_both_fx_roles(self):
        self.tx(currency_id='USD', gross_minor=10000, paid_minor=10000, book_minor=71980)
        self.move(delta=-71980)
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'book FX'):
            self.post()
        self.fx('book')
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'settlement FX'):
            self.post()
        self.fx('settle', role='settlement', movement='m')
        self.post()
        self.assertEqual(self.balance(), -71980)

    def test_movement_currency_must_match_account(self):
        self.tx()
        with self.assertRaises(sqlite3.IntegrityError):
            self.move(currency='USD')

    def test_wrong_snapshot_amount_rejected(self):
        self.tx(currency_id='USD', gross_minor=10000, paid_minor=10000, book_minor=71980)
        self.fx('bad', to_minor=72000)
        with self.assertRaises(sqlite3.IntegrityError):
            self.post()

    def test_snapshot_cannot_reference_other_transaction_leg(self):
        self.tx('t1')
        self.move('m1', tx='t1')
        self.tx('t2', currency_id='USD', gross_minor=10000, paid_minor=10000, book_minor=71980)
        with self.assertRaises(sqlite3.IntegrityError):
            self.fx('f', tx='t2', role='settlement', movement='m1')

    def test_quotes_do_not_change_old_amount(self):
        self.tx(currency_id='USD', gross_minor=10000, paid_minor=10000, book_minor=71980)
        self.fx('book')
        self.post()
        for id, rate in [('q1', '7.198'), ('q2', '7.3')]:
            self.put('fx_quotes', id=id, from_currency_id='USD', to_currency_id='CNY', rate_decimal=rate,
                     provider='TEST', quoted_at_ms=1, fetched_at_ms=1)
        self.assertEqual(self.db.execute('SELECT expense_minor FROM v_book_totals').fetchone()[0], 71980)
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE fx_snapshots SET to_minor=73000 WHERE id='book'")

    def test_fx_rates_are_positive_decimal_text(self):
        for id, rate in enumerate(['0', '-1', 'NaN', '1e2', '.5', '1.', '1.2.3']):
            with self.subTest(rate=rate), self.assertRaises(sqlite3.IntegrityError):
                self.put('fx_quotes', id=str(id), from_currency_id='USD', to_currency_id='CNY',
                         rate_decimal=rate, provider='TEST', quoted_at_ms=1, fetched_at_ms=1)

    def test_currency_definition_not_mutable(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE currencies SET minor_unit=3 WHERE id='CNY'")

    def test_account_currency_and_kind_locked_after_use(self):
        self.expense()
        for field, value in [('currency_id', 'USD'), ('kind', 'liability')]:
            with self.subTest(field=field), self.assertRaises(sqlite3.IntegrityError):
                self.db.execute(f'UPDATE accounts SET {field}=? WHERE id=?', (value, 'cash'))

    def test_book_currency_and_budget_currency_locked(self):
        self.budget()
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE books SET base_currency_id='USD' WHERE id='b1'")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE budgets SET currency_id='USD' WHERE id='budget'")

    def test_parent_and_deep_category_both_selectable(self):
        self.category('child', parent='b1expense')
        self.category('grandchild', parent='child')
        self.expense('parent')
        self.expense('leaf', category_id='grandchild')
        self.assertEqual(self.db.execute("SELECT depth FROM category_closure WHERE ancestor_id='b1expense' AND descendant_id='grandchild'").fetchone()[0], 2)
        self.assertEqual(self.db.execute('SELECT expense_minor FROM v_book_totals').fetchone()[0], 5600)

    def test_category_cycle_rejected(self):
        self.category('child', parent='b1expense')
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'cycle'):
            self.db.execute("UPDATE categories SET parent_id='child' WHERE id='b1expense'")

    def test_category_cross_book_and_cross_kind_rejected(self):
        for book, kind in [('b2', 'expense'), ('b1', 'income')]:
            with self.subTest(book=book, kind=kind), self.assertRaises(sqlite3.IntegrityError):
                self.category('bad'+book+kind, book=book, kind=kind, parent='b1expense')
        with self.assertRaises(sqlite3.IntegrityError):
            self.tx(category_id='b2expense')

    def test_root_sibling_names_unique(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.category('another', name='b1expense')

    def test_tag_cannot_cross_books(self):
        self.tx()
        self.put('tags', id='tag', book_id='b2', name='travel', name_key='travel', created_at_ms=1, updated_at_ms=1)
        with self.assertRaises(sqlite3.IntegrityError):
            self.put('transaction_tags', transaction_id='t', tag_id='tag', book_id='b1')

    def test_parent_budget_not_double_counted(self):
        self.budget()
        self.category('child', parent='b1expense')
        for id, cat in [('total', 'b1expense'), ('child-budget', 'child')]:
            self.put('budget_lines', id=id, budget_id='budget', book_id='b1', category_id=cat, amount_minor=10000)
        self.expense(category_id='child')
        self.assertEqual(self.db.execute('SELECT used_minor FROM v_budget_usage').fetchone()[0], 2800)
        self.assertEqual(self.db.execute("SELECT used_minor FROM v_budget_line_usage WHERE budget_line_id='total'").fetchone()[0], 2800)

    def test_budget_end_exclusive_and_leap_date(self):
        self.budget()
        self.expense(occurred_local_date='2026-11-01')
        self.assertEqual(self.db.execute('SELECT used_minor FROM v_budget_usage').fetchone()[0], 0)
        for date in ['2026-02-29', '2026-02-31', '2026-13-01', 'bad']:
            with self.subTest(date=date), self.assertRaises(sqlite3.IntegrityError):
                self.tx(date, occurred_local_date=date)
        self.tx('leap', occurred_local_date='2024-02-29')

    def test_calibration_separate_from_income_expense(self):
        self.adjust(after=1300000)
        self.adjust('cal', before=1300000, after=1298050, kind='calibration')
        self.assertEqual(self.balance(), 1298050)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM v_book_totals').fetchone()[0], 0)

    def test_stale_calibration_rejected(self):
        self.adjust()
        self.adjust('cal', before=1000000, after=900000, kind='calibration', publish=False)
        self.expense()
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'stale'):
            self.db.execute("UPDATE balance_adjustments SET posting_state='posted' WHERE id='cal'")
        self.assertEqual(self.balance(), 997200)

    def test_opening_unique_and_adjustment_immutable(self):
        self.adjust()
        with self.assertRaises(sqlite3.IntegrityError):
            self.adjust('again')
        for sql in ["UPDATE balance_adjustments SET after_minor=1 WHERE id='a'", "DELETE FROM balance_adjustments WHERE id='a'",
                    "UPDATE account_movements SET delta_minor=1 WHERE adjustment_id='a'"]:
            with self.subTest(sql=sql), self.assertRaises(sqlite3.IntegrityError):
                self.db.execute(sql)

    def test_compensating_adjustment(self):
        self.adjust()
        self.adjust('cal', before=1000000, after=900000, kind='calibration')
        self.adjust('reverse', before=900000, after=1000000, kind='calibration', reversal_of_id='cal')
        self.assertEqual(self.balance(), 1000000)

    def test_import_default_preserve_and_budget(self):
        self.adjust()
        self.budget()
        self.batch()
        self.imported()
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM v_posted_transactions').fetchone()[0], 0)
        self.commit_batch()
        self.assertEqual(self.balance(), 1000000)
        self.assertEqual(self.db.execute('SELECT used_minor FROM v_budget_usage').fetchone()[0], 2800)

    def test_preserve_edit_delete_never_changes_balance(self):
        self.adjust()
        self.batch()
        self.imported()
        self.commit_batch()
        self.db.execute('BEGIN')
        self.db.execute("UPDATE transactions SET posting_state='draft' WHERE id='t'")
        self.db.execute("UPDATE transactions SET gross_minor=3000,paid_minor=3000,book_minor=3000,revision=revision+1 WHERE id='t'")
        self.db.execute("UPDATE account_movements SET delta_minor=-3000 WHERE transaction_id='t'")
        self.post()
        self.db.execute('COMMIT')
        self.assertEqual(self.balance(), 1000000)
        self.db.execute("UPDATE transactions SET deleted_at_ms=2 WHERE id='t'")
        self.assertEqual(self.balance(), 1000000)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM v_posted_transactions').fetchone()[0], 0)

    def test_import_apply_and_assets_off_are_independent(self):
        self.adjust()
        self.batch(mode='apply')
        self.imported(mode='apply', include_in_assets=0)
        self.commit_batch()
        self.assertEqual(self.balance(), 1000000)
        self.db.execute("UPDATE transactions SET posting_state='draft' WHERE id='t'")
        self.db.execute("UPDATE transactions SET include_in_assets=1 WHERE id='t'")
        self.post()
        self.assertEqual(self.balance(), 997200)

    def test_import_policy_immutable_even_during_edit(self):
        self.batch()
        self.imported()
        self.commit_batch()
        self.db.execute("UPDATE transactions SET posting_state='draft' WHERE id='t'")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE transactions SET balance_mode='apply' WHERE id='t'")

    def test_import_row_unique_prevents_retry_double_write(self):
        self.batch()
        self.imported()
        self.commit_batch()
        with self.assertRaises(sqlite3.IntegrityError):
            self.tx('again', import_batch_id='batch', import_row_id='batchrow', balance_mode='preserve')

    def test_duplicate_is_explicitly_allowed(self):
        for id in ['b-a', 'b-b']:
            self.batch(id, duplicate=True)
            self.imported(id, batch=id, duplicate_override=1, source_provider='TEST', source_namespace='account-one', source_record_id='0000123')
            self.commit_batch(id)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM v_posted_transactions').fetchone()[0], 2)
        self.assertEqual(self.db.execute('SELECT source_record_id FROM transactions LIMIT 1').fetchone()[0], '0000123')

    def test_duplicate_requires_override(self):
        self.batch(duplicate=True)
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'selected/confirmed'):
            self.imported()

    def test_batch_count_mismatch_and_unconfirmed_commit_rejected(self):
        self.batch()
        with self.assertRaises(sqlite3.IntegrityError):
            self.commit_batch()
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE import_batches SET status='committing',confirmed_at_ms=NULL WHERE id='batch'")

    def test_committed_staging_immutable(self):
        self.batch()
        self.imported()
        self.commit_batch()
        for sql in ["UPDATE import_rows SET selected=0 WHERE id='batchrow'", "UPDATE import_batches SET balance_mode='apply' WHERE id='batch'",
                    "DELETE FROM import_rows WHERE id='batchrow'"]:
            with self.subTest(sql=sql), self.assertRaises(sqlite3.IntegrityError):
                self.db.execute(sql)

    def test_expense_edit_only_net_difference(self):
        self.adjust()
        self.expense()
        self.db.execute('BEGIN')
        self.db.execute("UPDATE transactions SET posting_state='draft' WHERE id='t'")
        self.db.execute("UPDATE transactions SET gross_minor=3000,paid_minor=3000,book_minor=3000 WHERE id='t'")
        self.db.execute("UPDATE account_movements SET delta_minor=-3000 WHERE transaction_id='t'")
        self.post()
        self.db.execute('COMMIT')
        self.assertEqual(self.balance(), 997000)

    def test_posted_financial_data_cannot_bypass_validation(self):
        self.expense()
        for sql in ["UPDATE transactions SET paid_minor=3000 WHERE id='t'", "UPDATE account_movements SET delta_minor=-3000 WHERE id='tm'",
                    "DELETE FROM transactions WHERE id='t'", "DELETE FROM account_movements WHERE id='tm'"]:
            with self.subTest(sql=sql), self.assertRaises(sqlite3.IntegrityError):
                self.db.execute(sql)

    def test_failed_transfer_transaction_rolls_back(self):
        self.adjust()
        self.db.execute('BEGIN')
        try:
            self.tx(kind='transfer', category_id=None, include_in_budget=0)
            self.move(leg='transfer_out')
            with self.assertRaises(sqlite3.IntegrityError):
                self.post()
        finally:
            self.db.execute('ROLLBACK')
        self.assertEqual(self.balance(), 1000000)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM transactions').fetchone()[0], 0)
        self.assertEqual(self.db.execute('PRAGMA foreign_key_check').fetchall(), [])

    def test_optimistic_revision_conflict(self):
        self.expense()
        a = self.db.execute("UPDATE transactions SET note='first',revision=revision+1 WHERE id='t' AND revision=1")
        b = self.db.execute("UPDATE transactions SET note='stale',revision=revision+1 WHERE id='t' AND revision=1")
        self.assertEqual((a.rowcount, b.rowcount), (1, 0))
        self.assertEqual(self.db.execute("SELECT note FROM transactions WHERE id='t'").fetchone()[0], 'first')

    def test_attachment_ready_and_path_constraints(self):
        self.tx()
        args = dict(content_sha256='a'*64, mime_type='image/png', byte_size=100, state='staged', created_at_ms=1)
        with self.assertRaises(sqlite3.IntegrityError):
            self.put('attachments', id='bad', relative_path='../secret.png', **args)
        self.put('attachments', id='img', relative_path='images/aa.png', **args)
        with self.assertRaises(sqlite3.IntegrityError):
            self.put('transaction_attachments', transaction_id='t', attachment_id='img', sort_order=0)
        self.db.execute("UPDATE attachments SET state='ready' WHERE id='img'")
        self.put('transaction_attachments', transaction_id='t', attachment_id='img', sort_order=0)
        self.post()
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE attachments SET relative_path='other.png' WHERE id='img'")

    def test_optional_coordinates_and_pair_validation(self):
        self.tx('none')
        self.tx('position', latitude_e6=39900000, longitude_e6=116400000)
        for value in [dict(latitude_e6=1), dict(latitude_e6=91000000, longitude_e6=1),
                      dict(latitude_e6=1.5, longitude_e6=1)]:
            with self.subTest(value=value), self.assertRaises(sqlite3.IntegrityError):
                self.tx('bad-position', **value)

    def test_settlement_time_must_match_transaction(self):
        self.tx()
        self.move(occurred_at_ms=1)
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'time mismatch'):
            self.post()

    def test_archive_preserves_global_balance_delete_is_explicit(self):
        self.adjust()
        self.expense()
        self.db.execute("UPDATE books SET archived_at_ms=2 WHERE id='b1'")
        self.db.execute("UPDATE accounts SET archived_at_ms=2 WHERE id='cash'")
        self.assertEqual(self.balance(), 997200)
        for sql in ["UPDATE books SET deleted_at_ms=2 WHERE id='b1'", "UPDATE accounts SET deleted_at_ms=2 WHERE id='cash'",
                    "UPDATE categories SET deleted_at_ms=2 WHERE id='b1expense'"]:
            with self.subTest(sql=sql), self.assertRaises(sqlite3.IntegrityError):
                self.db.execute(sql)

    def test_cannot_publish_into_deleted_book(self):
        self.db.execute("UPDATE books SET deleted_at_ms=2 WHERE id='b1'")
        self.tx()
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'entity is deleted'):
            self.post()

    def test_net_assets_group_currency_and_account_inclusion(self):
        self.adjust('cny-open', after=1000000)
        self.adjust('usd-open', account='usd', after=5000)
        self.adjust('credit-open', account='credit', after=-20000)
        self.adjust('bank-open', account='bank', after=200000)
        self.db.execute("UPDATE accounts SET include_in_net_assets=0 WHERE id='bank'")
        values = dict(self.db.execute('SELECT currency_id,net_minor FROM v_net_assets_by_currency'))
        self.assertEqual(values, {'CNY': 980000, 'USD': 5000})

    def test_exact_large_aggregate_and_overflow_is_visible(self):
        for id in ['large-a', 'large-b']:
            self.tx(id, kind='income', category_id='b1income', include_in_budget=0,
                    gross_minor=5000000000000000, paid_minor=5000000000000000, book_minor=5000000000000000)
            self.move(id+'m', tx=id, delta=5000000000000000, leg='income')
            self.post(id)
        value = self.db.execute("SELECT CAST(balance_minor AS TEXT) FROM v_account_balances WHERE account_id='cash'").fetchone()[0]
        self.assertEqual(value, '10000000000000000')
        with self.assertRaisesRegex(sqlite3.OperationalError, 'overflow'):
            self.db.execute('WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<1025) SELECT SUM(9007199254740991) FROM n').fetchone()


if __name__ == '__main__':
    print('Design-only verification; SQLite', sqlite3.sqlite_version, '; databases: :memory:', flush=True)
    unittest.main(verbosity=2)
