import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { ExpenseAmountInput } from './ExpenseAmountInput';

export interface CurrencySwitchAmounts { amount: string; discount: string; fee: string; coupon: string; }

/** Preserve value exactly. Only redundant decimal zeros may be removed; never round to a new minor unit. */
function prepareAmount(text: string, currency: CurrencyUnit, label: string, discount: boolean = false): string {
  try {
    if (text.length > 64 || !/^\d+(\.\d*)?([+−]\d+(\.\d*)?)*$/.test(text)) { throw new Error('INCOMPLETE_AMOUNT'); }
    const normalized = text.replace(/\d+(\.\d*)?/g, (term: string): string => term.includes('.') ?
      term.replace(/0+$/, '').replace(/\.$/, '') : term);
    const value = discount ? ExpenseAmountInput.evaluateDiscount(normalized, currency) : ExpenseAmountInput.nonnegative(normalized, currency);
    value.toSafeMinorNumber();
    return normalized;
  } catch (_) { throw new Error(label + '需填写完整，且最多支持 ' + currency.scale.toString() + ' 位小数；请调整后再切换'); }
}

export function prepareCurrencySwitch(draft: CurrencySwitchAmounts, currency: CurrencyUnit, kind: string): CurrencySwitchAmounts {
  return { amount: prepareAmount(draft.amount, currency, '金额'),
    discount: kind === 'expense' ? prepareAmount(draft.discount, currency, '优惠', true) : draft.discount,
    fee: kind === 'transfer' ? prepareAmount(draft.fee, currency, '手续费') : draft.fee,
    coupon: kind === 'transfer' ? prepareAmount(draft.coupon, currency, '抵扣金额') : draft.coupon };
}
