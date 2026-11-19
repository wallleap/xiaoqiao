import { SavedLedgerEntry } from './LedgerSnapshot';

export interface LedgerSearchCursor { occurredAtMs: number; id: string; }
export interface LedgerSearchPageResult {
  entries: SavedLedgerEntry[];
  hasMore: boolean;
  nextCursor?: LedgerSearchCursor;
}

/** Read-only flow range; endDateExclusive is excluded. Empty bounds mean all dates. */
export interface LedgerFlowQuery {
  startDate: string;
  endDateExclusive: string;
  kind: number;
}
export interface LedgerFlowDay { date: string; incomeMinor: string; expenseMinor: string; }
export interface LedgerFlowPage extends LedgerSearchPageResult { days: LedgerFlowDay[]; }
