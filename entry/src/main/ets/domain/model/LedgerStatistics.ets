export type StatisticsKind = 'expense' | 'income';
export type StatisticsBucketUnit = 'day' | 'month';

export interface StatisticsBucket {
  key: string;
  label: string;
  amountMinor: string;
}

export interface StatisticsCategory {
  key: string;
  name: string;
  iconKey: string;
  amountMinor: string;
  share: number;
}

export interface StatisticsBudgetCategory {
  key: string;
  name: string;
  colorKey: string;
  amountMinor: string;
  share: number;
}

export interface StatisticsTagCategory {
  key: string;
  name: string;
  colorKey: string;
  amountMinor: string;
  share: number;
  entryCount: number;
}

export interface StatisticsEntry {
  id: string;
  title: string;
  categoryKey: string;
  categoryName: string;
  iconKey: string;
  date: string;
  amountMinor: string;
}

export interface LedgerStatistics {
  bookId: string;
  startDate: string;
  endDateExclusive: string;
  kind: StatisticsKind;
  totalMinor: string;
  buckets: StatisticsBucket[];
  categories: StatisticsCategory[];
  budgetCategories: StatisticsBudgetCategory[];
  tagCategories: StatisticsTagCategory[];
}
