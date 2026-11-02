-- 小巧记账 V1 评审用DDL。只在纯内存SQLite测试；不是已授权的应用迁移。
-- 金额上限为ArkTS安全整数；累计溢出须交给域层精确求和，不得转REAL。
PRAGMA foreign_keys = ON;

CREATE TABLE db_meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
);
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY CHECK(typeof(version)='integer' AND version>0),
  checksum TEXT NOT NULL,
  applied_at_ms INTEGER NOT NULL
);
CREATE TABLE currencies (
  id TEXT PRIMARY KEY NOT NULL,
  code TEXT NOT NULL CHECK(length(code)=3 AND code NOT GLOB '*[^A-Z]*'),
  numeric_code TEXT,
  name TEXT NOT NULL,
  symbol TEXT NOT NULL,
  minor_unit INTEGER NOT NULL CHECK(typeof(minor_unit)='integer' AND minor_unit BETWEEN 0 AND 4),
  valid_from TEXT NOT NULL,
  valid_to TEXT,
  source_version TEXT NOT NULL,
  is_enabled INTEGER NOT NULL DEFAULT 1 CHECK(is_enabled IN (0,1)),
  UNIQUE(code, valid_from)
);
CREATE TABLE fx_quotes (
  id TEXT PRIMARY KEY NOT NULL,
  from_currency_id TEXT NOT NULL REFERENCES currencies(id),
  to_currency_id TEXT NOT NULL REFERENCES currencies(id),
  rate_decimal TEXT NOT NULL CHECK(typeof(rate_decimal)='text' AND length(rate_decimal) BETWEEN 1 AND 64
    AND rate_decimal NOT GLOB '*[^0-9.]*' AND rate_decimal NOT LIKE '%.%.%'
    AND substr(rate_decimal,1,1)<>'.' AND substr(rate_decimal,-1)<>'.' AND rate_decimal GLOB '*[1-9]*'),
  provider TEXT NOT NULL,
  quoted_at_ms INTEGER NOT NULL,
  fetched_at_ms INTEGER NOT NULL,
  CHECK(from_currency_id<>to_currency_id)
);
CREATE TABLE books (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  base_currency_id TEXT NOT NULL REFERENCES currencies(id),
  timezone TEXT NOT NULL,
  icon_key TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  archived_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1 CHECK(typeof(revision)='integer' AND revision>0),
  deleted_at_ms INTEGER
);
-- 账户全局共享，不含book_id；余额从有效资金变动推导。
CREATE TABLE accounts (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK(kind IN ('asset','liability')),
  currency_id TEXT NOT NULL REFERENCES currencies(id),
  brand TEXT,
  icon_key TEXT,
  icon_variant TEXT CHECK(icon_variant IN ('monochrome','color')),
  brand_color TEXT,
  include_in_net_assets INTEGER NOT NULL DEFAULT 1 CHECK(include_in_net_assets IN (0,1)),
  sort_order INTEGER NOT NULL DEFAULT 0,
  archived_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1 CHECK(typeof(revision)='integer' AND revision>0),
  deleted_at_ms INTEGER,
  UNIQUE(id,currency_id)
);
CREATE TABLE categories (
  id TEXT PRIMARY KEY NOT NULL,
  book_id TEXT NOT NULL REFERENCES books(id),
  kind TEXT NOT NULL CHECK(kind IN ('expense','income')),
  parent_id TEXT,
  name TEXT NOT NULL,
  name_key TEXT NOT NULL,
  icon_key TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  archived_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>0),
  deleted_at_ms INTEGER,
  UNIQUE(id,book_id,kind),
  FOREIGN KEY(parent_id,book_id,kind) REFERENCES categories(id,book_id,kind),
  CHECK(parent_id IS NULL OR parent_id<>id)
);
CREATE UNIQUE INDEX category_sibling_name ON categories(book_id,kind,COALESCE(parent_id,''),name_key)
  WHERE deleted_at_ms IS NULL;
