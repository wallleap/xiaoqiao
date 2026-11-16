-- V7: additive FX settlements; legacy monetary columns are never rewritten.

CREATE TABLE fx_transfer_details (
 transaction_id TEXT PRIMARY KEY NOT NULL REFERENCES transactions(id),
 purpose TEXT NOT NULL DEFAULT 'transfer' CHECK(purpose IN ('transfer','credit_repayment','loan_repayment','topup','withdrawal')),
 currency_id TEXT NOT NULL REFERENCES currencies(id),
 from_account_id TEXT NOT NULL,
 to_account_id TEXT NOT NULL,
 to_currency_id TEXT NOT NULL REFERENCES currencies(id),
 principal_minor INTEGER NOT NULL CHECK(principal_minor>0),
 book_fee_minor INTEGER NOT NULL CHECK(book_fee_minor>=0),
 out_minor INTEGER NOT NULL CHECK(typeof(out_minor)='integer' AND out_minor BETWEEN 0 AND 9007199254740991),
 in_minor INTEGER NOT NULL CHECK(typeof(in_minor)='integer' AND in_minor BETWEEN 1 AND 9007199254740991),
 fee_minor INTEGER NOT NULL DEFAULT 0 CHECK(typeof(fee_minor)='integer' AND fee_minor BETWEEN 0 AND 9007199254740991),
 coupon_minor INTEGER NOT NULL DEFAULT 0 CHECK(typeof(coupon_minor)='integer' AND coupon_minor BETWEEN 0 AND 9007199254740991),
 fee_in_expense INTEGER NOT NULL DEFAULT 1 CHECK(fee_in_expense=1),
 fee_in_budget INTEGER NOT NULL DEFAULT 1 CHECK(fee_in_budget IN (0,1)),
 FOREIGN KEY(from_account_id,currency_id) REFERENCES accounts(id,currency_id),
 FOREIGN KEY(to_account_id,to_currency_id) REFERENCES accounts(id,currency_id),
 CHECK(from_account_id<>to_account_id),
 CHECK(coupon_minor<=principal_minor AND out_minor=principal_minor+fee_minor-coupon_minor),
 CHECK(coupon_minor=0 OR purpose IN ('credit_repayment','loan_repayment')),
 CHECK(fee_in_budget<=fee_in_expense)
);

CREATE TRIGGER fx_transfer_details_insert BEFORE INSERT ON fx_transfer_details
 WHEN NOT EXISTS(SELECT 1 FROM transactions WHERE id=NEW.transaction_id AND kind='transfer' AND posting_state='draft')
 BEGIN SELECT RAISE(ABORT,'transfer details require draft transfer'); END;

CREATE TRIGGER fx_transfer_details_update BEFORE UPDATE ON fx_transfer_details
 WHEN NEW.transaction_id<>OLD.transaction_id OR NOT EXISTS(SELECT 1 FROM transactions WHERE id=OLD.transaction_id AND posting_state='draft')
 BEGIN SELECT RAISE(ABORT,'posted transfer details are immutable'); END;

CREATE TRIGGER fx_transfer_details_delete BEFORE DELETE ON fx_transfer_details
 WHEN EXISTS(SELECT 1 FROM transactions WHERE id=OLD.transaction_id AND posting_state='posted')
 BEGIN SELECT RAISE(ABORT,'posted transfer details cannot be deleted'); END;

CREATE VIEW v_transfer_details AS SELECT d.*,d.currency_id AS to_currency_id,d.in_minor AS principal_minor,d.fee_minor AS book_fee_minor FROM transfer_details d UNION ALL SELECT transaction_id,purpose,currency_id,from_account_id,to_account_id,out_minor,in_minor,fee_minor,coupon_minor,fee_in_expense,fee_in_budget,to_currency_id,principal_minor,book_fee_minor FROM fx_transfer_details;

ALTER TABLE expense_recoveries ADD COLUMN book_minor INTEGER CHECK(book_minor>=0);

ALTER TABLE expense_recoveries ADD COLUMN account_minor INTEGER CHECK(account_minor>0);

ALTER TABLE expense_recoveries ADD COLUMN account_currency_id TEXT REFERENCES currencies(id);

ALTER TABLE expense_recoveries ADD COLUMN fx_snapshot TEXT NOT NULL DEFAULT '';

DROP VIEW v_expense_recoveries;

