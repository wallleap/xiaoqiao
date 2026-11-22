"""V14 empty-prepaid cleanup tests. In-memory SQLite only; no device data."""
import sqlite3,unittest
import verify_category_deletion as category
from verify_account_details import statements

class PrepaidCleanupTests(unittest.TestCase):
 def setUp(self):
  f=category.CategoryDeletionTests();f.setUp();f.migrate();self.addCleanup(f.doCleanups)
  self.db=f.db;self.old=f.old;self.h=f.h
  for sql in statements('PrepaidCleanupSchema.ets'):self.db.execute(sql)
 def fund(self,project='p',event='e',posted=True):
  self.db.execute('INSERT INTO prepaid_projects(id,book_id,name,currency_id,created_at_ms,updated_at_ms) VALUES(?,?,?,?,1,1)',(project,'b1','空项目','CNY'))
  self.db.execute("INSERT INTO prepaid_events(id,project_id,sequence_no,kind,amount_minor,book_minor,account_id,account_currency_id,cash_minor,cash_book_minor,quote_json,local_date,occurred_at_ms,offset_minutes,created_at_ms) VALUES(?,?,1,'fund',100,100,'cash','CNY',100,100,?, '2026-11-20',1,0,1)",(event,project,'{"entry":{"categoryId":"b1expense"}}'))
  if posted:self.db.execute("UPDATE prepaid_events SET posting_state='posted' WHERE id=?",(event,))
 def cleanup(self,project='p',revision=1):
  self.db.execute('BEGIN')
  try:self.db.execute("INSERT INTO prepaid_cleanup_context VALUES(1,?,'b1',?)",(project,revision));self.db.execute('COMMIT')
  except:self.db.execute('ROLLBACK');raise
 def count(self,table):return self.db.execute('SELECT COUNT(*) FROM '+table).fetchone()[0]
 def test_empty_cleanup_clears_refs_preserves_balances(self):
  self.fund();self.db.execute("UPDATE prepaid_events SET deleted_at_ms=2 WHERE id='e'")
  before=self.old.balances();self.cleanup()
  self.assertEqual(before,self.old.balances())
  for table in ['prepaid_events','prepaid_projects','prepaid_cleanup_context','prepaid_cleanup_transactions','prepaid_cleanup_balances','prepaid_cleanup_resources']:self.assertEqual(0,self.count(table),table)
  self.db.execute("DELETE FROM categories WHERE id='b1expense'")
  self.assertEqual([],self.db.execute('PRAGMA foreign_key_check').fetchall())
 def test_effective_fund_and_draft_block(self):
  for posted in [True,False]:
   project='p'+str(posted);self.fund(project,project,posted)
   with self.assertRaisesRegex(sqlite3.IntegrityError,'PREPAID_NOT_EMPTY'):self.cleanup(project)
  self.assertEqual(2,self.count('prepaid_projects'));self.assertEqual(0,self.count('prepaid_cleanup_context'))
 def test_revision_and_wrong_book_block(self):
  self.fund();self.db.execute("UPDATE prepaid_events SET deleted_at_ms=2 WHERE id='e'")
  with self.assertRaisesRegex(sqlite3.IntegrityError,'PREPAID_CHANGED'):self.cleanup(revision=99)
  with self.assertRaisesRegex(sqlite3.IntegrityError,'PREPAID_CHANGED'):self.db.execute("INSERT INTO prepaid_cleanup_context VALUES(1,'p','b2',1)")
  self.assertEqual(1,self.count('prepaid_projects'))
 def test_raw_delete_stays_forbidden(self):
  self.fund();self.db.execute("UPDATE prepaid_events SET deleted_at_ms=2 WHERE id='e'")
  for table in ['prepaid_projects','prepaid_events']:
   with self.assertRaisesRegex(sqlite3.IntegrityError,'PREPAID_HISTORY_LOCKED'):self.db.execute('DELETE FROM '+table)
 def test_undo_and_cleanup_failure_roll_back_together(self):
  self.fund();before=self.old.balances()
  self.db.execute("CREATE TRIGGER injected AFTER DELETE ON prepaid_projects BEGIN SELECT RAISE(ABORT,'injected'); END")
  self.db.execute('BEGIN')
  with self.assertRaisesRegex(sqlite3.IntegrityError,'injected'):
   self.db.execute("UPDATE prepaid_events SET deleted_at_ms=2 WHERE id='e'")
   self.db.execute("INSERT INTO prepaid_cleanup_context VALUES(1,'p','b1',1)")
  self.db.execute('ROLLBACK')
  self.assertEqual(before,self.old.balances());self.assertEqual(1,self.db.execute('SELECT COUNT(*) FROM v_prepaid_events').fetchone()[0])
 def test_zero_remaining_with_history_is_not_empty(self):
  self.fund()
  self.db.execute("INSERT INTO prepaid_events(id,project_id,sequence_no,kind,amount_minor,book_minor,account_id,account_currency_id,cash_minor,cash_book_minor,local_date,occurred_at_ms,offset_minutes,created_at_ms) VALUES('r','p',2,'refund',100,100,'cash','CNY',100,100,'2026-11-20',2,0,2)")
  self.db.execute("INSERT INTO prepaid_allocations VALUES('r','e',100,100)")
  self.db.execute("UPDATE prepaid_events SET posting_state='posted' WHERE id='r'")
  self.assertEqual(0,self.db.execute("SELECT remaining_minor FROM v_prepaid_balances WHERE id='p'").fetchone()[0])
  with self.assertRaisesRegex(sqlite3.IntegrityError,'PREPAID_NOT_EMPTY'):self.cleanup()
 def test_attachment_cleanup_keeps_shared_resources(self):
  self.fund(posted=False);self.fund('other','other',False)
  for id,sha in [('shared','a'*64),('unique','b'*64)]:
   self.db.execute("INSERT INTO attachments(id,content_sha256,relative_path,mime_type,byte_size,state,created_at_ms) VALUES(?,?,?,'image/jpeg',1,'ready',1)",(id,sha,'images/'+sha+'.jpg'))
  self.db.execute("INSERT INTO prepaid_event_attachments VALUES('e','shared',0)")
  self.db.execute("INSERT INTO prepaid_event_attachments VALUES('other','shared',0)")
  self.db.execute("INSERT INTO prepaid_event_attachments VALUES('e','unique',1)")
  self.db.execute("UPDATE prepaid_events SET posting_state='posted'")
  self.db.execute("UPDATE prepaid_events SET deleted_at_ms=2 WHERE id='e'");self.cleanup()
  self.assertEqual([('shared',)],self.db.execute('SELECT id FROM attachments').fetchall())
  self.assertEqual([('images/'+'b'*64+'.jpg',)],self.db.execute('SELECT relative_path FROM book_deletion_files').fetchall())
  self.assertEqual([],self.db.execute('PRAGMA foreign_key_check').fetchall())
 def test_migration_changes_no_existing_data_and_rolls_back(self):
  self.fund();before=list(self.db.execute('SELECT * FROM prepaid_events'))
  other=category.CategoryDeletionTests();other.setUp();other.migrate()
  try:
   original=list(other.db.execute("SELECT name,sql FROM sqlite_master ORDER BY name"));other.db.execute('BEGIN')
   for sql in statements('PrepaidCleanupSchema.ets'):other.db.execute(sql)
   other.db.execute('ROLLBACK');self.assertEqual(original,list(other.db.execute("SELECT name,sql FROM sqlite_master ORDER BY name")))
  finally:other.doCleanups()
  self.assertEqual(before,list(self.db.execute('SELECT * FROM prepaid_events')))
 def test_book_deletion_still_works_with_v14_guards(self):
  self.fund();self.db.execute("UPDATE prepaid_events SET deleted_at_ms=2 WHERE id='e'")
  before=self.old.balances();self.db.execute("UPDATE books SET archived_at_ms=3 WHERE id='b1'")
  self.db.execute('BEGIN');self.old.prepare();self.db.execute("DELETE FROM books WHERE id='b1'");self.db.execute('COMMIT')
  self.assertEqual(before,self.old.balances());self.assertEqual(0,self.count('prepaid_events'));self.assertEqual(0,self.count('prepaid_projects'))
  self.assertEqual([],self.db.execute('PRAGMA foreign_key_check').fetchall())
 def test_other_project_and_book_untouched(self):
  self.fund();self.fund('other','other');self.db.execute("UPDATE prepaid_events SET deleted_at_ms=2 WHERE id='e'")
  before=self.old.balances();self.cleanup();self.assertEqual(before,self.old.balances());self.assertEqual([('other',)],self.db.execute('SELECT id FROM prepaid_projects').fetchall())

if __name__=='__main__':unittest.main()
