import { Money } from './Money';
import { ExchangeRate } from './ExchangeRate';

export interface FxConversion {
  rate: string;
  source: string;
  date: string;
  actual?: boolean;
}

export function validateConversion(from: Money, to: Money, quote?: FxConversion): void {
  if (from.currency.matches(to.currency)) {
    if (from.minor !== to.minor) { throw new Error('SAME_CURRENCY_AMOUNT_MISMATCH'); }
    return;
  }
  if (quote === undefined || !['ECB', 'ECB_CACHE', 'manual'].includes(quote.source) ||
    !/^\d{4}-\d{2}-\d{2}$/.test(quote.date) || !Number.isFinite(Date.parse(quote.date + 'T00:00:00Z'))) {
    throw new Error('FX_SNAPSHOT_COMMAND_REQUIRED');
  }
  const rate = new ExchangeRate(from.currency, to.currency, quote.rate);
  if (!quote.actual && rate.convert(from).minor !== to.minor) { throw new Error('FX_AMOUNT_MISMATCH'); }
  if (from.minor <= BigInt(0) || to.minor < BigInt(0)) { throw new Error('INVALID_SETTLEMENT'); }
}
