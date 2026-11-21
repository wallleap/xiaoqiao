-- V12: physically delete an archived book only inside a guarded, balance-preserving operation.
CREATE TABLE book_deletion_context (
 id INTEGER PRIMARY KEY CHECK(id=1), book_id TEXT NOT NULL, revision INTEGER NOT NULL,
 backup_uri TEXT NOT NULL CHECK(length(backup_uri)>0), occurred_at_ms INTEGER NOT NULL
);
CREATE TABLE book_deletion_balances (
 account_id TEXT PRIMARY KEY REFERENCES accounts(id), currency_id TEXT NOT NULL REFERENCES currencies(id),
 expected_minor INTEGER NOT NULL CHECK(typeof(expected_minor)='integer' AND abs(expected_minor)<=9007199254740991),
 carry_minor INTEGER NOT NULL CHECK(typeof(carry_minor)='integer' AND abs(carry_minor)<=9007199254740991),
 adjustment_id TEXT NOT NULL UNIQUE,
 CHECK(abs(expected_minor-carry_minor)<=9007199254740991)
);
CREATE TABLE book_deletion_resources (relative_path TEXT PRIMARY KEY);
CREATE TABLE book_deletion_merchants (id TEXT PRIMARY KEY);
CREATE TABLE book_deletion_files (relative_path TEXT PRIMARY KEY CHECK(length(relative_path) BETWEEN 8 AND 200 AND (relative_path GLOB 'images/*' OR relative_path GLOB 'icons/*') AND relative_path NOT LIKE '%..%'));
CREATE TRIGGER book_deletion_context_insert BEFORE INSERT ON book_deletion_context BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM books WHERE id=NEW.book_id AND revision=NEW.revision AND archived_at_ms IS NOT NULL AND deleted_at_ms IS NULL)
 OR EXISTS(SELECT 1 FROM db_meta WHERE key='active_book_id' AND value=NEW.book_id) THEN RAISE(ABORT,'BOOK_DELETE_UNAVAILABLE') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM v_prepaid_balances WHERE book_id=NEW.book_id AND (remaining_minor<>0 OR remaining_book_minor<>0)) THEN RAISE(ABORT,'BOOK_DELETE_PREPAID_OPEN') END;
END;
CREATE TRIGGER book_deletion_context_update BEFORE UPDATE ON book_deletion_context BEGIN SELECT RAISE(ABORT,'BOOK_DELETE_CONTEXT_LOCKED'); END;

DROP TRIGGER transaction_hard_delete;
CREATE TRIGGER transaction_hard_delete BEFORE DELETE ON transactions
 WHEN (OLD.posting_state='posted') AND NOT EXISTS(SELECT 1 FROM book_deletion_context c JOIN books b ON b.id=c.book_id WHERE c.id=1 AND b.archived_at_ms IS NOT NULL AND b.revision=c.revision AND c.book_id=OLD.book_id)
BEGIN SELECT RAISE(ABORT,'soft delete posted transactions'); END;

DROP TRIGGER movement_delete_guard;
CREATE TRIGGER movement_delete_guard BEFORE DELETE ON account_movements
 WHEN (COALESCE((SELECT posting_state FROM transactions WHERE id=OLD.transaction_id),'draft')='posted'
 OR COALESCE((SELECT posting_state FROM balance_adjustments WHERE id=OLD.adjustment_id),'draft')='posted') AND NOT EXISTS(SELECT 1 FROM book_deletion_context c JOIN books b ON b.id=c.book_id WHERE c.id=1 AND b.archived_at_ms IS NOT NULL AND b.revision=c.revision AND c.book_id=(SELECT book_id FROM transactions WHERE id=OLD.transaction_id))
BEGIN SELECT RAISE(ABORT,'source must be draft'); END;

DROP TRIGGER fx_delete_guard;
CREATE TRIGGER fx_delete_guard BEFORE DELETE ON fx_snapshots
 WHEN ((SELECT posting_state FROM transactions WHERE id=OLD.transaction_id)='posted') AND NOT EXISTS(SELECT 1 FROM book_deletion_context c JOIN books b ON b.id=c.book_id WHERE c.id=1 AND b.archived_at_ms IS NOT NULL AND b.revision=c.revision AND c.book_id=(SELECT book_id FROM transactions WHERE id=OLD.transaction_id))
