-- V2: same-record transfer purpose, fee and repayment coupon. Apply only to the verified V1 schema.
CREATE TABLE transfer_details (
 transaction_id TEXT PRIMARY KEY NOT NULL REFERENCES transactions(id),
 purpose TEXT NOT NULL DEFAULT 'transfer' CHECK(purpose IN ('transfer','credit_repayment','loan_repayment','topup','withdrawal')),
 currency_id TEXT NOT NULL DEFAULT 'CNY' CHECK(currency_id='CNY'),
 from_account_id TEXT NOT NULL,
 to_account_id TEXT NOT NULL,
 out_minor INTEGER NOT NULL CHECK(typeof(out_minor)='integer' AND out_minor BETWEEN 0 AND 9007199254740991),
 in_minor INTEGER NOT NULL CHECK(typeof(in_minor)='integer' AND in_minor BETWEEN 1 AND 9007199254740991),
 fee_minor INTEGER NOT NULL DEFAULT 0 CHECK(typeof(fee_minor)='integer' AND fee_minor BETWEEN 0 AND 9007199254740991),
 coupon_minor INTEGER NOT NULL DEFAULT 0 CHECK(typeof(coupon_minor)='integer' AND coupon_minor BETWEEN 0 AND 9007199254740991),
 fee_in_expense INTEGER NOT NULL DEFAULT 1 CHECK(fee_in_expense=1),
 fee_in_budget INTEGER NOT NULL DEFAULT 1 CHECK(fee_in_budget IN (0,1)),
 FOREIGN KEY(from_account_id,currency_id) REFERENCES accounts(id,currency_id),
 FOREIGN KEY(to_account_id,currency_id) REFERENCES accounts(id,currency_id),
 CHECK(from_account_id<>to_account_id),
 CHECK(coupon_minor<=in_minor AND out_minor=in_minor+fee_minor-coupon_minor),
 CHECK(coupon_minor=0 OR purpose IN ('credit_repayment','loan_repayment')),
 CHECK(fee_in_budget<=fee_in_expense)
);
CREATE TRIGGER transfer_details_insert BEFORE INSERT ON transfer_details
 WHEN NOT EXISTS(SELECT 1 FROM transactions WHERE id=NEW.transaction_id AND kind='transfer' AND posting_state='draft')
 BEGIN SELECT RAISE(ABORT,'transfer details require draft transfer'); END;
CREATE TRIGGER transfer_details_update BEFORE UPDATE ON transfer_details
 WHEN NEW.transaction_id<>OLD.transaction_id OR NOT EXISTS(SELECT 1 FROM transactions WHERE id=OLD.transaction_id AND posting_state='draft')
 BEGIN SELECT RAISE(ABORT,'posted transfer details are immutable'); END;
CREATE TRIGGER transfer_details_delete BEFORE DELETE ON transfer_details
 WHEN EXISTS(SELECT 1 FROM transactions WHERE id=OLD.transaction_id AND posting_state='posted')
 BEGIN SELECT RAISE(ABORT,'posted transfer details cannot be deleted'); END;
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
 SELECT CASE WHEN NEW.kind='transfer' AND NOT EXISTS(SELECT 1 FROM transfer_details WHERE transaction_id=NEW.id) AND (
 (SELECT COUNT(*) FROM account_movements WHERE transaction_id=NEW.id)<>2 OR
 (SELECT COUNT(DISTINCT account_id) FROM account_movements WHERE transaction_id=NEW.id)<>2 OR
 NOT EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg='transfer_out' AND currency_id=NEW.currency_id AND delta_minor=-NEW.paid_minor) OR
 NOT EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg='transfer_in'))
 THEN RAISE(ABORT,'incomplete transfer') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM transfer_details d WHERE d.transaction_id=NEW.id AND (
 NEW.kind<>'transfer' OR NEW.currency_id<>'CNY' OR NEW.book_currency_id<>'CNY' OR NEW.paid_minor<>d.in_minor OR
 EXISTS(SELECT 1 FROM fx_snapshots WHERE transaction_id=NEW.id) OR
 NOT EXISTS(SELECT 1 FROM accounts WHERE id=d.from_account_id AND currency_id='CNY' AND deleted_at_ms IS NULL) OR
 NOT EXISTS(SELECT 1 FROM accounts WHERE id=d.to_account_id AND currency_id='CNY' AND deleted_at_ms IS NULL) OR
 (d.purpose IN ('credit_repayment','loan_repayment') AND NOT EXISTS(SELECT 1 FROM accounts WHERE id=d.to_account_id AND kind='liability')) OR
 (SELECT COUNT(*) FROM account_movements WHERE transaction_id=NEW.id)<>(CASE WHEN d.out_minor=0 THEN 1 ELSE 2 END) OR
 NOT EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg='transfer_in' AND account_id=d.to_account_id AND currency_id='CNY' AND delta_minor=d.in_minor) OR
 (d.out_minor>0 AND NOT EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg='transfer_out' AND account_id=d.from_account_id AND currency_id='CNY' AND delta_minor=-d.out_minor)) OR
 EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg NOT IN ('transfer_out','transfer_in'))))
 THEN RAISE(ABORT,'transfer details do not match actual settlement') END;
 SELECT CASE WHEN NEW.kind<>'transfer' AND ((SELECT COUNT(*) FROM account_movements WHERE transaction_id=NEW.id)>1
 OR EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg<>NEW.kind))
 THEN RAISE(ABORT,'wrong income/expense settlement') END;
 SELECT CASE WHEN (NEW.kind<>'transfer' OR NOT EXISTS(SELECT 1 FROM transfer_details WHERE transaction_id=NEW.id)) AND EXISTS(SELECT 1 FROM account_movements m WHERE m.transaction_id=NEW.id
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

DROP VIEW v_book_totals;
CREATE VIEW v_book_totals AS
 SELECT t.book_id,t.book_currency_id,
 SUM(CASE WHEN t.kind='expense' THEN t.book_minor WHEN t.kind='transfer' AND d.fee_in_expense=1 THEN d.fee_minor ELSE 0 END) AS expense_minor,
 SUM(CASE WHEN t.kind='income' THEN t.book_minor ELSE 0 END) AS income_minor
 FROM v_posted_transactions t LEFT JOIN transfer_details d ON d.transaction_id=t.id GROUP BY t.book_id,t.book_currency_id;
DROP VIEW v_budget_usage;
CREATE VIEW v_budget_usage AS
 SELECT b.id AS budget_id,b.total_minor,COALESCE(SUM(CASE WHEN t.kind='expense' AND t.include_in_budget=1 THEN t.book_minor
 WHEN t.kind='transfer' AND d.fee_in_expense=1 AND d.fee_in_budget=1 THEN d.fee_minor ELSE 0 END),0) AS used_minor
 FROM budgets b LEFT JOIN v_posted_transactions t ON t.book_id=b.book_id
 AND t.occurred_local_date>=b.period_start_date AND t.occurred_local_date<b.period_end_date_exclusive
 LEFT JOIN transfer_details d ON d.transaction_id=t.id WHERE b.deleted_at_ms IS NULL GROUP BY b.id,b.total_minor;
