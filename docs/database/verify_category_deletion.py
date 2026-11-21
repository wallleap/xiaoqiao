"""V13 isolated SQLite migration/deletion tests. Never opens a device database."""
import sqlite3, unittest
import verify_book_deletion as previous
from verify_account_details import statements

class CategoryDeletionTests(unittest.TestCase):
 def setUp(self):
  self.old=previous.BookDeletionTests();self.old.setUp();self.addCleanup(self.old.doCleanups)
  self.db=self.old.db;self.h=self.old.h
  self.db.execute("INSERT INTO categories(id,book_id,kind,name,name_key,created_at_ms,updated_at_ms) VALUES('spare','b1','expense','其它','其它',1,1)")
 def migrate(self):
  self.db.execute('BEGIN')
  try:
   for sql in statements('CategoryDeletionSchema.ets'):self.db.execute(sql)
   self.db.execute('COMMIT')
  except:
   self.db.execute('ROLLBACK');raise
 def delete(self,id='b1expense'):
  self.db.execute('BEGIN')
  try:self.db.execute('DELETE FROM categories WHERE id=?',(id,));self.db.execute('COMMIT')
  except:self.db.execute('ROLLBACK');raise
 def rows(self,table):return list(self.db.execute('SELECT * FROM '+table+' ORDER BY rowid'))
 def test_migration_keeps_all_money_rows_and_refs(self):
  self.old.expense('a');before={t:self.rows(t) for t in ['transactions','account_movements','categories','accounts','books']}
  self.migrate()
  for t,v in before.items():self.assertEqual(v,self.rows(t),t)
  self.assertEqual([],self.db.execute('PRAGMA foreign_key_check').fetchall())
  self.assertEqual('ok',self.db.execute('PRAGMA quick_check').fetchone()[0])
 def test_delete_physically_preserves_tx_balance_and_history(self):
  self.old.expense('a');self.migrate();tx=self.rows('transactions');balance=self.old.balances();moves=self.rows('account_movements')
  self.delete();self.assertEqual(0,self.db.execute("SELECT count(*) FROM categories WHERE id='b1expense'").fetchone()[0])
  self.assertEqual(tx,self.rows('transactions'));self.assertEqual(balance,self.old.balances());self.assertEqual(moves,self.rows('account_movements'))
  self.assertEqual(1,self.db.execute("SELECT count(*) FROM v_historical_categories WHERE id='b1expense'").fetchone()[0])
  self.assertEqual([],self.db.execute('PRAGMA foreign_key_check').fetchall())
  with self.assertRaisesRegex(sqlite3.IntegrityError,'IMMUTABLE'):self.db.execute("UPDATE category_history SET name='bad'")
  with self.assertRaisesRegex(sqlite3.IntegrityError,'IMMUTABLE'):self.db.execute('DELETE FROM category_history_nodes')
 def test_new_transaction_cannot_use_deleted_category(self):
  self.old.expense('a');self.migrate();self.delete()
  with self.assertRaisesRegex(sqlite3.IntegrityError,'CATEGORY_UNAVAILABLE'):self.old.expense('b')
 def test_history_can_republish_and_reclassify(self):
  self.old.expense('a');self.migrate();self.delete()
  self.db.execute("UPDATE transactions SET posting_state='draft',revision=revision+1 WHERE id='a'")
  self.db.execute("UPDATE transactions SET note='updated' WHERE id='a'")
  self.db.execute("UPDATE transactions SET posting_state='posted' WHERE id='a'")
  self.db.execute("UPDATE transactions SET posting_state='draft',revision=revision+1 WHERE id='a'")
  self.db.execute("UPDATE transactions SET category_id='spare' WHERE id='a'")
  self.db.execute("UPDATE transactions SET posting_state='posted' WHERE id='a'")
  with self.assertRaisesRegex(sqlite3.IntegrityError,'CATEGORY_UNAVAILABLE'):
   self.db.execute("UPDATE transactions SET posting_state='draft' WHERE id='a'");self.db.execute("UPDATE transactions SET category_id='b1expense' WHERE id='a'")
 def test_frozen_full_path_and_ancestor_budget_closure(self):
  self.db.execute("INSERT INTO categories(id,book_id,kind,parent_id,name,name_key,icon_key,created_at_ms,updated_at_ms) VALUES('leaf','b1','expense','b1expense','午餐','午餐','food',1,1)")
  self.h.tx(id='leaf-tx',category_id='leaf',book_id='b1')
  self.migrate();before=self.db.execute("SELECT name FROM categories WHERE id='b1expense'").fetchone()[0];self.delete('leaf')
  path=self.db.execute("SELECT path FROM category_history WHERE id='leaf'").fetchone()[0];self.assertEqual(before+' / 午餐',path)
  self.assertEqual(1,self.db.execute("SELECT count(*) FROM category_closure WHERE ancestor_id='b1expense' AND descendant_id='leaf'").fetchone()[0])
  self.db.execute("UPDATE categories SET name='新名称' WHERE id='b1expense'")
  self.assertEqual(path,self.db.execute("SELECT path FROM category_history WHERE id='leaf'").fetchone()[0])
 def test_children_and_last_available_guard(self):
  self.db.execute("INSERT INTO categories(id,book_id,kind,parent_id,name,name_key,created_at_ms,updated_at_ms) VALUES('leaf','b1','expense','b1expense','午餐','午餐',1,1)")
  self.migrate()
  with self.assertRaisesRegex(sqlite3.IntegrityError,'CATEGORY_HAS_CHILDREN'):self.delete()
  self.delete('leaf');self.delete();
  with self.assertRaisesRegex(sqlite3.IntegrityError,'LAST_ACTIVE_CATEGORY'):self.delete('spare')
 def test_budget_reference_blocks(self):
  self.h.budget();self.db.execute("INSERT INTO budget_lines(id,budget_id,book_id,category_kind,category_id,amount_minor) VALUES('line','budget','b1','expense','b1expense',100)")
  self.migrate()
  with self.assertRaisesRegex(sqlite3.IntegrityError,'CATEGORY_HAS_BUDGET'):self.delete()
 def test_prepaid_reference_blocks_even_unpublished(self):
  self.migrate()
  self.db.execute("INSERT INTO prepaid_projects(id,book_id,name,currency_id,created_at_ms,updated_at_ms) VALUES('p','b1','项目','CNY',1,1)")
  self.db.execute("INSERT INTO prepaid_events(id,project_id,sequence_no,kind,amount_minor,book_minor,account_id,account_currency_id,cash_minor,cash_book_minor,quote_json,local_date,occurred_at_ms,offset_minutes,created_at_ms) VALUES('e','p',1,'fund',100,100,'cash','CNY',100,100,'{\"entry\":{\"categoryId\":\"b1expense\"}}','2026-11-20',1,0,1)")
  with self.assertRaisesRegex(sqlite3.IntegrityError,'CATEGORY_HAS_PREPAID'):self.delete()
 def test_book_deletion_clears_snapshots_and_keeps_balances(self):
  self.old.expense('a');self.migrate();self.delete();balance=self.old.balances()
  self.db.execute("UPDATE books SET archived_at_ms=9 WHERE id='b1'")
  self.db.execute('BEGIN');self.old.prepare();self.db.execute("DELETE FROM books WHERE id='b1'");self.db.execute('COMMIT')
  self.assertEqual(balance,self.old.balances());self.assertEqual([],self.rows('category_history'));self.assertEqual([],self.rows('category_history_nodes'))
  self.assertEqual([],self.db.execute('PRAGMA foreign_key_check').fetchall())
 def test_transaction_rollback_and_backup_restore(self):
  self.old.expense('a');self.migrate();backup=sqlite3.connect(':memory:');self.addCleanup(backup.close);self.db.backup(backup)
  self.db.execute('BEGIN');self.db.execute("DELETE FROM categories WHERE id='b1expense'");self.db.execute('ROLLBACK')
  self.assertEqual([],self.rows('category_history'));self.assertEqual(1,self.db.execute("SELECT count(*) FROM categories WHERE id='b1expense'").fetchone()[0])
  self.delete();backup.backup(self.db)
  self.assertEqual(1,self.db.execute("SELECT count(*) FROM categories WHERE id='b1expense'").fetchone()[0]);self.assertEqual([],self.rows('category_history'))

 def test_unused_category_has_no_remaining_entity_or_snapshot(self):
  self.migrate();self.delete()
  self.assertEqual([],self.rows('category_history'))
  self.assertEqual(0,self.db.execute("SELECT count(*) FROM category_references WHERE id='b1expense'").fetchone()[0])
 def test_migration_fault_rolls_back_original_schema_and_data(self):
  self.old.expense('a');before=self.rows('transactions')
  self.db.execute('BEGIN')
  try:
   for sql in statements('CategoryDeletionSchema.ets'):
    self.db.execute(sql)
    if sql.startswith('ALTER TABLE transactions_v13'):
     self.db.execute("UPDATE transactions SET note='fault' WHERE id='a'")
   self.fail('writer verification must reject altered original rows')
  except sqlite3.IntegrityError as e:
   self.assertIn('CATEGORY_MIGRATION_INTEGRITY',str(e));self.db.execute('ROLLBACK')
  self.assertEqual(before,self.rows('transactions'))
  self.assertEqual(0,self.db.execute("SELECT count(*) FROM sqlite_master WHERE name='category_history'").fetchone()[0])
  self.assertEqual([],self.db.execute('PRAGMA foreign_key_check').fetchall())
 def test_financial_proof_failure_rolls_back_category_deletion(self):
  self.old.expense('a');self.migrate();before=self.rows('transactions')
  self.db.execute("CREATE TRIGGER injected_fault AFTER INSERT ON category_history BEGIN UPDATE transactions SET revision=revision+1 WHERE id='a'; END")
  with self.assertRaisesRegex(sqlite3.IntegrityError,'CATEGORY_DELETE_FINANCE_CHANGED'):self.delete()
  self.assertEqual(before,self.rows('transactions'));self.assertEqual([],self.rows('category_history'))
  self.assertEqual(1,self.db.execute("SELECT count(*) FROM categories WHERE id='b1expense'").fetchone()[0])

if __name__=='__main__':unittest.main()
