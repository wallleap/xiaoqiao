import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { REVIEW_SCHEMA_STATEMENTS } from './ReviewSchema';

/** Only disposable, explicitly named P0 databases. Does not open the real ledger. */
export class ValidationDatabase {
  static requireName(name: string): void {
    if (!/^xiaoqiao_p0_[a-zA-Z0-9_-]+\.db$/.test(name)) {
      throw new Error('VALIDATION_DATABASE_NAME_REQUIRED');
    }
  }

  static async open(context: common.Context, name: string): Promise<relationalStore.RdbStore> {
    ValidationDatabase.requireName(name);
    return relationalStore.getRdbStore(context, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
  }

  static async create(context: common.Context, name: string): Promise<relationalStore.RdbStore> {
    const store = await ValidationDatabase.open(context, name);
    try {
      const existing = await store.querySql("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
      try {
        if (existing.rowCount > 0) {
          throw new Error('VALIDATION_DATABASE_NOT_EMPTY');
        }
      } finally {
        existing.close();
      }
      for (const statement of REVIEW_SCHEMA_STATEMENTS) {
        await store.executeSql(statement);
      }
      // Read the writer PRAGMA through execute(), not a reader-pool query.
      if (await store.execute('PRAGMA foreign_keys') !== 1) {
        throw new Error('FOREIGN_KEYS_NOT_ENABLED');
      }
      return store;
    } catch (error) {
      await store.close();
      throw error as Error;
    }
  }

  static async remove(context: common.Context, name: string): Promise<void> {
    ValidationDatabase.requireName(name);
    await relationalStore.deleteRdbStore(context, name);
  }
}
