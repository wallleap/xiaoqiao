import { relationalStore } from '@kit.ArkData';
import { REVIEW_SCHEMA_SHA256 } from './ReviewSchema';
import { TRANSFER_SCHEMA_SHA256, TRANSFER_SCHEMA_STATEMENTS } from './TransferSchema';
import { SPENDING_NATURE_SCHEMA_SHA256 } from './SpendingNatureSchema';
import { BUDGET_NATURE_SCHEMA_SHA256 } from './BudgetNatureSchema';
import { RECOVERY_SCHEMA_SHA256 } from './RecoverySchema';
import { NATURE_COLOR_SCHEMA_SHA256 } from './NatureColorSchema';
import { MULTICURRENCY_SCHEMA_SHA256 } from './MulticurrencySchema';
import { PREPAID_SCHEMA_SHA256 } from './PrepaidSchema';
import { ACCOUNT_DETAILS_SCHEMA_SHA256 } from './AccountDetailsSchema';
import { RdbSession } from './RdbSession';

/** Additive extension only: original transaction and movement rows are never rewritten. */
export class TransferMigration {
  static backupName(name: string): string { return name.replace(/\.db$/, '') + '_before_transfer_v2.db'; }

  static async status(db: relationalStore.RdbStore): Promise<number> {
    const meta = await db.querySql("SELECT value FROM db_meta WHERE key='schema_checksum'");
    try { if (!meta.goToFirstRow() || meta.getString(0) !== REVIEW_SCHEMA_SHA256) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); } }
    finally { meta.close(); }
    const rows = await db.querySql('SELECT version,checksum FROM schema_migrations ORDER BY version');
    let version: number = 1;
    try {
      if ((rows.rowCount < 1 || rows.rowCount > 9) || !rows.goToFirstRow() || rows.getLong(0) !== 1 || rows.getString(1) !== REVIEW_SCHEMA_SHA256) {
        throw new Error('UNSUPPORTED_LEDGER_SCHEMA');
      }
      if (rows.rowCount >= 2) {
        if (!rows.goToNextRow() || rows.getLong(0) !== 2 || rows.getString(1) !== TRANSFER_SCHEMA_SHA256) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
        version = 2;
      }
      if (rows.rowCount >= 3) {
        if (!rows.goToNextRow() || rows.getLong(0) !== 3 || rows.getString(1) !== SPENDING_NATURE_SCHEMA_SHA256) {
          throw new Error('UNSUPPORTED_LEDGER_SCHEMA');
        }
        version = 3;
      }
      if (rows.rowCount >= 4) {
        if (!rows.goToNextRow() || rows.getLong(0) !== 4 || rows.getString(1) !== BUDGET_NATURE_SCHEMA_SHA256) {
          throw new Error('UNSUPPORTED_LEDGER_SCHEMA');
        }
        version = 4;
      }
      if (rows.rowCount >= 5) {
        if (!rows.goToNextRow() || rows.getLong(0) !== 5 || rows.getString(1) !== RECOVERY_SCHEMA_SHA256) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
        version = 5;
      }
      if (rows.rowCount >= 6) {
        if (!rows.goToNextRow() || rows.getLong(0) !== 6 || rows.getString(1) !== NATURE_COLOR_SCHEMA_SHA256) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
        version = 6;
      }
      if (rows.rowCount >= 7) {
        if (!rows.goToNextRow() || rows.getLong(0) !== 7 || rows.getString(1) !== MULTICURRENCY_SCHEMA_SHA256) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
        version = 7;
      }
      if (rows.rowCount >= 8) {
        if (!rows.goToNextRow() || rows.getLong(0) !== 8 || rows.getString(1) !== PREPAID_SCHEMA_SHA256) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
        version = 8;
      }
      if (rows.rowCount >= 9) {
        if (!rows.goToNextRow() || rows.getLong(0) !== 9 || rows.getString(1) !== ACCOUNT_DETAILS_SCHEMA_SHA256) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
        version = 9;
      }
    } finally { rows.close(); }
    const marker = await db.querySql("SELECT value FROM db_meta WHERE key='transfer_schema_checksum'");
    try {
      if (version >= 2 ? (!marker.goToFirstRow() || marker.getString(0) !== TRANSFER_SCHEMA_SHA256) : marker.rowCount !== 0) {
        throw new Error('UNSUPPORTED_LEDGER_SCHEMA');
      }
    } finally { marker.close(); }
    return version;
  }

  private static async fingerprint(db: relationalStore.RdbStore): Promise<string> {
    const values: string[] = [];
    for (const table of ['accounts', 'transactions', 'account_movements', 'balance_adjustments', 'categories', 'transaction_tags', 'transaction_attachments', 'import_batches', 'import_rows']) {
      const count = await db.querySql('SELECT COUNT(*) FROM ' + table);
      try { count.goToFirstRow(); values.push(table + ':' + count.getLong(0)); } finally { count.close(); }
    }
    const rows = await db.querySql("SELECT id,revision,posting_state,COALESCE(CAST(deleted_at_ms AS TEXT),''),CAST(gross_minor AS TEXT),CAST(discount_minor AS TEXT),CAST(paid_minor AS TEXT),COALESCE(CAST(book_minor AS TEXT),''),balance_mode FROM transactions ORDER BY id");
    try { while (rows.goToNextRow()) { const row: string[] = []; for (let index = 0; index < 9; index++) { row.push(rows.getString(index)); } values.push(JSON.stringify(row)); } }
    finally { rows.close(); }
    const movements = await db.querySql('SELECT account_id,CAST(delta_minor AS TEXT) FROM v_effective_movements ORDER BY account_id,id');
    const balances: Map<string, bigint> = new Map();
    try { while (movements.goToNextRow()) { const id = movements.getString(0); balances.set(id, (balances.get(id) || BigInt(0)) + BigInt(movements.getString(1))); } }
    finally { movements.close(); }
    balances.forEach((value: bigint, key: string) => { values.push(key + ':' + value.toString()); });
    return JSON.stringify(values);
  }

  /** Caller owns a transaction; also used during first creation of an empty store. */
  static async apply(db: relationalStore.RdbStore, backup: string = '', verifyExisting: boolean = true): Promise<void> {
    // Newly created tables may be invisible to the native reader until first commit.
    // There is no historical data to compare in that creation transaction.
    const before = verifyExisting ? await TransferMigration.fingerprint(db) : '';
    for (const sql of TRANSFER_SCHEMA_STATEMENTS) { await db.executeSql(sql); }
    const fk = await db.querySql('PRAGMA foreign_key_check');
    try { if (fk.rowCount !== 0) { throw new Error('MIGRATION_FOREIGN_KEY_CHECK_FAILED'); } } finally { fk.close(); }
    const integrity = await db.querySql('PRAGMA quick_check');
    try { if (!integrity.goToFirstRow() || integrity.getString(0) !== 'ok') { throw new Error('MIGRATION_INTEGRITY_CHECK_FAILED'); } }
    finally { integrity.close(); }
    if (verifyExisting && before !== await TransferMigration.fingerprint(db)) { throw new Error('MIGRATION_DATA_CHANGED'); }
    await db.insert('schema_migrations', { version: 2, checksum: TRANSFER_SCHEMA_SHA256, applied_at_ms: Date.now() });
    await db.insert('db_meta', { key: 'transfer_schema_checksum', value: TRANSFER_SCHEMA_SHA256 });
    if (backup.length > 0) { await db.insert('db_meta', { key: 'transfer_schema_backup', value: backup }); }
  }

  static async upgrade(db: relationalStore.RdbStore, name: string): Promise<void> {
    const session = RdbSession.forStore(db);
    const backup = TransferMigration.backupName(name);
    await session.read(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await TransferMigration.status(store) !== 1) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await store.backup(backup);
    });
    await session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await TransferMigration.status(store) !== 1) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await TransferMigration.apply(store, backup);
    });
  }
}
