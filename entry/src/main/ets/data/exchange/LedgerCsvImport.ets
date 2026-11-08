import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';
import { ExpenseCategory, LedgerSnapshot } from '../../domain/model/LedgerSnapshot';

export interface CsvTable {
  headers: string[];
  rows: string[][];
  delimiter: string;
}

export interface CsvColumnMapping {
  date: number;
  type: number;
  amount: number;
  category: number;
  account: number;
  note: number;
  sourceId: number;
  merchant: number;
  address: number;
}

export interface CsvPreviewRow {
  rowNumber: number;
  raw: string[];
  date: string;
  time: string;
  timeKnown: boolean;
  type: string;
  amount: string;
  categoryId: string;
  categoryName: string;
  createCategory: boolean;
  accountId: string;
  accountName: string;
  createAccount: boolean;
  sourceId: string;
  duplicate: boolean;
  duplicateReason: string;
  selected: boolean;
  merchant: string;
  address: string;
  note: string;
  valid: boolean;
  issues: string[];
}

export interface CsvImportOptions {
  createMissingCategories: boolean;
  createMissingAccounts: boolean;
  existingIds: string[];
}

interface ParsedAmount {
  decimal: string;
  negative: boolean;
}

interface ParsedDateTime {
  localDate: string;
  time: string;
  timeKnown: boolean;
  occurredAtMs: number;
  offsetMinutes: number;
}

function normalizeHeader(value: string): string {
  return value.trim().toLowerCase().replace(/\s+/g, '');
}

function column(headers: string[], aliases: string[]): number {
  for (let index = 0; index < headers.length; index++) {
    const header = normalizeHeader(headers[index]);
    if (aliases.some((alias: string) => header === normalizeHeader(alias))) { return index; }
  }
  return -1;
}

export function detectCsvMapping(headers: string[]): CsvColumnMapping {
  return {
    date: column(headers, ['日期', '交易时间', '交易日期', 'date', 'time']),
    type: column(headers, ['类型', '收支类型', '方向', 'type']),
    amount: column(headers, ['金额', '实付金额', '交易金额', 'amount']),
    category: column(headers, ['分类', '收支分类', 'category']),
    account: column(headers, ['账户', '付款账户', '收款账户', 'account']),
    note: column(headers, ['备注', '商品', '说明', 'note', 'memo']),
    sourceId: column(headers, ['账目ID', '交易单号', '交易订单号', '来源记录编号', 'sourceid', 'transactionid']),
    merchant: column(headers, ['商户', '交易对方', '商家', 'merchant']),
    address: column(headers, ['地址', '商户地址', 'address'])
  };
}

function delimiterOf(text: string): string {
  const firstLine = text.split(/\r?\n/)[0] || '';
  const counts: string[] = [',', '\t', ';'];
  let selected = ',';
  let maximum = -1;
  for (const candidate of counts) {
    const length = firstLine.split(candidate).length;
    if (length > maximum) { maximum = length; selected = candidate; }
  }
  return selected;
}

export function parseCsv(text: string): CsvTable {
  const source = text.startsWith('\uFEFF') ? text.substring(1) : text;
  const delimiter = delimiterOf(source);
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = '';
  let quoted = false;
  for (let index = 0; index < source.length; index++) {
    const char = source[index];
    if (char === '"') {
      if (quoted && source[index + 1] === '"') { cell += '"'; index++; }
      else { quoted = !quoted; }
    } else if (char === delimiter && !quoted) {
      row.push(cell); cell = '';
    } else if ((char === '\n' || char === '\r') && !quoted) {
      if (char === '\r' && source[index + 1] === '\n') { index++; }
      row.push(cell); cell = ''; rows.push(row); row = [];
    } else { cell += char; }
  }
  if (quoted) { throw new Error('CSV_UNCLOSED_QUOTE'); }
  if (cell.length > 0 || row.length > 0) { row.push(cell); rows.push(row); }
  while (rows.length > 0 && rows[rows.length - 1].every((value: string) => value.trim().length === 0)) { rows.pop(); }
  if (rows.length === 0) { throw new Error('CSV_EMPTY'); }
  return { headers: rows[0].map((value: string) => value.trim()), rows: rows.slice(1), delimiter: delimiter };
}

