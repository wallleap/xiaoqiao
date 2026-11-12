-- Refunds/reimbursements are positive receipts linked to an expense, never ordinary income.
CREATE TABLE expense_recoveries (
  id TEXT PRIMARY KEY NOT NULL,
  transaction_id TEXT NOT NULL REFERENCES transactions(id),
  book_id TEXT NOT NULL REFERENCES books(id),
  kind TEXT NOT NULL CHECK(kind IN ('refund','reimbursement')),
  amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor BETWEEN 1 AND 9007199254740991),
  account_id TEXT REFERENCES accounts(id),
  balance_mode TEXT NOT NULL DEFAULT 'apply' CHECK(balance_mode IN ('apply','preserve')),
  occurred_at_ms INTEGER NOT NULL CHECK(typeof(occurred_at_ms)='integer'),
  local_date TEXT NOT NULL CHECK(length(local_date)=10 AND date(local_date,'+0 days') IS NOT NULL AND date(local_date,'+0 days')=local_date),
  offset_minutes INTEGER NOT NULL CHECK(offset_minutes BETWEEN -840 AND 840),
  note TEXT NOT NULL DEFAULT '',
  import_batch_id TEXT REFERENCES import_batches(id),
  source_record_id TEXT,
  import_row_id TEXT UNIQUE,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>0),
  deleted_at_ms INTEGER,
  FOREIGN KEY(import_row_id,import_batch_id) REFERENCES import_rows(id,batch_id),
  CHECK((import_row_id IS NULL)=(import_batch_id IS NULL)),
  CHECK(balance_mode='apply' OR import_row_id IS NOT NULL)
);
CREATE INDEX recovery_parent ON expense_recoveries(transaction_id,deleted_at_ms);
CREATE INDEX recovery_period ON expense_recoveries(book_id,local_date,deleted_at_ms);
CREATE VIEW v_expense_recoveries AS
 SELECT r.*,t.category_id,t.spending_nature_id,t.include_in_budget,t.merchant_name_snapshot,t.address_text,t.latitude_e6,t.longitude_e6
 FROM expense_recoveries r JOIN v_posted_transactions t ON t.id=r.transaction_id
 WHERE r.deleted_at_ms IS NULL AND (r.import_batch_id IS NULL OR EXISTS(SELECT 1 FROM import_batches b WHERE b.id=r.import_batch_id AND b.status='committed'));
CREATE TRIGGER recovery_insert_guard BEFORE INSERT ON expense_recoveries
BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM transactions t WHERE t.id=NEW.transaction_id AND t.book_id=NEW.book_id AND t.kind='expense' AND t.currency_id='CNY' AND t.book_currency_id='CNY' AND t.book_minor=t.paid_minor AND t.deleted_at_ms IS NULL AND t.posting_state='posted') THEN RAISE(ABORT,'RECOVERY_SOURCE_INVALID') END;
 SELECT CASE WHEN NEW.import_row_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM import_rows WHERE id=NEW.import_row_id AND batch_id=NEW.import_batch_id AND selected=1 AND validation_status IN ('valid','duplicate') AND EXISTS(SELECT 1 FROM import_batches b WHERE b.id=NEW.import_batch_id AND b.book_id=NEW.book_id AND b.balance_mode=NEW.balance_mode AND b.status='committing')) THEN RAISE(ABORT,'RECOVERY_SOURCE_INVALID') END;
 SELECT CASE WHEN NEW.account_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM accounts WHERE id=NEW.account_id AND currency_id='CNY' AND deleted_at_ms IS NULL AND archived_at_ms IS NULL) THEN RAISE(ABORT,'ACCOUNT_UNAVAILABLE') END;
 SELECT CASE WHEN NEW.deleted_at_ms IS NULL AND NEW.amount_minor+COALESCE((SELECT SUM(amount_minor) FROM expense_recoveries WHERE transaction_id=NEW.transaction_id AND deleted_at_ms IS NULL),0)>(SELECT paid_minor FROM transactions WHERE id=NEW.transaction_id) THEN RAISE(ABORT,'RECOVERY_EXCEEDS_PAID') END;
