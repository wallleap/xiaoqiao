import { ManualCurrencyRate, ManualRatePath, BUILTIN_CURRENCY_CODES, currencySettings, manualRatePaths, manualPathRate, combineCurrencyRates } from '../../core/money/CurrencySettings';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { crossRate, currencyUnit } from '../../core/money/Currencies';

export interface OfficialRate { from: string; to: string; rate: string; date: string; source: string; }
interface EcbCurrencyRate { code: string; rate: string; }
interface EcbDay { date: string; rates: EcbCurrencyRate[]; }
interface EcbCache { fetchedAt: number; days: EcbDay[]; }

/** Downloads public quotes only. No ledger amounts, accounts or user identifiers leave the device. */
export class OfficialExchangeRates {
  private static store: preferences.Preferences | undefined = undefined;
  private static days: EcbDay[] = [];
  private static fetchedAt: number = 0;
  private static pending: Promise<void> | undefined = undefined;

  static initialize(context: common.Context): void {
    if (OfficialExchangeRates.store !== undefined) { return; }
    OfficialExchangeRates.store = preferences.getPreferencesSync(context, { name: 'ecb_reference_rates' });
    try {
      const cache = JSON.parse(OfficialExchangeRates.store.getSync('cache', '{}') as string) as EcbCache;
      if (!Array.isArray(cache.days) || !Number.isSafeInteger(cache.fetchedAt)) { return; }
      const days = cache.days.filter((day: EcbDay) => OfficialExchangeRates.validDay(day));
      OfficialExchangeRates.days = days.sort((a: EcbDay, b: EcbDay) => b.date.localeCompare(a.date));
      OfficialExchangeRates.fetchedAt = cache.fetchedAt;
    } catch (_) { /* A missing or corrupt quote cache is replaced by a new public-data download. */ }
  }

  private static validDay(day: EcbDay): boolean {
    return typeof day.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(day.date) && Array.isArray(day.rates) &&
      day.rates.length > 1 && day.rates.every((item: EcbCurrencyRate) => typeof item.code === 'string' &&
        /^[A-Z]{3}$/.test(item.code) && typeof item.rate === 'string' && /^\d{1,16}(\.\d{1,12})?$/.test(item.rate) && Number(item.rate) > 0);
  }

  private static parse(xml: string): EcbDay[] {
    if (xml.length > 8 * 1024 * 1024 || !xml.includes('www.ecb.int/vocabulary/2002-08-01/eurofxref') ||
      !xml.includes('European Central Bank')) { throw new Error('FX_RESPONSE_INVALID'); }
    const result: EcbDay[] = [];
    const dates = /<Cube\s+time=['"](\d{4}-\d{2}-\d{2})['"]\s*>([\s\S]*?)<\/Cube>/g;
    let day = dates.exec(xml);
    while (day !== null) {
      const rates: EcbCurrencyRate[] = [{ code: 'EUR', rate: '1' }];
      const quotes = /<Cube\s+currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]\s*\/>/g;
      let quote = quotes.exec(day[2]);
      while (quote !== null) { rates.push({ code: quote[1], rate: quote[2] }); quote = quotes.exec(day[2]); }
      const value: EcbDay = { date: day[1], rates: rates };
      if (!OfficialExchangeRates.validDay(value)) { throw new Error('FX_RESPONSE_INVALID'); }
      result.push(value); day = dates.exec(xml);
    }
    if (result.length === 0) { throw new Error('FX_RESPONSE_INVALID'); }
    return result.sort((a: EcbDay, b: EcbDay) => b.date.localeCompare(a.date));
  }

  private static async download(history: boolean): Promise<void> {
    const request = http.createHttp();
    try {
      const response = await request.request('https://www.ecb.europa.eu/stats/eurofxref/' +
        (history ? 'eurofxref-hist.xml' : 'eurofxref-hist-90d.xml'), {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000, readTimeout: 15000, usingCache: false,
        header: { 'Accept': 'application/xml, text/xml' }
      });
      if (response.responseCode !== 200 || typeof response.result !== 'string') { throw new Error('FX_DOWNLOAD_FAILED'); }
      const days = OfficialExchangeRates.parse(response.result);
      // Merge with earlier cached history; a short feed must not erase old recorded-date quotes.
      const merged = new Map<string, EcbDay>();
      for (const day of OfficialExchangeRates.days) { merged.set(day.date, day); }
      for (const day of days) { merged.set(day.date, day); }
      OfficialExchangeRates.days = Array.from(merged.values()).sort((a: EcbDay, b: EcbDay) => b.date.localeCompare(a.date));
      OfficialExchangeRates.fetchedAt = Date.now();
      const cache: EcbCache = { fetchedAt: OfficialExchangeRates.fetchedAt, days: OfficialExchangeRates.days };
      OfficialExchangeRates.store?.putSync('cache', JSON.stringify(cache));
      OfficialExchangeRates.store?.flushSync();
    } finally { request.destroy(); }
  }

