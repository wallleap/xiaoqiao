import { relationalStore } from '@kit.ArkData';
import { BUDGET_NATURE_SCHEMA_SHA256, BUDGET_NATURE_SCHEMA_STATEMENTS } from './BudgetNatureSchema';
import { RdbSession } from './RdbSession';
import { SpendingNatureMigration } from './SpendingNatureMigration';

/** Additive v4 migration: creates monthly budget-category allocations without rewriting transactions. */
export class BudgetNatureMigration {
  static backupName(name: string): string { return name.replace(/\.db$/, '') + '_before_budget_nature_v4.db'; }

  static async status(db: relationalStore.RdbStore): Promise<number> {
    const version = await SpendingNatureMigration.status(db);
    const marker = await db.querySql("SELECT value FROM db_meta WHERE key='budget_nature_schema_checksum'");
    try {
      if (version < 4) {
        if (marker.rowCount !== 0) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
        return version;
      }
      if (!marker.goToFirstRow() || marker.getString(0) !== BUDGET_NATURE_SCHEMA_SHA256) {
        throw new Error('UNSUPPORTED_LEDGER_SCHEMA');
      }
      const table = await db.querySql("SELECT name FROM sqlite_master WHERE type='table' AND name='budget_nature_lines'");
      try { if (!table.goToFirstRow()) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); } } finally { table.close(); }
      return version;
    } finally { marker.close(); }
  }

  private static async fingerprint(db: relationalStore.RdbStore): Promise<string> {
    const values: string[] = [];
    for (const table of ['books', 'transactions', 'account_movements', 'budgets', 'budget_lines', 'spending_natures']) {
      const count = await db.querySql('SELECT COUNT(*) FROM ' + table);
      try { count.goToFirstRow(); values.push(table + ':' + count.getLong(0)); } finally { count.close(); }
    }
    const budgets = await db.querySql('SELECT id,revision,CAST(total_minor AS TEXT) FROM budgets ORDER BY id');
    try {
      while (budgets.goToNextRow()) {
        values.push(budgets.getString(0) + ':' + budgets.getLong(1) + ':' + budgets.getString(2));
      }
    } finally { budgets.close(); }
    return JSON.stringify(values);
  }

  static async apply(db: relationalStore.RdbStore, backup: string = '', verifyExisting: boolean = true): Promise<void> {
    const before = verifyExisting ? await BudgetNatureMigration.fingerprint(db) : '';
    for (const sql of BUDGET_NATURE_SCHEMA_STATEMENTS) { await db.executeSql(sql); }
    const references = await db.querySql('PRAGMA foreign_key_check');
    try { if (references.rowCount !== 0) { throw new Error('MIGRATION_FOREIGN_KEY_CHECK_FAILED'); } } finally { references.close(); }
    const integrity = await db.querySql('PRAGMA quick_check');
    try { if (!integrity.goToFirstRow() || integrity.getString(0) !== 'ok') { throw new Error('MIGRATION_INTEGRITY_CHECK_FAILED'); } }
    finally { integrity.close(); }
    if (verifyExisting && before !== await BudgetNatureMigration.fingerprint(db)) {
      throw new Error('MIGRATION_DATA_CHANGED');
    }
    await db.insert('schema_migrations', { version: 4, checksum: BUDGET_NATURE_SCHEMA_SHA256, applied_at_ms: Date.now() });
    await db.insert('db_meta', { key: 'budget_nature_schema_checksum', value: BUDGET_NATURE_SCHEMA_SHA256 });
    if (backup.length > 0) { await db.insert('db_meta', { key: 'budget_nature_schema_backup', value: backup }); }
  }

  static async upgrade(db: relationalStore.RdbStore, name: string): Promise<void> {
    const session = RdbSession.forStore(db);
    const backup = BudgetNatureMigration.backupName(name);
    await session.read(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await BudgetNatureMigration.status(store) !== 3) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await store.backup(backup);
    });
    await session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await BudgetNatureMigration.status(store) !== 3) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await BudgetNatureMigration.apply(store, backup);
    });
  }

  static async upgradeCandidate(db: relationalStore.RdbStore): Promise<void> {
    const session = RdbSession.forStore(db);
    await session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await BudgetNatureMigration.status(store) !== 3) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await BudgetNatureMigration.apply(store, '', true);
    });
  }
}