END;
CREATE TRIGGER recovery_update_guard BEFORE UPDATE ON expense_recoveries
BEGIN
 SELECT CASE WHEN NEW.id<>OLD.id OR NEW.transaction_id<>OLD.transaction_id OR NEW.book_id<>OLD.book_id OR NEW.balance_mode<>OLD.balance_mode OR NEW.import_batch_id IS NOT OLD.import_batch_id OR NEW.source_record_id IS NOT OLD.source_record_id OR NEW.import_row_id IS NOT OLD.import_row_id THEN RAISE(ABORT,'RECOVERY_IDENTITY_LOCKED') END;
 SELECT CASE WHEN NEW.deleted_at_ms IS NULL AND NEW.amount_minor+COALESCE((SELECT SUM(amount_minor) FROM expense_recoveries WHERE transaction_id=NEW.transaction_id AND deleted_at_ms IS NULL AND id<>OLD.id),0)>(SELECT paid_minor FROM transactions WHERE id=NEW.transaction_id) THEN RAISE(ABORT,'RECOVERY_EXCEEDS_PAID') END;
 SELECT CASE WHEN NEW.deleted_at_ms IS NULL AND NEW.account_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM accounts WHERE id=NEW.account_id AND currency_id='CNY' AND deleted_at_ms IS NULL AND (archived_at_ms IS NULL OR id=OLD.account_id)) THEN RAISE(ABORT,'ACCOUNT_UNAVAILABLE') END;
END;
CREATE TRIGGER recovered_expense_guard BEFORE UPDATE OF paid_minor,deleted_at_ms,kind,currency_id,book_currency_id ON transactions
WHEN EXISTS(SELECT 1 FROM expense_recoveries WHERE transaction_id=OLD.id AND deleted_at_ms IS NULL)
BEGIN
 SELECT CASE WHEN NEW.deleted_at_ms IS NOT NULL THEN RAISE(ABORT,'EXPENSE_HAS_RECOVERIES') END;
 SELECT CASE WHEN NEW.kind<>'expense' OR NEW.currency_id<>'CNY' OR NEW.book_currency_id<>'CNY' OR NEW.paid_minor<(SELECT SUM(amount_minor) FROM expense_recoveries WHERE transaction_id=OLD.id AND deleted_at_ms IS NULL) THEN RAISE(ABORT,'RECOVERY_EXCEEDS_PAID') END;
END;
CREATE TRIGGER recovery_account_delete_guard BEFORE UPDATE OF deleted_at_ms ON accounts
WHEN NEW.deleted_at_ms IS NOT NULL AND EXISTS(SELECT 1 FROM expense_recoveries WHERE account_id=OLD.id)
BEGIN SELECT RAISE(ABORT,'account has recovery history'); END;
CREATE TRIGGER recovery_account_currency_guard BEFORE UPDATE OF currency_id,kind ON accounts
WHEN (NEW.currency_id<>OLD.currency_id OR NEW.kind<>OLD.kind) AND EXISTS(SELECT 1 FROM expense_recoveries WHERE account_id=OLD.id)
BEGIN SELECT RAISE(ABORT,'account has recovery history'); END;
DROP VIEW v_effective_movements;
CREATE VIEW v_effective_movements AS
 SELECT m.* FROM account_movements m JOIN v_posted_transactions t ON t.id=m.transaction_id WHERE t.include_in_assets=1 AND t.balance_mode='apply'
 UNION ALL SELECT m.* FROM account_movements m JOIN balance_adjustments a ON a.id=m.adjustment_id WHERE a.posting_state='posted'
 UNION ALL SELECT r.id,r.account_id,'CNY',r.transaction_id,NULL,'income',r.amount_minor,r.occurred_at_ms FROM v_expense_recoveries r WHERE r.account_id IS NOT NULL AND r.balance_mode='apply';
