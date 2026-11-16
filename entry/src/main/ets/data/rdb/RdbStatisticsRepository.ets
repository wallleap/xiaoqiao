import { relationalStore } from '@kit.ArkData';
import { LedgerStatistics, StatisticsBucket, StatisticsBucketUnit, StatisticsBudgetCategory,
  StatisticsCategory, StatisticsEntry, StatisticsKind, StatisticsTagCategory } from '../../domain/model/LedgerStatistics';

interface CategoryMeta {
  id: string;
  parentId: string;
  name: string;
  iconKey: string;
}

interface NatureMeta {
  id: string;
  name: string;
  colorKey: string;
}

interface StatisticsRawEntry {
  id: string;
  kind: string;
  tagSourceId?: string;
  note: string;
  categoryId: string;
  natureId: string;
  includeInBudget: boolean;
  bookMinor: string;
  paidMinor: string;
  date: string;
  feeMinor: string;
  feeInExpense: boolean;
  feeInBudget: boolean;
  occurredAtMs: number;
}

interface CategoryTotal {
  key: string;
  name: string;
  iconKey: string;
  amount: bigint;
}

interface BudgetCategoryTotal {
  key: string;
  name: string;
  colorKey: string;
  amount: bigint;
}

interface TagMeta {
  id: string;
  name: string;
  colorKey: string;
}

interface TagTotal {
  tag: TagMeta;
  amount: bigint;
  entryCount: number;
}

const TRANSFER_FEE_KEY: string = 'transfer_fee';
const UNASSIGNED_KEY: string = 'unassigned';

function pad(value: number): string {
  return String(value).padStart(2, '0');
}

function parseDate(value: string): Date {
  const parts = value.split('-');
  return new Date(Date.UTC(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0, 0));
}

function formatDate(date: Date): string {
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
}

function nextDay(value: string): string {
  const date = parseDate(value);
  date.setUTCDate(date.getUTCDate() + 1);
  return formatDate(date);
}

function nextMonth(value: string): string {
  const date = parseDate(value);
  date.setUTCMonth(date.getUTCMonth() + 1);
  return formatDate(date);
}

function bucketKey(date: string, unit: StatisticsBucketUnit): string {
  return unit === 'month' ? date.substring(0, 7) : date;
}

function bucketLabel(key: string, unit: StatisticsBucketUnit): string {
  if (unit === 'month') { return Number(key.substring(5)) + '月'; }
  return `${Number(key.substring(5, 7))}/${Number(key.substring(8, 10))}`;
}

function shareOf(amount: bigint, total: bigint): number {
  if (total <= BigInt(0)) { return 0; }
  return Number(amount * BigInt(10000) / total) / 100;
}

export class RdbStatisticsRepository {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  private validateRange(startDate: string, endDateExclusive: string): void {
    const pattern = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/;
    if (!pattern.test(startDate) || !pattern.test(endDateExclusive) || startDate >= endDateExclusive) {
      throw new Error('INVALID_STATISTICS_RANGE');
    }
  }

  private async categories(bookId: string): Promise<Map<string, CategoryMeta>> {
    const values: Map<string, CategoryMeta> = new Map();
    const rows = await this.store.querySql(
      "SELECT id,COALESCE(parent_id,''),name,COALESCE(icon_key,'other') FROM categories WHERE book_id=?",
      [bookId]);
    try {
      while (rows.goToNextRow()) {
        values.set(rows.getString(0), { id: rows.getString(0), parentId: rows.getString(1),
          name: rows.getString(2), iconKey: rows.getString(3) });
      }
    } finally { rows.close(); }
    return values;
  }

  private async natures(): Promise<Map<string, NatureMeta>> {
    const values: Map<string, NatureMeta> = new Map();
    const rows = await this.store.querySql(
      "SELECT id,name,COALESCE(custom_color,color_token,'neutral') FROM spending_natures WHERE deleted_at_ms IS NULL");
    try {
      while (rows.goToNextRow()) {
        values.set(rows.getString(0), { id: rows.getString(0), name: rows.getString(1), colorKey: rows.getString(2) });
      }
    } finally { rows.close(); }
    return values;
  }

