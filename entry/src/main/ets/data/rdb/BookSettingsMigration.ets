import { relationalStore } from '@kit.ArkData';
import { BOOK_SETTINGS_SCHEMA_SHA256, BOOK_SETTINGS_SCHEMA_STATEMENTS } from './BookSettingsSchema';
import { RdbSession } from './RdbSession';
import { BookCoverMigration } from './BookCoverMigration';

/** V11 migration: book currency, monthly cycle and currency-aware prepaid guard; legacy monetary rows remain intact. */
export class BookSettingsMigration {
  static backupName(name: string): string { return name.replace(/\.db$/, '') + '_before_book_settings_v11.db'; }

  static async status(db: relationalStore.RdbStore): Promise<number> {
    const version = await BookCoverMigration.status(db);
    const marker = await db.querySql("SELECT value FROM db_meta WHERE key='book_settings_schema_checksum'");
    try {
      if (version < 11) {
        if (marker.rowCount !== 0) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
        return version;
      }
      if (!marker.goToFirstRow() || marker.getString(0) !== BOOK_SETTINGS_SCHEMA_SHA256) {
        throw new Error('UNSUPPORTED_LEDGER_SCHEMA');
      }
      const columns = await db.querySql("PRAGMA table_info('books')");
      const found: string[] = [];
      try { while (columns.goToNextRow()) { found.push(columns.getString(1)); } } finally { columns.close(); }
      if (!['month_start_day'].every((name: string) => found.includes(name))) {
        throw new Error('UNSUPPORTED_LEDGER_SCHEMA');
      }
      return version;
    } finally { marker.close(); }
  }

  private static async fingerprint(db: relationalStore.RdbStore): Promise<string> {
    const values: string[] = [];
    for (const table of ['accounts', 'prepaid_projects', 'prepaid_events', 'books', 'transactions', 'account_movements', 'budgets', 'budget_lines', 'spending_natures', 'expense_recoveries', 'fx_snapshots']) {
      const count = await db.querySql('SELECT COUNT(*) FROM ' + table);
      try { count.goToFirstRow(); values.push(table + ':' + count.getLong(0)); } finally { count.close(); }
    }
    const books = await db.querySql('SELECT id,name,base_currency_id,timezone,icon_key,sort_order,archived_at_ms,created_at_ms,updated_at_ms,revision,deleted_at_ms FROM books ORDER BY id');
    try {
      while (books.goToNextRow()) {
        const row: string[] = [];
        for (let i = 0; i < 11; i++) { row.push(books.isColumnNull(i) ? '<null>' : books.getString(i)); }
        values.push(JSON.stringify(row));
      }
    } finally { books.close(); }
    const accounts = await db.querySql("SELECT id,name,kind,currency_id,brand,icon_key,icon_variant,brand_color,include_in_net_assets,sort_order,archived_at_ms,created_at_ms,updated_at_ms,revision,deleted_at_ms,account_type,issuer_key,card_tail,note FROM accounts ORDER BY id");
    try {
      while (accounts.goToNextRow()) {
        const row: string[] = [];
        for (let i = 0; i < 19; i++) { row.push(accounts.isColumnNull(i) ? '<null>' : accounts.getString(i)); }
        values.push(JSON.stringify(row));
      }
    } finally { accounts.close(); }
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
    const before = verifyExisting ? await BookSettingsMigration.fingerprint(db) : '';
    for (const sql of BOOK_SETTINGS_SCHEMA_STATEMENTS) { await db.executeSql(sql); }
    const references = await db.querySql('PRAGMA foreign_key_check');
    try { if (references.rowCount !== 0) { throw new Error('MIGRATION_FOREIGN_KEY_CHECK_FAILED'); } } finally { references.close(); }
    const integrity = await db.querySql('PRAGMA quick_check');
    try { if (!integrity.goToFirstRow() || integrity.getString(0) !== 'ok') { throw new Error('MIGRATION_INTEGRITY_CHECK_FAILED'); } }
    finally { integrity.close(); }
    if (verifyExisting && before !== await BookSettingsMigration.fingerprint(db)) {
      throw new Error('MIGRATION_DATA_CHANGED');
    }
    await db.insert('schema_migrations', { version: 11, checksum: BOOK_SETTINGS_SCHEMA_SHA256, applied_at_ms: Date.now() });
    await db.insert('db_meta', { key: 'book_settings_schema_checksum', value: BOOK_SETTINGS_SCHEMA_SHA256 });
    if (backup.length > 0) { await db.insert('db_meta', { key: 'book_settings_schema_backup', value: backup }); }
  }

  static async upgrade(db: relationalStore.RdbStore, name: string): Promise<void> {
    const session = RdbSession.forStore(db);
    const backup = BookSettingsMigration.backupName(name);
    await session.read(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await BookSettingsMigration.status(store) !== 10) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await store.backup(backup);
    });
    await session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await BookSettingsMigration.status(store) !== 10) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await BookSettingsMigration.apply(store, backup);
    });
  }

  static async upgradeCandidate(db: relationalStore.RdbStore): Promise<void> {
    const session = RdbSession.forStore(db);
    await session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      if (await BookSettingsMigration.status(store) !== 10) { throw new Error('MIGRATION_SOURCE_MISMATCH'); }
      await BookSettingsMigration.apply(store, '', true);
    });
  }
}