CREATE VIEW v_expense_recoveries AS SELECT r.id,r.transaction_id,r.book_id,r.kind,r.amount_minor,r.account_id,r.balance_mode,r.occurred_at_ms,r.local_date,r.offset_minutes,r.note,r.import_batch_id,r.source_record_id,r.import_row_id,r.created_at_ms,r.updated_at_ms,r.revision,r.deleted_at_ms,COALESCE(r.book_minor,r.amount_minor) AS book_minor,COALESCE(r.account_minor,r.amount_minor) AS account_minor,COALESCE(r.account_currency_id,t.currency_id) AS account_currency_id,r.fx_snapshot,t.currency_id,t.book_currency_id,t.category_id,t.spending_nature_id,t.include_in_budget,t.merchant_name_snapshot,t.address_text,t.latitude_e6,t.longitude_e6 FROM expense_recoveries r JOIN v_posted_transactions t ON t.id=r.transaction_id WHERE r.deleted_at_ms IS NULL AND (r.import_batch_id IS NULL OR EXISTS(SELECT 1 FROM import_batches b WHERE b.id=r.import_batch_id AND b.status='committed'));

DROP TRIGGER recovery_insert_guard;

CREATE TRIGGER recovery_insert_guard BEFORE INSERT ON expense_recoveries
BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM transactions t WHERE t.id=NEW.transaction_id AND t.book_id=NEW.book_id AND t.kind='expense' AND t.deleted_at_ms IS NULL AND t.posting_state='posted') THEN RAISE(ABORT,'RECOVERY_SOURCE_INVALID') END;
 SELECT CASE WHEN NEW.import_row_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM import_rows WHERE id=NEW.import_row_id AND batch_id=NEW.import_batch_id AND selected=1 AND validation_status IN ('valid','duplicate') AND EXISTS(SELECT 1 FROM import_batches b WHERE b.id=NEW.import_batch_id AND b.book_id=NEW.book_id AND b.balance_mode=NEW.balance_mode AND b.status='committing')) THEN RAISE(ABORT,'RECOVERY_SOURCE_INVALID') END;
 SELECT CASE WHEN NEW.account_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM accounts WHERE id=NEW.account_id AND currency_id=COALESCE(NEW.account_currency_id,(SELECT currency_id FROM transactions WHERE id=NEW.transaction_id)) AND deleted_at_ms IS NULL AND archived_at_ms IS NULL) THEN RAISE(ABORT,'ACCOUNT_UNAVAILABLE') END;
 SELECT CASE WHEN NEW.deleted_at_ms IS NULL AND NEW.amount_minor+COALESCE((SELECT SUM(amount_minor) FROM expense_recoveries WHERE transaction_id=NEW.transaction_id AND deleted_at_ms IS NULL),0)>(SELECT paid_minor FROM transactions WHERE id=NEW.transaction_id) THEN RAISE(ABORT,'RECOVERY_EXCEEDS_PAID') END;
END;

DROP TRIGGER recovery_update_guard;

CREATE TRIGGER recovery_update_guard BEFORE UPDATE ON expense_recoveries
BEGIN
 SELECT CASE WHEN NEW.id<>OLD.id OR NEW.transaction_id<>OLD.transaction_id OR NEW.book_id<>OLD.book_id OR NEW.balance_mode<>OLD.balance_mode OR NEW.import_batch_id IS NOT OLD.import_batch_id OR NEW.source_record_id IS NOT OLD.source_record_id OR NEW.import_row_id IS NOT OLD.import_row_id THEN RAISE(ABORT,'RECOVERY_IDENTITY_LOCKED') END;
 SELECT CASE WHEN NEW.deleted_at_ms IS NULL AND NEW.amount_minor+COALESCE((SELECT SUM(amount_minor) FROM expense_recoveries WHERE transaction_id=NEW.transaction_id AND deleted_at_ms IS NULL AND id<>OLD.id),0)>(SELECT paid_minor FROM transactions WHERE id=NEW.transaction_id) THEN RAISE(ABORT,'RECOVERY_EXCEEDS_PAID') END;
 SELECT CASE WHEN NEW.deleted_at_ms IS NULL AND NEW.account_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM accounts WHERE id=NEW.account_id AND currency_id=COALESCE(NEW.account_currency_id,(SELECT currency_id FROM transactions WHERE id=NEW.transaction_id)) AND deleted_at_ms IS NULL AND (archived_at_ms IS NULL OR id=OLD.account_id)) THEN RAISE(ABORT,'ACCOUNT_UNAVAILABLE') END;
END;

DROP TRIGGER recovered_expense_guard;

