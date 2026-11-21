import { BUILTIN_CURRENCIES, CURRENCIES, CurrencyDefinition } from './Currencies';

export interface CurrencyFlagChoice { code: string; region: string; }
export interface ManualCurrencyRate { from: string; to: string; rate: string; date: string; }
export interface CurrencySettings { version: number; flags: CurrencyFlagChoice[]; rates: ManualCurrencyRate[]; }
export interface CurrencyProfile extends CurrencyDefinition { enabled: boolean; custom: boolean; }

export const BUILTIN_CURRENCY_CODES: string[] = BUILTIN_CURRENCIES.map((item: CurrencyDefinition) => item.code);
let profiles: CurrencyProfile[] = BUILTIN_CURRENCIES.map((item: CurrencyDefinition): CurrencyProfile =>
  ({ code: item.code, name: item.name, symbol: item.symbol, scale: item.scale, enabled: true, custom: false }));
let settings: CurrencySettings = { version: 1, flags: [], rates: [] };

export function currencyProfiles(): CurrencyProfile[] { return profiles.map((item: CurrencyProfile): CurrencyProfile =>
  ({ code: item.code, name: item.name, symbol: item.symbol, scale: item.scale, enabled: item.enabled, custom: item.custom })); }
export function currencySettings(): CurrencySettings { return JSON.parse(JSON.stringify(settings)) as CurrencySettings; }
export function enabledCurrencies(current: string = ''): CurrencyDefinition[] {
  return profiles.filter((item: CurrencyProfile) => item.enabled || item.code === current);
}
export function configuredFlag(code: string): string | undefined {
  return settings.flags.find((item: CurrencyFlagChoice) => item.code === code)?.region;
}
export function installCurrencySettings(values: CurrencyProfile[], value: CurrencySettings): void {
  validateCurrencySettings(values, value);
  profiles = values; settings = value;
  // Keep the array identity used by existing money formatting and editors.
  CURRENCIES.splice(0, CURRENCIES.length, ...values.map((item: CurrencyProfile): CurrencyDefinition =>
    ({ code: item.code, name: item.name, symbol: item.symbol, scale: item.scale })));
}
export function validateCurrencySettings(values: CurrencyProfile[], value: CurrencySettings): void {
  if (!Array.isArray(values) || values.length < 1 || values.length > 200 || value.version !== 1 ||
    !Array.isArray(value.flags) || !Array.isArray(value.rates) || value.rates.length > 1000) { throw new Error('CURRENCY_SETTINGS_INVALID'); }
  const codes: Set<string> = new Set();
  for (const item of values) {
    if (!/^[A-Z]{3}$/.test(item.code) || codes.has(item.code) || typeof item.name !== 'string' || !item.name.trim() || item.name.length > 40 ||
      typeof item.symbol !== 'string' || !item.symbol.trim() || item.symbol.length > 12 || !Number.isInteger(item.scale) || item.scale < 0 || item.scale > 4 ||
      typeof item.enabled !== 'boolean' || typeof item.custom !== 'boolean') { throw new Error('CURRENCY_SETTINGS_INVALID'); }
    codes.add(item.code);
  }
  if (!values.some((item: CurrencyProfile) => item.code === 'CNY' && item.enabled && item.scale === 2)) { throw new Error('CURRENCY_CNY_REQUIRED'); }
  for (const code of BUILTIN_CURRENCY_CODES) { if (!codes.has(code)) { throw new Error('CURRENCY_BUILTIN_REQUIRED'); } }
  const pairs: Set<string> = new Set();
  for (const rate of value.rates) {
    if (!codes.has(rate.from) || !codes.has(rate.to) || rate.from === rate.to || !validManualRate(rate.rate) ||
      !/^\d{4}-\d{2}-\d{2}$/.test(rate.date) || !Number.isFinite(Date.parse(rate.date + 'T00:00:00Z')) ||
      pairs.has([rate.from,rate.to].sort().join('/'))) { throw new Error('CURRENCY_RATE_INVALID'); }
    pairs.add([rate.from,rate.to].sort().join('/'));
  }
  const flags: Set<string> = new Set();
  for (const flag of value.flags) {
    if (!codes.has(flag.code) || flags.has(flag.code) || !/^(|[a-z]{2,5}(-[a-z]{2,3})?)$/.test(flag.region)) { throw new Error('CURRENCY_FLAG_INVALID'); }
    flags.add(flag.code);
  }
}
export function validManualRate(rate: string): boolean {
  return typeof rate === 'string' && /^\d{1,16}(\.\d{1,12})?$/.test(rate) && BigInt(rate.replace('.', '')) > BigInt(0);
}

interface RateFraction { numerator: bigint; denominator: bigint; }
interface RateStep { code: string; value: RateFraction; date: string; }
export interface ManualRatePath { code: string; numerator: string; denominator: string; date: string; }
function fraction(rate: string): RateFraction {
  const parts = rate.split('.');
  return { numerator: BigInt(parts.join('')), denominator: BigInt(10) ** BigInt((parts[1] || '').length) };
}
function decimal(value: RateFraction): string {
  const unit = BigInt('1000000000000');
  const scaled = value.numerator * unit;
  let amount = scaled / value.denominator;
  if (scaled % value.denominator * BigInt(2) >= value.denominator) { amount++; }
  if (amount <= BigInt(0)) { throw new Error('FX_RATE_OUT_OF_RANGE'); }
  const digits = amount.toString().padStart(13, '0');
  const result = (digits.slice(0,-12) + '.' + digits.slice(-12)).replace(/0+$/, '').replace(/\.$/, '');
  if (!validManualRate(result)) { throw new Error('FX_RATE_OUT_OF_RANGE'); }
  return result;
}
export function manualPathRate(path: ManualRatePath): string {
  return decimal({ numerator: BigInt(path.numerator), denominator: BigInt(path.denominator) });
}
export function combineCurrencyRates(first: ManualRatePath, middle: string, last: ManualRatePath): string {
  const bridge = fraction(middle);
  return decimal({ numerator: BigInt(first.numerator)*bridge.numerator*BigInt(last.denominator),
    denominator: BigInt(first.denominator)*bridge.denominator*BigInt(last.numerator) });
}
/** Shortest manual path, direct pair first. Both directions share one saved value. */
export function manualRatePaths(from: string, rates: ManualCurrencyRate[]): ManualRatePath[] {
  const queue: RateStep[] = [{ code: from, value: fraction('1'), date: '' }];
  const seen: Set<string> = new Set([from]); const result: ManualRatePath[] = [];
  for (let index = 0; index < queue.length; index++) {
    const step = queue[index];
    result.push({ code: step.code, numerator: step.value.numerator.toString(), denominator: step.value.denominator.toString(), date: step.date });
    for (const rate of rates) {
      const forward = rate.from === step.code; const backward = rate.to === step.code;
      if (!forward && !backward) { continue; }
      const code = forward ? rate.to : rate.from;
      if (seen.has(code)) { continue; }
      const value = fraction(rate.rate); seen.add(code);
      queue.push({ code: code, date: !step.date || rate.date < step.date ? rate.date : step.date,
        value: { numerator: step.value.numerator * (forward ? value.numerator : value.denominator),
          denominator: step.value.denominator * (forward ? value.denominator : value.numerator) } });
    }
  }
  return result;
}