CREATE TABLE tags (
  id TEXT PRIMARY KEY NOT NULL,
  book_id TEXT NOT NULL REFERENCES books(id),
  name TEXT NOT NULL,
  name_key TEXT NOT NULL,
  color_token TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>0),
  deleted_at_ms INTEGER,
  UNIQUE(id,book_id)
);
CREATE UNIQUE INDEX tag_name ON tags(book_id,name_key) WHERE deleted_at_ms IS NULL;
CREATE TABLE merchants (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  normalized_name TEXT NOT NULL,
  default_address TEXT,
  archived_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>0),
  deleted_at_ms INTEGER
);
CREATE TABLE import_profiles (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  profile_version INTEGER NOT NULL CHECK(profile_version>0),
  parse_options_json TEXT NOT NULL,
  column_mapping_json TEXT NOT NULL,
  value_mapping_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE TABLE import_batches (
  id TEXT PRIMARY KEY NOT NULL,
  book_id TEXT NOT NULL REFERENCES books(id),
  file_sha256 TEXT NOT NULL,
  file_name TEXT NOT NULL,
  sheet_name TEXT,
  header_row INTEGER NOT NULL CHECK(header_row>0),
  encoding TEXT,
  delimiter TEXT,
  profile_snapshot_json TEXT NOT NULL,
  balance_mode TEXT NOT NULL DEFAULT 'preserve' CHECK(balance_mode IN ('apply','preserve')),
  status TEXT NOT NULL DEFAULT 'staged' CHECK(status IN ('staged','validated','committing','committed','failed')),
  total_count INTEGER NOT NULL CHECK(total_count>=0),
  selected_count INTEGER NOT NULL DEFAULT 0 CHECK(selected_count>=0),
  skipped_count INTEGER NOT NULL DEFAULT 0 CHECK(skipped_count>=0),
  confirmed_at_ms INTEGER,
  committed_at_ms INTEGER,
  error_code TEXT,
  created_at_ms INTEGER NOT NULL,
  CHECK(selected_count+skipped_count<=total_count),
  CHECK(status NOT IN ('committing','committed') OR confirmed_at_ms IS NOT NULL),
  CHECK(status<>'committed' OR (committed_at_ms IS NOT NULL AND selected_count+skipped_count=total_count)),
  UNIQUE(id,book_id,balance_mode)
);
CREATE TABLE import_rows (
  id TEXT PRIMARY KEY NOT NULL,
  batch_id TEXT NOT NULL REFERENCES import_batches(id),
  sheet_name TEXT NOT NULL DEFAULT '',
  row_number INTEGER NOT NULL CHECK(row_number>0),
  raw_json TEXT NOT NULL,
  normalized_json TEXT,
  validation_status TEXT NOT NULL DEFAULT 'pending' CHECK(validation_status IN ('pending','valid','duplicate','invalid')),
  issue_codes_json TEXT NOT NULL DEFAULT '[]',
  duplicate_candidate_ids_json TEXT NOT NULL DEFAULT '[]',
  selected INTEGER NOT NULL DEFAULT 0 CHECK(selected IN (0,1)),
  UNIQUE(batch_id,sheet_name,row_number),
  UNIQUE(id,batch_id),
  CHECK(selected=0 OR validation_status IN ('valid','duplicate'))
);
CREATE TABLE transactions (
  id TEXT PRIMARY KEY NOT NULL,
  book_id TEXT NOT NULL REFERENCES books(id),
  kind TEXT NOT NULL CHECK(kind IN ('expense','income','transfer')),
  group_id TEXT,
  category_id TEXT,
  currency_id TEXT NOT NULL REFERENCES currencies(id),
  gross_minor INTEGER NOT NULL CHECK(typeof(gross_minor)='integer' AND gross_minor BETWEEN 1 AND 9007199254740991),
  discount_minor INTEGER NOT NULL DEFAULT 0 CHECK(typeof(discount_minor)='integer' AND discount_minor BETWEEN 0 AND 9007199254740991),
  paid_minor INTEGER NOT NULL CHECK(typeof(paid_minor)='integer' AND paid_minor BETWEEN 1 AND 9007199254740991),
  book_currency_id TEXT NOT NULL REFERENCES currencies(id),
  book_minor INTEGER CHECK(book_minor IS NULL OR (typeof(book_minor)='integer' AND book_minor BETWEEN 0 AND 9007199254740991)),
  include_in_budget INTEGER NOT NULL DEFAULT 0 CHECK(include_in_budget IN (0,1)),
  include_in_assets INTEGER NOT NULL DEFAULT 1 CHECK(include_in_assets IN (0,1)),
  balance_mode TEXT NOT NULL DEFAULT 'apply' CHECK(balance_mode IN ('apply','preserve')),
  reimbursement_status TEXT NOT NULL DEFAULT 'none' CHECK(reimbursement_status IN ('none','pending')),
  merchant_id TEXT REFERENCES merchants(id),
  merchant_name_snapshot TEXT,
  address_text TEXT,
  latitude_e6 INTEGER CHECK(latitude_e6 IS NULL OR (typeof(latitude_e6)='integer' AND latitude_e6 BETWEEN -90000000 AND 90000000)),
  longitude_e6 INTEGER CHECK(longitude_e6 IS NULL OR (typeof(longitude_e6)='integer' AND longitude_e6 BETWEEN -180000000 AND 180000000)),
  note TEXT NOT NULL DEFAULT '',
  import_batch_id TEXT,
  import_row_id TEXT UNIQUE,
  source_provider TEXT,
  source_namespace TEXT,
  source_record_id TEXT,
  source_fingerprint TEXT,
  duplicate_override INTEGER NOT NULL DEFAULT 0 CHECK(duplicate_override IN (0,1)),
  occurred_at_ms INTEGER NOT NULL CHECK(typeof(occurred_at_ms)='integer'),
  occurred_local_date TEXT NOT NULL CHECK(length(occurred_local_date)=10
    AND date(occurred_local_date,'+0 days') IS NOT NULL
    AND date(occurred_local_date,'+0 days')=occurred_local_date),
  occurred_timezone TEXT NOT NULL,
  occurred_offset_minutes INTEGER NOT NULL CHECK(occurred_offset_minutes BETWEEN -840 AND 840),
  posting_state TEXT NOT NULL DEFAULT 'draft' CHECK(posting_state IN ('draft','posted')),
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1 CHECK(typeof(revision)='integer' AND revision>0),
  deleted_at_ms INTEGER,
  UNIQUE(id,book_id),
  FOREIGN KEY(category_id,book_id,kind) REFERENCES categories(id,book_id,kind),
  FOREIGN KEY(import_row_id,import_batch_id) REFERENCES import_rows(id,batch_id),
  FOREIGN KEY(import_batch_id,book_id,balance_mode) REFERENCES import_batches(id,book_id,balance_mode),
  CHECK((latitude_e6 IS NULL)=(longitude_e6 IS NULL)),
  CHECK(kind='transfer' OR book_minor IS NOT NULL),
  CHECK(gross_minor-discount_minor=paid_minor),
  CHECK(kind='expense' OR (discount_minor=0 AND include_in_budget=0 AND reimbursement_status='none')),
  CHECK((kind='transfer' AND category_id IS NULL) OR (kind<>'transfer' AND category_id IS NOT NULL)),
  CHECK((import_batch_id IS NULL)=(import_row_id IS NULL)),
  CHECK(balance_mode='apply' OR import_row_id IS NOT NULL),
  CHECK(source_record_id IS NULL OR typeof(source_record_id)='text')
);
CREATE TABLE transaction_tags (
  transaction_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  book_id TEXT NOT NULL,
  PRIMARY KEY(transaction_id,tag_id),
  FOREIGN KEY(transaction_id,book_id) REFERENCES transactions(id,book_id),
  FOREIGN KEY(tag_id,book_id) REFERENCES tags(id,book_id)
);
CREATE TABLE balance_adjustments (
  id TEXT PRIMARY KEY NOT NULL,
  account_id TEXT NOT NULL REFERENCES accounts(id),
  kind TEXT NOT NULL CHECK(kind IN ('opening','calibration')),
  before_minor INTEGER NOT NULL CHECK(typeof(before_minor)='integer' AND before_minor BETWEEN -9007199254740991 AND 9007199254740991),
  after_minor INTEGER NOT NULL CHECK(typeof(after_minor)='integer' AND after_minor BETWEEN -9007199254740991 AND 9007199254740991),
  delta_minor INTEGER NOT NULL CHECK(typeof(delta_minor)='integer' AND delta_minor BETWEEN -9007199254740991 AND 9007199254740991),
  reversal_of_id TEXT UNIQUE REFERENCES balance_adjustments(id),
  reason TEXT NOT NULL,
  occurred_at_ms INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>0),
  posting_state TEXT NOT NULL DEFAULT 'draft' CHECK(posting_state IN ('draft','posted')),
  CHECK(after_minor-before_minor=delta_minor),
  CHECK(kind<>'opening' OR (before_minor=0 AND reversal_of_id IS NULL)),
  CHECK(kind='opening' OR delta_minor<>0),
  CHECK(reversal_of_id IS NULL OR reversal_of_id<>id)
);
CREATE UNIQUE INDEX one_opening_per_account ON balance_adjustments(account_id) WHERE kind='opening';
CREATE TABLE account_movements (
  id TEXT PRIMARY KEY NOT NULL,
  account_id TEXT NOT NULL,
  currency_id TEXT NOT NULL,
  transaction_id TEXT REFERENCES transactions(id),
  adjustment_id TEXT REFERENCES balance_adjustments(id),
  leg TEXT NOT NULL CHECK(leg IN ('expense','income','transfer_out','transfer_in','adjustment')),
  delta_minor INTEGER NOT NULL CHECK(typeof(delta_minor)='integer' AND delta_minor BETWEEN -9007199254740991 AND 9007199254740991),
  occurred_at_ms INTEGER NOT NULL,
  FOREIGN KEY(account_id,currency_id) REFERENCES accounts(id,currency_id),
  UNIQUE(transaction_id,leg),
  UNIQUE(adjustment_id),
  UNIQUE(id,transaction_id),
  CHECK((transaction_id IS NOT NULL AND adjustment_id IS NULL AND leg<>'adjustment' AND delta_minor<>0)
     OR (transaction_id IS NULL AND adjustment_id IS NOT NULL AND leg='adjustment')),
  CHECK(leg NOT IN ('expense','transfer_out') OR delta_minor<0),
  CHECK(leg NOT IN ('income','transfer_in') OR delta_minor>0)
);
CREATE TABLE fx_snapshots (
  id TEXT PRIMARY KEY NOT NULL,
  transaction_id TEXT NOT NULL REFERENCES transactions(id),
  account_movement_id TEXT,
  role TEXT NOT NULL CHECK(role IN ('book','settlement')),
  from_currency_id TEXT NOT NULL REFERENCES currencies(id),
  to_currency_id TEXT NOT NULL REFERENCES currencies(id),
  from_minor INTEGER NOT NULL CHECK(typeof(from_minor)='integer' AND from_minor BETWEEN 1 AND 9007199254740991),
  to_minor INTEGER NOT NULL CHECK(typeof(to_minor)='integer' AND to_minor BETWEEN 0 AND 9007199254740991),
  rate_decimal TEXT NOT NULL CHECK(typeof(rate_decimal)='text' AND length(rate_decimal) BETWEEN 1 AND 64
    AND rate_decimal NOT GLOB '*[^0-9.]*' AND rate_decimal NOT LIKE '%.%.%'
    AND substr(rate_decimal,1,1)<>'.' AND substr(rate_decimal,-1)<>'.' AND rate_decimal GLOB '*[1-9]*'),
  rate_source TEXT NOT NULL,
  rate_time_ms INTEGER NOT NULL,
  rounding_mode TEXT NOT NULL CHECK(rounding_mode IN ('HALF_UP','ACTUAL')),
  calculation_version INTEGER NOT NULL CHECK(calculation_version>0),
  FOREIGN KEY(account_movement_id,transaction_id) REFERENCES account_movements(id,transaction_id),
  CHECK(from_currency_id<>to_currency_id),
  CHECK((role='book' AND account_movement_id IS NULL) OR (role='settlement' AND account_movement_id IS NOT NULL))
);
CREATE UNIQUE INDEX one_book_conversion ON fx_snapshots(transaction_id) WHERE role='book';
CREATE UNIQUE INDEX one_settlement_conversion ON fx_snapshots(account_movement_id) WHERE role='settlement';
CREATE TABLE budgets (
  id TEXT PRIMARY KEY NOT NULL,
  book_id TEXT NOT NULL REFERENCES books(id),
  currency_id TEXT NOT NULL REFERENCES currencies(id),
  period_start_date TEXT NOT NULL CHECK(date(period_start_date,'+0 days') IS NOT NULL AND date(period_start_date,'+0 days')=period_start_date),
  period_end_date_exclusive TEXT NOT NULL CHECK(date(period_end_date_exclusive,'+0 days') IS NOT NULL AND date(period_end_date_exclusive,'+0 days')=period_end_date_exclusive),
  total_minor INTEGER NOT NULL CHECK(typeof(total_minor)='integer' AND total_minor BETWEEN 0 AND 9007199254740991),
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>0),
  deleted_at_ms INTEGER,
  UNIQUE(id,book_id),
  CHECK(period_start_date<period_end_date_exclusive)
);
CREATE UNIQUE INDEX budget_period ON budgets(book_id,period_start_date,period_end_date_exclusive) WHERE deleted_at_ms IS NULL;
CREATE TABLE budget_lines (
  id TEXT PRIMARY KEY NOT NULL,
  budget_id TEXT NOT NULL,
  book_id TEXT NOT NULL,
  category_id TEXT NOT NULL,
  category_kind TEXT NOT NULL DEFAULT 'expense' CHECK(category_kind='expense'),
  amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor BETWEEN 0 AND 9007199254740991),
  FOREIGN KEY(budget_id,book_id) REFERENCES budgets(id,book_id),
  FOREIGN KEY(category_id,book_id,category_kind) REFERENCES categories(id,book_id,kind),
  UNIQUE(budget_id,category_id)
);
CREATE TABLE attachments (
  id TEXT PRIMARY KEY NOT NULL,
  content_sha256 TEXT NOT NULL UNIQUE CHECK(length(content_sha256)=64 AND content_sha256 NOT GLOB '*[^0-9a-f]*'),
  relative_path TEXT NOT NULL UNIQUE CHECK(relative_path NOT LIKE '/%' AND instr(relative_path,'..')=0 AND instr(relative_path,char(92))=0),
  mime_type TEXT NOT NULL,
  byte_size INTEGER NOT NULL CHECK(typeof(byte_size)='integer' AND byte_size>0),
  width INTEGER CHECK(width>0),
  height INTEGER CHECK(height>0),
  state TEXT NOT NULL CHECK(state IN ('staged','ready','missing')),
  created_at_ms INTEGER NOT NULL,
  deleted_at_ms INTEGER
);
CREATE TABLE transaction_attachments (
  transaction_id TEXT NOT NULL REFERENCES transactions(id),
  attachment_id TEXT NOT NULL REFERENCES attachments(id),
  sort_order INTEGER NOT NULL CHECK(sort_order>=0),
  caption TEXT,
  PRIMARY KEY(transaction_id,attachment_id),
  UNIQUE(transaction_id,sort_order)
);

