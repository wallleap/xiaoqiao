import { isSpendingNatureColor, isCustomNatureColor } from '../../domain/model/SpendingNature';
import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';
import { ExpenseCategory, LedgerSnapshot } from '../../domain/model/LedgerSnapshot';
import { BackupFiles } from '../backup/BackupFiles';
import { util } from '@kit.ArkTS';
import { LedgerLocation, locationFromDegrees } from '../../domain/model/LedgerLocation';

export interface CsvTable {
  headers: string[];
  rows: string[][];
  rowNumbers?: number[];
  delimiter: string;
}

export interface CsvColumnMapping {
  date: number;
  time: number;
  type: number;
  amount: number;
  transferAmount: number;
  category: number;
  account: number;
  toAccount: number;
  purpose: number;
  fee: number;
  coupon: number;
  feeBudget: number;
  note: number;
  sourceId: number;
  merchant: number;
  address: number;
  /** Optional for compatibility with saved mappings and callers created before map export. */
  includeInBudget?: number;
  spendingNature?: number;
  spendingNatureColor?: number;
  originalEntryId?: number;
  reimbursementPending?: number;
  latitude?: number;
  longitude?: number;
  status: number;
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
  toAccountId?: string;
  toAccountName?: string;
  createToAccount?: boolean;
  transferPurpose?: string;
  transferFee?: string;
  transferCoupon?: string;
  feeInBudget?: boolean;
  sourceId: string;
  duplicate: boolean;
  duplicateReason: string;
  selected: boolean;
  merchant: string;
  address: string;
  location?: LedgerLocation;
  includeInBudget?: boolean;
  spendingNatureId?: string;
  originalEntryId?: string;
  reimbursementPending?: boolean;
  sourceStatus: string;
  note: string;
  valid: boolean;
  issues: string[];
}

export interface CsvImportOptions {
  createMissingCategories: boolean;
  createMissingAccounts: boolean;
  feeInBudget?: boolean;
  existingIds: string[];
}

export async function readDelimitedText(uri: string): Promise<string> {
  const bytes = new Uint8Array(await BackupFiles.read(uri, 8 * 1024 * 1024));
  try { return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes); }
  catch (_) { return util.TextDecoder.create('gb18030').decodeToString(bytes); }
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
    time: column(headers, ['时间', '交易时刻', 'clock', 'timeonly']),
    type: column(headers, ['类型', '收支类型', '收/支', '方向', 'type']),
    amount: column(headers, ['金额', '金额(元)', '金额（元）', '实付金额', '交易金额', 'amount']),
    transferAmount: column(headers, ['原金额', '转账金额', '转出金额', 'transferamount']),
    category: column(headers, ['分类', '收支分类', '交易分类', '交易类型', 'category']),
    account: column(headers, ['账户', '付款账户', '支付方式', '收/付款方式', 'account']),
    toAccount: column(headers, ['转入账户', '收款账户', '对方账户', '到账账户', 'targetaccount']),
    purpose: column(headers, ['转账用途', '用途', '交易用途', '交易类型', 'purpose']),
    fee: column(headers, ['手续费', '转账手续费', '服务费', 'fee']),
    coupon: column(headers, ['转账优惠', '还款优惠', '优惠券', 'coupon']),
    feeBudget: column(headers, ['手续费计入预算', '手续费入预算', 'feebudget']),
    note: column(headers, ['备注', '商品', '说明', 'note', 'memo']),
    sourceId: column(headers, ['账目ID', '交易单号', '交易订单号', '来源记录编号', 'sourceid', 'transactionid']),
    merchant: column(headers, ['商户', '交易对方', '商家', 'merchant']),
    address: column(headers, ['地址', '商户地址', 'address']),
    includeInBudget: column(headers, ['计入预算', 'includeinbudget']),
    spendingNature: column(headers, ['预算分类', 'spendingnature']),
    spendingNatureColor: column(headers, ['预算分类颜色', 'spendingnaturecolor']),
    originalEntryId: column(headers, ['关联支出ID', '原支出ID', 'originalentryid']),
    reimbursementPending: column(headers, ['待报销', 'reimbursementpending']),
    latitude: column(headers, ['纬度', '纬度(度)', '纬度（度）', 'latitude', 'lat']),
    longitude: column(headers, ['经度', '经度(度)', '经度（度）', 'longitude', 'lng', 'lon']),
    status: column(headers, ['交易状态', '当前状态', '状态', 'status'])
  };
}

