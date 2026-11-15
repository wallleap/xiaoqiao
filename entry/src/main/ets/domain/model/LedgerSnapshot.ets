import { BudgetNatureLine } from './SpendingNature';
import { LedgerAttachmentDraft } from './LedgerAttachment';
import { LedgerLocation } from './LedgerLocation';

export interface ExpenseCategory {
  id: string;
  name: string;
  parentId: string;
  iconKey: string;
}

export interface SpendingNatureChoice {
  id: string;
  name: string;
  colorKey: string;
}

export interface TagChoice {
  id: string;
  name: string;
  colorKey: string;
}

export interface LedgerAccount {
  id: string;
  name: string;
  currencyId: string;
  kind?: string;
}

export interface SavedLedgerEntry {
  id: string;
  note: string;
  category: string;
  iconKey: string;
  account: string;
  accountId?: string;
  date: string;
  occurredAtMs: number;
  offsetMinutes: number;
  income: boolean;
  transfer?: boolean;
  toAccount?: string;
  expenseMinor?: string;
  transferFeeMinor?: string;
  transferCouponMinor?: string;
  minor: string;
  grossMinor: string;
  discountMinor: string;
  tagIds?: string[];
  tagNames?: string[];
  merchantId?: string;
  merchant?: string;
  address?: string;
  location?: LedgerLocation;
  recoveryKind?: string;
  originalEntryId?: string;
  reimbursementPending?: boolean;
  recoveredMinor?: string;
  reimbursedMinor?: string;
  refundedMinor?: string;
  includeInBudget?: boolean;
  spendingNatureName?: string;
  spendingNatureColor?: string;
  transferPurpose?: string;
  feeInBudget?: boolean;
  attachments?: LedgerAttachmentDraft[];
}

export interface LedgerSnapshot {
  bookId: string;
  bookName: string;
  categories: ExpenseCategory[];
  incomeCategories: ExpenseCategory[];
  spendingNatures: SpendingNatureChoice[];
  tags: TagChoice[];
  budgetNatureLines: BudgetNatureLine[];
  accounts: LedgerAccount[];
  entries: SavedLedgerEntry[];
  incomeMinor: string;
  expenseMinor: string;
  budgetTotalMinor: string;
  budgetUsedMinor: string;
}

/** All posted user transactions across books; recovery receipts are not separate entries. */
export interface LedgerUsageSummary { firstEntryDate: string; entryCount: string; }