function parseDateTime(value: string): ParsedDateTime {
  if (/^[0-9]+(?:\.[0-9]+)?$/.test(value.trim())) {
    const serial = Number(value.trim());
    if (serial > 20000 && serial < 80000) {
      const utc = new Date(Date.UTC(1899, 11, 30) + Math.floor(serial) * 86400000);
      const localDate = `${utc.getUTCFullYear()}-${String(utc.getUTCMonth() + 1).padStart(2, '0')}-` +
        String(utc.getUTCDate()).padStart(2, '0');
      const date = new Date(utc.getUTCFullYear(), utc.getUTCMonth(), utc.getUTCDate(), 12, 0, 0, 0);
      return { localDate: localDate, time: '', timeKnown: false,
        occurredAtMs: date.getTime(), offsetMinutes: -date.getTimezoneOffset() };
    }
  }
  const normalized = value.trim().replace(/[年/.]/g, '-').replace(/月/g, '-').replace(/日/g, '');
  const match = normalized.match(/^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})(?:[T\s]+([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?)?/);
  if (match === null) { return { localDate: '', time: '', timeKnown: false, occurredAtMs: 0, offsetMinutes: 0 }; }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const timeKnown = match[4] !== undefined;
  const hour = timeKnown ? Number(match[4]) : 12;
  const minute = timeKnown ? Number(match[5]) : 0;
  const second = timeKnown ? Number(match[6] || '0') : 0;
  const date = new Date(year, month - 1, day, hour, minute, second, 0);
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day ||
    hour > 23 || minute > 59 || second > 59) {
    return { localDate: '', time: '', timeKnown: false, occurredAtMs: 0, offsetMinutes: 0 };
  }
  const localDate = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  return { localDate: localDate,
    time: timeKnown ? `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}` : '',
    timeKnown: timeKnown, occurredAtMs: date.getTime(), offsetMinutes: -date.getTimezoneOffset() };
}

function type(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (normalized.includes('支出') || normalized.includes('expense') ||
    normalized.includes('付款') || normalized.includes('支付')) { return 'expense'; }
  if (normalized.includes('收入') || normalized.includes('income') ||
    normalized.includes('收款')) { return 'income'; }
  return '';
}

function amount(value: string): ParsedAmount {
  const normalized = value.replace(/[,\s￥¥]/g, '');
  const negative = normalized.startsWith('-');
  const unsigned = normalized.replace(/^[+-]/, '');
  if (unsigned.length === 0) { throw new Error('INVALID_AMOUNT'); }
  const decimal = Money.parse(unsigned, new CurrencyUnit('CNY', 'CNY', 2)).toDecimalString();
  if (decimal === '0.00') { throw new Error('INVALID_AMOUNT'); }
  return { decimal: decimal, negative: negative };
}

function categoryPathMap(categories: ExpenseCategory[]): Map<string, string> {
  const result: Map<string, string> = new Map();
  const byId: Map<string, ExpenseCategory> = new Map();
  categories.forEach((category: ExpenseCategory) => { byId.set(category.id, category); });
  const path = (category: ExpenseCategory): string => {
    const values: string[] = [category.name];
    let parentId = category.parentId;
    const visited: Set<string> = new Set();
    while (parentId.length > 0 && !visited.has(parentId)) {
      visited.add(parentId);
      const parent = byId.get(parentId);
      if (parent === undefined) { break; }
      values.unshift(parent.name); parentId = parent.parentId;
    }
    return values.join(' / ');
  };
  for (const category of categories) {
    const full = path(category);
    result.set(normalizeHeader(full), category.id);
    result.set(normalizeHeader(category.name), result.get(normalizeHeader(category.name)) || category.id);
  }
  return result;
}