  private async tagLinks(bookId: string, startDate: string, endDateExclusive: string): Promise<Map<string, TagMeta[]>> {
    const links: Map<string, TagMeta[]> = new Map();
    const rows = await this.store.querySql('SELECT tt.transaction_id,g.id,g.name,COALESCE(g.color_token,\'neutral\') ' +
      'FROM transaction_tags tt JOIN tags g ON g.id=tt.tag_id JOIN v_posted_transactions tx ON tx.id=tt.transaction_id ' +
      'WHERE tt.book_id=? AND ((tx.occurred_local_date>=? AND tx.occurred_local_date<?) OR EXISTS(SELECT 1 FROM v_expense_recoveries r WHERE r.transaction_id=tx.id AND r.local_date>=? AND r.local_date<?)) ' +
      'ORDER BY g.sort_order,g.created_at_ms,g.id',
      [bookId, startDate, endDateExclusive, startDate, endDateExclusive]);
    try {
      while (rows.goToNextRow()) {
        const transactionId = rows.getString(0);
        const values = links.get(transactionId) || [];
        values.push({ id: rows.getString(1), name: rows.getString(2), colorKey: rows.getString(3) });
        links.set(transactionId, values);
      }
    } finally { rows.close(); }
    return links;
  }

  private async rawEntries(bookId: string, startDate: string, endDateExclusive: string): Promise<StatisticsRawEntry[]> {
    const values: StatisticsRawEntry[] = [];
    const rows = await this.store.querySql(
      "SELECT t.id,t.kind,COALESCE(t.note,''),COALESCE(t.category_id,''),COALESCE(raw.spending_nature_id,'')," +
      "t.include_in_budget,CAST(COALESCE(t.book_minor,0) AS TEXT),CAST(COALESCE(t.paid_minor,0) AS TEXT)," +
      "t.occurred_local_date,CAST(COALESCE(d.book_fee_minor,0) AS TEXT),COALESCE(d.fee_in_expense,1)," +
      "COALESCE(d.fee_in_budget,1),t.occurred_at_ms " +
      "FROM v_posted_transactions t JOIN transactions raw ON raw.id=t.id LEFT JOIN v_transfer_details d ON d.transaction_id=t.id " +
      "WHERE t.book_id=? AND t.occurred_local_date>=? AND t.occurred_local_date<? " +
      "ORDER BY t.occurred_at_ms DESC,t.created_at_ms DESC,t.id DESC",
      [bookId, startDate, endDateExclusive]);
    try {
      while (rows.goToNextRow()) {
        values.push({ id: rows.getString(0), kind: rows.getString(1), note: rows.getString(2),
          categoryId: rows.getString(3), natureId: rows.getString(4), includeInBudget: rows.getLong(5) === 1,
          bookMinor: rows.getString(6), paidMinor: rows.getString(7), date: rows.getString(8),
          feeMinor: rows.getString(9), feeInExpense: rows.getLong(10) === 1, feeInBudget: rows.getLong(11) === 1,
          occurredAtMs: rows.getLong(12) });
      }
    } finally { rows.close(); }
    const receipts = await this.store.querySql("SELECT id,transaction_id,kind,note,category_id,COALESCE(spending_nature_id,''),include_in_budget,CAST(book_minor AS TEXT),local_date,occurred_at_ms FROM v_expense_recoveries WHERE book_id=? AND local_date>=? AND local_date<?", [bookId, startDate, endDateExclusive]);
    try {
      while (receipts.goToNextRow()) {
        const minor = '-' + receipts.getString(7);
        values.push({ id: receipts.getString(0), tagSourceId: receipts.getString(1), kind: 'expense',
          note: (receipts.getString(2) === 'refund' ? '退款' : '报销到账') + (receipts.getString(3) ? ' · ' + receipts.getString(3) : ''),
          categoryId: receipts.getString(4), natureId: receipts.getString(5), includeInBudget: receipts.getLong(6) === 1,
          bookMinor: minor, paidMinor: minor, date: receipts.getString(8), occurredAtMs: receipts.getLong(9),
          feeMinor: '0', feeInExpense: false, feeInBudget: false });
      }
    } finally { receipts.close(); }
    values.sort((a: StatisticsRawEntry, b: StatisticsRawEntry) => b.occurredAtMs - a.occurredAtMs || a.id.localeCompare(b.id));
    return values;
  }

