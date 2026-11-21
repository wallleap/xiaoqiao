"""V12 physical book deletion. In-memory SQLite only, never the application database."""
import sqlite3
import unittest
import verify_book_settings as settings
from verify_account_details import statements

class BookDeletionTests(unittest.TestCase):
    def setUp(self):
        f=settings.BookSettingsTests();f.setUp();f.migrate();self.addCleanup(f.doCleanups)
        self.db=f.db;self.h=f.helper
        for sql in statements('BookDeletionSchema.ets'):self.db.execute(sql)
        self.db.execute("INSERT OR REPLACE INTO db_meta(key,value) VALUES('active_book_id','b2')")

    def balances(self):
        return dict(self.db.execute('SELECT account_id,balance_minor FROM v_account_balances'))

    def prepare(self, book='b1', revision=1):
        self.db.execute('INSERT INTO book_deletion_context VALUES(1,?,?,?,?)',(book,revision,'test-full-backup.xqbackup',99))
        sums={}
        for account,delta in self.db.execute("SELECT m.account_id,m.delta_minor FROM v_effective_movements m WHERE m.transaction_id IN (SELECT id FROM transactions WHERE book_id=?) OR (m.adjustment_id IS NULL AND m.id IN (SELECT e.id FROM prepaid_events e JOIN prepaid_projects p ON p.id=e.project_id WHERE p.book_id=?))",(book,book)):
            sums[account]=sums.get(account,0)+delta
        for account,currency in self.db.execute('SELECT id,currency_id FROM accounts'):
            self.db.execute('INSERT INTO book_deletion_balances VALUES(?,?,?,?,?)',(account,currency,self.balances()[account],sums.get(account,0),'carry-'+account))

    def expense(self,id,book='b1',amount=100,account='cash',date='2026-11-20',apply=True):
        extra={}
        if not apply:
            self.h.batch(id=id+'batch');self.db.execute("UPDATE import_batches SET status='committing' WHERE id=?",(id+'batch',))
            extra={'import_batch_id':id+'batch','import_row_id':id+'batchrow'}
        self.h.tx(id=id,book_id=book,category_id=book+'expense',gross_minor=amount,paid_minor=amount,book_minor=amount,include_in_assets=1,balance_mode='apply' if apply else 'preserve',occurred_local_date=date,**extra)
        self.h.move(id=id+'move',tx=id,account=account,delta=-amount)
        self.db.execute("UPDATE transactions SET posting_state='posted' WHERE id=?",(id,))
        if not apply:self.h.commit_batch(id+'batch')

    def test_deletes_every_row_and_keeps_exact_balance(self):
        self.expense('a',amount=500);self.expense('b',book='b2',amount=200);self.expense('preserved',amount=700,apply=False)
        before=self.balances();other=list(self.db.execute("SELECT * FROM transactions WHERE book_id='b2'"))
        self.db.execute("UPDATE books SET archived_at_ms=3 WHERE id='b1'")
        self.db.execute('BEGIN');self.prepare();self.db.execute("DELETE FROM books WHERE id='b1'");self.db.execute('COMMIT')
        self.assertEqual(before,self.balances());self.assertEqual(other,list(self.db.execute("SELECT * FROM transactions WHERE book_id='b2'")))
        for t in ['transactions','categories','tags','budgets','import_batches','expense_recoveries','prepaid_projects']:
            self.assertEqual(0,self.db.execute('SELECT COUNT(*) FROM '+t+' WHERE book_id=\'b1\'').fetchone()[0])
        self.assertEqual([(-500,'账本删除余额结转')],list(self.db.execute("SELECT delta_minor,reason FROM balance_adjustments WHERE reason='账本删除余额结转'")))
        self.assertEqual([],list(self.db.execute('PRAGMA foreign_key_check')))
        for t in ['book_deletion_context','book_deletion_balances','book_deletion_resources','book_deletion_merchants']:
            self.assertEqual(0,self.db.execute('SELECT COUNT(*) FROM '+t).fetchone()[0])

    def test_live_book_raw_delete_and_ordinary_hard_delete_still_blocked(self):
        self.expense('a')
        with self.assertRaises(sqlite3.IntegrityError):self.db.execute("DELETE FROM books WHERE id='b1'")
        with self.assertRaises(sqlite3.IntegrityError):self.db.execute("DELETE FROM transactions WHERE id='a'")
        with self.assertRaises(sqlite3.IntegrityError):self.db.execute("DELETE FROM account_movements WHERE transaction_id='a'")
        with self.assertRaises(sqlite3.IntegrityError):self.prepare()

    def test_failed_balance_proof_rolls_back_everything(self):
        self.expense('a');self.db.execute("UPDATE books SET archived_at_ms=3 WHERE id='b1'");before=self.balances()
        self.db.execute('BEGIN');self.prepare();self.db.execute("UPDATE book_deletion_balances SET carry_minor=1 WHERE account_id='cash'")
        with self.assertRaises(sqlite3.IntegrityError):self.db.execute("DELETE FROM books WHERE id='b1'")
        self.db.execute('ROLLBACK');self.assertEqual(before,self.balances());self.assertEqual(1,self.db.execute("SELECT COUNT(*) FROM transactions WHERE id='a'").fetchone()[0])

    def test_unsettled_prepaid_blocks_delete(self):
        h=self.h;h.put('prepaid_projects',id='p',book_id='b1',name='P',currency_id='CNY',created_at_ms=1,updated_at_ms=1)
        h.put('prepaid_events',id='fund',project_id='p',sequence_no=1,kind='fund',amount_minor=100,book_minor=100,account_id='cash',account_currency_id='CNY',cash_minor=100,cash_book_minor=100,local_date='2026-11-20',occurred_at_ms=1,offset_minutes=0,created_at_ms=1)
        self.db.execute("UPDATE prepaid_events SET posting_state='posted' WHERE id='fund'");self.db.execute("UPDATE books SET archived_at_ms=3 WHERE id='b1'")
        with self.assertRaisesRegex(sqlite3.IntegrityError,'BOOK_DELETE_PREPAID_OPEN'):self.prepare()

    def test_shared_attachment_retained_unique_attachment_queued(self):
        self.expense('a');self.expense('b',book='b2')
        for id in ['shared','unique']:
            self.h.put('attachments',id=id,relative_path='images/'+id+'.png',content_sha256=('a' if id=='shared' else 'b')*64,byte_size=1,mime_type='image/png',state='ready',created_at_ms=1)
            self.h.put('transaction_attachments',transaction_id='a',attachment_id=id,sort_order=0 if id=='shared' else 1)
        self.h.put('transaction_attachments',transaction_id='b',attachment_id='shared',sort_order=0)
        self.db.execute("UPDATE books SET archived_at_ms=3 WHERE id='b1'");self.db.execute('BEGIN');self.prepare();self.db.execute("DELETE FROM books WHERE id='b1'");self.db.execute('COMMIT')
        self.assertEqual([('shared',)],list(self.db.execute('SELECT id FROM attachments')))
        self.assertEqual([('images/unique.png',)],list(self.db.execute('SELECT relative_path FROM book_deletion_files')))

    def test_foreign_currency_liability_and_recovery_keep_balances(self):
        self.expense('credit-expense',amount=300,account='credit')
        self.expense('a',amount=500)
        h=self.h
        h.tx(id='usd-expense',currency_id='USD',gross_minor=100,paid_minor=100,book_minor=700)
        h.move(id='usd-move',tx='usd-expense',account='usd',currency='USD',delta=-100)
        h.put('fx_snapshots',id='fx',transaction_id='usd-expense',role='book',from_currency_id='USD',to_currency_id='CNY',from_minor=100,to_minor=700,rate_decimal='7',rate_source='manual',rate_time_ms=1,rounding_mode='HALF_UP',calculation_version=1)
        self.db.execute("UPDATE transactions SET posting_state='posted' WHERE id='usd-expense'")
        h.put('expense_recoveries',id='refund',transaction_id='a',book_id='b1',kind='refund',amount_minor=100,book_minor=100,account_minor=100,account_currency_id='CNY',account_id='cash',local_date='2026-11-20',occurred_at_ms=1,offset_minutes=0,note='',created_at_ms=1,updated_at_ms=1)
        before=self.balances();self.db.execute("UPDATE books SET archived_at_ms=3 WHERE id='b1'")
        self.db.execute('BEGIN');self.prepare();self.db.execute("DELETE FROM books WHERE id='b1'");self.db.execute('COMMIT')
        self.assertEqual(before,self.balances())
        self.assertEqual({'cash':-400,'credit':-300,'usd':-100},dict(self.db.execute("SELECT account_id,delta_minor FROM balance_adjustments WHERE reason='账本删除余额结转'")))
        self.assertEqual(0,self.db.execute('SELECT COUNT(*) FROM fx_snapshots').fetchone()[0])
        self.assertEqual(0,self.db.execute('SELECT COUNT(*) FROM expense_recoveries').fetchone()[0])

    def test_settled_prepaid_cleans_up_and_preserves_fund_outflow(self):
        h=self.h;h.put('prepaid_projects',id='p',book_id='b1',name='P',currency_id='CNY',created_at_ms=1,updated_at_ms=1)
        h.put('prepaid_events',id='fund',project_id='p',sequence_no=1,kind='fund',amount_minor=100,book_minor=100,account_id='cash',account_currency_id='CNY',cash_minor=100,cash_book_minor=100,local_date='2026-11-20',occurred_at_ms=1,offset_minutes=0,created_at_ms=1)
        self.db.execute("UPDATE prepaid_events SET posting_state='posted' WHERE id='fund'")
        h.tx(id='consume-t',gross_minor=100,paid_minor=100,book_minor=100,include_in_assets=0)
        self.db.execute("UPDATE transactions SET posting_state='posted' WHERE id='consume-t'")
        h.put('prepaid_events',id='consume',project_id='p',sequence_no=2,kind='consume',amount_minor=100,book_minor=100,account_currency_id='CNY',transaction_id='consume-t',local_date='2026-11-20',occurred_at_ms=1,offset_minutes=0,created_at_ms=1)
        h.put('prepaid_allocations',event_id='consume',fund_id='fund',amount_minor=100,book_minor=100)
        self.db.execute("UPDATE prepaid_events SET posting_state='posted' WHERE id='consume'")
        before=self.balances();self.db.execute("UPDATE books SET archived_at_ms=3 WHERE id='b1'")
        self.db.execute('BEGIN');self.prepare();self.db.execute("DELETE FROM books WHERE id='b1'");self.db.execute('COMMIT')
        self.assertEqual(before,self.balances())
        for t in ['prepaid_projects','prepaid_events','prepaid_allocations']:
            self.assertEqual(0,self.db.execute('SELECT COUNT(*) FROM '+t).fetchone()[0])

    def test_transfer_legs_are_consolidated_per_account(self):
        h=self.h;h.tx(id='transfer',kind='transfer',category_id=None,include_in_budget=0,gross_minor=500,paid_minor=500,book_minor=500)
        h.put('transfer_details',transaction_id='transfer',purpose='transfer',currency_id='CNY',from_account_id='cash',to_account_id='bank',out_minor=510,in_minor=500,fee_minor=10,coupon_minor=0,fee_in_expense=1,fee_in_budget=1)
        h.move(id='out',tx='transfer',account='cash',delta=-510,leg='transfer_out');h.move(id='in',tx='transfer',account='bank',delta=500,leg='transfer_in')
        self.db.execute("UPDATE transactions SET posting_state='posted' WHERE id='transfer'")
        before=self.balances();self.db.execute("UPDATE books SET archived_at_ms=3 WHERE id='b1'")
        self.db.execute('BEGIN');self.prepare();self.db.execute("DELETE FROM books WHERE id='b1'");self.db.execute('COMMIT')
        self.assertEqual(before,self.balances());self.assertEqual(0,self.db.execute('SELECT COUNT(*) FROM transfer_details').fetchone()[0])

    def test_migration_preserves_data_and_rolls_back_guard_changes(self):
        f=settings.BookSettingsTests();f.setUp();f.migrate();self.addCleanup(f.doCleanups);db=f.db
        names=[r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]
        before={name:list(db.execute('SELECT * FROM '+name)) for name in names}
        guards=list(db.execute("SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name"))
        db.execute('BEGIN')
        for sql in statements('BookDeletionSchema.ets'):db.execute(sql)
        db.execute('ROLLBACK')
        self.assertEqual(guards,list(db.execute("SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name")))
        self.assertEqual(0,db.execute("SELECT COUNT(*) FROM sqlite_master WHERE name='book_deletion_context'").fetchone()[0])
        backup=sqlite3.connect(':memory:');self.addCleanup(backup.close);db.backup(backup)
        db.execute('BEGIN')
        for sql in statements('BookDeletionSchema.ets'):db.execute(sql)
        db.execute('COMMIT')
        self.assertEqual(before,{name:list(db.execute('SELECT * FROM '+name)) for name in names})
        backup.backup(db)
        self.assertEqual(guards,list(db.execute("SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name")))

    def test_context_cannot_delete_another_books_rows(self):
        self.expense('a');self.expense('other',book='b2');self.db.execute("UPDATE books SET archived_at_ms=3 WHERE id='b1'")
        self.db.execute('BEGIN');self.prepare()
        with self.assertRaises(sqlite3.IntegrityError):self.db.execute("DELETE FROM transactions WHERE id='other'")
        with self.assertRaises(sqlite3.IntegrityError):self.db.execute("DELETE FROM account_movements WHERE transaction_id='other'")
        self.db.execute('ROLLBACK')
        self.assertEqual(1,self.db.execute("SELECT COUNT(*) FROM transactions WHERE id='other'").fetchone()[0])

if __name__=='__main__':unittest.main()
