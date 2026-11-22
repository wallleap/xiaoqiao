import { relationalStore } from '@kit.ArkData';
import { PREPAID_CLEANUP_SCHEMA_SHA256, PREPAID_CLEANUP_SCHEMA_STATEMENTS } from './PrepaidCleanupSchema';
import { CategoryDeletionMigration } from './CategoryDeletionMigration';
import { RdbSession } from './RdbSession';

/** V14 only adds empty-project deletion guards. Existing financial rows are never rewritten. */
export class PrepaidCleanupMigration {
  static backupName(name: string): string { return name.replace(/\.db$/, '') + '_before_prepaid_cleanup_v14.db'; }
  static async status(db: relationalStore.RdbStore): Promise<number> {
    const version = await CategoryDeletionMigration.status(db);
    const marker = await db.querySql("SELECT value FROM db_meta WHERE key='prepaid_cleanup_schema_checksum'");
    try {
      if (version < 14) {
        if (marker.rowCount !== 0) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
        return version;
      }
      if (!marker.goToFirstRow() || marker.getString(0) !== PREPAID_CLEANUP_SCHEMA_SHA256) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
      for (const table of ['prepaid_cleanup_context', 'prepaid_cleanup_transactions', 'prepaid_cleanup_balances', 'prepaid_cleanup_resources']) {
        const rows = await db.querySql('SELECT COUNT(*) FROM ' + table);
        try { if (!rows.goToFirstRow() || rows.getLong(0) !== 0) { throw new Error('PREPAID_CLEANUP_INCOMPLETE'); } }
        finally { rows.close(); }
      }
      return version;
    } finally { marker.close(); }
  }
  static async apply(db: relationalStore.RdbStore): Promise<void> {
    for (const sql of PREPAID_CLEANUP_SCHEMA_STATEMENTS) { await db.executeSql(sql); }
    const foreignKeys = await db.querySql('PRAGMA foreign_key_check');
    try { if (foreignKeys.rowCount !== 0) { throw new Error('MIGRATION_FOREIGN_KEY_CHECK_FAILED'); } } finally { foreignKeys.close(); }
    const integrity = await db.querySql('PRAGMA quick_check');
    try { if (!integrity.goToFirstRow() || integrity.getString(0) !== 'ok') { throw new Error('MIGRATION_INTEGRITY_CHECK_FAILED'); } } finally { integrity.close(); }
    await db.insert('schema_migrations', { version: 14, checksum: PREPAID_CLEANUP_SCHEMA_SHA256, applied_at_ms: Date.now() });
    await db.insert('db_meta', { key: 'prepaid_cleanup_schema_checksum', value: PREPAID_CLEANUP_SCHEMA_SHA256 });
  }
  static async upgrade(db: relationalStore.RdbStore, name: string): Promise<void> {
    const session = RdbSession.forStore(db);
    await session.read(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await PrepaidCleanupMigration.status(store) !== 13) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await store.backup(PrepaidCleanupMigration.backupName(name));
    });
    await PrepaidCleanupMigration.upgradeCandidate(db);
  }
  static async upgradeCandidate(db: relationalStore.RdbStore): Promise<void> {
    await RdbSession.forStore(db).write(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await PrepaidCleanupMigration.status(store) !== 13) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await PrepaidCleanupMigration.apply(store);
    });
  }
}
