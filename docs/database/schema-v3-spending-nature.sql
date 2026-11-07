CREATE TABLE spending_natures (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  name_key TEXT NOT NULL,
  color_token TEXT NOT NULL CHECK(color_token IN ('survival','experience','growth','emergency','calm','creative','social','neutral')),
  built_in INTEGER NOT NULL DEFAULT 0 CHECK(built_in IN (0,1)),
  sort_order INTEGER NOT NULL DEFAULT 0,
  archived_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1 CHECK(typeof(revision)='integer' AND revision>0),
  deleted_at_ms INTEGER
);

CREATE UNIQUE INDEX spending_nature_name
ON spending_natures(name_key) WHERE deleted_at_ms IS NULL;

INSERT INTO spending_natures
  (id,name,name_key,color_token,built_in,sort_order,created_at_ms,updated_at_ms)
VALUES
  ('nature-survival','生存保障','生存保障','survival',1,0,1,1),
  ('nature-experience','体验享受','体验享受','experience',1,1,1,1),
  ('nature-growth','成长提升','成长提升','growth',1,2,1,1),
  ('nature-emergency','突发支出','突发支出','emergency',1,3,1,1);

ALTER TABLE transactions
ADD COLUMN spending_nature_id TEXT REFERENCES spending_natures(id);

CREATE INDEX transaction_spending_nature
ON transactions(spending_nature_id,occurred_local_date);

CREATE TRIGGER transaction_spending_nature_insert
BEFORE INSERT ON transactions
WHEN NEW.spending_nature_id IS NOT NULL AND (
  NEW.kind<>'expense' OR NOT EXISTS(
    SELECT 1 FROM spending_natures
    WHERE id=NEW.spending_nature_id AND archived_at_ms IS NULL AND deleted_at_ms IS NULL
  )
)
BEGIN SELECT RAISE(ABORT,'invalid spending nature'); END;

CREATE TRIGGER transaction_spending_nature_update
BEFORE UPDATE OF spending_nature_id ON transactions
WHEN NEW.spending_nature_id IS NOT NULL AND (
  NEW.kind<>'expense' OR NOT EXISTS(
    SELECT 1 FROM spending_natures
    WHERE id=NEW.spending_nature_id AND deleted_at_ms IS NULL
  )
)
BEGIN SELECT RAISE(ABORT,'invalid spending nature update'); END;