CREATE INDEX transaction_book_date ON transactions(book_id,occurred_local_date,id) WHERE posting_state='posted' AND deleted_at_ms IS NULL;
CREATE INDEX transaction_category_date ON transactions(category_id,occurred_local_date);
-- 外部编号只索引，不唯一；允许用户明确保留重复。
CREATE INDEX transaction_external_source ON transactions(source_provider,source_namespace,source_record_id);
CREATE INDEX category_parent ON categories(book_id,kind,parent_id,sort_order);
CREATE INDEX movement_account_date ON account_movements(account_id,occurred_at_ms,id);
CREATE INDEX import_row_status ON import_rows(batch_id,validation_status,selected);
CREATE INDEX fx_quote_pair_date ON fx_quotes(from_currency_id,to_currency_id,quoted_at_ms DESC);

-- 多级分类只有parent_id一套真相；首版用递归视图，不维护第二份闭包缓存。
CREATE VIEW category_closure AS
WITH RECURSIVE c(ancestor_id,descendant_id,depth) AS (
 SELECT id,id,0 FROM categories
 UNION ALL
 SELECT c.ancestor_id,n.id,c.depth+1 FROM c JOIN categories n ON n.parent_id=c.descendant_id
) SELECT * FROM c;
CREATE VIEW v_posted_transactions AS
 SELECT t.* FROM transactions t
 WHERE t.posting_state='posted' AND t.deleted_at_ms IS NULL
 AND (t.import_batch_id IS NULL OR EXISTS(SELECT 1 FROM import_batches b WHERE b.id=t.import_batch_id AND b.status='committed'));