export function detectHeaderRowIndex(rows: string[][]): number {
  let headerIndex = -1;
  for (let index = 0; index < rows.length && index < 50; index++) {
    const mapping = detectCsvMapping(rows[index]);
    if (mapping.date >= 0 && mapping.amount >= 0 && (mapping.type >= 0 || mapping.purpose >= 0)) {
      headerIndex = index;
      break;
    }
  }
  if (headerIndex < 0) {
    headerIndex = rows.findIndex((row: string[]) => row.some((value: string) => value.trim().length > 0));
  }
  return headerIndex;
}

export function tableFromRows(rows: string[][], delimiter: string = ',', headerIndexOverride: number = -1): CsvTable {
  const headerIndex = headerIndexOverride >= 0 && headerIndexOverride < rows.length ?
    headerIndexOverride : detectHeaderRowIndex(rows);
  if (headerIndex < 0) { throw new Error('CSV_EMPTY'); }
  const body: string[][] = [];
  const rowNumbers: number[] = [];
  for (let index = headerIndex + 1; index < rows.length; index++) {
    if (rows[index].some((value: string) => value.trim().length > 0)) {
      body.push(rows[index]);
      rowNumbers.push(index + 1);
    }
  }
  return { headers: rows[headerIndex].map((value: string) => value.trim()), rows: body,
    rowNumbers: rowNumbers, delimiter: delimiter };
}

export function detectCsvDelimiter(text: string): string {
  const lines = text.split(/\r?\n/).filter((value: string) => value.trim().length > 0).slice(0, 20);
  const counts: string[] = [',', '\t', ';'];
  let selected = ',';
  let maximum = -1;
  for (const candidate of counts) {
    for (const line of lines) {
      const length = line.split(candidate).length;
      if (length > maximum) { maximum = length; selected = candidate; }
    }
  }
  return selected;
}

export function parseCsvRows(text: string, delimiter: string = ''): string[][] {
  const source = text.startsWith('\uFEFF') ? text.substring(1) : text;
  const selectedDelimiter = delimiter.length > 0 ? delimiter : detectCsvDelimiter(source);
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = '';
  let quoted = false;
  for (let index = 0; index < source.length; index++) {
    const char = source[index];
    if (char === '"') {
      if (quoted && source[index + 1] === '"') { cell += '"'; index++; }
      else { quoted = !quoted; }
    } else if (char === selectedDelimiter && !quoted) {
      row.push(cell); cell = '';
    } else if ((char === '\n' || char === '\r') && !quoted) {
      if (char === '\r' && source[index + 1] === '\n') { index++; }
      row.push(cell); cell = ''; rows.push(row); row = [];
    } else { cell += char; }
  }
  if (quoted) { throw new Error('CSV_UNCLOSED_QUOTE'); }
  if (cell.length > 0 || row.length > 0) { row.push(cell); rows.push(row); }
  while (rows.length > 0 && rows[rows.length - 1].every((value: string) => value.trim().length === 0)) { rows.pop(); }
  return rows;
}

export function parseCsv(text: string, delimiter: string = ''): CsvTable {
  const source = text.startsWith('\uFEFF') ? text.substring(1) : text;
  const selectedDelimiter = delimiter.length > 0 ? delimiter : detectCsvDelimiter(source);
  return tableFromRows(parseCsvRows(source, selectedDelimiter), selectedDelimiter);
}