CREATE TRIGGER recovered_expense_guard BEFORE UPDATE OF paid_minor,book_minor,deleted_at_ms,kind,currency_id,book_currency_id ON transactions
WHEN EXISTS(SELECT 1 FROM expense_recoveries WHERE transaction_id=OLD.id AND deleted_at_ms IS NULL)
BEGIN
 SELECT CASE WHEN NEW.deleted_at_ms IS NOT NULL THEN RAISE(ABORT,'EXPENSE_HAS_RECOVERIES') END;
 SELECT CASE WHEN NEW.kind<>'expense' OR NEW.currency_id<>OLD.currency_id OR NEW.book_currency_id<>OLD.book_currency_id OR NEW.paid_minor<(SELECT SUM(amount_minor) FROM expense_recoveries WHERE transaction_id=OLD.id AND deleted_at_ms IS NULL) OR NEW.book_minor<(SELECT SUM(COALESCE(book_minor,amount_minor)) FROM expense_recoveries WHERE transaction_id=OLD.id AND deleted_at_ms IS NULL) THEN RAISE(ABORT,'RECOVERY_EXCEEDS_PAID') END;
END;

DROP TRIGGER transaction_publish;

CREATE TRIGGER transaction_publish BEFORE UPDATE OF posting_state ON transactions
 WHEN NEW.posting_state='posted' AND OLD.posting_state='draft'
 BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM books WHERE id=NEW.book_id AND deleted_at_ms IS NULL)
 OR (NEW.category_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM categories WHERE id=NEW.category_id AND deleted_at_ms IS NULL))
 OR EXISTS(SELECT 1 FROM account_movements m JOIN accounts a ON a.id=m.account_id WHERE m.transaction_id=NEW.id AND a.deleted_at_ms IS NOT NULL)
 THEN RAISE(ABORT,'source entity is deleted') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND occurred_at_ms<>NEW.occurred_at_ms)
 THEN RAISE(ABORT,'settlement time mismatch') END;
 SELECT CASE WHEN NEW.currency_id=NEW.book_currency_id AND NEW.paid_minor<>NEW.book_minor
 THEN RAISE(ABORT,'same currency book amount mismatch') END;
 SELECT CASE WHEN NEW.currency_id<>NEW.book_currency_id AND NEW.book_minor IS NOT NULL AND NOT EXISTS(
 SELECT 1 FROM fx_snapshots f WHERE f.transaction_id=NEW.id AND f.role='book'
 AND f.from_currency_id=NEW.currency_id AND f.to_currency_id=NEW.book_currency_id
 AND f.from_minor=NEW.paid_minor AND f.to_minor=NEW.book_minor)
 THEN RAISE(ABORT,'missing book FX snapshot') END;
 SELECT CASE WHEN NEW.kind='transfer' AND NOT EXISTS(SELECT 1 FROM v_transfer_details WHERE transaction_id=NEW.id) AND (
 (SELECT COUNT(*) FROM account_movements WHERE transaction_id=NEW.id)<>2 OR
 (SELECT COUNT(DISTINCT account_id) FROM account_movements WHERE transaction_id=NEW.id)<>2 OR
 NOT EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg='transfer_out' AND currency_id=NEW.currency_id AND delta_minor=-NEW.paid_minor) OR
 NOT EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg='transfer_in'))
 THEN RAISE(ABORT,'incomplete transfer') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM v_transfer_details d WHERE d.transaction_id=NEW.id AND (
 NEW.kind<>'transfer' OR NEW.currency_id<>d.currency_id OR NEW.paid_minor<>d.principal_minor OR
 NOT EXISTS(SELECT 1 FROM accounts WHERE id=d.from_account_id AND currency_id=d.currency_id AND deleted_at_ms IS NULL) OR
 NOT EXISTS(SELECT 1 FROM accounts WHERE id=d.to_account_id AND currency_id=d.to_currency_id AND deleted_at_ms IS NULL) OR
 (d.purpose IN ('credit_repayment','loan_repayment') AND NOT EXISTS(SELECT 1 FROM accounts WHERE id=d.to_account_id AND kind='liability')) OR
 (SELECT COUNT(*) FROM account_movements WHERE transaction_id=NEW.id)<>(CASE WHEN d.out_minor=0 THEN 1 ELSE 2 END) OR
 NOT EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg='transfer_in' AND account_id=d.to_account_id AND currency_id=d.to_currency_id AND delta_minor=d.in_minor) OR
 (d.out_minor>0 AND NOT EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg='transfer_out' AND account_id=d.from_account_id AND currency_id=d.currency_id AND delta_minor=-d.out_minor)) OR
 EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg NOT IN ('transfer_out','transfer_in'))))
 THEN RAISE(ABORT,'transfer details do not match actual settlement') END;
 SELECT CASE WHEN NEW.kind<>'transfer' AND ((SELECT COUNT(*) FROM account_movements WHERE transaction_id=NEW.id)>1
 OR EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg<>NEW.kind))
 THEN RAISE(ABORT,'wrong income/expense settlement') END;
 SELECT CASE WHEN (NEW.kind<>'transfer' OR NOT EXISTS(SELECT 1 FROM v_transfer_details WHERE transaction_id=NEW.id)) AND EXISTS(SELECT 1 FROM account_movements m WHERE m.transaction_id=NEW.id
 AND m.currency_id=NEW.currency_id AND abs(m.delta_minor)<>NEW.paid_minor)
 THEN RAISE(ABORT,'same currency settlement mismatch') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM account_movements m WHERE m.transaction_id=NEW.id AND m.currency_id<>NEW.currency_id
 AND NOT EXISTS(SELECT 1 FROM fx_snapshots f WHERE f.transaction_id=NEW.id AND f.role='settlement' AND f.account_movement_id=m.id
 AND f.from_currency_id=NEW.currency_id AND f.to_currency_id=m.currency_id AND f.from_minor=NEW.paid_minor AND f.to_minor=abs(m.delta_minor)))
 THEN RAISE(ABORT,'missing settlement FX snapshot') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM fx_snapshots f WHERE f.transaction_id=NEW.id AND (
 f.from_currency_id<>NEW.currency_id OR f.from_minor<>NEW.paid_minor OR
 (f.role='book' AND (NEW.book_minor IS NULL OR f.to_currency_id<>NEW.book_currency_id OR f.to_minor<>NEW.book_minor)) OR
 (f.role='settlement' AND NOT EXISTS(SELECT 1 FROM account_movements m WHERE m.id=f.account_movement_id AND m.transaction_id=NEW.id
 AND m.currency_id=f.to_currency_id AND abs(m.delta_minor)=f.to_minor))))
 THEN RAISE(ABORT,'FX snapshot does not match transaction') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM transaction_attachments a JOIN attachments f ON f.id=a.attachment_id
 WHERE a.transaction_id=NEW.id AND (f.state<>'ready' OR f.deleted_at_ms IS NOT NULL))
 THEN RAISE(ABORT,'attachment not ready') END;
 SELECT CASE WHEN NEW.import_row_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM import_rows r WHERE r.id=NEW.import_row_id AND r.selected=1
 AND r.validation_status IN ('valid','duplicate') AND (r.validation_status<>'duplicate' OR NEW.duplicate_override=1))
 THEN RAISE(ABORT,'import row not selected/confirmed') END;
 END;

