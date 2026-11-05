import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';

export const DEFAULT_MONTHLY_BUDGET_MINOR: string = '250000';

export interface BudgetPeriod { start: string; endExclusive: string; }
export interface BudgetProgress { remainingMinor: string; percentText: string; ringValue: number; overBudget: boolean; }

export class MonthlyBudget {
  static period(month: string): BudgetPeriod {
    if (!/^\d{4}-\d{2}$/.test(month)) { throw new Error('INVALID_MONTH'); }
    const year = Number(month.substring(0, 4));
    const value = Number(month.substring(5));
    if (year < 1 || year > 9998 || value < 1 || value > 12) { throw new Error('INVALID_MONTH'); }
    const end = value === 12 ? `${String(year + 1).padStart(4, '0')}-01` : `${String(year).padStart(4, '0')}-${String(value + 1).padStart(2, '0')}`;
    return { start: month + '-01', endExclusive: end + '-01' };
  }

  static parse(text: string, currency: CurrencyUnit): Money {
    const value = Money.parse(text, currency);
    if (value.minor < BigInt(0)) { throw new Error('NEGATIVE_BUDGET'); }
    value.toSafeMinorNumber();
    return value;
  }

  static progress(totalMinor: string, usedMinor: string): BudgetProgress {
    const total = BigInt(totalMinor);
    const used = BigInt(usedMinor);
    const remaining = total - used;
    // Percentage is derived from integer minor units, rounded once to one decimal place.
    const tenths = total > BigInt(0) ? (used * BigInt(1000) + total / BigInt(2)) / total : BigInt(0);
    return { remainingMinor: remaining.toString(), overBudget: remaining < BigInt(0),
      percentText: total === BigInt(0) ? '—' : `${tenths / BigInt(10)}.${tenths % BigInt(10)}%`,
      ringValue: total === BigInt(0) ? (used > BigInt(0) ? 100 : 0) :
        Number(tenths > BigInt(1000) ? BigInt(1000) : tenths) / 10 };
  }
}