function parseDateTime(value: string): ParsedDateTime {
  if (/^[0-9]+(?:\.[0-9]+)?$/.test(value.trim())) {
    const serial = Number(value.trim());
    if (serial > 20000 && serial < 80000) {
      const whole = Math.floor(serial);
      const fraction = serial - whole;
      const utc = new Date(Date.UTC(1899, 11, 30) + whole * 86400000);
      const localDate = `${utc.getUTCFullYear()}-${String(utc.getUTCMonth() + 1).padStart(2, '0')}-` +
        String(utc.getUTCDate()).padStart(2, '0');
      const totalSeconds = Math.round(fraction * 86400);
      const hour = Math.floor(totalSeconds / 3600);
      const minute = Math.floor((totalSeconds % 3600) / 60);
      const second = totalSeconds % 60;
      const date = new Date(utc.getUTCFullYear(), utc.getUTCMonth(), utc.getUTCDate(), hour, minute, second, 0);
      return { localDate: localDate,
        time: `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`,
        timeKnown: fraction > 0,
        occurredAtMs: date.getTime(), offsetMinutes: -date.getTimezoneOffset() };
    }
  }
  let normalized = value.trim().replace(/[年/.]/g, '-').replace(/月/g, '-').replace(/日/g, '');
  const afternoon = /下午|晚上/.test(normalized);
  normalized = normalized.replace(/上午|下午|凌晨|晚上/g, ' ').replace(/\s+/g, ' ').trim();
  let year = 0;
  let month = 0;
  let day = 0;
  let timeKnown = false;
  let hour = 12;
  let minute = 0;
  let second = 0;
  let match = normalized.match(/^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})(?:[T\s]+([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?)?/);
  if (match !== null) {
    year = Number(match[1]); month = Number(match[2]); day = Number(match[3]);
    timeKnown = match[4] !== undefined;
    hour = timeKnown ? Number(match[4]) : 12;
    minute = timeKnown ? Number(match[5]) : 0;
    second = timeKnown ? Number(match[6] || '0') : 0;
  } else {
    match = normalized.match(/^([0-9]{4})([0-9]{2})([0-9]{2})(?:[T\s]+([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?)?/);
    if (match !== null) {
      year = Number(match[1]); month = Number(match[2]); day = Number(match[3]);
      timeKnown = match[4] !== undefined;
      hour = timeKnown ? Number(match[4]) : 12;
      minute = timeKnown ? Number(match[5]) : 0;
      second = timeKnown ? Number(match[6] || '0') : 0;
    } else {
      match = normalized.match(/^([0-9]{1,2})-([0-9]{1,2})-([0-9]{4})(?:[T\s]+([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?)?/);
      if (match === null) { return { localDate: '', time: '', timeKnown: false, occurredAtMs: 0, offsetMinutes: 0 }; }
      const first = Number(match[1]);
      const secondPart = Number(match[2]);
      year = Number(match[3]);
      month = first > 12 ? secondPart : first;
      day = first > 12 ? first : secondPart;
      timeKnown = match[4] !== undefined;
      hour = timeKnown ? Number(match[4]) : 12;
      minute = timeKnown ? Number(match[5]) : 0;
      second = timeKnown ? Number(match[6] || '0') : 0;
    }
  }
  if (afternoon && timeKnown && hour < 12) { hour += 12; }
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
  if (/退款|refund/.test(normalized)) { return 'refund'; }
  if (/报销|reimbursement/.test(normalized)) { return 'reimbursement'; }
  if (normalized.includes('支出') || normalized.includes('expense') ||
    normalized.includes('付款') || normalized.includes('支付')) { return 'expense'; }
  if (normalized.includes('收入') || normalized.includes('income') ||
    normalized.includes('收款')) { return 'income'; }
  return '';
}

export function transferPurposeFromText(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (normalized.includes('信用卡')) { return 'credit_repayment'; }
  if (normalized.includes('借款') || normalized.includes('贷款')) { return 'loan_repayment'; }
  if (normalized.includes('还款')) { return 'credit_repayment'; }
  if (normalized.includes('充值')) { return 'topup'; }
  if (normalized.includes('提现')) { return 'withdrawal'; }
  return 'transfer';
}

function isTransferText(value: string): boolean {
  return /转账|还款|充值|提现/.test(value.trim().toLowerCase());
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

function optionalAmount(value: string): string {
  if (value.trim().length === 0) { return '0.00'; }
  const normalized = value.replace(/[,\s￥¥]/g, '');
  if (normalized.startsWith('-')) { throw new Error('INVALID_AMOUNT'); }
  const decimal = Money.parse(normalized.replace(/^[+-]/, ''), new CurrencyUnit('CNY', 'CNY', 2)).toDecimalString();
  return decimal;
}

function feeBudget(value: string, fallback: boolean): boolean {
  const normalized = value.trim().toLowerCase();
  if (['否', 'false', '0', 'no', '不计入'].includes(normalized)) { return false; }
  if (['是', 'true', '1', 'yes', '计入'].includes(normalized)) { return true; }
  return fallback;
}

export function importStatusIssue(status: string, rawType: string): string {
  const normalized = status.trim();
  if (normalized.length === 0) { return ''; }
  if (/退款|已退|撤销|取消|关闭|失败/.test(normalized)) { return `交易状态跳过：${normalized}`; }
  if (rawType.trim() === '/' || rawType.trim() === '不计收支') { return '不计收支，已跳过'; }
  if (/零钱通/.test(normalized) && !/成功|已到账/.test(normalized)) { return `交易状态跳过：${normalized}`; }
  if (/成功|已到账|已收款|已支付|已转账|已存入|对方已收钱/.test(normalized)) { return ''; }
  return `交易状态需确认：${normalized}`;
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
  options: CsvImportOptions = { createMissingCategories: false, createMissingAccounts: false,
    feeInBudget: false, existingIds: [] }): CsvPreviewRow[] {
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
    const rawTransferAmount = mapping.transferAmount >= 0 ? raw[mapping.transferAmount] || '' : '';
    const rawCategory = mapping.category >= 0 ? raw[mapping.category] || '' : '';
    const rawAccount = mapping.account >= 0 ? raw[mapping.account] || '' : '';
    const rawToAccount = mapping.toAccount >= 0 ? raw[mapping.toAccount] || '' : '';
    const rawPurpose = mapping.purpose >= 0 ? raw[mapping.purpose] || '' : '';
    const rawFee = mapping.fee >= 0 ? raw[mapping.fee] || '' : '';
    const rawCoupon = mapping.coupon >= 0 ? raw[mapping.coupon] || '' : '';
    const rawFeeBudget = mapping.feeBudget >= 0 ? raw[mapping.feeBudget] || '' : '';
    const sourceId = mapping.sourceId >= 0 ? (raw[mapping.sourceId] || '').trim() : '';
    const merchant = mapping.merchant >= 0 ? (raw[mapping.merchant] || '').trim() : '';
    const address = mapping.address >= 0 ? (raw[mapping.address] || '').trim() : '';
    const latitudeColumn = mapping.latitude ?? -1;
    const longitudeColumn = mapping.longitude ?? -1;
    const latitude = latitudeColumn >= 0 ? (raw[latitudeColumn] || '').trim() : '';
    const longitude = longitudeColumn >= 0 ? (raw[longitudeColumn] || '').trim() : '';
    let location: LedgerLocation | undefined = undefined;
    if (latitude.length > 0 || longitude.length > 0) {
      if (latitude.length === 0 || longitude.length === 0) {
        issues.push('纬度和经度必须同时填写，或同时留空');
      } else {
        // Accept decimal/scientific notation from spreadsheets, never hex, units or non-finite values.
        const coordinate = /^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/;
        if (!coordinate.test(latitude) || !coordinate.test(longitude)) {
          issues.push('纬度和经度须为十进制度数');
        } else {
          try { location = locationFromDegrees(Number(latitude), Number(longitude)); }
          catch (_) { issues.push('纬度须在 -90～90，经度须在 -180～180 之间'); }
        }
      }
    }
    const budgetText = (mapping.includeInBudget ?? -1) >= 0 ? (raw[mapping.includeInBudget ?? -1] || '').trim().toLowerCase() : '';
    const includeInBudget = ['是', '1', 'true'].includes(budgetText);
    if (budgetText && !['是', '否', '1', '0', 'true', 'false'].includes(budgetText)) { issues.push('计入预算须为是或否'); }
    const natureName = (mapping.spendingNature ?? -1) >= 0 ? (raw[mapping.spendingNature ?? -1] || '').trim() : '';
    const nature = snapshot.spendingNatures.find((item) => normalizeHeader(item.name) === normalizeHeader(natureName));
    const originalEntryId = (mapping.originalEntryId ?? -1) >= 0 ? (raw[mapping.originalEntryId ?? -1] || '').trim() : '';
    const pendingText = (mapping.reimbursementPending ?? -1) >= 0 ? (raw[mapping.reimbursementPending ?? -1] || '').trim().toLowerCase() : '';
    const reimbursementPending = ['是', '1', 'true', '待报销'].includes(pendingText);
    if (pendingText.length > 0 && !['是', '否', '1', '0', 'true', 'false', '待报销'].includes(pendingText)) { issues.push('待报销须为是或否'); }
    const status = mapping.status >= 0 ? (raw[mapping.status] || '').trim() : '';
    let parsedDate = parseDateTime(rawDate);
    const rawTime = mapping.time >= 0 ? raw[mapping.time] || '' : '';
    if (!parsedDate.timeKnown && parsedDate.localDate.length > 0 && /^[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?$/.test(rawTime.trim())) {
      parsedDate = parseDateTime(parsedDate.localDate + ' ' + rawTime.trim());
    }
    const transfer = isTransferText(rawType) || isTransferText(rawPurpose);
    const effectiveRawAmount = transfer && rawTransferAmount.trim().length > 0 ? rawTransferAmount : rawAmount;
    let kind = transfer ? 'transfer' : type(rawType);
    if (kind.length === 0) { kind = type(rawPurpose); }
    const recovery = kind === 'refund' || kind === 'reimbursement';
    if (kind === 'expense' && natureName.length > 0 && nature === undefined) { issues.push('预算分类未匹配，请先在设置中创建同名预算分类'); }
    const natureColor = (mapping.spendingNatureColor ?? -1) >= 0 ? (raw[mapping.spendingNatureColor ?? -1] || '').trim() : '';
    if (kind === 'expense' && natureColor.length > 0) {
      if (!isSpendingNatureColor(natureColor)) { issues.push('预算分类颜色须为预设颜色名或 #RRGGBB'); }
      else if (natureName.length === 0) { issues.push('填写预算分类颜色时须同时填写预算分类'); }
      else if (nature !== undefined && (isCustomNatureColor(natureColor) ? natureColor.toUpperCase() : natureColor) !== nature.colorKey) {
        issues.push('预算分类颜色与现有分类不一致，请先在预算分类管理中设置相同颜色');
      }
    }
    if (recovery && originalEntryId.length === 0) { issues.push('报销或退款必须填写关联支出ID'); }
    if (!recovery && originalEntryId.length > 0) { issues.push('关联支出ID仅用于报销或退款'); }
    if (reimbursementPending && kind !== 'expense') { issues.push('只有支出可以标记待报销'); }
    let paid = '';
    let negative = false;
    let transferFee = '0.00';
    let transferCoupon = '0.00';
    const transferPurpose = transferPurposeFromText(rawPurpose || rawType);
    try {
      const parsed = amount(effectiveRawAmount);
      paid = parsed.decimal;
      negative = parsed.negative;
      if (recovery && negative) { issues.push('报销或退款金额须为正数'); }
      if (kind.length === 0) { kind = negative ? 'expense' : 'income'; }
      if (kind === 'transfer') {
        transferFee = optionalAmount(rawFee);
        transferCoupon = optionalAmount(rawCoupon);
        const paidMoney = Money.parse(paid, new CurrencyUnit('CNY', 'CNY', 2));
        const couponMoney = Money.parse(transferCoupon, new CurrencyUnit('CNY', 'CNY', 2));
        if (couponMoney.minor > paidMoney.minor) { issues.push('转账优惠不能大于转账金额'); }
        if (couponMoney.minor > BigInt(0) &&
          transferPurpose !== 'credit_repayment' && transferPurpose !== 'loan_repayment') {
          issues.push('只有还款转账可以使用优惠');
        }
      }
    } catch (_) { issues.push('金额无效'); }
    let categoryId = kind === 'transfer' || recovery ? '' : (kind === 'income' ?
      incomeCategoryIds.get(normalizeHeader(rawCategory)) :
      expenseCategoryIds.get(normalizeHeader(rawCategory))) || '';
    let categoryName = recovery ? (kind === 'refund' ? '退款' : '报销到账') : kind === 'transfer' ? '转账' : rawCategory.trim();
    let createCategory = false;
    if (kind !== 'transfer' && !recovery && categoryId.length === 0) {
      if (options.createMissingCategories) {
        categoryName = categoryName || (kind === 'income' ? '其他收入' : '其它');
        createCategory = true;
      } else {
        const candidates = kind === 'income' ? snapshot.incomeCategories : snapshot.categories;
        const fallback = candidates.find((category: ExpenseCategory) =>
          ['其它', '其他', '其他收入'].includes(category.name)) ||
          candidates.find((category: ExpenseCategory) => category.name.includes('其他'));
        categoryId = fallback?.id || '';
        categoryName = fallback?.name || (kind === 'income' ? '其他收入' : '其它');
        createCategory = categoryId.length === 0;
      }
    }
    const mappedAccountText = kind !== 'transfer' && rawAccount.trim().length === 0 ? rawToAccount : rawAccount;
    const accountText = ['不使用账户', '无'].includes(mappedAccountText.trim()) ? '' : mappedAccountText;
    const accountId = accountText.trim().length === 0 ? '' :
      accountIds.get(normalizeHeader(accountText)) || '';
    const createAccount = accountText.trim().length > 0 && accountId.length === 0 && options.createMissingAccounts;
    const toAccountId = rawToAccount.trim().length === 0 ? '' :
      accountIds.get(normalizeHeader(rawToAccount)) || '';
    const createToAccount = rawToAccount.trim().length > 0 && toAccountId.length === 0 && options.createMissingAccounts;
    if (recovery && accountText.trim().length > 0 && !['不使用账户', '无'].includes(accountText.trim()) && accountId.length === 0 && !createAccount) { issues.push('到账账户未匹配'); }
    if (parsedDate.localDate.length === 0) { issues.push('日期无效'); }
    if (kind.length === 0) { issues.push('类型无法判断'); }
    const statusIssue = recovery && /^(退款成功|已退款|报销成功|已到账)$/.test(status) ? '' : importStatusIssue(status, transfer || recovery ? '' : rawType);
    if (statusIssue.length > 0) { issues.push(statusIssue); }
    if (paid.length === 0 && !issues.includes('金额无效')) { issues.push('金额无效'); }
    if (kind === 'transfer') {
      if (accountId.length === 0 && !createAccount) { issues.push('转出账户未匹配'); }
      if (toAccountId.length === 0 && !createToAccount) { issues.push('转入账户未匹配'); }
      if ((accountId.length > 0 && toAccountId.length > 0 && accountId === toAccountId) ||
        (createAccount && createToAccount && normalizeHeader(rawAccount) === normalizeHeader(rawToAccount))) {
        issues.push('转出和转入账户不能相同');
      }
    } else if (!recovery && categoryId.length === 0 && !createCategory) {
      issues.push('分类未匹配');
    }
    // Unmatched accounts intentionally leave the entry without an account and never affect balances.
    let duplicate = false;
    let duplicateReason = '';
    if (sourceId.length > 0 && (seenIds.has(sourceId) || existingIds.has(sourceId))) {
      duplicate = true;
      duplicateReason = seenIds.has(sourceId) ? '文件内重复' : '历史账目已有';
    }
    if (sourceId.length > 0) { seenIds.add(sourceId); }
    result.push({ rowNumber: table.rowNumbers?.[index] || index + 2, raw: raw, date: parsedDate.localDate, time: parsedDate.time,
      timeKnown: parsedDate.timeKnown, type: kind, amount: paid,
      categoryId: categoryId, categoryName: categoryName, createCategory: createCategory,
      accountId: accountId, accountName: accountId.length > 0 || createAccount ? accountText.trim() : '',
      createAccount: createAccount, toAccountId: toAccountId,
      toAccountName: toAccountId.length > 0 || createToAccount ? rawToAccount.trim() : '',
      createToAccount: createToAccount, transferPurpose: kind === 'transfer' ? transferPurpose : '',
      transferFee: transferFee, transferCoupon: transferCoupon,
      feeInBudget: kind === 'transfer' ? feeBudget(rawFeeBudget, options.feeInBudget === true) : false,
      sourceId: sourceId, duplicate: duplicate, duplicateReason: duplicateReason,
      selected: issues.length === 0 && !duplicate,
      merchant: merchant, address: address, location: location, includeInBudget: kind === 'expense' && includeInBudget,
      spendingNatureId: kind === 'expense' ? nature?.id : undefined, originalEntryId: originalEntryId, reimbursementPending: reimbursementPending,
      sourceStatus: status,
      note: mapping.note >= 0 ? raw[mapping.note] || '' : '', valid: issues.length === 0, issues: issues });
  });
  return result;
}
