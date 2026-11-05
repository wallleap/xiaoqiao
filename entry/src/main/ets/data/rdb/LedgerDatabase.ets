import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { REVIEW_SCHEMA_SHA256, REVIEW_SCHEMA_STATEMENTS } from './ReviewSchema';
import { RdbSession } from './RdbSession';

export const DEFAULT_BOOK_ID: string = 'book-default';

/** Only creates an empty database. Unknown or mismatched existing schemas are never migrated here. */
export class LedgerDatabase {
  static requireName(name: string): void {
    if (name !== 'xiaoqiao.db' && !/^xiaoqiao_app_test_[a-zA-Z0-9_-]+\.db$/.test(name)) {
      throw new Error('INVALID_LEDGER_DATABASE_NAME');
    }
  }

  static async open(context: common.Context, name: string = 'xiaoqiao.db'): Promise<relationalStore.RdbStore> {
    LedgerDatabase.requireName(name);
    const store = await relationalStore.getRdbStore(context,
      { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
    try {
      await RdbSession.forStore(store).write(async (db: relationalStore.RdbStore): Promise<void> => {
        const objects = await db.querySql("SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' AND type IN ('table','view','trigger')");
        const empty = objects.rowCount === 0;
        objects.close();
        if (empty) {
          // PRAGMA is configured before the transaction by RdbSession.
          for (const sql of REVIEW_SCHEMA_STATEMENTS) {
            if (!sql.startsWith('PRAGMA')) { await db.executeSql(sql); }
          }
          await LedgerDatabase.seed(db);
        } else {
          // No IF NOT EXISTS, schema repair, reseeding, or version upgrade of nonempty databases.
          const meta = await db.querySql("SELECT value FROM db_meta WHERE key='schema_checksum'");
          try {
            if (!meta.goToFirstRow() || meta.getString(0) !== REVIEW_SCHEMA_SHA256) {
              throw new Error('UNSUPPORTED_LEDGER_SCHEMA');
            }
          } finally { meta.close(); }
          const migration = await db.querySql('SELECT version,checksum FROM schema_migrations ORDER BY version');
          try {
            if (migration.rowCount !== 1 || !migration.goToFirstRow() || migration.getLong(0) !== 1 ||
              migration.getString(1) !== REVIEW_SCHEMA_SHA256) { throw new Error('UNSUPPORTED_LEDGER_SCHEMA'); }
          } finally { migration.close(); }
        }
      });
      return store;
    } catch (error) {
      await store.close();
      throw error as Error;
    }
  }

  private static async seed(db: relationalStore.RdbStore): Promise<void> {
    const now = Date.now();
    await db.insert('db_meta', { key: 'schema_checksum', value: REVIEW_SCHEMA_SHA256 });
    await db.insert('schema_migrations', { version: 1, checksum: REVIEW_SCHEMA_SHA256, applied_at_ms: now });
    await db.insert('currencies', { id: 'CNY', code: 'CNY', numeric_code: '156', name: '人民币', symbol: '¥',
      minor_unit: 2, valid_from: '2026-01-01', source_version: 'xiaoqiao-cny-v1' });
    await db.insert('books', { id: DEFAULT_BOOK_ID, name: '日常账本', base_currency_id: 'CNY',
      timezone: 'Asia/Shanghai', created_at_ms: now, updated_at_ms: now });
    const names: string[] = ['餐饮', '交通', '服饰', '汽车', '娱乐', '个护', '生活', '学习', '医疗健康', '人情', '公益', '保险', '其他'];
    const icons: string[] = ['food', 'transport', 'clothes', 'car', 'fun', 'care', 'home', 'study', 'health', 'gift', 'charity', 'insurance', 'other'];
    for (let index = 0; index < names.length; index++) {
      await db.insert('categories', { id: 'expense-' + icons[index], book_id: DEFAULT_BOOK_ID, kind: 'expense',
        name: names[index], name_key: names[index], icon_key: icons[index], sort_order: index,
        created_at_ms: now, updated_at_ms: now });
    }
    const meals: string[] = ['早餐', '午餐', '晚餐', '夜宵', '外卖'];
    for (let index = 0; index < meals.length; index++) {
      await db.insert('categories', { id: 'expense-food-' + index, book_id: DEFAULT_BOOK_ID, kind: 'expense',
        parent_id: 'expense-food', name: meals[index], name_key: meals[index], icon_key: 'food', sort_order: index,
        created_at_ms: now, updated_at_ms: now });
    }
    // No fabricated transactions, budgets, accounts, or opening balances.
  }
}
