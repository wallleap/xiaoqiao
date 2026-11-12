import { relationalStore } from '@kit.ArkData';
import { RECOVERY_SCHEMA_SHA256, RECOVERY_SCHEMA_STATEMENTS } from './RecoverySchema';
import { RdbSession } from './RdbSession';
import { BudgetNatureMigration } from './BudgetNatureMigration';

/** V5 migration: linked receipts; existing expense and account rows remain intact. */
export class RecoveryMigration {
  static backupName(name: string): string { return name.replace(/\.db$/, '') + '_before_recovery_v5.db'; }

  static async status(db: relationalStore.RdbStore): Promise<number> {
    const version = await BudgetNatureMigration.status(db);
    const marker = await db.querySql("SELECT value FROM db_meta WHERE key='recovery_schema_checksum'");
    try {
      if (version < 5) {
        if (marker.rowCount !== 0) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
        return version;
      }
      if (!marker.goToFirstRow() || marker.getString(0) !== RECOVERY_SCHEMA_SHA256) {
        throw new Error('UNSUPPORTED_LEDGER_SCHEMA');
      }
      const table = await db.querySql("SELECT name FROM sqlite_master WHERE type='table' AND name='expense_recoveries'");
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
    const originals = await db.querySql("SELECT id,revision,kind,CAST(paid_minor AS TEXT),CAST(book_minor AS TEXT),include_in_assets,include_in_budget,reimbursement_status FROM transactions ORDER BY id");
    try { while (originals.goToNextRow()) { const row: string[] = []; for (let i = 0; i < 8; i++) { row.push(originals.getString(i)); } values.push(JSON.stringify(row)); } } finally { originals.close(); }
    const movements = await db.querySql('SELECT id,account_id,CAST(delta_minor AS TEXT) FROM v_effective_movements ORDER BY id');
    try { while (movements.goToNextRow()) { values.push(movements.getString(0) + ':' + movements.getString(1) + ':' + movements.getString(2)); } } finally { movements.close(); }
    return JSON.stringify(values);
  }

  static async apply(db: relationalStore.RdbStore, backup: string = '', verifyExisting: boolean = true): Promise<void> {
    const before = verifyExisting ? await RecoveryMigration.fingerprint(db) : '';
    for (const sql of RECOVERY_SCHEMA_STATEMENTS) { await db.executeSql(sql); }
    const references = await db.querySql('PRAGMA foreign_key_check');
    try { if (references.rowCount !== 0) { throw new Error('MIGRATION_FOREIGN_KEY_CHECK_FAILED'); } } finally { references.close(); }
    const integrity = await db.querySql('PRAGMA quick_check');
    try { if (!integrity.goToFirstRow() || integrity.getString(0) !== 'ok') { throw new Error('MIGRATION_INTEGRITY_CHECK_FAILED'); } }
    finally { integrity.close(); }
    if (verifyExisting && before !== await RecoveryMigration.fingerprint(db)) {
      throw new Error('MIGRATION_DATA_CHANGED');
    }
    await db.insert('schema_migrations', { version: 5, checksum: RECOVERY_SCHEMA_SHA256, applied_at_ms: Date.now() });
    await db.insert('db_meta', { key: 'recovery_schema_checksum', value: RECOVERY_SCHEMA_SHA256 });
    if (backup.length > 0) { await db.insert('db_meta', { key: 'recovery_schema_backup', value: backup }); }
  }

  static async upgrade(db: relationalStore.RdbStore, name: string): Promise<void> {
    const session = RdbSession.forStore(db);
    const backup = RecoveryMigration.backupName(name);
    await session.read(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await RecoveryMigration.status(store) !== 4) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await store.backup(backup);
    });
    await session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await RecoveryMigration.status(store) !== 4) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await RecoveryMigration.apply(store, backup);
    });
  }

  static async upgradeCandidate(db: relationalStore.RdbStore): Promise<void> {
    const session = RdbSession.forStore(db);
    await session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await RecoveryMigration.status(store) !== 4) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await RecoveryMigration.apply(store, '', true);
    });
  }
}
