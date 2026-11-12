import { LedgerBackupPackage } from '../backup/LedgerBackupPackage';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { REVIEW_SCHEMA_SHA256, REVIEW_SCHEMA_STATEMENTS } from './ReviewSchema';
import { TransferMigration } from './TransferMigration';
import { SpendingNatureMigration } from './SpendingNatureMigration';
import { RecoveryMigration } from './RecoveryMigration';
import { BudgetNatureMigration } from './BudgetNatureMigration';
import { RdbSession } from './RdbSession';
import { LocalLedgerBackup } from './LocalLedgerBackup';

export const DEFAULT_BOOK_ID: string = 'book-default';

/** Creates schema only for an empty database. Compatible stores may receive one-time, nonoverwriting income defaults. */
export class LedgerDatabase {
  static requireName(name: string): void {
    if (name !== 'xiaoqiao.db' && !/^xiaoqiao_app_test_[a-zA-Z0-9_-]+\.db$/.test(name)) {
      throw new Error('INVALID_LEDGER_DATABASE_NAME');
    }
  }

  static async open(context: common.Context, name: string = 'xiaoqiao.db'): Promise<relationalStore.RdbStore> {
    return LedgerDatabase.openInternal(context, name, name.startsWith('xiaoqiao_app_test_'));
  }

  /** Invoked only by the explicit local upgrade confirmation, never ordinary foreground loading. */
  static async upgrade(context: common.Context): Promise<void> {
    const store = await LedgerDatabase.openInternal(context, 'xiaoqiao.db', true);
    await store.close();
  }

  private static async openInternal(context: common.Context, name: string, allowUpgrade: boolean): Promise<relationalStore.RdbStore> {
    LedgerDatabase.requireName(name);
    const store = await relationalStore.getRdbStore(context, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
    const session = RdbSession.forStore(store);
    try {
      await session.read(async (db: relationalStore.RdbStore): Promise<void> => {
        const backup = new LocalLedgerBackup(context, name, session);
        await backup.recover(db);
        await new LedgerBackupPackage(context, name, backup).recover(db);
      });
      const empty = await session.read(async (db: relationalStore.RdbStore): Promise<boolean> => {
        const objects = await db.querySql("SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' AND type IN ('table','view','trigger')");
        try { return objects.rowCount === 0; } finally { objects.close(); }
      });
      if (empty) {
        await session.write(async (db: relationalStore.RdbStore): Promise<void> => {
          for (const sql of REVIEW_SCHEMA_STATEMENTS) { if (!sql.startsWith('PRAGMA')) { await db.executeSql(sql); } }
          await LedgerDatabase.seed(db);
          await TransferMigration.apply(db, '', false);
          await SpendingNatureMigration.apply(db, '', false);
          await BudgetNatureMigration.apply(db, '', false);
          await RecoveryMigration.apply(db, '', false);
          await LedgerDatabase.ensureIncomeCategories(db);
        });
      } else {
        let version = await session.read(async (db: relationalStore.RdbStore): Promise<number> => RecoveryMigration.status(db));
        if (version < 5 && !allowUpgrade) { throw new Error('LEDGER_UPGRADE_REQUIRED'); }
        if (version === 1) {
          if (!allowUpgrade) { throw new Error('LEDGER_UPGRADE_REQUIRED'); }
          await TransferMigration.upgrade(store, name);
          version = 2;
        }
        if (version === 2) {
          await SpendingNatureMigration.upgrade(store, name);
          version = 3;
        }
        if (version === 3) {
          await BudgetNatureMigration.upgrade(store, name);
          version = 4;
        }
        if (version === 4) { await RecoveryMigration.upgrade(store, name); }
        await session.write(async (db: relationalStore.RdbStore): Promise<void> => { await LedgerDatabase.ensureIncomeCategories(db); });
      }
      return store;
    } catch (error) { await store.close(); throw error as Error; }
  }

  /** Add defaults only once, only when this book has never had income categories. */
  private static async ensureIncomeCategories(db: relationalStore.RdbStore): Promise<void> {
    const marker = await db.querySql("SELECT value FROM db_meta WHERE key='income_categories_v1'");
    try { if (marker.goToFirstRow()) { return; } } finally { marker.close(); }
    const existing = await db.querySql("SELECT id FROM categories WHERE book_id=? AND kind='income' LIMIT 1", [DEFAULT_BOOK_ID]);
    const hasIncome = existing.rowCount > 0;
    existing.close();
    if (!hasIncome) {
      const names: string[] = ['工资', '奖金', '兼职', '理财', '红包', '其他收入'];
      const icons: string[] = ['salary', 'bonus', 'sidejob', 'investment', 'gift', 'other'];
      const now = Date.now();
      for (let index = 0; index < names.length; index++) {
        await db.insert('categories', { id: 'income-' + icons[index], book_id: DEFAULT_BOOK_ID, kind: 'income',
          name: names[index], name_key: names[index], icon_key: icons[index], sort_order: index,
          created_at_ms: now, updated_at_ms: now });
      }
    }
    await db.insert('db_meta', { key: 'income_categories_v1', value: '1' });
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
