import { CurrencyUnit } from './CurrencyUnit';
import { Money } from './Money';

/** Exact, finite decimal quote: one source major unit equals rate target major units. */
export class ExchangeRate {
  readonly source: CurrencyUnit;
  readonly target: CurrencyUnit;
  readonly decimal: string;
  private readonly coefficient: bigint;
  private readonly decimalScale: number;

  constructor(source: CurrencyUnit, target: CurrencyUnit, rate: string) {
    if (source.matches(target) || rate.length > 64 || !/^[0-9]+(\.[0-9]+)?$/.test(rate)) {
      throw new Error('INVALID_EXCHANGE_RATE');
    }
    const parts = rate.split('.');
    const fraction = parts.length === 2 ? parts[1] : '';
    const coefficient = BigInt(parts[0] + fraction);
    if (coefficient <= BigInt(0)) {
      throw new Error('INVALID_EXCHANGE_RATE');
    }
    this.source = source;
    this.target = target;
    this.decimal = rate;
    this.coefficient = coefficient;
    this.decimalScale = fraction.length;
  }

  /** HALF_UP: ties round away from zero, only once at the target currency boundary. */
  convert(amount: Money): Money {
    if (!amount.currency.matches(this.source)) {
      throw new Error('CURRENCY_MISMATCH');
    }
    const negative = amount.minor < BigInt(0);
    const absolute = negative ? -amount.minor : amount.minor;
    const numerator = absolute * this.coefficient * this.power(this.target.scale);
    const denominator = this.power(this.source.scale + this.decimalScale);
    let rounded = numerator / denominator;
    if ((numerator % denominator) * BigInt(2) >= denominator) {
      rounded += BigInt(1);
    }
    return Money.fromMinor(negative ? -rounded : rounded, this.target);
  }

  private power(exponent: number): bigint {
    return BigInt(10) ** BigInt(exponent);
  }
}
