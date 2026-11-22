"""Generate V14 cleanup guards from checked-in V13, using temporary in-memory SQLite only."""
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'docs/database'))
from verify_category_deletion import CategoryDeletionTests
f=CategoryDeletionTests();f.setUp();f.migrate();db=f.db
result=[
"CREATE TABLE prepaid_cleanup_context(id INTEGER PRIMARY KEY CHECK(id=1),project_id TEXT NOT NULL,book_id TEXT NOT NULL,revision INTEGER NOT NULL);",
"CREATE TABLE prepaid_cleanup_transactions(id TEXT PRIMARY KEY);",
"CREATE TABLE prepaid_cleanup_balances(account_id TEXT PRIMARY KEY,balance_minor INTEGER NOT NULL);",
"CREATE TABLE prepaid_cleanup_resources(relative_path TEXT PRIMARY KEY);"
]
scopes={
'prepaid_project_no_delete': 'OLD.id=(SELECT project_id FROM prepaid_cleanup_context WHERE id=1)',
'prepaid_event_no_delete': 'OLD.project_id=(SELECT project_id FROM prepaid_cleanup_context WHERE id=1)',
'prepaid_allocation_no_delete': 'OLD.event_id IN (SELECT id FROM prepaid_events WHERE project_id=(SELECT project_id FROM prepaid_cleanup_context WHERE id=1))',
'prepaid_attachment_no_delete': 'OLD.event_id IN (SELECT id FROM prepaid_events WHERE project_id=(SELECT project_id FROM prepaid_cleanup_context WHERE id=1))',
 'transaction_hard_delete': 'OLD.id IN (SELECT id FROM prepaid_cleanup_transactions)',
 'movement_delete_guard': 'OLD.transaction_id IN (SELECT id FROM prepaid_cleanup_transactions)',
 'fx_delete_guard': 'OLD.transaction_id IN (SELECT id FROM prepaid_cleanup_transactions)'
}
for name,scope in scopes.items():
 sql=db.execute("SELECT sql FROM sqlite_master WHERE type='trigger' AND name=?",(name,)).fetchone()[0]
 head,body=sql.split('BEGIN',1)
 assert 'WHEN ' in head
 head=head.replace('WHEN ','WHEN (',1).rstrip()+') AND NOT (EXISTS(SELECT 1 FROM prepaid_cleanup_context WHERE id=1) AND ('+scope+'))\n'
 result.extend(['DROP TRIGGER '+name+';',head+'BEGIN'+body+';'])