CREATE VIEW v_effective_movements AS
 SELECT m.* FROM account_movements m JOIN v_posted_transactions t ON t.id=m.transaction_id
 WHERE t.include_in_assets=1 AND t.balance_mode='apply'
 UNION ALL
 SELECT m.* FROM account_movements m JOIN balance_adjustments a ON a.id=m.adjustment_id WHERE a.posting_state='posted';
-- SUM可能超出64位或ArkTS安全整数；调用方必须检测，必要时分批精确求和。
CREATE VIEW v_account_balances AS
 SELECT a.id AS account_id,a.currency_id,COALESCE(SUM(m.delta_minor),0) AS balance_minor
 FROM accounts a LEFT JOIN v_effective_movements m ON m.account_id=a.id
 WHERE a.deleted_at_ms IS NULL GROUP BY a.id,a.currency_id;
CREATE VIEW v_book_totals AS
 SELECT book_id,book_currency_id,
 SUM(CASE WHEN kind='expense' THEN book_minor ELSE 0 END) AS expense_minor,
 SUM(CASE WHEN kind='income' THEN book_minor ELSE 0 END) AS income_minor
 FROM v_posted_transactions GROUP BY book_id,book_currency_id;
CREATE VIEW v_budget_usage AS
 SELECT b.id AS budget_id,b.total_minor,COALESCE(SUM(t.book_minor),0) AS used_minor
 FROM budgets b LEFT JOIN v_posted_transactions t ON t.book_id=b.book_id AND t.kind='expense'
 AND t.include_in_budget=1 AND t.occurred_local_date>=b.period_start_date AND t.occurred_local_date<b.period_end_date_exclusive
 WHERE b.deleted_at_ms IS NULL GROUP BY b.id,b.total_minor;