export function previewCsv(table: CsvTable, mapping: CsvColumnMapping, snapshot: LedgerSnapshot,
  options: CsvImportOptions = { createMissingCategories: true, createMissingAccounts: true, existingIds: [] }): CsvPreviewRow[] {
  const expenseCategoryIds = categoryPathMap(snapshot.categories);
  const incomeCategoryIds = categoryPathMap(snapshot.incomeCategories);
  const accountIds: Map<string, string> = new Map();
  snapshot.accounts.forEach((account) => { accountIds.set(normalizeHeader(account.name), account.id); });
  const result: CsvPreviewRow[] = [];
  const seenIds: Set<string> = new Set();
  const existingIds: Set<string> = new Set(options.existingIds);
  table.rows.forEach((raw: string[], index: number) => {
    const issues: string[] = [];
    const rawDate = mapping.date >= 0 ? raw[mapping.date] || '' : '';
    const rawType = mapping.type >= 0 ? raw[mapping.type] || '' : '';
    const rawAmount = mapping.amount >= 0 ? raw[mapping.amount] || '' : '';
    const rawCategory = mapping.category >= 0 ? raw[mapping.category] || '' : '';
    const rawAccount = mapping.account >= 0 ? raw[mapping.account] || '' : '';
    const sourceId = mapping.sourceId >= 0 ? (raw[mapping.sourceId] || '').trim() : '';
    const merchant = mapping.merchant >= 0 ? (raw[mapping.merchant] || '').trim() : '';
    const address = mapping.address >= 0 ? (raw[mapping.address] || '').trim() : '';
    const parsedDate = parseDateTime(rawDate);
    let kind = type(rawType);
    let paid = '';
    let negative = false;
    try {
      const parsed = amount(rawAmount);
      paid = parsed.decimal;
      negative = parsed.negative;
      if (kind.length === 0) { kind = negative ? 'expense' : 'income'; }
    } catch (_) { issues.push('金额无效'); }
    const categoryId = (kind === 'income' ?
      incomeCategoryIds.get(normalizeHeader(rawCategory)) :
      expenseCategoryIds.get(normalizeHeader(rawCategory))) || '';
    const categoryName = rawCategory.trim().length > 0 ? rawCategory.trim() : '未分类';
    const createCategory = categoryId.length === 0 && options.createMissingCategories;
    const accountId = rawAccount.trim().length === 0 ? '' :
      accountIds.get(normalizeHeader(rawAccount)) || '';
    const createAccount = rawAccount.trim().length > 0 && accountId.length === 0 && options.createMissingAccounts;
    if (parsedDate.localDate.length === 0) { issues.push('日期无效'); }
    if (kind.length === 0) { issues.push('类型无法判断'); }
    if (paid.length === 0) { issues.push('金额无效'); }
    if (categoryId.length === 0 && !createCategory) { issues.push('分类未匹配'); }
    if (rawAccount.trim().length > 0 && accountId.length === 0 && !createAccount) { issues.push('账户未匹配'); }
    let duplicate = false;
    let duplicateReason = '';
    if (sourceId.length > 0 && (seenIds.has(sourceId) || existingIds.has(sourceId))) {
      duplicate = true;
      duplicateReason = seenIds.has(sourceId) ? '文件内重复' : '历史账目已有';
    }
    if (sourceId.length > 0) { seenIds.add(sourceId); }
    result.push({ rowNumber: index + 2, raw: raw, date: parsedDate.localDate, time: parsedDate.time,
      timeKnown: parsedDate.timeKnown, type: kind, amount: paid,
      categoryId: categoryId, categoryName: categoryName, createCategory: createCategory,
      accountId: accountId, accountName: rawAccount.trim(), createAccount: createAccount,
      sourceId: sourceId, duplicate: duplicate, duplicateReason: duplicateReason,
      selected: issues.length === 0 && !duplicate,
      merchant: merchant, address: address,
      note: mapping.note >= 0 ? raw[mapping.note] || '' : '', valid: issues.length === 0, issues: issues });
  });
  return result;
}