  static async quote(from: string, to: string, date: string): Promise<OfficialRate> {
    currencyUnit(from); currencyUnit(to);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) { throw new Error('FX_DATE_INVALID'); }
    if (from === to) { return { from: from, to: to, rate: '1', date: date, source: 'same_currency' }; }
    const rates = currencySettings().rates;
    const direct = rates.find((item: ManualCurrencyRate) => (item.from === from && item.to === to) || (item.from === to && item.to === from));
    if (direct !== undefined) {
      return { from: from, to: to, rate: direct.from === from ? direct.rate : crossRate('1', direct.rate), date: direct.date, source: 'manual' };
    }
    if (!BUILTIN_CURRENCY_CODES.includes(from) || !BUILTIN_CURRENCY_CODES.includes(to)) {
      const sources = manualRatePaths(from, rates); const targets = manualRatePaths(to, rates);
      const path = sources.find((item: ManualRatePath) => item.code === to);
      if (path !== undefined) { return { from: from, to: to, rate: manualPathRate(path), date: path.date, source: 'manual' }; }
      const source = sources.find((item: ManualRatePath) => BUILTIN_CURRENCY_CODES.includes(item.code));
      const target = targets.find((item: ManualRatePath) => BUILTIN_CURRENCY_CODES.includes(item.code));
      if (source === undefined || target === undefined) { throw new Error('FX_MANUAL_RATE_MISSING'); }
      const bridge = await OfficialExchangeRates.quote(source.code, target.code, date);
      return { from: from, to: to, rate: combineCurrencyRates(source, bridge.rate, target),
        date: [source.date,target.date,bridge.date].filter((value: string) => value.length > 0).sort()[0], source: 'manual' };
    }
    return OfficialExchangeRates.onlineQuote(from, to, date);
  }

  private static async onlineQuote(from: string, to: string, date: string): Promise<OfficialRate> {
    let downloadFailed = false;
    const old = OfficialExchangeRates.days.length === 0 || Date.now() - OfficialExchangeRates.fetchedAt > 6 * 3600000;
    const oldest = OfficialExchangeRates.days[OfficialExchangeRates.days.length - 1];
    const history = oldest !== undefined && date < oldest.date;
    if (old || history) {
      try {
        if (OfficialExchangeRates.pending === undefined) { OfficialExchangeRates.pending = OfficialExchangeRates.download(history); }
        await OfficialExchangeRates.pending;
      } catch (_) { downloadFailed = true; }
      finally { OfficialExchangeRates.pending = undefined; }
    }
    const earliest = OfficialExchangeRates.days[OfficialExchangeRates.days.length - 1];
    if (!downloadFailed && earliest !== undefined && date < earliest.date) {
      try {
        if (OfficialExchangeRates.pending === undefined) { OfficialExchangeRates.pending = OfficialExchangeRates.download(true); }
        await OfficialExchangeRates.pending;
      } catch (_) { downloadFailed = true; }
      finally { OfficialExchangeRates.pending = undefined; }
    }
    if (!downloadFailed && !OfficialExchangeRates.days.some((value: EcbDay) => value.date <= date)) {
      try { await OfficialExchangeRates.download(true); } catch (_) { downloadFailed = true; }
    }
    const day = OfficialExchangeRates.days.find((value: EcbDay) => value.date <= date);
    if (day === undefined) { throw new Error(downloadFailed ? 'FX_OFFLINE_NO_RATE' : 'FX_DATE_UNAVAILABLE'); }
    const source = day.rates.find((item: EcbCurrencyRate) => item.code === from);
    const target = day.rates.find((item: EcbCurrencyRate) => item.code === to);
    if (source === undefined || target === undefined) { throw new Error('FX_CURRENCY_UNAVAILABLE'); }
    return { from: from, to: to, rate: crossRate(target.rate, source.rate), date: day.date,
      source: downloadFailed ? 'ECB_CACHE' : 'ECB' };
  }
}
