import { relationalStore } from '@kit.ArkData';
import { NATURE_COLOR_SCHEMA_SHA256, NATURE_COLOR_SCHEMA_STATEMENTS } from './NatureColorSchema';
import { RdbSession } from './RdbSession';
import { RecoveryMigration } from './RecoveryMigration';

/** V6 migration: additive custom RGB color; existing categories and ledger rows remain intact. */
export class NatureColorMigration {
  static backupName(name: string): string { return name.replace(/\.db$/, '') + '_before_nature_color_v6.db'; }

  static async status(db: relationalStore.RdbStore): Promise<number> {
    const version = await RecoveryMigration.status(db);
    const marker = await db.querySql("SELECT value FROM db_meta WHERE key='nature_color_schema_checksum'");
    try {
      if (version < 6) {
        if (marker.rowCount !== 0) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
        return version;
      }
      if (!marker.goToFirstRow() || marker.getString(0) !== NATURE_COLOR_SCHEMA_SHA256) {
        throw new Error('UNSUPPORTED_LEDGER_SCHEMA');
      }
      const columns = await db.querySql("PRAGMA table_info('spending_natures')");
      let found = false;
      try { while (columns.goToNextRow()) { if (columns.getString(1) === 'custom_color') { found = true; } } } finally { columns.close(); }
      if (!found) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
      return version;
    } finally { marker.close(); }
  }

  private static async fingerprint(db: relationalStore.RdbStore): Promise<string> {
    const values: string[] = [];
    for (const table of ['books', 'transactions', 'account_movements', 'budgets', 'budget_lines', 'spending_natures']) {
      const count = await db.querySql('SELECT COUNT(*) FROM ' + table);
      try { count.goToFirstRow(); values.push(table + ':' + count.getLong(0)); } finally { count.close(); }
    }
    const natures = await db.querySql('SELECT id,name,name_key,color_token,built_in,sort_order,revision,archived_at_ms,deleted_at_ms FROM spending_natures ORDER BY id');
    try {
      while (natures.goToNextRow()) {
        const row: string[] = [];
        for (let i = 0; i < 9; i++) { row.push(natures.isColumnNull(i) ? '' : natures.getString(i)); }
        values.push(JSON.stringify(row));
      }
    } finally { natures.close(); }
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
    const before = verifyExisting ? await NatureColorMigration.fingerprint(db) : '';
    for (const sql of NATURE_COLOR_SCHEMA_STATEMENTS) { await db.executeSql(sql); }
    const references = await db.querySql('PRAGMA foreign_key_check');
    try { if (references.rowCount !== 0) { throw new Error('MIGRATION_FOREIGN_KEY_CHECK_FAILED'); } } finally { references.close(); }
    const integrity = await db.querySql('PRAGMA quick_check');
    try { if (!integrity.goToFirstRow() || integrity.getString(0) !== 'ok') { throw new Error('MIGRATION_INTEGRITY_CHECK_FAILED'); } }
    finally { integrity.close(); }
    if (verifyExisting && before !== await NatureColorMigration.fingerprint(db)) {
      throw new Error('MIGRATION_DATA_CHANGED');
    }
    await db.insert('schema_migrations', { version: 6, checksum: NATURE_COLOR_SCHEMA_SHA256, applied_at_ms: Date.now() });
    await db.insert('db_meta', { key: 'nature_color_schema_checksum', value: NATURE_COLOR_SCHEMA_SHA256 });
    if (backup.length > 0) { await db.insert('db_meta', { key: 'nature_color_schema_backup', value: backup }); }
  }

  static async upgrade(db: relationalStore.RdbStore, name: string): Promise<void> {
    const session = RdbSession.forStore(db);
    const backup = NatureColorMigration.backupName(name);
    await session.read(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await NatureColorMigration.status(store) !== 5) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await store.backup(backup);
    });
    await session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await NatureColorMigration.status(store) !== 5) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await NatureColorMigration.apply(store, backup);
    });
  }

  static async upgradeCandidate(db: relationalStore.RdbStore): Promise<void> {
    const session = RdbSession.forStore(db);
    await session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await NatureColorMigration.status(store) !== 5) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await NatureColorMigration.apply(store, '', true);
    });
  }
}