DROP VIEW v_book_totals;
CREATE VIEW v_book_totals AS
 SELECT book_id,book_currency_id,SUM(expense_minor) AS expense_minor,SUM(income_minor) AS income_minor FROM (
 SELECT t.book_id,t.book_currency_id,CASE WHEN t.kind='expense' THEN t.book_minor WHEN t.kind='transfer' AND d.fee_in_expense=1 THEN d.fee_minor ELSE 0 END AS expense_minor,CASE WHEN t.kind='income' THEN t.book_minor ELSE 0 END AS income_minor FROM v_posted_transactions t LEFT JOIN transfer_details d ON d.transaction_id=t.id
 UNION ALL SELECT book_id,'CNY',-amount_minor,0 FROM v_expense_recoveries) GROUP BY book_id,book_currency_id;
CREATE VIEW v_budget_expense_flows AS
 SELECT id,book_id,category_id,spending_nature_id,occurred_local_date AS local_date,book_minor AS amount_minor FROM v_posted_transactions WHERE kind='expense' AND include_in_budget=1
 UNION ALL SELECT id,book_id,category_id,spending_nature_id,local_date,-amount_minor FROM v_expense_recoveries WHERE include_in_budget=1
 UNION ALL SELECT t.id,t.book_id,NULL,NULL,t.occurred_local_date,d.fee_minor FROM v_posted_transactions t JOIN transfer_details d ON d.transaction_id=t.id WHERE d.fee_in_expense=1 AND d.fee_in_budget=1;
DROP VIEW v_budget_usage;
CREATE VIEW v_budget_usage AS
 SELECT b.id AS budget_id,b.total_minor,COALESCE(SUM(f.amount_minor),0) AS used_minor FROM budgets b LEFT JOIN v_budget_expense_flows f ON f.book_id=b.book_id AND f.local_date>=b.period_start_date AND f.local_date<b.period_end_date_exclusive WHERE b.deleted_at_ms IS NULL GROUP BY b.id,b.total_minor;
DROP VIEW v_budget_line_usage;
CREATE VIEW v_budget_line_usage AS
 SELECT l.id AS budget_line_id,l.budget_id,l.amount_minor,COALESCE(SUM(f.amount_minor),0) AS used_minor FROM budget_lines l JOIN budgets b ON b.id=l.budget_id LEFT JOIN category_closure c ON c.ancestor_id=l.category_id LEFT JOIN v_budget_expense_flows f ON f.category_id=c.descendant_id AND f.book_id=b.book_id AND f.local_date>=b.period_start_date AND f.local_date<b.period_end_date_exclusive WHERE b.deleted_at_ms IS NULL GROUP BY l.id,l.budget_id,l.amount_minor;

DROP TRIGGER batch_commit;
CREATE TRIGGER batch_commit BEFORE UPDATE OF status ON import_batches WHEN NEW.status='committed' AND OLD.status<>'committed'
BEGIN
 SELECT CASE WHEN NEW.selected_count<>(SELECT COUNT(*) FROM import_rows WHERE batch_id=NEW.id AND selected=1)
 OR NEW.total_count<>(SELECT COUNT(*) FROM import_rows WHERE batch_id=NEW.id)
 OR NEW.selected_count<>((SELECT COUNT(*) FROM transactions WHERE import_batch_id=NEW.id AND posting_state='posted' AND deleted_at_ms IS NULL)+(SELECT COUNT(*) FROM expense_recoveries WHERE import_batch_id=NEW.id AND deleted_at_ms IS NULL))
 THEN RAISE(ABORT,'batch counts/unpublished records mismatch') END;
END;
DROP TRIGGER batch_policy_locked;
CREATE TRIGGER batch_policy_locked BEFORE UPDATE OF balance_mode,book_id ON import_batches
WHEN EXISTS(SELECT 1 FROM transactions WHERE import_batch_id=OLD.id) OR EXISTS(SELECT 1 FROM expense_recoveries WHERE import_batch_id=OLD.id)
BEGIN SELECT RAISE(ABORT,'batch policy is in use'); END;

CREATE TRIGGER recovery_no_hard_delete BEFORE DELETE ON expense_recoveries
BEGIN SELECT RAISE(ABORT,'recovery history must be soft-deleted'); END;
