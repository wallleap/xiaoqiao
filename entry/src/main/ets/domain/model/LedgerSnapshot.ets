export interface ExpenseCategory {
  id: string;
  name: string;
  parentId: string;
  iconKey: string;
}

export interface LedgerAccount {
  id: string;
  name: string;
  currencyId: string;
}

export interface SavedLedgerEntry {
  id: string;
  note: string;
  category: string;
  iconKey: string;
  account: string;
  date: string;
  occurredAtMs: number;
  offsetMinutes: number;
  income: boolean;
  minor: string;
  grossMinor: string;
  discountMinor: string;
}

export interface LedgerSnapshot {
  bookId: string;
  bookName: string;
  categories: ExpenseCategory[];
  incomeCategories: ExpenseCategory[];
  accounts: LedgerAccount[];
  entries: SavedLedgerEntry[];
  incomeMinor: string;
  expenseMinor: string;
  budgetTotalMinor: string;
  budgetUsedMinor: string;
}
