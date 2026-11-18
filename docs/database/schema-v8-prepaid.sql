-- V8: prepaid assets with append-only payments, FIFO cost allocations and linked expenses.
CREATE TABLE prepaid_projects (
 id TEXT PRIMARY KEY NOT NULL,
 book_id TEXT NOT NULL REFERENCES books(id),
 name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 40),
 merchant TEXT NOT NULL DEFAULT '',
 currency_id TEXT NOT NULL REFERENCES currencies(id),
 expiry_date TEXT NOT NULL DEFAULT '' CHECK(expiry_date='' OR (length(expiry_date)=10 AND date(expiry_date)=expiry_date)),
 note TEXT NOT NULL DEFAULT '',
 include_in_net_assets INTEGER NOT NULL DEFAULT 1 CHECK(include_in_net_assets IN (0,1)),
 revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>0),
 created_at_ms INTEGER NOT NULL,
 updated_at_ms INTEGER NOT NULL
);
CREATE TABLE prepaid_events (
 id TEXT PRIMARY KEY NOT NULL,
 project_id TEXT NOT NULL REFERENCES prepaid_projects(id),
 sequence_no INTEGER NOT NULL CHECK(sequence_no>0),
 kind TEXT NOT NULL CHECK(kind IN ('fund','consume','refund')),
 amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor BETWEEN 1 AND 9007199254740991),
 book_minor INTEGER NOT NULL CHECK(typeof(book_minor)='integer' AND book_minor BETWEEN 0 AND 9007199254740991),
 account_id TEXT,
 account_currency_id TEXT NOT NULL REFERENCES currencies(id),
 cash_minor INTEGER NOT NULL DEFAULT 0 CHECK(typeof(cash_minor)='integer' AND cash_minor BETWEEN 0 AND 9007199254740991),
 cash_book_minor INTEGER NOT NULL DEFAULT 0 CHECK(typeof(cash_book_minor)='integer' AND cash_book_minor BETWEEN 0 AND 9007199254740991),
 quote_json TEXT NOT NULL DEFAULT '{}',
 transaction_id TEXT UNIQUE REFERENCES transactions(id),
 local_date TEXT NOT NULL CHECK(length(local_date)=10 AND date(local_date)=local_date),
 occurred_at_ms INTEGER NOT NULL,
 offset_minutes INTEGER NOT NULL CHECK(offset_minutes BETWEEN -840 AND 840),
 note TEXT NOT NULL DEFAULT '',
 posting_state TEXT NOT NULL DEFAULT 'draft' CHECK(posting_state IN ('draft','posted')),
 created_at_ms INTEGER NOT NULL,
 deleted_at_ms INTEGER,
 FOREIGN KEY(account_id,account_currency_id) REFERENCES accounts(id,currency_id),
 UNIQUE(project_id,sequence_no),
 CHECK((kind='consume' AND account_id IS NULL AND cash_minor=0 AND cash_book_minor=0) OR (kind<>'consume' AND account_id IS NOT NULL AND cash_minor>0)),
 CHECK(kind<>'fund' OR (transaction_id IS NULL AND book_minor=cash_book_minor))
);
CREATE TABLE prepaid_allocations (
 event_id TEXT NOT NULL REFERENCES prepaid_events(id),
 fund_id TEXT NOT NULL REFERENCES prepaid_events(id),
 amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor BETWEEN 1 AND 9007199254740991),
 book_minor INTEGER NOT NULL CHECK(typeof(book_minor)='integer' AND book_minor BETWEEN 0 AND 9007199254740991),
 PRIMARY KEY(event_id,fund_id)
);
CREATE TABLE prepaid_event_attachments (
 event_id TEXT NOT NULL REFERENCES prepaid_events(id),
 attachment_id TEXT NOT NULL REFERENCES attachments(id),
 sort_order INTEGER NOT NULL DEFAULT 0,
 PRIMARY KEY(event_id,attachment_id)
);
CREATE INDEX prepaid_book ON prepaid_projects(book_id,created_at_ms,id);
CREATE INDEX prepaid_event_project ON prepaid_events(project_id,sequence_no);
CREATE VIEW v_prepaid_events AS SELECT e.* FROM prepaid_events e WHERE posting_state='posted' AND deleted_at_ms IS NULL;
CREATE VIEW v_prepaid_balances AS
 SELECT p.*,
 COALESCE((SELECT SUM(amount_minor) FROM v_prepaid_events WHERE project_id=p.id AND kind='fund'),0) AS funded_minor,
 COALESCE((SELECT SUM(amount_minor) FROM v_prepaid_events WHERE project_id=p.id AND kind='consume'),0) AS consumed_minor,
 COALESCE((SELECT SUM(amount_minor) FROM v_prepaid_events WHERE project_id=p.id AND kind='refund'),0) AS refunded_minor,
 COALESCE((SELECT SUM(CASE WHEN kind='fund' THEN amount_minor ELSE -amount_minor END) FROM v_prepaid_events WHERE project_id=p.id),0) AS remaining_minor,
 COALESCE((SELECT SUM(CASE WHEN kind='fund' THEN book_minor ELSE -book_minor END) FROM v_prepaid_events WHERE project_id=p.id),0) AS remaining_book_minor
 FROM prepaid_projects p;
