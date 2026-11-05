/** Saved record snapshot used by receipt and edit screens; all money remains integer text. */
export interface EntryDetail {
  id: string;
  bookId: string;
  bookName: string;
  kind: string;
  revision: number;
  categoryId: string;
  categoryName: string;
  categoryPath: string;
  iconKey: string;
  accountId: string;
  accountName: string;
  currencyId: string;
  currencyCode: string;
  currencySymbol: string;
  currencyScale: number;
  grossMinor: string;
  discountMinor: string;
  paidMinor: string;
  bookMinor: string;
  includeInBudget: boolean;
  includeInAssets: boolean;
  balanceMode: string;
  occurredAtMs: number;
  localDate: string;
  timezone: string;
  offsetMinutes: number;
  note: string;
  canEdit: boolean;
}