result.append("""CREATE TRIGGER prepaid_cleanup_execute AFTER INSERT ON prepaid_cleanup_context
BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM prepaid_projects p JOIN books b ON b.id=p.book_id WHERE p.id=NEW.project_id AND p.book_id=NEW.book_id AND p.revision=NEW.revision AND b.deleted_at_ms IS NULL AND b.archived_at_ms IS NULL) THEN RAISE(ABORT,'PREPAID_CHANGED') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM prepaid_events WHERE project_id=NEW.project_id AND deleted_at_ms IS NULL) THEN RAISE(ABORT,'PREPAID_NOT_EMPTY') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM prepaid_cleanup_transactions) OR EXISTS(SELECT 1 FROM prepaid_cleanup_balances) OR EXISTS(SELECT 1 FROM prepaid_cleanup_resources) THEN RAISE(ABORT,'PREPAID_CLEANUP_INCOMPLETE') END;
 INSERT INTO prepaid_cleanup_transactions SELECT transaction_id FROM prepaid_events WHERE project_id=NEW.project_id AND transaction_id IS NOT NULL;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM transactions t JOIN prepaid_cleanup_transactions c ON c.id=t.id WHERE t.deleted_at_ms IS NULL OR t.book_id<>NEW.book_id OR t.kind='transfer')
 OR EXISTS(SELECT 1 FROM expense_recoveries WHERE transaction_id IN (SELECT id FROM prepaid_cleanup_transactions))
 OR EXISTS(SELECT 1 FROM prepaid_events WHERE project_id<>NEW.project_id AND transaction_id IN (SELECT id FROM prepaid_cleanup_transactions))
 OR EXISTS(SELECT 1 FROM prepaid_allocations a JOIN prepaid_events e ON e.id=a.event_id JOIN prepaid_events fund ON fund.id=a.fund_id WHERE (e.project_id=NEW.project_id OR fund.project_id=NEW.project_id) AND e.project_id<>fund.project_id)
 THEN RAISE(ABORT,'PREPAID_LINKED_HISTORY') END;
 INSERT INTO prepaid_cleanup_balances SELECT account_id,balance_minor FROM v_account_balances;
 INSERT OR IGNORE INTO prepaid_cleanup_resources SELECT a.relative_path FROM attachments a JOIN prepaid_event_attachments l ON l.attachment_id=a.id JOIN prepaid_events e ON e.id=l.event_id WHERE e.project_id=NEW.project_id;
 INSERT OR IGNORE INTO prepaid_cleanup_resources SELECT a.relative_path FROM attachments a JOIN transaction_attachments l ON l.attachment_id=a.id WHERE l.transaction_id IN (SELECT id FROM prepaid_cleanup_transactions);
 DELETE FROM prepaid_event_attachments WHERE event_id IN (SELECT id FROM prepaid_events WHERE project_id=NEW.project_id);
 DELETE FROM prepaid_allocations WHERE event_id IN (SELECT id FROM prepaid_events WHERE project_id=NEW.project_id);
 DELETE FROM transaction_attachments WHERE transaction_id IN (SELECT id FROM prepaid_cleanup_transactions);
 DELETE FROM transaction_tags WHERE transaction_id IN (SELECT id FROM prepaid_cleanup_transactions);
 DELETE FROM fx_snapshots WHERE transaction_id IN (SELECT id FROM prepaid_cleanup_transactions);
 DELETE FROM account_movements WHERE transaction_id IN (SELECT id FROM prepaid_cleanup_transactions);
 DELETE FROM prepaid_events WHERE project_id=NEW.project_id;
 DELETE FROM transactions WHERE id IN (SELECT id FROM prepaid_cleanup_transactions);
 DELETE FROM prepaid_projects WHERE id=NEW.project_id;
 DELETE FROM attachments WHERE relative_path IN (SELECT relative_path FROM prepaid_cleanup_resources)
 AND NOT EXISTS(SELECT 1 FROM transaction_attachments WHERE attachment_id=attachments.id)
 AND NOT EXISTS(SELECT 1 FROM prepaid_event_attachments WHERE attachment_id=attachments.id)
 AND NOT EXISTS(SELECT 1 FROM categories WHERE icon_key='resource:'||attachments.relative_path)
 AND NOT EXISTS(SELECT 1 FROM accounts WHERE icon_key='resource:'||attachments.relative_path)
 AND NOT EXISTS(SELECT 1 FROM category_history_nodes WHERE icon_key='resource:'||attachments.relative_path);
 INSERT OR IGNORE INTO book_deletion_files SELECT relative_path FROM prepaid_cleanup_resources WHERE NOT EXISTS(SELECT 1 FROM attachments WHERE relative_path=prepaid_cleanup_resources.relative_path);
 SELECT CASE WHEN (SELECT COUNT(*) FROM prepaid_cleanup_balances)<>(SELECT COUNT(*) FROM v_account_balances) OR EXISTS(SELECT 1 FROM prepaid_cleanup_balances p LEFT JOIN v_account_balances b ON b.account_id=p.account_id WHERE b.account_id IS NULL OR b.balance_minor<>p.balance_minor) THEN RAISE(ABORT,'PREPAID_CLEANUP_BALANCE_CHANGED') END;
 DELETE FROM prepaid_cleanup_resources;
 DELETE FROM prepaid_cleanup_balances;
 DELETE FROM prepaid_cleanup_transactions;
 DELETE FROM prepaid_cleanup_context WHERE id=NEW.id;
END;""")
# Validate schema in isolation. No existing device data is opened or changed.
db.execute('BEGIN')
for sql in result:db.execute(sql)
db.execute('COMMIT');f.doCleanups()
raw=('-- Generated by tools/generate-prepaid-cleanup-schema.py; do not hand edit.\n'+'\n\n'.join(result)+'\n').encode()
(ROOT/'docs/database/schema-v14-prepaid-cleanup.sql').write_bytes(raw)
(ROOT/'entry/src/main/ets/data/rdb/PrepaidCleanupSchema.ets').write_text('// Generated by tools/generate-prepaid-cleanup-schema.py; do not hand edit.\n'+f'export const PREPAID_CLEANUP_SCHEMA_SHA256: string = "{hashlib.sha256(raw).hexdigest()}";\nexport const PREPAID_CLEANUP_SCHEMA_STATEMENTS: string[] = [\n'+',\n'.join('  '+json.dumps(s,ensure_ascii=False) for s in result)+'\n];\n')
print(f'Generated and isolated-validated {len(result)} V14 statements.')