  private rootCategory(id: string, categories: Map<string, CategoryMeta>): CategoryMeta | undefined {
    let current = categories.get(id);
    const visited: Set<string> = new Set();
    while (current !== undefined && current.parentId.length > 0 && !visited.has(current.id)) {
      visited.add(current.id);
      const parent = categories.get(current.parentId);
      if (parent === undefined) { break; }
      current = parent;
    }
    return current;
  }

  private effectiveAmount(entry: StatisticsRawEntry, kind: StatisticsKind): bigint {
    if (kind === 'income') { return entry.kind === 'income' ? BigInt(entry.bookMinor || entry.paidMinor) : BigInt(0); }
    if (entry.kind === 'expense') { return BigInt(entry.bookMinor || entry.paidMinor); }
    return entry.kind === 'transfer' && entry.feeInExpense ? BigInt(entry.feeMinor) : BigInt(0);
  }

  private buildBuckets(startDate: string, endDateExclusive: string, unit: StatisticsBucketUnit,
    totals: Map<string, bigint>): StatisticsBucket[] {
    const buckets: StatisticsBucket[] = [];
    let cursor = unit === 'month' ? startDate.substring(0, 7) + '-01' : startDate;
    const limit = unit === 'month' ? endDateExclusive.substring(0, 7) + '-01' : endDateExclusive;
    let guard = 0;
    while (cursor < limit && guard < 4000) {
      const key = bucketKey(cursor, unit);
      buckets.push({ key: key, label: bucketLabel(key, unit), amountMinor: (totals.get(key) || BigInt(0)).toString() });
      cursor = unit === 'month' ? nextMonth(cursor) : nextDay(cursor);
      guard++;
    }
    return buckets;
  }