CREATE VIEW v_budget_line_usage AS
 SELECT l.id AS budget_line_id,l.budget_id,l.amount_minor,COALESCE(SUM(t.book_minor),0) AS used_minor
 FROM budget_lines l JOIN budgets b ON b.id=l.budget_id
 LEFT JOIN category_closure c ON c.ancestor_id=l.category_id
 LEFT JOIN v_posted_transactions t ON t.category_id=c.descendant_id AND t.book_id=b.book_id
 AND t.kind='expense' AND t.include_in_budget=1
 AND t.occurred_local_date>=b.period_start_date AND t.occurred_local_date<b.period_end_date_exclusive
 WHERE b.deleted_at_ms IS NULL GROUP BY l.id,l.budget_id,l.amount_minor;

CREATE TRIGGER currency_definition_immutable BEFORE UPDATE OF code,numeric_code,minor_unit,valid_from,source_version ON currencies
 BEGIN SELECT RAISE(ABORT,'currency definition is immutable; create a new version'); END;
CREATE TRIGGER quote_immutable BEFORE UPDATE ON fx_quotes
 BEGIN SELECT RAISE(ABORT,'quotes are append-only'); END;
CREATE TRIGGER book_currency_locked BEFORE UPDATE OF base_currency_id ON books
 WHEN NEW.base_currency_id<>OLD.base_currency_id AND
 (EXISTS(SELECT 1 FROM transactions WHERE book_id=OLD.id) OR EXISTS(SELECT 1 FROM budgets WHERE book_id=OLD.id))
 BEGIN SELECT RAISE(ABORT,'book currency is in use'); END;
