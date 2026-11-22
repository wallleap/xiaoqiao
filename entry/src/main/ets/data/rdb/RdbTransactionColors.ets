import { relationalStore } from '@kit.ArkData';
import { RdbSession } from './RdbSession';
import { DEFAULT_TRANSACTION_COLORS, TransactionColors } from '../../presentation/ledger/TransactionColors';

const SETTINGS_KEY: string = 'transaction_colors_v1';
/** Stored in the existing metadata table, so database backups and rollback include colors atomically. */
export class RdbTransactionColors {
  static async read(db: relationalStore.RdbStore): Promise<string> {
    const rows = await db.querySql('SELECT value FROM db_meta WHERE key=?', [SETTINGS_KEY]);
    try {
      const json = rows.goToFirstRow() ? rows.getString(0) : DEFAULT_TRANSACTION_COLORS;
      return JSON.stringify(TransactionColors.parse(json));
    } finally { rows.close(); }
  }
  static async load(session: RdbSession): Promise<void> {
    TransactionColors.publish(await session.read((db: relationalStore.RdbStore): Promise<string> => RdbTransactionColors.read(db)));
  }
  static async save(session: RdbSession, json: string): Promise<void> {
    const normalized = JSON.stringify(TransactionColors.parse(json));
    await session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      await db.executeSql('INSERT OR REPLACE INTO db_meta(key,value) VALUES(?,?)', [SETTINGS_KEY, normalized]);
    });
    // Publish only after the durable write succeeds; failed writes keep the previous choice.
    TransactionColors.publish(normalized);
  }
}
