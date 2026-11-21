"""Generate V13 from the checked-in V1–V12 schema, in an isolated in-memory database only."""
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'docs/database'))
from verify_book_deletion import BookDeletionTests
f=BookDeletionTests();f.setUp();db=f.db
objects=list(db.execute("SELECT type,name,sql FROM sqlite_master WHERE type IN ('trigger','view') AND sql IS NOT NULL ORDER BY rowid"))
indexes=[r[0] for r in db.execute("SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name='transactions' AND sql IS NOT NULL ORDER BY rowid")]
tx=db.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='transactions'").fetchone()[0]
result=['PRAGMA defer_foreign_keys=ON;', 'CREATE TABLE category_migration_tx_proof AS SELECT * FROM transactions;', 'CREATE TABLE category_migration_balance_proof AS SELECT account_id,balance_minor FROM v_account_balances;']
result += [f'DROP {kind.upper()} "{name}";' for kind,name,_ in reversed(objects)]
result += ["""CREATE TABLE category_references(id TEXT PRIMARY KEY NOT NULL,book_id TEXT NOT NULL REFERENCES books(id),kind TEXT NOT NULL CHECK(kind IN ('expense','income')),UNIQUE(id,book_id,kind));""",
'INSERT INTO category_references SELECT id,book_id,kind FROM categories;',
"""CREATE TABLE category_history(id TEXT PRIMARY KEY NOT NULL,book_id TEXT NOT NULL REFERENCES books(id),kind TEXT NOT NULL,name TEXT NOT NULL,icon_key TEXT NOT NULL,path TEXT NOT NULL,root_id TEXT NOT NULL,root_name TEXT NOT NULL,root_icon TEXT NOT NULL,deleted_at_ms INTEGER NOT NULL,FOREIGN KEY(id,book_id,kind) REFERENCES category_references(id,book_id,kind));""",
"""CREATE TABLE category_history_nodes(snapshot_id TEXT NOT NULL REFERENCES category_history(id),node_id TEXT NOT NULL,parent_id TEXT,name TEXT NOT NULL,icon_key TEXT NOT NULL,depth INTEGER NOT NULL,PRIMARY KEY(snapshot_id,node_id));"""]
result += ["CREATE TABLE category_delete_tx_proof(id TEXT PRIMARY KEY,paid_minor INTEGER,book_minor INTEGER,revision INTEGER);", "CREATE TABLE category_delete_balance_proof(account_id TEXT PRIMARY KEY,balance_minor INTEGER);"]
new=tx.replace('CREATE TABLE transactions (','CREATE TABLE transactions_v13 (',1).replace('REFERENCES categories(id,book_id,kind)','REFERENCES category_references(id,book_id,kind)')
assert new!=tx and 'CREATE TABLE transactions_v13' in new
result += [new+';','INSERT INTO transactions_v13 SELECT * FROM transactions;','DROP TABLE transactions;','ALTER TABLE transactions_v13 RENAME TO transactions;']+ [s+';' for s in indexes]
for kind,name,sql in objects:
 if name=='category_closure':
  sql=sql.replace(') SELECT * FROM c',') SELECT * FROM c UNION SELECT node_id,snapshot_id,depth FROM category_history_nodes')
 if name=='transaction_publish':
  old='NOT EXISTS(SELECT 1 FROM categories WHERE id=NEW.category_id AND deleted_at_ms IS NULL)'
  assert old in sql
  sql=sql.replace(old,"NOT EXISTS(SELECT 1 FROM categories WHERE id=NEW.category_id AND deleted_at_ms IS NULL) AND NOT (NEW.category_id=OLD.category_id AND EXISTS(SELECT 1 FROM category_history WHERE id=NEW.category_id AND book_id=NEW.book_id AND kind=NEW.kind))")
 if name=='book_physical_delete':
  sql=sql.replace(' DELETE FROM categories WHERE book_id=OLD.id;'," DELETE FROM category_history_nodes WHERE snapshot_id IN (SELECT id FROM category_history WHERE book_id=OLD.id);\n DELETE FROM category_history WHERE book_id=OLD.id;\n DELETE FROM categories WHERE book_id=OLD.id;\n DELETE FROM category_references WHERE book_id=OLD.id;")
  sql=sql.replace(" INSERT OR IGNORE INTO book_deletion_resources SELECT substr(icon_key,10) FROM categories", " INSERT OR IGNORE INTO book_deletion_resources SELECT substr(icon_key,10) FROM category_history WHERE book_id=OLD.id AND icon_key LIKE 'resource:%';\n INSERT OR IGNORE INTO book_deletion_resources SELECT substr(n.icon_key,10) FROM category_history_nodes n JOIN category_history h ON h.id=n.snapshot_id WHERE h.book_id=OLD.id AND n.icon_key LIKE 'resource:%';\n INSERT OR IGNORE INTO book_deletion_resources SELECT substr(icon_key,10) FROM categories")
  # Any snapshot may still require a shared attachment/icon.
  sql=sql.replace("AND NOT EXISTS(SELECT 1 FROM accounts WHERE icon_key='resource:'||attachments.relative_path)","AND NOT EXISTS(SELECT 1 FROM accounts WHERE icon_key='resource:'||attachments.relative_path) AND NOT EXISTS(SELECT 1 FROM category_history_nodes WHERE icon_key='resource:'||attachments.relative_path)")
  sql=sql.replace("AND NOT EXISTS(SELECT 1 FROM accounts a WHERE a.icon_key='resource:'||book_deletion_resources.relative_path)","AND NOT EXISTS(SELECT 1 FROM accounts a WHERE a.icon_key='resource:'||book_deletion_resources.relative_path) AND NOT EXISTS(SELECT 1 FROM category_history_nodes n WHERE n.icon_key='resource:'||book_deletion_resources.relative_path)")
 result.append(sql+';')
