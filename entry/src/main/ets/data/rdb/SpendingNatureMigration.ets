import { relationalStore } from '@kit.ArkData';
import { SPENDING_NATURE_SCHEMA_SHA256, SPENDING_NATURE_SCHEMA_STATEMENTS } from './SpendingNatureSchema';
import { RdbSession } from './RdbSession';
import { TransferMigration } from './TransferMigration';

/** Additive v3 migration: existing transactions are never rewritten. */
export class SpendingNatureMigration {
  static backupName(name: string): string { return name.replace(/\.db$/, '') + '_before_spending_nature_v3.db'; }

  static async status(db: relationalStore.RdbStore): Promise<number> {
    const version = await TransferMigration.status(db);
    const marker = await db.querySql("SELECT value FROM db_meta WHERE key='spending_nature_schema_checksum'");
    try {
      if (version < 3) {
        if (marker.rowCount !== 0) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
        return version;
      }
      if (!marker.goToFirstRow() || marker.getString(0) !== SPENDING_NATURE_SCHEMA_SHA256) {
        throw new Error('UNSUPPORTED_LEDGER_SCHEMA');
      }
      const table = await db.querySql("SELECT name FROM sqlite_master WHERE type='table' AND name='spending_natures'");
      try { if (!table.goToFirstRow()) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); } } finally { table.close(); }
      const columns = await db.querySql("PRAGMA table_info('transactions')");
      let hasColumn = false;
      try {
        while (columns.goToNextRow()) { if (columns.getString(1) === 'spending_nature_id') { hasColumn = true; break; } }
      } finally { columns.close(); }
      if (!hasColumn) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
      return version;
    } finally { marker.close(); }
  }

  private static async fingerprint(db: relationalStore.RdbStore): Promise<string> {
    const values: string[] = [];
    for (const table of ['books', 'categories', 'transactions', 'account_movements', 'balance_adjustments', 'budgets', 'transaction_tags']) {
      const count = await db.querySql('SELECT COUNT(*) FROM ' + table);
      try { count.goToFirstRow(); values.push(table + ':' + count.getLong(0)); } finally { count.close(); }
    }
    const rows = await db.querySql('SELECT id,kind,revision,posting_state,CAST(gross_minor AS TEXT),CAST(discount_minor AS TEXT),CAST(paid_minor AS TEXT) FROM transactions ORDER BY id');
    try {
      while (rows.goToNextRow()) {
        const row: string[] = [];
        for (let index = 0; index < 7; index++) { row.push(rows.getString(index)); }
        values.push(JSON.stringify(row));
      }
    } finally { rows.close(); }
    return JSON.stringify(values);
  }

  /** Caller owns a transaction; candidate backups use the copied archive as their rollback source. */
  static async apply(db: relationalStore.RdbStore, backup: string = '', verifyExisting: boolean = true): Promise<void> {
    const before = verifyExisting ? await SpendingNatureMigration.fingerprint(db) : '';
    for (const sql of SPENDING_NATURE_SCHEMA_STATEMENTS) { await db.executeSql(sql); }
    const references = await db.querySql('PRAGMA foreign_key_check');
    try { if (references.rowCount !== 0) { throw new Error('MIGRATION_FOREIGN_KEY_CHECK_FAILED'); } } finally { references.close(); }
    const integrity = await db.querySql('PRAGMA quick_check');
    try { if (!integrity.goToFirstRow() || integrity.getString(0) !== 'ok') { throw new Error('MIGRATION_INTEGRITY_CHECK_FAILED'); } }
    finally { integrity.close(); }
    if (verifyExisting && before !== await SpendingNatureMigration.fingerprint(db)) {
      throw new Error('MIGRATION_DATA_CHANGED');
    }
    await db.insert('schema_migrations', { version: 3, checksum: SPENDING_NATURE_SCHEMA_SHA256, applied_at_ms: Date.now() });
    await db.insert('db_meta', { key: 'spending_nature_schema_checksum', value: SPENDING_NATURE_SCHEMA_SHA256 });
    if (backup.length > 0) { await db.insert('db_meta', { key: 'spending_nature_schema_backup', value: backup }); }
  }

  static async upgrade(db: relationalStore.RdbStore, name: string): Promise<void> {
    const session = RdbSession.forStore(db);
    const backup = SpendingNatureMigration.backupName(name);
    await session.read(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await SpendingNatureMigration.status(store) !== 2) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await store.backup(backup);
    });
    await session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await SpendingNatureMigration.status(store) !== 2) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await SpendingNatureMigration.apply(store, backup);
    });
  }

  static async upgradeCandidate(db: relationalStore.RdbStore): Promise<void> {
    const session = RdbSession.forStore(db);
    await session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await SpendingNatureMigration.status(store) !== 2) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await SpendingNatureMigration.apply(store, '', true);
    });
  }
}
