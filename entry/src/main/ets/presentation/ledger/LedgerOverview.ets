import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';
import { SavedLedgerEntry } from '../../domain/model/LedgerSnapshot';
import { categoryIcon } from './CategoryIcons';

export enum LedgerKind { All, Expense, Income }

export interface NavigationHandoff {
  titleOpacity: number;
  filterOffset: number;
  inNavigation: boolean;
}

/** Scroll-linked handoff: fade the title before the filters enter its fixed frame. */
export function navigationHandoff(offset: number, filterStart: number, titleHeight: number): NavigationHandoff {
  if (!Number.isFinite(filterStart)) {
    return { titleOpacity: 1, filterOffset: titleHeight, inNavigation: false };
  }
  const fade = Math.max(0, Math.min(1, (offset - filterStart + titleHeight) / titleHeight));
  return { titleOpacity: 1 - fade * fade * (3 - 2 * fade),
    filterOffset: Math.max(0, Math.min(titleHeight, filterStart + titleHeight - offset)),
    inNavigation: offset >= filterStart };
}

export interface LedgerEntry {
  id: string;
  title: string;
  category: string;
  account: string;
  date: string;
  time: string;
  income: boolean;
  transfer?: boolean;
  recoveryKind?: string;
  reimbursementPending?: boolean;
  recoveryBadges?: string[];
  toAccount?: string;
  expenseMinor?: string;
  transferFeeMinor?: string;
  transferCouponMinor?: string;
  minor: string;
  grossMinor: string;
  discountMinor: string;
  tags?: string[];
  tagIds?: string[];
  icon: Resource;
}

export function displayAmount(minor: string): string {
  const value = Money.fromMinorText(minor, new CurrencyUnit('CNY', 'CNY', 2)).toDecimalString();
  const parts = value.split('.');
  return parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',') + '.' + parts[1];
}

/** Badges describe the original expense; receipt rows already name their own type. */
function expenseRecoveryBadges(entry: SavedLedgerEntry): string[] {
  if (entry.income || entry.transfer || entry.recoveryKind) { return []; }
  const paid = BigInt(entry.minor);
  const reimbursed = BigInt(entry.reimbursedMinor || '0');
  const refunded = BigInt(entry.refundedMinor || '0');
  const recovered = BigInt(entry.recoveredMinor || (reimbursed + refunded).toString());
  const badges: string[] = [];
  if (entry.reimbursementPending && reimbursed === BigInt(0) && recovered < paid) { badges.push('待报销'); }
  if (reimbursed > BigInt(0)) { badges.push(reimbursed >= paid ? '已报销' : '部分报销'); }
  if (refunded > BigInt(0)) { badges.push(refunded >= paid ? '已退款' : '部分退款'); }
  return badges;
}

export function presentEntry(entry: SavedLedgerEntry): LedgerEntry {
  const local = new Date(entry.occurredAtMs + entry.offsetMinutes * 60000);
  return { id: entry.id, title: entry.recoveryKind ? (entry.recoveryKind === 'refund' ? '退款' : '报销到账') + (entry.note ? ' · ' + entry.note : '') : entry.note.length > 0 ? entry.note : entry.category, category: entry.category,
    account: entry.account, date: entry.date, time: String(local.getUTCHours()).padStart(2, '0') + ':' +
      String(local.getUTCMinutes()).padStart(2, '0'), income: entry.income, recoveryKind: entry.recoveryKind, reimbursementPending: entry.reimbursementPending === true && BigInt(entry.recoveredMinor || '0') < BigInt(entry.minor), transfer: entry.transfer, toAccount: entry.toAccount, minor: entry.minor,
    expenseMinor: entry.expenseMinor, transferFeeMinor: entry.transferFeeMinor, transferCouponMinor: entry.transferCouponMinor,
    grossMinor: entry.grossMinor, discountMinor: entry.discountMinor, tags: entry.tagNames || [],
    tagIds: entry.tagIds || [], recoveryBadges: expenseRecoveryBadges(entry),
    icon: entry.transfer ? $r('app.media.lucide_arrow_left_right1') : categoryIcon(entry.iconKey) };
}

export function filterEntries(entries: LedgerEntry[], kind: LedgerKind, query: string,
  account: string, tagIds: string[] = []): LedgerEntry[] {
  const keyword = query.trim().toLowerCase();
  return entries.filter((entry: LedgerEntry) =>
    (kind === LedgerKind.All || (entry.transfer ? kind === LedgerKind.Expense && BigInt(entry.expenseMinor || '0') > BigInt(0) : entry.income === (kind === LedgerKind.Income))) &&
    (account.length === 0 || entry.account === account || entry.toAccount === account) &&
    tagIds.every((tagId: string) => (entry.tagIds || []).includes(tagId)) &&
    (keyword.length === 0 || (entry.title + entry.category + entry.account + (entry.toAccount || '') +
      (entry.tags || []).join(' ')).toLowerCase().includes(keyword)));
}

/** Explicit UI test fixture only. Normal launch has no example transactions. Never persisted. */
export function previewEntries(expanded: boolean = false): LedgerEntry[] {
  const entries: LedgerEntry[] = [
    { id: 'preview-lunch', title: '午餐', category: '餐饮', account: '微信零钱', date: '2026-10-28',
      time: '12:30', income: false, minor: '2800', grossMinor: '3000', discountMinor: '200', icon: categoryIcon('colorful_icon_0287') },
    { id: 'preview-metro', title: '地铁', category: '交通', account: '微信零钱', date: '2026-10-28',
      time: '08:20', income: false, minor: '400', grossMinor: '400', discountMinor: '0', icon: categoryIcon('colorful_icon_0111') },
    { id: 'preview-salary', title: '工资', category: '工资', account: '日常储蓄卡', date: '2026-10-25',
      time: '09:00', income: true, minor: '860000', grossMinor: '860000', discountMinor: '0', icon: categoryIcon('colorful_icon_0138') }
  ];
  if (expanded) {
    for (let index = 0; index < 12; index++) {
      entries.push({ id: index === 11 ? 'preview-scroll-tail' : `preview-scroll-${index}`,
        title: index === 11 ? '滚动验证末项' : `日常支出 ${index + 1}`, category: '餐饮', account: '微信零钱',
        date: '2026-10-24', time: '12:30', income: false, minor: '1000', grossMinor: '1000', discountMinor: '0', icon: categoryIcon('colorful_icon_0287') });
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
