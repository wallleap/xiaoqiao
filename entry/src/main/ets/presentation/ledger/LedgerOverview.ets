import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';

export enum LedgerKind { All, Expense, Income }

export interface LedgerEntry {
  id: string;
  title: string;
  category: string;
  account: string;
  date: string;
  time: string;
  income: boolean;
  minor: string;
  icon: Resource;
}

export function displayAmount(minor: string): string {
  const value = Money.fromMinorText(minor, new CurrencyUnit('CNY', 'CNY', 2)).toDecimalString();
  const parts = value.split('.');
  return parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',') + '.' + parts[1];
}

export function filterEntries(entries: LedgerEntry[], kind: LedgerKind, query: string,
  account: string): LedgerEntry[] {
  const keyword = query.trim().toLowerCase();
  return entries.filter((entry: LedgerEntry) =>
    (kind === LedgerKind.All || entry.income === (kind === LedgerKind.Income)) &&
    (account.length === 0 || entry.account === account) &&
    (keyword.length === 0 || (entry.title + entry.category + entry.account).toLowerCase().includes(keyword)));
}

/** Explicit UI test fixture only. Normal launch has no example transactions. Never persisted. */
export function previewEntries(expanded: boolean = false): LedgerEntry[] {
  const entries: LedgerEntry[] = [
    { id: 'preview-lunch', title: '午餐', category: '餐饮', account: '微信零钱', date: '2026-10-28',
      time: '12:30', income: false, minor: '2800', icon: $r('app.media.colorful_icon_0287') },
    { id: 'preview-metro', title: '地铁', category: '交通', account: '微信零钱', date: '2026-10-28',
      time: '08:20', income: false, minor: '400', icon: $r('app.media.colorful_icon_0111') },
    { id: 'preview-salary', title: '工资', category: '工资', account: '日常储蓄卡', date: '2026-10-25',
      time: '09:00', income: true, minor: '860000', icon: $r('app.media.colorful_icon_0138') }
  ];
  if (expanded) {
    for (let index = 0; index < 12; index++) {
      entries.push({ id: index === 11 ? 'preview-scroll-tail' : `preview-scroll-${index}`,
        title: index === 11 ? '滚动验证末项' : `日常支出 ${index + 1}`, category: '餐饮', account: '微信零钱',
        date: '2026-10-24', time: '12:30', income: false, minor: '1000', icon: $r('app.media.colorful_icon_0287') });
    }
  }
  return entries;
}
