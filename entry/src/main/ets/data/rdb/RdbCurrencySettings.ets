import { relationalStore } from '@kit.ArkData';
import { RdbSession } from './RdbSession';
import { CurrencyProfile, CurrencySettings, BUILTIN_CURRENCY_CODES, currencySettings,
  installCurrencySettings, validateCurrencySettings } from '../../core/money/CurrencySettings';

const SETTINGS_KEY: string = 'currency_settings_v1';
export interface StoredCurrencySettings { currencies: CurrencyProfile[]; settings: CurrencySettings; }

/** Currency definitions and settings share the existing database backup/rollback boundary. */
export class RdbCurrencySettings {
  private readonly session: RdbSession;
  constructor(session: RdbSession) { this.session = session; }
  static async read(db: relationalStore.RdbStore): Promise<StoredCurrencySettings> {
    const rows = await db.querySql('SELECT code,name,symbol,minor_unit,is_enabled FROM currencies ORDER BY rowid');
    const values: CurrencyProfile[] = [];
    try { while (rows.goToNextRow()) {
      const code = rows.getString(0);
      values.push({ code: code, name: rows.getString(1), symbol: rows.getString(2), scale: rows.getLong(3),
        enabled: rows.getLong(4) === 1, custom: !BUILTIN_CURRENCY_CODES.includes(code) });
    } } finally { rows.close(); }
    const meta = await db.querySql('SELECT value FROM db_meta WHERE key=?', [SETTINGS_KEY]);
    let settings: CurrencySettings = { version: 1, flags: [], rates: [] };
    try { if (meta.goToFirstRow()) { settings = JSON.parse(meta.getString(0)) as CurrencySettings; } } finally { meta.close(); }
    validateCurrencySettings(values, settings);
    return { currencies: values, settings: settings };
  }
  async load(): Promise<void> {
    const value = await this.session.read((db: relationalStore.RdbStore) => RdbCurrencySettings.read(db));
    installCurrencySettings(value.currencies, value.settings);
  }
  async save(profile: CurrencyProfile | undefined, settings: CurrencySettings, removeCode: string = ''): Promise<void> {
    // Read, validate and write under the same transaction; publish only after commit.
    const saved = await this.session.write(async (db: relationalStore.RdbStore): Promise<StoredCurrencySettings> => {
      const current = await RdbCurrencySettings.read(db);
      if (removeCode) {
        if (BUILTIN_CURRENCY_CODES.includes(removeCode)) { throw new Error('不能删除内置币种'); }
        // Foreign keys cover archived/deleted history as well: used definitions remain immutable.
        await db.executeSql('DELETE FROM currencies WHERE id=?', [removeCode]);
      }
      if (profile !== undefined) {
        const old = current.currencies.find((item: CurrencyProfile) => item.code === profile.code);
        if (old !== undefined) {
          if (old.scale !== profile.scale) { throw new Error('已有币种的小数位数不能修改'); }
          await db.executeSql('UPDATE currencies SET name=?,symbol=?,is_enabled=? WHERE id=?',
            [profile.name,profile.symbol,profile.enabled ? 1 : 0,profile.code]);
        } else {
          await db.insert('currencies', { id: profile.code, code: profile.code, name: profile.name, symbol: profile.symbol,
            minor_unit: profile.scale, valid_from: new Date().toISOString().slice(0,10), source_version: 'user-currency-v1', is_enabled: profile.enabled ? 1 : 0 });
        }
      }
      const next = current.currencies.filter((item: CurrencyProfile) => item.code !== removeCode);
      if (profile !== undefined) {
        const index = next.findIndex((item: CurrencyProfile) => item.code === profile.code);
        if (index < 0) { next.push(profile); } else { next[index] = profile; }
      }
      validateCurrencySettings(next, settings);
      await db.executeSql('INSERT OR REPLACE INTO db_meta(key,value) VALUES(?,?)', [SETTINGS_KEY,JSON.stringify(settings)]);
      // querySql can use a separate reader and cannot see this transaction's uncommitted writes.
      // Publish the validated write result only after RdbSession commits, rather than rereading here.
      return { currencies: next, settings: settings };
    });
    installCurrencySettings(saved.currencies, saved.settings);
  }
  async setEnabled(profile: CurrencyProfile, enabled: boolean): Promise<void> {
    const updated: CurrencyProfile = { code: profile.code, name: profile.name, symbol: profile.symbol,
      scale: profile.scale, enabled: enabled, custom: profile.custom };
    await this.save(updated, currencySettings());
  }
}
