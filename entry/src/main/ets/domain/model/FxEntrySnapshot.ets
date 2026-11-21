import { FxConversion, validateConversion } from '../../core/money/FxConversion';
import { currencyUnit } from '../../core/money/Currencies';
import { Money } from '../../core/money/Money';

/** Portable exact monetary fields. All amounts are minor-unit integer strings. */
export interface FxEntrySnapshot {
  currencyId: string;
  paidMinor: string;
  grossMinor: string;
  discountMinor: string;
  bookMinor: string;
  bookCurrencyId?: string;
  accountCurrencyId: string;
  accountMinor: string;
  bookFx?: FxConversion;
  accountFx?: FxConversion;
  receivedCurrencyId?: string;
  receivedMinor?: string;
  bookFeeMinor?: string;
}

export function parseFxEntry(text: string): FxEntrySnapshot {
  if (text.length > 4096) { throw new Error('FX_IMPORT_INVALID'); }
  const value = JSON.parse(text) as FxEntrySnapshot;
  const from = currencyUnit(value.currencyId);
  const paid = Money.fromMinorText(value.paidMinor, from);
  const gross = Money.fromMinorText(value.grossMinor, from);
  const discount = Money.fromMinorText(value.discountMinor, from);
  if (paid.minor <= BigInt(0) || gross.subtract(discount).minor !== paid.minor || discount.minor < BigInt(0)) { throw new Error('FX_IMPORT_INVALID'); }
  const book = Money.fromMinorText(value.bookMinor, currencyUnit(value.bookCurrencyId || 'CNY'));
  validateConversion(paid, book, value.bookFx);
  paid.toSafeMinorNumber(); gross.toSafeMinorNumber(); discount.toSafeMinorNumber(); book.toSafeMinorNumber();
  const settled = Money.fromMinorText(value.receivedMinor || value.accountMinor, currencyUnit(value.receivedCurrencyId || value.accountCurrencyId));
  settled.toSafeMinorNumber();
  if (settled.minor <= BigInt(0)) { throw new Error('FX_IMPORT_INVALID'); }
  validateConversion(paid, settled, value.accountFx);
  if (value.bookFeeMinor !== undefined) {
    const fee = Money.fromMinorText(value.bookFeeMinor, currencyUnit(value.bookCurrencyId || 'CNY'));
    fee.toSafeMinorNumber();
    if (fee.minor < BigInt(0)) { throw new Error('FX_IMPORT_INVALID'); }
  }
  return value;
}
