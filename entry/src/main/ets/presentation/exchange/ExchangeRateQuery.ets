import { CURRENCIES, CurrencyDefinition } from '../../core/money/Currencies';

export interface QueryRate { from: string; to: string; rate: string; date: string; source: string; }
export interface ExchangeRateRow { code: string; name: string; rate: string; date: string; cached: boolean; error: string; }
export type RateQuery = (from: string, to: string, date: string) => Promise<QueryRate>;

/** Read public quotes through the existing service; every row retains its actual quote date. */
export async function queryExchangeRates(base: string, date: string, query: RateQuery): Promise<ExchangeRateRow[]> {
  const targets = CURRENCIES.filter((item: CurrencyDefinition) => item.code !== base);
  return Promise.all(targets.map(async (currency: CurrencyDefinition): Promise<ExchangeRateRow> => {
    try {
      const value = await query(base, currency.code, date);
      return { code: currency.code, name: currency.name, rate: value.rate, date: value.date,
        cached: value.source === 'ECB_CACHE', error: '' };
    } catch (_) {
      return { code: currency.code, name: currency.name, rate: '', date: '', cached: false, error: '暂不可用' };
    }
  }));
}

export function filterExchangeRates(rows: ExchangeRateRow[], keyword: string): ExchangeRateRow[] {
  const value = keyword.trim().toLowerCase();
  return rows.filter((row: ExchangeRateRow) => !value || (row.code + ' ' + row.name).toLowerCase().includes(value));
}

/** Rebuild a row when its quote direction or rendered content changes. */
export function exchangeRateRowKey(base: string, row: ExchangeRateRow): string {
  return [base, row.code, row.rate, row.date, row.cached ? 'cache' : 'official', row.error].join('|');
}