CREATE TRIGGER account_currency_locked BEFORE UPDATE OF currency_id,kind ON accounts
 WHEN (NEW.currency_id<>OLD.currency_id OR NEW.kind<>OLD.kind) AND EXISTS(SELECT 1 FROM account_movements WHERE account_id=OLD.id)
 BEGIN SELECT RAISE(ABORT,'account denomination/type is in use'); END;
CREATE TRIGGER category_scope_locked BEFORE UPDATE OF book_id,kind ON categories
 WHEN NEW.book_id<>OLD.book_id OR NEW.kind<>OLD.kind
 BEGIN SELECT RAISE(ABORT,'category scope is immutable'); END;
CREATE TRIGGER category_cycle BEFORE UPDATE OF parent_id ON categories
 WHEN NEW.parent_id IS NOT NULL AND EXISTS(SELECT 1 FROM category_closure WHERE ancestor_id=OLD.id AND descendant_id=NEW.parent_id)
 BEGIN SELECT RAISE(ABORT,'category cycle'); END;
CREATE TRIGGER transaction_draft_insert BEFORE INSERT ON transactions WHEN NEW.posting_state<>'draft'
 BEGIN SELECT RAISE(ABORT,'create draft then publish in one transaction'); END;
CREATE TRIGGER transaction_currency_insert BEFORE INSERT ON transactions
 WHEN NEW.book_currency_id<>(SELECT base_currency_id FROM books WHERE id=NEW.book_id)
 BEGIN SELECT RAISE(ABORT,'wrong book currency'); END;
CREATE TRIGGER transaction_currency_update BEFORE UPDATE OF book_id,book_currency_id ON transactions
 WHEN NEW.book_currency_id<>(SELECT base_currency_id FROM books WHERE id=NEW.book_id)
 BEGIN SELECT RAISE(ABORT,'wrong book currency'); END;
CREATE TRIGGER transaction_finance_locked BEFORE UPDATE OF book_id,kind,category_id,currency_id,gross_minor,discount_minor,paid_minor,book_currency_id,book_minor,include_in_assets,include_in_budget,balance_mode,import_row_id,import_batch_id,occurred_at_ms,occurred_local_date ON transactions
 WHEN OLD.posting_state='posted' AND NEW.posting_state='posted'
 BEGIN SELECT RAISE(ABORT,'edit financial fields through draft and republish'); END;
CREATE TRIGGER transaction_hard_delete BEFORE DELETE ON transactions WHEN OLD.posting_state='posted'
 BEGIN SELECT RAISE(ABORT,'soft delete posted transactions'); END;
CREATE TRIGGER import_identity_locked BEFORE UPDATE OF import_row_id,import_batch_id,balance_mode ON transactions
 WHEN NEW.import_row_id IS NOT OLD.import_row_id OR NEW.import_batch_id IS NOT OLD.import_batch_id OR NEW.balance_mode<>OLD.balance_mode
 BEGIN SELECT RAISE(ABORT,'import identity and balance policy are immutable'); END;
CREATE TRIGGER adjustment_draft_insert BEFORE INSERT ON balance_adjustments WHEN NEW.posting_state<>'draft'
 BEGIN SELECT RAISE(ABORT,'create adjustment draft then publish'); END;
CREATE TRIGGER adjustment_immutable BEFORE UPDATE ON balance_adjustments WHEN OLD.posting_state='posted'
 BEGIN SELECT RAISE(ABORT,'posted adjustment is immutable; use compensating adjustment'); END;
CREATE TRIGGER adjustment_no_delete BEFORE DELETE ON balance_adjustments WHEN OLD.posting_state='posted'
 BEGIN SELECT RAISE(ABORT,'posted adjustment is immutable'); END;
CREATE TRIGGER budget_currency_insert BEFORE INSERT ON budgets
 WHEN NEW.currency_id<>(SELECT base_currency_id FROM books WHERE id=NEW.book_id)
 BEGIN SELECT RAISE(ABORT,'budget must use book currency'); END;
CREATE TRIGGER budget_currency_update BEFORE UPDATE OF book_id,currency_id ON budgets
 WHEN NEW.currency_id<>(SELECT base_currency_id FROM books WHERE id=NEW.book_id)
 BEGIN SELECT RAISE(ABORT,'budget must use book currency'); END;

