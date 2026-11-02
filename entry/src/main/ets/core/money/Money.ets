import { CurrencyUnit } from './CurrencyUnit';

/** Wire/JSON amounts are decimal integer strings, never JSON floating point values. */
export interface MoneyData {
  currencyId: string;
  amountMinor: string;
}

export class Money {
  readonly minor: bigint;
  readonly currency: CurrencyUnit;

  private constructor(minor: bigint, currency: CurrencyUnit) {
    this.minor = minor;
    this.currency = currency;
  }

  static fromMinor(minor: bigint, currency: CurrencyUnit): Money {
    return new Money(minor, currency);
  }

  static fromMinorText(text: string, currency: CurrencyUnit): Money {
    if (text.length > 1024 || !/^-?(0|[1-9][0-9]*)$/.test(text)) {
      throw new Error('INVALID_MINOR_AMOUNT');
    }
    return new Money(BigInt(text), currency);
  }

  static parse(text: string, currency: CurrencyUnit): Money {
    const input = text.trim();
    if (input.length === 0 || input.length > 1024 || !/^-?[0-9]+(\.[0-9]+)?$/.test(input)) {
      throw new Error('INVALID_AMOUNT');
    }
    const negative = input.startsWith('-');
    const absolute = negative ? input.substring(1) : input;
    const parts = absolute.split('.');
    const fraction = parts.length === 2 ? parts[1] : '';
    if (fraction.length > currency.scale) {
      throw new Error('AMOUNT_PRECISION_EXCEEDED');
    }
    const digits = parts[0] + fraction.padEnd(currency.scale, '0');
    const value = BigInt(digits);
    return new Money(negative ? -value : value, currency);
  }

  static fromData(data: MoneyData, currency: CurrencyUnit): Money {
    if (data.currencyId !== currency.id) {
      throw new Error('CURRENCY_MISMATCH');
    }
    return Money.fromMinorText(data.amountMinor, currency);
  }

  add(other: Money): Money {
    this.requireCurrency(other);
    return new Money(this.minor + other.minor, this.currency);
  }

  subtract(other: Money): Money {
    this.requireCurrency(other);
    return new Money(this.minor - other.minor, this.currency);
  }

  negate(): Money {
    return new Money(-this.minor, this.currency);
  }

  toDecimalString(): string {
    const negative = this.minor < BigInt(0);
    const digits = (negative ? -this.minor : this.minor).toString();
    const scale = this.currency.scale;
    if (scale === 0) {
      return (negative ? '-' : '') + digits;
    }
    const padded = digits.padStart(scale + 1, '0');
    return (negative ? '-' : '') + padded.substring(0, padded.length - scale) + '.' +
      padded.substring(padded.length - scale);
  }

  toData(): MoneyData {
    return { currencyId: this.currency.id, amountMinor: this.minor.toString() };
  }

  /** V1 persisted values deliberately retain the SQL safe-integer limit. */
  toSafeMinorNumber(): number {
    const limit = BigInt('9007199254740991');
    if (this.minor > limit || this.minor < -limit) {
      throw new Error('PERSISTED_AMOUNT_OUT_OF_RANGE');
    }
    return Number(this.minor.toString());
  }

  private requireCurrency(other: Money): void {
    if (!this.currency.matches(other.currency)) {
      throw new Error('CURRENCY_MISMATCH');
    }
  }
}
