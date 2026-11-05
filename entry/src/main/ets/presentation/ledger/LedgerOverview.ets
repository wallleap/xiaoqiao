import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';
import { SavedLedgerEntry } from '../../domain/model/LedgerSnapshot';
import { categoryIcon } from './CategoryIcons';

export enum LedgerKind { All, Expense, Income }

export interface LedgerEntry {
  id: string;
  title: string;
  category: string;
  account: string;
  date: string;
  time: string;
  income: boolean;
  transfer?: boolean;
  toAccount?: string;
  expenseMinor?: string;
  transferFeeMinor?: string;
  transferCouponMinor?: string;
  minor: string;
  grossMinor: string;
  discountMinor: string;
  icon: Resource;
}

export function displayAmount(minor: string): string {
  const value = Money.fromMinorText(minor, new CurrencyUnit('CNY', 'CNY', 2)).toDecimalString();
  const parts = value.split('.');
  return parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',') + '.' + parts[1];
}

export function presentEntry(entry: SavedLedgerEntry): LedgerEntry {
  const local = new Date(entry.occurredAtMs + entry.offsetMinutes * 60000);
  return { id: entry.id, title: entry.note.length > 0 ? entry.note : entry.category, category: entry.category,
    account: entry.account, date: entry.date, time: String(local.getUTCHours()).padStart(2, '0') + ':' +
      String(local.getUTCMinutes()).padStart(2, '0'), income: entry.income, transfer: entry.transfer, toAccount: entry.toAccount, minor: entry.minor,
      expenseMinor: entry.expenseMinor, transferFeeMinor: entry.transferFeeMinor, transferCouponMinor: entry.transferCouponMinor, grossMinor: entry.grossMinor, discountMinor: entry.discountMinor, icon: entry.transfer ? $r('app.media.lucide_arrow_left_right1') : categoryIcon(entry.iconKey) };
}

export function filterEntries(entries: LedgerEntry[], kind: LedgerKind, query: string,
  account: string): LedgerEntry[] {
  const keyword = query.trim().toLowerCase();
  return entries.filter((entry: LedgerEntry) =>
    (kind === LedgerKind.All || (entry.transfer ? kind === LedgerKind.Expense && BigInt(entry.expenseMinor || '0') > BigInt(0) : entry.income === (kind === LedgerKind.Income))) &&
    (account.length === 0 || entry.account === account || entry.toAccount === account) &&
    (keyword.length === 0 || (entry.title + entry.category + entry.account + (entry.toAccount || '')).toLowerCase().includes(keyword)));
}

/** Explicit UI test fixture only. Normal launch has no example transactions. Never persisted. */
export function previewEntries(expanded: boolean = false): LedgerEntry[] {
  const entries: LedgerEntry[] = [
    { id: 'preview-lunch', title: '午餐', category: '餐饮', account: '微信零钱', date: '2026-10-28',
      time: '12:30', income: false, minor: '2800', grossMinor: '3000', discountMinor: '200', icon: $r('app.media.colorful_icon_0287') },
    { id: 'preview-metro', title: '地铁', category: '交通', account: '微信零钱', date: '2026-10-28',
      time: '08:20', income: false, minor: '400', grossMinor: '400', discountMinor: '0', icon: $r('app.media.colorful_icon_0111') },
    { id: 'preview-salary', title: '工资', category: '工资', account: '日常储蓄卡', date: '2026-10-25',
      time: '09:00', income: true, minor: '860000', grossMinor: '860000', discountMinor: '0', icon: $r('app.media.colorful_icon_0138') }
  ];
  if (expanded) {
    for (let index = 0; index < 12; index++) {
      entries.push({ id: index === 11 ? 'preview-scroll-tail' : `preview-scroll-${index}`,
        title: index === 11 ? '滚动验证末项' : `日常支出 ${index + 1}`, category: '餐饮', account: '微信零钱',
        date: '2026-10-24', time: '12:30', income: false, minor: '1000', grossMinor: '1000', discountMinor: '0', icon: $r('app.media.colorful_icon_0287') });
    }
  }
  return entries;
}


export interface DailyTotals { incomeMinor: string; expenseMinor: string; }

/** Sum only the supplied visible entries; keep integer precision, including values beyond Number.MAX_SAFE_INTEGER. */
export function dailyTotals(entries: LedgerEntry[], date: string): DailyTotals {
  let income = BigInt(0);
  let expense = BigInt(0);
  for (const entry of entries) {
    if (entry.date === date) {
      if (entry.transfer) { expense += BigInt(entry.expenseMinor || '0'); }
      else if (entry.income) { income += BigInt(entry.minor); } else { expense += BigInt(entry.minor); }
    }
  }
  return { incomeMinor: income.toString(), expenseMinor: expense.toString() };
}

export function isToday(date: string, now: Date = new Date()): boolean {
  const localDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
  return date === localDate;
}
