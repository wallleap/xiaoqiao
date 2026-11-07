CREATE TABLE budget_nature_lines (
  id TEXT PRIMARY KEY NOT NULL,
  budget_id TEXT NOT NULL,
  book_id TEXT NOT NULL,
  spending_nature_id TEXT NOT NULL REFERENCES spending_natures(id),
  amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor BETWEEN 0 AND 9007199254740991),
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1 CHECK(typeof(revision)='integer' AND revision>0),
  FOREIGN KEY(budget_id,book_id) REFERENCES budgets(id,book_id),
  UNIQUE(budget_id,spending_nature_id)
);

CREATE INDEX budget_nature_line_nature
ON budget_nature_lines(spending_nature_id,budget_id);

CREATE TRIGGER budget_nature_line_limit_insert
BEFORE INSERT ON budget_nature_lines
WHEN NEW.amount_minor + COALESCE((
  SELECT SUM(amount_minor) FROM budget_nature_lines WHERE budget_id=NEW.budget_id
),0) > COALESCE((SELECT total_minor FROM budgets WHERE id=NEW.budget_id),0)
BEGIN SELECT RAISE(ABORT,'budget nature allocation exceeds total'); END;

CREATE TRIGGER budget_nature_line_limit_update
BEFORE UPDATE OF amount_minor,budget_id,spending_nature_id ON budget_nature_lines
WHEN NEW.amount_minor + COALESCE((
  SELECT SUM(amount_minor) FROM budget_nature_lines
  WHERE budget_id=NEW.budget_id AND id<>OLD.id
),0) > COALESCE((SELECT total_minor FROM budgets WHERE id=NEW.budget_id),0)
BEGIN SELECT RAISE(ABORT,'budget nature allocation exceeds total'); END;

CREATE TRIGGER budget_total_guard
BEFORE UPDATE OF total_minor ON budgets
WHEN NEW.total_minor < COALESCE((
  SELECT SUM(amount_minor) FROM budget_nature_lines WHERE budget_id=OLD.id
),0)
BEGIN SELECT RAISE(ABORT,'budget total is below nature allocations'); END;