BEGIN SELECT RAISE(ABORT,'FX source must be draft'); END;

DROP TRIGGER transfer_details_delete;
CREATE TRIGGER transfer_details_delete BEFORE DELETE ON transfer_details
 WHEN (EXISTS(SELECT 1 FROM transactions WHERE id=OLD.transaction_id AND posting_state='posted')) AND NOT EXISTS(SELECT 1 FROM book_deletion_context c JOIN books b ON b.id=c.book_id WHERE c.id=1 AND b.archived_at_ms IS NOT NULL AND b.revision=c.revision AND c.book_id=(SELECT book_id FROM transactions WHERE id=OLD.transaction_id))
BEGIN SELECT RAISE(ABORT,'posted transfer details cannot be deleted'); END;

DROP TRIGGER fx_transfer_details_delete;
CREATE TRIGGER fx_transfer_details_delete BEFORE DELETE ON fx_transfer_details
 WHEN (EXISTS(SELECT 1 FROM transactions WHERE id=OLD.transaction_id AND posting_state='posted')) AND NOT EXISTS(SELECT 1 FROM book_deletion_context c JOIN books b ON b.id=c.book_id WHERE c.id=1 AND b.archived_at_ms IS NOT NULL AND b.revision=c.revision AND c.book_id=(SELECT book_id FROM transactions WHERE id=OLD.transaction_id))
BEGIN SELECT RAISE(ABORT,'posted transfer details cannot be deleted'); END;

DROP TRIGGER recovery_no_hard_delete;
CREATE TRIGGER recovery_no_hard_delete BEFORE DELETE ON expense_recoveries
 WHEN (1) AND NOT EXISTS(SELECT 1 FROM book_deletion_context c JOIN books b ON b.id=c.book_id WHERE c.id=1 AND b.archived_at_ms IS NOT NULL AND b.revision=c.revision AND c.book_id=OLD.book_id)
BEGIN SELECT RAISE(ABORT,'recovery history must be soft-deleted'); END;

DROP TRIGGER import_row_delete_guard;
CREATE TRIGGER import_row_delete_guard BEFORE DELETE ON import_rows
 WHEN ((SELECT status FROM import_batches WHERE id=OLD.batch_id)='committed') AND NOT EXISTS(SELECT 1 FROM book_deletion_context c JOIN books b ON b.id=c.book_id WHERE c.id=1 AND b.archived_at_ms IS NOT NULL AND b.revision=c.revision AND c.book_id=(SELECT book_id FROM import_batches WHERE id=OLD.batch_id))
BEGIN SELECT RAISE(ABORT,'committed import rows are immutable'); END;

DROP TRIGGER prepaid_project_no_delete;
CREATE TRIGGER prepaid_project_no_delete BEFORE DELETE ON prepaid_projects
 WHEN (1) AND NOT EXISTS(SELECT 1 FROM book_deletion_context c JOIN books b ON b.id=c.book_id WHERE c.id=1 AND b.archived_at_ms IS NOT NULL AND b.revision=c.revision AND c.book_id=OLD.book_id)
BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;

DROP TRIGGER prepaid_event_no_delete;
CREATE TRIGGER prepaid_event_no_delete BEFORE DELETE ON prepaid_events
 WHEN (1) AND NOT EXISTS(SELECT 1 FROM book_deletion_context c JOIN books b ON b.id=c.book_id WHERE c.id=1 AND b.archived_at_ms IS NOT NULL AND b.revision=c.revision AND c.book_id=(SELECT book_id FROM prepaid_projects WHERE id=OLD.project_id))
BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;

DROP TRIGGER prepaid_allocation_no_delete;
CREATE TRIGGER prepaid_allocation_no_delete BEFORE DELETE ON prepaid_allocations
 WHEN (1) AND NOT EXISTS(SELECT 1 FROM book_deletion_context c JOIN books b ON b.id=c.book_id WHERE c.id=1 AND b.archived_at_ms IS NOT NULL AND b.revision=c.revision AND c.book_id=(SELECT p.book_id FROM prepaid_events e JOIN prepaid_projects p ON p.id=e.project_id WHERE e.id=OLD.event_id))
BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;

DROP TRIGGER prepaid_attachment_no_delete;
CREATE TRIGGER prepaid_attachment_no_delete BEFORE DELETE ON prepaid_event_attachments
 WHEN (1) AND NOT EXISTS(SELECT 1 FROM book_deletion_context c JOIN books b ON b.id=c.book_id WHERE c.id=1 AND b.archived_at_ms IS NOT NULL AND b.revision=c.revision AND c.book_id=(SELECT p.book_id FROM prepaid_events e JOIN prepaid_projects p ON p.id=e.project_id WHERE e.id=OLD.event_id))
BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;

CREATE TRIGGER book_physical_delete BEFORE DELETE ON books BEGIN
 SELECT CASE WHEN OLD.archived_at_ms IS NULL OR NOT EXISTS(SELECT 1 FROM book_deletion_context WHERE id=1 AND book_id=OLD.id AND revision=OLD.revision)
 OR EXISTS(SELECT 1 FROM db_meta WHERE key='active_book_id' AND value=OLD.id) THEN RAISE(ABORT,'BOOK_DELETE_UNAVAILABLE') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM v_prepaid_balances WHERE book_id=OLD.id AND (remaining_minor<>0 OR remaining_book_minor<>0)) THEN RAISE(ABORT,'BOOK_DELETE_PREPAID_OPEN') END;
 SELECT CASE WHEN (SELECT COUNT(*) FROM book_deletion_balances)<>(SELECT COUNT(*) FROM accounts)
 OR EXISTS(SELECT 1 FROM book_deletion_balances p JOIN accounts a ON a.id=p.account_id WHERE p.currency_id<>a.currency_id OR p.expected_minor<>(SELECT balance_minor FROM v_account_balances WHERE account_id=p.account_id)) THEN RAISE(ABORT,'BOOK_DELETE_BALANCE_CHANGED') END;
 INSERT OR IGNORE INTO book_deletion_resources SELECT a.relative_path FROM attachments a WHERE EXISTS(SELECT 1 FROM transaction_attachments l JOIN transactions t ON t.id=l.transaction_id WHERE l.attachment_id=a.id AND t.book_id=OLD.id) OR EXISTS(SELECT 1 FROM prepaid_event_attachments l JOIN prepaid_events e ON e.id=l.event_id JOIN prepaid_projects p ON p.id=e.project_id WHERE l.attachment_id=a.id AND p.book_id=OLD.id);
 INSERT OR IGNORE INTO book_deletion_resources SELECT substr(icon_key,10) FROM categories WHERE book_id=OLD.id AND icon_key LIKE 'resource:%';
 INSERT OR IGNORE INTO book_deletion_merchants SELECT merchant_id FROM transactions WHERE book_id=OLD.id AND merchant_id IS NOT NULL;
 DELETE FROM transaction_attachments WHERE transaction_id IN (SELECT id FROM transactions WHERE book_id=OLD.id);
 DELETE FROM transaction_tags WHERE book_id=OLD.id;
 DELETE FROM fx_snapshots WHERE transaction_id IN (SELECT id FROM transactions WHERE book_id=OLD.id);
 DELETE FROM account_movements WHERE transaction_id IN (SELECT id FROM transactions WHERE book_id=OLD.id);
 DELETE FROM transfer_details WHERE transaction_id IN (SELECT id FROM transactions WHERE book_id=OLD.id);
 DELETE FROM fx_transfer_details WHERE transaction_id IN (SELECT id FROM transactions WHERE book_id=OLD.id);
 DELETE FROM expense_recoveries WHERE book_id=OLD.id;
 DELETE FROM prepaid_event_attachments WHERE event_id IN (SELECT e.id FROM prepaid_events e JOIN prepaid_projects p ON p.id=e.project_id WHERE p.book_id=OLD.id);
 DELETE FROM prepaid_allocations WHERE event_id IN (SELECT e.id FROM prepaid_events e JOIN prepaid_projects p ON p.id=e.project_id WHERE p.book_id=OLD.id);
 DELETE FROM prepaid_events WHERE project_id IN (SELECT id FROM prepaid_projects WHERE book_id=OLD.id);
 DELETE FROM prepaid_projects WHERE book_id=OLD.id;
 DELETE FROM transactions WHERE book_id=OLD.id;
 DELETE FROM budget_lines WHERE book_id=OLD.id;
 DELETE FROM budget_nature_lines WHERE book_id=OLD.id;
 DELETE FROM budgets WHERE book_id=OLD.id;
 DELETE FROM tags WHERE book_id=OLD.id;
 DELETE FROM categories WHERE book_id=OLD.id;
 DELETE FROM import_rows WHERE batch_id IN (SELECT id FROM import_batches WHERE book_id=OLD.id);
 DELETE FROM import_batches WHERE book_id=OLD.id;
 DELETE FROM merchants WHERE id IN (SELECT id FROM book_deletion_merchants) AND NOT EXISTS(SELECT 1 FROM transactions WHERE merchant_id=merchants.id);
 DELETE FROM attachments WHERE relative_path IN (SELECT relative_path FROM book_deletion_resources) AND NOT EXISTS(SELECT 1 FROM transaction_attachments WHERE attachment_id=attachments.id) AND NOT EXISTS(SELECT 1 FROM prepaid_event_attachments WHERE attachment_id=attachments.id) AND NOT EXISTS(SELECT 1 FROM categories WHERE icon_key='resource:'||attachments.relative_path) AND NOT EXISTS(SELECT 1 FROM accounts WHERE icon_key='resource:'||attachments.relative_path);
 INSERT OR IGNORE INTO book_deletion_files SELECT relative_path FROM book_deletion_resources WHERE NOT EXISTS(SELECT 1 FROM attachments a WHERE a.relative_path=book_deletion_resources.relative_path) AND NOT EXISTS(SELECT 1 FROM categories c WHERE c.icon_key='resource:'||book_deletion_resources.relative_path) AND NOT EXISTS(SELECT 1 FROM accounts a WHERE a.icon_key='resource:'||book_deletion_resources.relative_path);
 INSERT INTO balance_adjustments(id,account_id,kind,before_minor,after_minor,delta_minor,reason,occurred_at_ms,created_at_ms)
 SELECT p.adjustment_id,p.account_id,'calibration',p.expected_minor-p.carry_minor,p.expected_minor,p.carry_minor,'账本删除余额结转',c.occurred_at_ms,c.occurred_at_ms FROM book_deletion_balances p CROSS JOIN book_deletion_context c WHERE p.carry_minor<>0;
 INSERT INTO account_movements(id,account_id,currency_id,adjustment_id,leg,delta_minor,occurred_at_ms)
 SELECT p.adjustment_id||'-movement',p.account_id,p.currency_id,p.adjustment_id,'adjustment',p.carry_minor,c.occurred_at_ms FROM book_deletion_balances p CROSS JOIN book_deletion_context c WHERE p.carry_minor<>0;
 UPDATE balance_adjustments SET posting_state='posted' WHERE id IN (SELECT adjustment_id FROM book_deletion_balances WHERE carry_minor<>0);
 UPDATE accounts SET revision=revision+1,updated_at_ms=(SELECT occurred_at_ms FROM book_deletion_context) WHERE id IN (SELECT account_id FROM book_deletion_balances WHERE carry_minor<>0);
END;
CREATE TRIGGER book_delete_verify AFTER DELETE ON books BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM book_deletion_balances p WHERE p.expected_minor<>(SELECT balance_minor FROM v_account_balances WHERE account_id=p.account_id)) THEN RAISE(ABORT,'BOOK_DELETE_BALANCE_CHANGED') END;
 DELETE FROM book_deletion_balances;
 DELETE FROM book_deletion_resources;
 DELETE FROM book_deletion_merchants;
 DELETE FROM book_deletion_context;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM pragma_foreign_key_check) THEN RAISE(ABORT,'BOOK_DELETE_FOREIGN_KEY') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM pragma_quick_check WHERE quick_check<>'ok') THEN RAISE(ABORT,'BOOK_DELETE_INTEGRITY') END;
END;