DROP VIEW v_effective_movements;

CREATE VIEW v_effective_movements AS
 SELECT m.* FROM account_movements m JOIN v_posted_transactions t ON t.id=m.transaction_id WHERE t.include_in_assets=1 AND t.balance_mode='apply'
 UNION ALL SELECT m.* FROM account_movements m JOIN balance_adjustments a ON a.id=m.adjustment_id WHERE a.posting_state='posted'
 UNION ALL SELECT r.id,r.account_id,r.account_currency_id,r.transaction_id,NULL,'income',r.account_minor,r.occurred_at_ms FROM v_expense_recoveries r WHERE r.account_id IS NOT NULL AND r.balance_mode='apply';

DROP VIEW v_book_totals;

CREATE VIEW v_book_totals AS
 SELECT book_id,book_currency_id,SUM(expense_minor) AS expense_minor,SUM(income_minor) AS income_minor FROM (
 SELECT t.book_id,t.book_currency_id,CASE WHEN t.kind='expense' THEN t.book_minor WHEN t.kind='transfer' AND d.fee_in_expense=1 THEN d.book_fee_minor ELSE 0 END AS expense_minor,CASE WHEN t.kind='income' THEN t.book_minor ELSE 0 END AS income_minor FROM v_posted_transactions t LEFT JOIN v_transfer_details d ON d.transaction_id=t.id
 UNION ALL SELECT book_id,book_currency_id,-book_minor,0 FROM v_expense_recoveries) GROUP BY book_id,book_currency_id;

DROP VIEW v_budget_expense_flows;

CREATE VIEW v_budget_expense_flows AS
 SELECT id,book_id,category_id,spending_nature_id,occurred_local_date AS local_date,book_minor AS amount_minor FROM v_posted_transactions WHERE kind='expense' AND include_in_budget=1
 UNION ALL SELECT id,book_id,category_id,spending_nature_id,local_date,-book_minor FROM v_expense_recoveries WHERE include_in_budget=1
 UNION ALL SELECT t.id,t.book_id,NULL,NULL,t.occurred_local_date,d.book_fee_minor FROM v_posted_transactions t JOIN v_transfer_details d ON d.transaction_id=t.id WHERE d.fee_in_expense=1 AND d.fee_in_budget=1;
