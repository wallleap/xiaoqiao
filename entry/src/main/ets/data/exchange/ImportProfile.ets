import { CsvColumnMapping, CsvPreviewRow } from './LedgerCsvImport';

export interface ImportProfileOptions {
  headerRow: number;
  delimiter: string;
  createMissingCategories: boolean;
  createMissingAccounts: boolean;
  feeInBudget: boolean;
}

export interface CsvImportMetadata {
  headerRow: number;
  sheetName: string;
  sourceKind: string;
  encoding: string;
  profileSnapshot: string;
  feeInBudget: boolean;
}

export interface ImportProfile {
  id: string;
  name: string;
  sourceKind: string;
  profileVersion: number;
  mapping: CsvColumnMapping;
  options: ImportProfileOptions;
  updatedAtMs: number;
}

export interface ImportBatchSummary {
  id: string;
  fileName: string;
  sheetName: string;
  status: string;
  balanceMode: string;
  totalCount: number;
  selectedCount: number;
  skippedCount: number;
  issueCount: number;
  committedAtMs: number;
}

export interface ImportBatchRowDetail {
  rowNumber: number;
  validationStatus: string;
  selected: boolean;
  issues: string[];
  rawPreview: string;
  normalizedType: string;
  normalizedDate: string;
  normalizedAmount: string;
}

export interface ImportPreviewCounts {
  validSelected: number;
  issues: number;
  duplicates: number;
  newCategories: number;
  newAccounts: number;
}

export function countImportPreview(rows: CsvPreviewRow[]): ImportPreviewCounts {
  const categories: Set<string> = new Set();
  const accounts: Set<string> = new Set();
  let validSelected = 0;
  let issues = 0;
  let duplicates = 0;
  for (const row of rows) {
    if (row.valid && row.selected) { validSelected++; }
    if (!row.valid) { issues++; }
    if (row.duplicate) { duplicates++; }
    if (row.valid && row.selected && row.createCategory) {
      let path = '';
      const parts = row.categoryName.split(/\s*[\/>]\s*/)
        .map((value: string) => value.trim().toLowerCase())
        .filter((value: string) => value.length > 0);
      for (const part of parts) {
        path += '/' + part;
        categories.add(row.type + ':' + path);
      }
    }
    if (row.valid && row.selected && row.createAccount) {
      accounts.add(row.accountName.trim().toLowerCase());
    }
    if (row.valid && row.selected && row.createToAccount === true) {
      accounts.add((row.toAccountName || '').trim().toLowerCase());
    }
  }
  return { validSelected: validSelected, issues: issues, duplicates: duplicates,
    newCategories: categories.size, newAccounts: accounts.size };
}
