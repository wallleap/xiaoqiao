import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';

/** Addition/subtraction only. No eval, parseFloat, or binary floating point money arithmetic. */
export class ExpenseAmountInput {
  static append(expression: string, key: string, scale: number = 2): string {
    if (key === '⌫') { return expression.length <= 1 ? '0' : expression.substring(0, expression.length - 1); }
    if (key === '+' || key === '−') {
      if (expression.endsWith('+') || expression.endsWith('−')) {
        return expression.substring(0, expression.length - 1) + key;
      }
      return expression.endsWith('.') ? expression + '0' + key : expression + key;
    }
    if (!/^[0-9.]$/.test(key) || expression.length >= 64) { return expression; }
    const start = Math.max(expression.lastIndexOf('+'), expression.lastIndexOf('−')) + 1;
    const operand = expression.substring(start);
    if (key === '.') {
      if (scale === 0 || operand.includes('.')) { return expression; }
      return expression + (operand.length === 0 ? '0.' : '.');
    }
    if (operand.includes('.') && operand.split('.')[1].length >= scale) { return expression; }
    return operand === '0' ? expression.substring(0, start) + key : expression + key;
  }

  /** Discount UI policy: nine integer digits per operand and at most 64 expression characters. */
  static appendDiscount(expression: string, key: string, scale: number): string {
    const next = ExpenseAmountInput.append(expression, key, scale);
    return next.length <= 64 && next.split(/[+−]/).every((term: string) => term.split('.')[0].length <= 9)
      ? next : expression;
  }

  static evaluateDiscount(expression: string, currency: CurrencyUnit): Money {
    if (expression.split(/[+−]/).some((term: string) => term.split('.')[0].length > 9)) {
      throw new Error('DISCOUNT_OUT_OF_RANGE');
    }
    const value = ExpenseAmountInput.evaluate(expression, currency);
    if (value.minor < BigInt(0) || value.minor >= BigInt(10) ** BigInt(9 + currency.scale)) {
      throw new Error('DISCOUNT_OUT_OF_RANGE');
    }
    return value;
  }

  /** Pending trailing operators are allowed only while typing, never for preview or save. */
  static paidAmount(gross: string, discount: string, currency: CurrencyUnit, allowPending: boolean = false): Money {
    const grossInput = allowPending && /[+−]$/.test(gross) ? gross.slice(0, -1) : gross;
    const discountInput = allowPending && /[+−]$/.test(discount) ? discount.slice(0, -1) : discount;
    const paid = ExpenseAmountInput.evaluate(grossInput, currency)
      .subtract(ExpenseAmountInput.evaluateDiscount(discountInput || '0', currency));
    paid.toSafeMinorNumber();
    return paid;
  }

  static appendChecked(gross: string, discount: string, key: string, currency: CurrencyUnit,
    discountEditing: boolean): string {
    const next = discountEditing ? ExpenseAmountInput.appendDiscount(discount, key, currency.scale) :
      ExpenseAmountInput.append(gross, key, currency.scale);
    // Recovery must remain possible even when deletion leaves a pending expression.
    if (key !== '⌫') {
      ExpenseAmountInput.paidAmount(discountEditing ? gross : next, discountEditing ? next : discount, currency, true);
    }
    return next;
  }

  static nonnegative(expression: string, currency: CurrencyUnit, allowPending: boolean = false): Money {
    const amount = ExpenseAmountInput.paidAmount(expression, '0', currency, allowPending);
    if (amount.minor < BigInt(0)) { throw new Error('NEGATIVE_AMOUNT'); }
    return amount;
  }

  static appendNonnegative(expression: string, key: string, currency: CurrencyUnit): string {
    const next = ExpenseAmountInput.append(expression, key, currency.scale);
    if (key !== '⌫') { ExpenseAmountInput.nonnegative(next, currency, true); }
    return next;
  }

  static evaluate(expression: string, currency: CurrencyUnit): Money {
    if (expression.length > 64 || !/^\d+(\.\d*)?([+−]\d+(\.\d*)?)*$/.test(expression)) {
      throw new Error('INCOMPLETE_AMOUNT_EXPRESSION');
    }
    const terms = expression.split(/[+−]/);
    const signs = expression.match(/[+−]/g) || [];
    let result = Money.parse(terms[0].endsWith('.') ? terms[0] + '0' : terms[0], currency);
    for (let index = 1; index < terms.length; index++) {
      const text = terms[index].endsWith('.') ? terms[index] + '0' : terms[index];
      const term = Money.parse(text, currency);
      result = signs[index - 1] === '+' ? result.add(term) : result.subtract(term);
    }
    result.toSafeMinorNumber();
    return result;
  }
}