  async snapshot(bookId: string, startDate: string, endDateExclusive: string, kind: StatisticsKind,
    unit: StatisticsBucketUnit): Promise<LedgerStatistics> {
    this.validateRange(startDate, endDateExclusive);
    const records = await this.rawEntries(bookId, startDate, endDateExclusive);
    const categories = await this.categories(bookId);
    const natures = await this.natures();
    const tagsByTransaction = await this.tagLinks(bookId, startDate, endDateExclusive);
    const categoryTotals: Map<string, CategoryTotal> = new Map();
    const budgetTotals: Map<string, BudgetCategoryTotal> = new Map();
    const bucketTotals: Map<string, bigint> = new Map();
    const tagTotals: Map<string, TagTotal> = new Map();
    let total = BigInt(0);
    for (const entry of records) {
      const amount = this.effectiveAmount(entry, kind);
      if (amount === BigInt(0)) { continue; }
      total += amount;
      const key = bucketKey(entry.date, unit);
      bucketTotals.set(key, (bucketTotals.get(key) || BigInt(0)) + amount);
      for (const tag of tagsByTransaction.get(entry.tagSourceId || entry.id) || []) {
        const current = tagTotals.get(tag.id);
        tagTotals.set(tag.id, { tag: tag, amount: (current?.amount || BigInt(0)) + amount,
          entryCount: (current?.entryCount || 0) + 1 });
      }
      if (entry.kind === 'transfer') {
        const current = categoryTotals.get(TRANSFER_FEE_KEY);
        categoryTotals.set(TRANSFER_FEE_KEY, { key: TRANSFER_FEE_KEY, name: '转账手续费', iconKey: 'transfer',
          amount: (current?.amount || BigInt(0)) + amount });
        if (kind === 'expense' && entry.feeInBudget) {
          const assigned = budgetTotals.get(UNASSIGNED_KEY);
          budgetTotals.set(UNASSIGNED_KEY, { key: UNASSIGNED_KEY, name: '未分配', colorKey: 'neutral',
            amount: (assigned?.amount || BigInt(0)) + amount });
        }
        continue;
      }
      const category = this.rootCategory(entry.categoryId, categories);
      if (category !== undefined) {
        const current = categoryTotals.get(category.id);
        categoryTotals.set(category.id, { key: category.id, name: category.name, iconKey: category.iconKey,
          amount: (current?.amount || BigInt(0)) + amount });
      }
      if (kind === 'expense' && entry.kind === 'expense' && entry.includeInBudget) {
        const nature = entry.natureId.length > 0 ? natures.get(entry.natureId) : undefined;
        const natureKey = nature?.id || UNASSIGNED_KEY;
        const current = budgetTotals.get(natureKey);
        budgetTotals.set(natureKey, { key: natureKey, name: nature?.name || '未分配',
          colorKey: nature?.colorKey || 'neutral', amount: (current?.amount || BigInt(0)) + amount });
      }
    }
    const categoryValues: StatisticsCategory[] = [];
    categoryTotals.forEach((value: CategoryTotal) => {
      categoryValues.push({ key: value.key, name: value.name, iconKey: value.iconKey, amountMinor: value.amount.toString(),
        share: shareOf(value.amount, total) });
    });
    categoryValues.sort((left: StatisticsCategory, right: StatisticsCategory): number => {
      const leftAmount = BigInt(left.amountMinor);
      const rightAmount = BigInt(right.amountMinor);
      if (leftAmount === rightAmount) { return left.name.localeCompare(right.name, 'zh-CN'); }
      return leftAmount > rightAmount ? -1 : 1;
    });
    const budgetValues: StatisticsBudgetCategory[] = [];
    budgetTotals.forEach((value: BudgetCategoryTotal) => {
      budgetValues.push({ key: value.key, name: value.name, colorKey: value.colorKey, amountMinor: value.amount.toString(),
        share: shareOf(value.amount, total) });
    });
    budgetValues.sort((left: StatisticsBudgetCategory, right: StatisticsBudgetCategory): number => {
      const leftAmount = BigInt(left.amountMinor);
      const rightAmount = BigInt(right.amountMinor);
      if (leftAmount === rightAmount) { return left.name.localeCompare(right.name, 'zh-CN'); }
      return leftAmount > rightAmount ? -1 : 1;
    });
    const tagValues: StatisticsTagCategory[] = [];
    tagTotals.forEach((value: TagTotal) => {
      tagValues.push({ key: value.tag.id, name: value.tag.name, colorKey: value.tag.colorKey,
        amountMinor: value.amount.toString(), share: shareOf(value.amount, total), entryCount: value.entryCount });
    });
    tagValues.sort((left: StatisticsTagCategory, right: StatisticsTagCategory): number => {
      const leftAmount = BigInt(left.amountMinor);
      const rightAmount = BigInt(right.amountMinor);
      if (leftAmount === rightAmount) { return left.name.localeCompare(right.name, 'zh-CN'); }
      return leftAmount > rightAmount ? -1 : 1;
    });
    return { bookId: bookId, startDate: startDate, endDateExclusive: endDateExclusive, kind: kind,
      totalMinor: total.toString(), buckets: this.buildBuckets(startDate, endDateExclusive, unit, bucketTotals),
      categories: categoryValues, budgetCategories: kind === 'expense' ? budgetValues : [], tagCategories: tagValues };
  }

  async entries(bookId: string, startDate: string, endDateExclusive: string, kind: StatisticsKind,
    categoryKey: string, tagId: string = ''): Promise<StatisticsEntry[]> {
    this.validateRange(startDate, endDateExclusive);
    const records = await this.rawEntries(bookId, startDate, endDateExclusive);
    const categories = await this.categories(bookId);
    const tagsByTransaction = await this.tagLinks(bookId, startDate, endDateExclusive);
    const values: StatisticsEntry[] = [];
    for (const entry of records) {
      const amount = this.effectiveAmount(entry, kind);
      if (amount === BigInt(0)) { continue; }
      let entryKey = TRANSFER_FEE_KEY;
      let entryName = '转账手续费';
      let iconKey = 'transfer';
      if (entry.kind !== 'transfer') {
        const category = this.rootCategory(entry.categoryId, categories);
        entryKey = category?.id || '';
        entryName = category?.name || '未知分类';
        iconKey = category?.iconKey || 'other';
      }
      if (categoryKey.length > 0 && categoryKey !== entryKey) { continue; }
      if (tagId.length > 0 && !(tagsByTransaction.get(entry.tagSourceId || entry.id) || []).some((tag: TagMeta) => tag.id === tagId)) {
        continue;
      }
      values.push({ id: entry.id, title: entry.note.length > 0 ? entry.note : entryName, categoryKey: entryKey,
        categoryName: entryName, iconKey: iconKey, date: entry.date, amountMinor: amount.toString() });
    }
    return values;
  }
}
