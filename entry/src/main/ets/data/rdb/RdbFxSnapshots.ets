import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { Money } from '../../core/money/Money';
import { FxConversion, validateConversion } from '../../core/money/FxConversion';

export class RdbFxSnapshots {
  static async read(db: relationalStore.RdbStore, id: string, role: string): Promise<FxConversion | undefined> {
    const rows = await db.querySql('SELECT rate_decimal,rate_source,rate_time_ms,rounding_mode FROM fx_snapshots WHERE transaction_id=? AND role=?', [id, role]);
    try {
      if (!rows.goToFirstRow()) { return undefined; }
      return { rate: rows.getString(0), source: rows.getString(1), date: new Date(rows.getLong(2)).toISOString().substring(0,10), actual: rows.getString(3) === 'ACTUAL' };
    } finally { rows.close(); }
  }
  static async insert(db: relationalStore.RdbStore, transactionId: string, from: Money, to: Money,
    quote: FxConversion | undefined, movementId: string = ''): Promise<void> {
    validateConversion(from, to, quote);
    if (from.currency.matches(to.currency) || quote === undefined) { return; }
    await db.insert('fx_snapshots', { id: util.generateRandomUUID(), transaction_id: transactionId,
      account_movement_id: movementId || null, role: movementId ? 'settlement' : 'book',
      from_currency_id: from.currency.id, to_currency_id: to.currency.id,
      from_minor: from.toSafeMinorNumber(), to_minor: to.toSafeMinorNumber(), rate_decimal: quote.rate,
      rate_source: quote.source, rate_time_ms: Date.parse(quote.date + 'T00:00:00Z'),
      rounding_mode: quote.actual ? 'ACTUAL' : 'HALF_UP', calculation_version: 1 });
  }
}