-- 转账完整性、同币等额、跨币快照与附件发布校验。
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
 SELECT CASE WHEN NEW.kind='transfer' AND (
 (SELECT COUNT(*) FROM account_movements WHERE transaction_id=NEW.id)<>2 OR
 (SELECT COUNT(DISTINCT account_id) FROM account_movements WHERE transaction_id=NEW.id)<>2 OR
 NOT EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg='transfer_out' AND currency_id=NEW.currency_id AND delta_minor=-NEW.paid_minor) OR
 NOT EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg='transfer_in'))
 THEN RAISE(ABORT,'incomplete transfer') END;
 SELECT CASE WHEN NEW.kind<>'transfer' AND ((SELECT COUNT(*) FROM account_movements WHERE transaction_id=NEW.id)>1
 OR EXISTS(SELECT 1 FROM account_movements WHERE transaction_id=NEW.id AND leg<>NEW.kind))
 THEN RAISE(ABORT,'wrong income/expense settlement') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM account_movements m WHERE m.transaction_id=NEW.id
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
CREATE TRIGGER adjustment_publish BEFORE UPDATE OF posting_state ON balance_adjustments
 WHEN NEW.posting_state='posted' AND OLD.posting_state='draft'
 BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM account_movements m WHERE m.adjustment_id=NEW.id AND m.account_id=NEW.account_id
 AND m.delta_minor=NEW.delta_minor AND m.leg='adjustment' AND m.occurred_at_ms=NEW.occurred_at_ms) THEN RAISE(ABORT,'missing adjustment movement') END;
 SELECT CASE WHEN NEW.before_minor<>(SELECT balance_minor FROM v_account_balances WHERE account_id=NEW.account_id)
 OR NOT EXISTS(SELECT 1 FROM v_account_balances WHERE account_id=NEW.account_id)
 THEN RAISE(ABORT,'stale adjustment balance') END;
 SELECT CASE WHEN NEW.reversal_of_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM balance_adjustments a WHERE a.id=NEW.reversal_of_id
 AND a.account_id=NEW.account_id AND a.posting_state='posted' AND NEW.delta_minor=-a.delta_minor)
 THEN RAISE(ABORT,'invalid compensation') END;
 END;
CREATE TRIGGER batch_policy_locked BEFORE UPDATE OF balance_mode,book_id ON import_batches
 WHEN EXISTS(SELECT 1 FROM transactions WHERE import_batch_id=OLD.id)
 BEGIN SELECT RAISE(ABORT,'batch policy is in use'); END;
CREATE TRIGGER batch_committed_locked BEFORE UPDATE ON import_batches WHEN OLD.status='committed'
 BEGIN SELECT RAISE(ABORT,'committed batch is immutable'); END;
CREATE TRIGGER batch_commit BEFORE UPDATE OF status ON import_batches WHEN NEW.status='committed' AND OLD.status<>'committed'
 BEGIN
 SELECT CASE WHEN NEW.selected_count<>(SELECT COUNT(*) FROM import_rows WHERE batch_id=NEW.id AND selected=1)
 OR NEW.total_count<>(SELECT COUNT(*) FROM import_rows WHERE batch_id=NEW.id)
 OR NEW.selected_count<>(SELECT COUNT(*) FROM transactions WHERE import_batch_id=NEW.id AND posting_state='posted' AND deleted_at_ms IS NULL)
 THEN RAISE(ABORT,'batch counts/unpublished records mismatch') END;
 END;

-- 已发布资金明细和汇率必须先随账目进入同一编辑事务，防止绕开发布校验。
CREATE TRIGGER movement_insert_guard BEFORE INSERT ON account_movements
 WHEN COALESCE((SELECT posting_state FROM transactions WHERE id=NEW.transaction_id),'draft')='posted'
 OR COALESCE((SELECT posting_state FROM balance_adjustments WHERE id=NEW.adjustment_id),'draft')='posted'
 BEGIN SELECT RAISE(ABORT,'source must be draft'); END;
CREATE TRIGGER movement_update_guard BEFORE UPDATE ON account_movements
 WHEN COALESCE((SELECT posting_state FROM transactions WHERE id=OLD.transaction_id),'draft')='posted'
 OR COALESCE((SELECT posting_state FROM balance_adjustments WHERE id=OLD.adjustment_id),'draft')='posted'
 OR COALESCE((SELECT posting_state FROM transactions WHERE id=NEW.transaction_id),'draft')='posted'
 OR COALESCE((SELECT posting_state FROM balance_adjustments WHERE id=NEW.adjustment_id),'draft')='posted'
 BEGIN SELECT RAISE(ABORT,'source must be draft'); END;
CREATE TRIGGER movement_delete_guard BEFORE DELETE ON account_movements
 WHEN COALESCE((SELECT posting_state FROM transactions WHERE id=OLD.transaction_id),'draft')='posted'
 OR COALESCE((SELECT posting_state FROM balance_adjustments WHERE id=OLD.adjustment_id),'draft')='posted'
 BEGIN SELECT RAISE(ABORT,'source must be draft'); END;
CREATE TRIGGER fx_insert_guard BEFORE INSERT ON fx_snapshots
 WHEN (SELECT posting_state FROM transactions WHERE id=NEW.transaction_id)='posted'
 BEGIN SELECT RAISE(ABORT,'FX source must be draft'); END;
CREATE TRIGGER fx_update_guard BEFORE UPDATE ON fx_snapshots
 WHEN (SELECT posting_state FROM transactions WHERE id=OLD.transaction_id)='posted'
 OR (SELECT posting_state FROM transactions WHERE id=NEW.transaction_id)='posted'
 BEGIN SELECT RAISE(ABORT,'FX source must be draft'); END;