result += ["""CREATE VIEW v_historical_categories AS SELECT id,book_id,kind,parent_id,name,icon_key,deleted_at_ms,NULL AS frozen_path,NULL AS frozen_root_id,NULL AS frozen_root_name,NULL AS frozen_root_icon FROM categories UNION ALL SELECT id,book_id,kind,NULL,name,icon_key,NULL,path,root_id,root_name,root_icon FROM category_history;""",
"""CREATE TRIGGER category_reference_insert AFTER INSERT ON categories BEGIN INSERT INTO category_references VALUES(NEW.id,NEW.book_id,NEW.kind); END;""",
"""CREATE TRIGGER category_reference_reuse BEFORE INSERT ON categories WHEN EXISTS(SELECT 1 FROM category_references WHERE id=NEW.id) BEGIN SELECT RAISE(ABORT,'CATEGORY_ID_REUSED'); END;""",
"""CREATE TRIGGER category_transaction_insert BEFORE INSERT ON transactions WHEN NEW.category_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM categories WHERE id=NEW.category_id AND book_id=NEW.book_id AND kind=NEW.kind AND deleted_at_ms IS NULL AND archived_at_ms IS NULL) BEGIN SELECT RAISE(ABORT,'CATEGORY_UNAVAILABLE'); END;""",
"""CREATE TRIGGER category_transaction_update BEFORE UPDATE OF category_id ON transactions WHEN NEW.category_id IS NOT OLD.category_id AND NEW.category_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM categories WHERE id=NEW.category_id AND book_id=NEW.book_id AND kind=NEW.kind AND deleted_at_ms IS NULL AND archived_at_ms IS NULL) BEGIN SELECT RAISE(ABORT,'CATEGORY_UNAVAILABLE'); END;""",
"""CREATE TRIGGER category_physical_delete BEFORE DELETE ON categories WHEN NOT EXISTS(SELECT 1 FROM book_deletion_context WHERE book_id=OLD.book_id) BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM categories WHERE parent_id=OLD.id) THEN RAISE(ABORT,'CATEGORY_HAS_CHILDREN') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM budget_lines WHERE category_id=OLD.id) THEN RAISE(ABORT,'CATEGORY_HAS_BUDGET') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM prepaid_events e JOIN prepaid_projects p ON p.id=e.project_id WHERE p.book_id=OLD.book_id AND (json_extract(e.quote_json,'$.entry.categoryId')=OLD.id OR e.transaction_id IN (SELECT id FROM transactions WHERE category_id=OLD.id))) THEN RAISE(ABORT,'CATEGORY_HAS_PREPAID') END;
 SELECT CASE WHEN OLD.deleted_at_ms IS NULL AND OLD.archived_at_ms IS NULL AND NOT EXISTS(SELECT 1 FROM categories WHERE id<>OLD.id AND book_id=OLD.book_id AND kind=OLD.kind AND deleted_at_ms IS NULL AND archived_at_ms IS NULL) THEN RAISE(ABORT,'LAST_ACTIVE_CATEGORY') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM category_delete_tx_proof) OR EXISTS(SELECT 1 FROM category_delete_balance_proof) THEN RAISE(ABORT,'CATEGORY_DELETE_INCOMPLETE') END;
 INSERT INTO category_delete_tx_proof SELECT id,paid_minor,book_minor,revision FROM transactions;
 INSERT INTO category_delete_balance_proof SELECT account_id,balance_minor FROM v_account_balances;
 INSERT INTO category_history SELECT OLD.id,OLD.book_id,OLD.kind,OLD.name,COALESCE(OLD.icon_key,'other'),'',OLD.id,OLD.name,COALESCE(OLD.icon_key,'other'),CAST(strftime('%s','now') AS INTEGER)*1000 WHERE EXISTS(SELECT 1 FROM transactions WHERE category_id=OLD.id);
 INSERT INTO category_history_nodes WITH RECURSIVE path(id,parent_id,name,icon_key,depth) AS (SELECT OLD.id,OLD.parent_id,OLD.name,COALESCE(OLD.icon_key,'other'),0 UNION ALL SELECT c.id,c.parent_id,c.name,COALESCE(c.icon_key,'other'),path.depth+1 FROM categories c JOIN path ON c.id=path.parent_id) SELECT OLD.id,id,parent_id,name,icon_key,depth FROM path WHERE EXISTS(SELECT 1 FROM category_history WHERE id=OLD.id);
 UPDATE category_history SET path=(SELECT group_concat(name,' / ') FROM (SELECT name FROM category_history_nodes WHERE snapshot_id=OLD.id ORDER BY depth DESC)),root_id=(SELECT node_id FROM category_history_nodes WHERE snapshot_id=OLD.id ORDER BY depth DESC LIMIT 1),root_name=(SELECT name FROM category_history_nodes WHERE snapshot_id=OLD.id ORDER BY depth DESC LIMIT 1),root_icon=(SELECT icon_key FROM category_history_nodes WHERE snapshot_id=OLD.id ORDER BY depth DESC LIMIT 1) WHERE id=OLD.id;
END;""",
"""CREATE TRIGGER category_delete_verify AFTER DELETE ON categories WHEN NOT EXISTS(SELECT 1 FROM book_deletion_context WHERE book_id=OLD.book_id) BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM book_deletion_context WHERE book_id=OLD.book_id) AND (EXISTS(SELECT * FROM category_delete_tx_proof EXCEPT SELECT id,paid_minor,book_minor,revision FROM transactions) OR EXISTS(SELECT id,paid_minor,book_minor,revision FROM transactions EXCEPT SELECT * FROM category_delete_tx_proof) OR EXISTS(SELECT * FROM category_delete_balance_proof EXCEPT SELECT account_id,balance_minor FROM v_account_balances) OR EXISTS(SELECT account_id,balance_minor FROM v_account_balances EXCEPT SELECT * FROM category_delete_balance_proof)) THEN RAISE(ABORT,'CATEGORY_DELETE_FINANCE_CHANGED') END;
 DELETE FROM category_references WHERE id=OLD.id AND NOT EXISTS(SELECT 1 FROM category_history WHERE id=OLD.id) AND NOT EXISTS(SELECT 1 FROM transactions WHERE category_id=OLD.id);
 DELETE FROM category_delete_tx_proof;
 DELETE FROM category_delete_balance_proof;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM pragma_foreign_key_check) OR EXISTS(SELECT 1 FROM pragma_quick_check WHERE quick_check<>'ok') THEN RAISE(ABORT,'CATEGORY_DELETE_INTEGRITY') END;
END;""",
"""CREATE TRIGGER category_history_update BEFORE UPDATE ON category_history WHEN NOT EXISTS(SELECT 1 FROM categories WHERE id=OLD.id) BEGIN SELECT RAISE(ABORT,'CATEGORY_HISTORY_IMMUTABLE'); END;""",
"""CREATE TRIGGER category_history_delete BEFORE DELETE ON category_history WHEN NOT EXISTS(SELECT 1 FROM book_deletion_context WHERE book_id=OLD.book_id) BEGIN SELECT RAISE(ABORT,'CATEGORY_HISTORY_IMMUTABLE'); END;""",
"""CREATE TRIGGER category_history_node_update BEFORE UPDATE ON category_history_nodes BEGIN SELECT RAISE(ABORT,'CATEGORY_HISTORY_IMMUTABLE'); END;""",
"""CREATE TRIGGER category_history_node_delete BEFORE DELETE ON category_history_nodes WHEN NOT EXISTS(SELECT 1 FROM category_history h JOIN book_deletion_context c ON c.book_id=h.book_id WHERE h.id=OLD.snapshot_id) BEGIN SELECT RAISE(ABORT,'CATEGORY_HISTORY_IMMUTABLE'); END;""",
"""CREATE TABLE category_migration_check(id INTEGER);""",
"""CREATE TRIGGER category_migration_verify BEFORE INSERT ON category_migration_check BEGIN SELECT CASE WHEN EXISTS(SELECT 1 FROM pragma_foreign_key_check) OR EXISTS(SELECT 1 FROM pragma_quick_check WHERE quick_check<>'ok') OR EXISTS(SELECT * FROM category_migration_tx_proof EXCEPT SELECT * FROM transactions) OR EXISTS(SELECT * FROM transactions EXCEPT SELECT * FROM category_migration_tx_proof) OR EXISTS(SELECT account_id,balance_minor FROM category_migration_balance_proof EXCEPT SELECT account_id,balance_minor FROM v_account_balances) OR EXISTS(SELECT account_id,balance_minor FROM v_account_balances EXCEPT SELECT account_id,balance_minor FROM category_migration_balance_proof) THEN RAISE(ABORT,'CATEGORY_MIGRATION_INTEGRITY') END; END;""",
'INSERT INTO category_migration_check VALUES(1);','DROP TABLE category_migration_check;','DROP TABLE category_migration_tx_proof;','DROP TABLE category_migration_balance_proof;','PRAGMA defer_foreign_keys=OFF;']
# Verify construction and the complete writer-side rebuild before publishing generated files.
db.execute('BEGIN')
for sql in result:db.execute(sql)
db.execute('COMMIT')
f.doCleanups()
raw=('-- Generated by tools/generate-category-deletion-schema.py from checked-in V1–V12; do not hand edit.\n'+'\n\n'.join(result)+'\n').encode()
(ROOT/'docs/database/schema-v13-category-deletion.sql').write_bytes(raw)
(ROOT/'entry/src/main/ets/data/rdb/CategoryDeletionSchema.ets').write_text('// Generated by tools/generate-category-deletion-schema.py; do not hand edit.\n'+f'export const CATEGORY_DELETION_SCHEMA_SHA256: string = "{hashlib.sha256(raw).hexdigest()}";\nexport const CATEGORY_DELETION_SCHEMA_STATEMENTS: string[] = [\n'+',\n'.join('  '+json.dumps(s,ensure_ascii=False) for s in result)+'\n];\n')
print(f'Generated and isolated-validated {len(result)} V13 statements; no device database accessed.')