CREATE TRIGGER prepaid_project_currency_lock BEFORE UPDATE OF book_id,currency_id ON prepaid_projects
 BEGIN SELECT RAISE(ABORT,'PREPAID_CHANGED'); END;
CREATE TRIGGER prepaid_project_no_delete BEFORE DELETE ON prepaid_projects
 BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;
CREATE TRIGGER prepaid_event_insert BEFORE INSERT ON prepaid_events
 BEGIN
 SELECT CASE WHEN NEW.posting_state<>'draft' THEN RAISE(ABORT,'PREPAID_HISTORY_LOCKED') END;
 SELECT CASE WHEN NEW.account_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM accounts WHERE id=NEW.account_id AND archived_at_ms IS NULL AND deleted_at_ms IS NULL) THEN RAISE(ABORT,'ACCOUNT_UNAVAILABLE') END;
 END;
CREATE TRIGGER prepaid_event_publish BEFORE UPDATE OF posting_state ON prepaid_events
 WHEN OLD.posting_state='draft' AND NEW.posting_state='posted'
 BEGIN
 SELECT CASE WHEN NEW.kind<>'fund' AND ((SELECT COALESCE(SUM(amount_minor),0) FROM prepaid_allocations WHERE event_id=NEW.id)<>NEW.amount_minor OR (SELECT COALESCE(SUM(book_minor),0) FROM prepaid_allocations WHERE event_id=NEW.id)<>NEW.book_minor) THEN RAISE(ABORT,'PREPAID_ALLOCATION') END;
 SELECT CASE WHEN NEW.kind='consume' AND ((NEW.book_minor=0 AND NEW.transaction_id IS NOT NULL) OR (NEW.book_minor>0 AND NOT EXISTS(SELECT 1 FROM transactions t JOIN prepaid_projects p ON p.id=NEW.project_id WHERE t.id=NEW.transaction_id AND t.book_id=p.book_id AND t.kind='expense' AND t.currency_id='CNY' AND t.paid_minor=NEW.book_minor AND t.book_minor=NEW.book_minor AND t.include_in_assets=0 AND t.posting_state='posted' AND t.deleted_at_ms IS NULL AND NOT EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=t.id)))) THEN RAISE(ABORT,'PREPAID_ALLOCATION') END;
 END;
CREATE TRIGGER prepaid_event_locked BEFORE UPDATE OF id,project_id,sequence_no,kind,amount_minor,book_minor,account_id,account_currency_id,cash_minor,cash_book_minor,quote_json,transaction_id,local_date,occurred_at_ms,offset_minutes,note ON prepaid_events
 WHEN OLD.posting_state='posted'
 BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;
CREATE TRIGGER prepaid_event_no_draft BEFORE UPDATE OF posting_state ON prepaid_events
 WHEN OLD.posting_state='posted'
 BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;
CREATE TRIGGER prepaid_event_no_delete BEFORE DELETE ON prepaid_events
 BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;
CREATE TRIGGER prepaid_event_undo BEFORE UPDATE OF deleted_at_ms ON prepaid_events
 WHEN OLD.deleted_at_ms IS NULL AND NEW.deleted_at_ms IS NOT NULL
 BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM v_prepaid_events WHERE project_id=OLD.project_id AND sequence_no>OLD.sequence_no) THEN RAISE(ABORT,'PREPAID_UNDO_ORDER') END;
 END;
