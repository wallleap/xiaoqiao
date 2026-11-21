import { BUILTIN_CURRENCY_CODES, enabledCurrencies } from '../../core/money/CurrencySettings';
import { CurrencyDefinition } from '../../core/money/Currencies';

export interface QueryRate { from: string; to: string; rate: string; date: string; source: string; }
export interface ExchangeRateRow { code: string; name: string; rate: string; date: string; cached: boolean; error: string; manual?: boolean; }
export type RateQuery = (from: string, to: string, date: string) => Promise<QueryRate>;

/** Read public quotes through the existing service; every row retains its actual quote date. */
export async function queryExchangeRates(base: string, date: string, query: RateQuery): Promise<ExchangeRateRow[]> {
  const enabled = enabledCurrencies().filter((item: CurrencyDefinition) => item.code !== base);
  const targets = enabled.filter((item: CurrencyDefinition) => !BUILTIN_CURRENCY_CODES.includes(item.code))
    .concat(enabled.filter((item: CurrencyDefinition) => BUILTIN_CURRENCY_CODES.includes(item.code)));
  return Promise.all(targets.map(async (currency: CurrencyDefinition): Promise<ExchangeRateRow> => {
    try {
      const value = await query(base, currency.code, date);
      return { code: currency.code, name: currency.name, rate: value.rate, date: value.date,
        cached: value.source === 'ECB_CACHE', manual: value.source === 'manual', error: '' };
    } catch (error) {
      return { code: currency.code, name: currency.name, rate: '', date: '', cached: false,
        error: (error as Error).message === 'FX_MANUAL_RATE_MISSING' ? '缺少手动汇率' : '暂不可用' };
    }
  }));
}

export function filterExchangeRates(rows: ExchangeRateRow[], keyword: string): ExchangeRateRow[] {
  const value = keyword.trim().toLowerCase();
  return rows.filter((row: ExchangeRateRow) => !value || (row.code + ' ' + row.name).toLowerCase().includes(value));
}

/** Rebuild a row when its quote direction or rendered content changes. */
export function exchangeRateRowKey(base: string, row: ExchangeRateRow): string {
  return [base, row.code, row.rate, row.date, row.manual ? 'manual' : row.cached ? 'cache' : 'official', row.error].join('|');
}