CREATE TRIGGER fx_delete_guard BEFORE DELETE ON fx_snapshots
 WHEN (SELECT posting_state FROM transactions WHERE id=OLD.transaction_id)='posted'
 BEGIN SELECT RAISE(ABORT,'FX source must be draft'); END;
CREATE TRIGGER import_row_insert_guard BEFORE INSERT ON import_rows
 WHEN (SELECT status FROM import_batches WHERE id=NEW.batch_id)='committed'
 BEGIN SELECT RAISE(ABORT,'committed import rows are immutable'); END;
CREATE TRIGGER import_row_update_guard BEFORE UPDATE ON import_rows
 WHEN (SELECT status FROM import_batches WHERE id=OLD.batch_id)='committed'
 OR (SELECT status FROM import_batches WHERE id=NEW.batch_id)='committed'
 BEGIN SELECT RAISE(ABORT,'committed import rows are immutable'); END;
CREATE TRIGGER import_row_delete_guard BEFORE DELETE ON import_rows
 WHEN (SELECT status FROM import_batches WHERE id=OLD.batch_id)='committed'
 BEGIN SELECT RAISE(ABORT,'committed import rows are immutable'); END;
CREATE TRIGGER attachment_link_insert BEFORE INSERT ON transaction_attachments
 WHEN NOT EXISTS(SELECT 1 FROM attachments WHERE id=NEW.attachment_id AND state='ready' AND deleted_at_ms IS NULL)
 BEGIN SELECT RAISE(ABORT,'attachment not ready'); END;
CREATE TRIGGER attachment_link_update BEFORE UPDATE ON transaction_attachments
 WHEN NOT EXISTS(SELECT 1 FROM attachments WHERE id=NEW.attachment_id AND state='ready' AND deleted_at_ms IS NULL)
 BEGIN SELECT RAISE(ABORT,'attachment not ready'); END;
CREATE TRIGGER attachment_content_immutable BEFORE UPDATE OF content_sha256,relative_path,mime_type,byte_size,width,height ON attachments
 WHEN OLD.state IN ('ready','missing')
 BEGIN SELECT RAISE(ABORT,'attachment content is immutable'); END;

-- 归档保留历史资金影响；删除必须通过明确的关联处理流程。
CREATE TRIGGER account_delete_guard BEFORE UPDATE OF deleted_at_ms ON accounts
 WHEN NEW.deleted_at_ms IS NOT NULL AND EXISTS(SELECT 1 FROM account_movements WHERE account_id=OLD.id)
 BEGIN SELECT RAISE(ABORT,'account has history; archive or explicitly resolve it'); END;
CREATE TRIGGER book_delete_guard BEFORE UPDATE OF deleted_at_ms ON books
 WHEN NEW.deleted_at_ms IS NOT NULL AND (EXISTS(SELECT 1 FROM transactions WHERE book_id=OLD.id AND deleted_at_ms IS NULL)
 OR EXISTS(SELECT 1 FROM budgets WHERE book_id=OLD.id AND deleted_at_ms IS NULL))
 BEGIN SELECT RAISE(ABORT,'book has active transactions/budgets'); END;
CREATE TRIGGER category_delete_guard BEFORE UPDATE OF deleted_at_ms ON categories
 WHEN NEW.deleted_at_ms IS NOT NULL AND (EXISTS(SELECT 1 FROM categories WHERE parent_id=OLD.id AND deleted_at_ms IS NULL)
 OR EXISTS(SELECT 1 FROM transactions WHERE category_id=OLD.id AND deleted_at_ms IS NULL)
 OR EXISTS(SELECT 1 FROM budget_lines WHERE category_id=OLD.id))
 BEGIN SELECT RAISE(ABORT,'category has active references'); END;
CREATE TRIGGER category_parent_deleted_insert BEFORE INSERT ON categories
 WHEN NEW.parent_id IS NOT NULL AND EXISTS(SELECT 1 FROM categories WHERE id=NEW.parent_id AND deleted_at_ms IS NOT NULL)
 BEGIN SELECT RAISE(ABORT,'parent category is deleted'); END;
CREATE TRIGGER category_parent_deleted_update BEFORE UPDATE OF parent_id,deleted_at_ms ON categories
 WHEN NEW.deleted_at_ms IS NULL AND NEW.parent_id IS NOT NULL AND EXISTS(SELECT 1 FROM categories WHERE id=NEW.parent_id AND deleted_at_ms IS NOT NULL)
 BEGIN SELECT RAISE(ABORT,'parent category is deleted'); END;
-- 净资产先按币种分组；跨币种估值交给明确报价时点的域服务。
CREATE VIEW v_net_assets_by_currency AS
 SELECT b.currency_id,SUM(b.balance_minor) AS net_minor
 FROM v_account_balances b JOIN accounts a ON a.id=b.account_id
 WHERE a.include_in_net_assets=1 GROUP BY b.currency_id;