CREATE TRIGGER prepaid_allocation_insert BEFORE INSERT ON prepaid_allocations
 BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM prepaid_events e JOIN v_prepaid_events f ON f.id=NEW.fund_id WHERE e.id=NEW.event_id AND e.posting_state='draft' AND e.kind IN ('consume','refund') AND f.kind='fund' AND f.project_id=e.project_id AND f.sequence_no<e.sequence_no) THEN RAISE(ABORT,'PREPAID_ALLOCATION') END;
 SELECT CASE WHEN NEW.amount_minor+COALESCE((SELECT SUM(a.amount_minor) FROM prepaid_allocations a JOIN prepaid_events e ON e.id=a.event_id WHERE a.fund_id=NEW.fund_id AND e.deleted_at_ms IS NULL),0)>(SELECT amount_minor FROM prepaid_events WHERE id=NEW.fund_id) OR NEW.book_minor+COALESCE((SELECT SUM(a.book_minor) FROM prepaid_allocations a JOIN prepaid_events e ON e.id=a.event_id WHERE a.fund_id=NEW.fund_id AND e.deleted_at_ms IS NULL),0)>(SELECT book_minor FROM prepaid_events WHERE id=NEW.fund_id) THEN RAISE(ABORT,'PREPAID_ALLOCATION') END;
 END;
CREATE TRIGGER prepaid_allocation_no_update BEFORE UPDATE ON prepaid_allocations BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;
CREATE TRIGGER prepaid_allocation_no_delete BEFORE DELETE ON prepaid_allocations BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;
CREATE TRIGGER prepaid_transaction_finance_lock BEFORE UPDATE OF posting_state,paid_minor,book_minor,currency_id,category_id,book_id,include_in_assets,include_in_budget,deleted_at_ms ON transactions
 WHEN EXISTS(SELECT 1 FROM v_prepaid_events WHERE transaction_id=OLD.id)
 BEGIN SELECT RAISE(ABORT,'PREPAID_LINKED_TRANSACTION'); END;
CREATE TRIGGER prepaid_account_delete_guard BEFORE UPDATE OF deleted_at_ms ON accounts
 WHEN NEW.deleted_at_ms IS NOT NULL AND EXISTS(SELECT 1 FROM prepaid_events WHERE account_id=OLD.id)
 BEGIN SELECT RAISE(ABORT,'account has prepaid history'); END;
DROP VIEW v_effective_movements;
CREATE VIEW v_effective_movements AS
 SELECT m.* FROM account_movements m JOIN v_posted_transactions t ON t.id=m.transaction_id WHERE t.include_in_assets=1 AND t.balance_mode='apply'
 UNION ALL SELECT m.* FROM account_movements m JOIN balance_adjustments a ON a.id=m.adjustment_id WHERE a.posting_state='posted'
 UNION ALL SELECT r.id,r.account_id,r.account_currency_id,r.transaction_id,NULL,'income',r.account_minor,r.occurred_at_ms FROM v_expense_recoveries r WHERE r.account_id IS NOT NULL AND r.balance_mode='apply'
 UNION ALL SELECT e.id,e.account_id,e.account_currency_id,NULL,NULL,CASE WHEN e.kind='fund' THEN 'expense' ELSE 'income' END,CASE WHEN e.kind='fund' THEN -e.cash_minor ELSE e.cash_minor END,e.occurred_at_ms FROM v_prepaid_events e WHERE e.kind IN ('fund','refund');

CREATE TRIGGER prepaid_attachment_insert BEFORE INSERT ON prepaid_event_attachments
 WHEN NOT EXISTS(SELECT 1 FROM prepaid_events WHERE id=NEW.event_id AND posting_state='draft')
 BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;
CREATE TRIGGER prepaid_attachment_no_update BEFORE UPDATE ON prepaid_event_attachments BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;
CREATE TRIGGER prepaid_attachment_no_delete BEFORE DELETE ON prepaid_event_attachments BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;

CREATE TRIGGER prepaid_event_no_restore BEFORE UPDATE OF deleted_at_ms ON prepaid_events
 WHEN OLD.deleted_at_ms IS NOT NULL
 BEGIN SELECT RAISE(ABORT,'PREPAID_HISTORY_LOCKED'); END;
