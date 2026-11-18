import { Money } from '../../core/money/Money';
import { LedgerAttachmentDraft } from './LedgerAttachment';
import { LedgerLocation } from './LedgerLocation';

/** Original entry form context, retained without creating an ordinary expense at payment time. */
export interface PrepaidEntryContext {
  categoryId: string;
  categoryName: string;
  spendingNatureId: string;
  includeInBudget: boolean;
  grossMinor: string;
  discountMinor: string;
  addressText: string;
  location?: LedgerLocation;
  tagIds: string[];
  tagNames: string[];
}
interface PrepaidQuoteData {
  entry?: PrepaidEntryContext;
}
export function prepaidEntryContext(json: string): PrepaidEntryContext | undefined {
  try {
    const value=(JSON.parse(json) as PrepaidQuoteData).entry;
    if (value===undefined || !Array.isArray(value.tagIds) || !Array.isArray(value.tagNames) || typeof value.categoryId!=='string' || typeof value.addressText!=='string') { return undefined; }
    return value;
  } catch (_) { return undefined; }
}

export type PrepaidEventKind = 'fund' | 'consume' | 'refund';
export interface PrepaidProject {
  id: string;
  bookId: string;
  name: string;
  merchant: string;
  currencyId: string;
  expiryDate: string;
  note: string;
  includeInNetAssets: boolean;
  revision: number;
  fundedMinor: string;
  consumedMinor: string;
  refundedMinor: string;
  remainingMinor: string;
  remainingBookMinor: string;
}
export interface PrepaidEvent {
  entryContext?: PrepaidEntryContext;
  id: string;
  projectId: string;
  kind: PrepaidEventKind;
  amountMinor: string;
  bookMinor: string;
  accountId: string;
  accountName: string;
  accountCurrencyId: string;
  cashMinor: string;
  cashBookMinor: string;
  transactionId: string;
  localDate: string;
  occurredAtMs: number;
  note: string;
  attachments: LedgerAttachmentDraft[];
  remainingMinor: string;
  remainingBookMinor: string;
}
export interface PrepaidDetail { project: PrepaidProject; events: PrepaidEvent[]; }
export interface PrepaidProjectCommand {
  id: string;
  bookId: string;
  name: string;
  merchant: string;
  currencyId: string;
  expiryDate: string;
  note: string;
  includeInNetAssets: boolean;
  expectedRevision?: number;
}
export interface PrepaidEventCommand {
  entryContext?: PrepaidEntryContext;
  id: string;
  projectId: string;
  bookId: string;
  expectedRevision: number;
  kind: PrepaidEventKind;
  amount: Money;
  accountId: string;
  cash?: Money;
  cashBook?: Money;
  /** Public/manual quote metadata captured with each payment, never refreshed retroactively. */
  rateSource: string;
  rateDate: string;
  bookRate: string;
  cashRate: string;
  categoryId: string;
  incomeCategoryId: string;
  spendingNatureId: string;
  includeInBudget: boolean;
  occurredAtMs: number;
  localDate: string;
  offsetMinutes: number;
  note: string;
  attachments?: LedgerAttachmentDraft[];
}
export interface PrepaidAllocation { fundId: string; amountMinor: string; bookMinor: string; }

/** FIFO by immutable payment creation order; last use of a lot consumes its exact remaining cost. */
export function allocatePrepaid(events: PrepaidEvent[], amount: bigint): PrepaidAllocation[] {
  if (amount <= BigInt(0)) { throw new Error('PREPAID_AMOUNT'); }
  const result: PrepaidAllocation[] = [];
  let remaining = amount;
  for (const event of events) {
    if (event.kind !== 'fund' || remaining === BigInt(0)) { continue; }
    const available = BigInt(event.remainingMinor);
    if (available <= BigInt(0)) { continue; }
    const used = remaining < available ? remaining : available;
    const cost = BigInt(event.remainingBookMinor);
    const numerator = cost * used;
    const book = used === available ? cost : numerator / available +
      (numerator % available * BigInt(2) >= available ? BigInt(1) : BigInt(0));
    result.push({ fundId: event.id, amountMinor: used.toString(), bookMinor: book.toString() });
    remaining -= used;
  }
  if (remaining !== BigInt(0)) { throw new Error('PREPAID_EXCEEDS_REMAINING'); }
  return result;
}

export function validPrepaidDate(text: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(text) && Number.isFinite(Date.parse(text + 'T00:00:00Z')) &&
    new Date(text + 'T00:00:00Z').toISOString().substring(0, 10) === text;
}
export function prepaidToday(): string {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
}
export function prepaidStatus(project: PrepaidProject): string {
  if (BigInt(project.remainingMinor) === BigInt(0)) { return BigInt(project.fundedMinor) > BigInt(0) ? '已结清' : '待付款'; }
  return BigInt(project.consumedMinor) > BigInt(0) || BigInt(project.refundedMinor) > BigInt(0) ? '部分核销' : '待核销';
}
export function prepaidExpiry(project: PrepaidProject): string {
  if (!project.expiryDate || BigInt(project.remainingMinor) === BigInt(0)) { return ''; }
  const days = Math.round((Date.parse(project.expiryDate + 'T00:00:00Z') - Date.parse(prepaidToday() + 'T00:00:00Z')) / 86400000);
  return days < 0 ? '已到期' : days === 0 ? '今日到期' : days <= 30 ? days.toString() + ' 天后到期' : '';
}
export function prepaidError(error: Error): string {
  const code = error.message || '';
  if (code.includes('PREPAID_EXCEEDS') || code.includes('PREPAID_ALLOCATION')) { return '金额超过预付款可用余额，请刷新后重试'; }
  if (code.includes('PREPAID_CHANGED')) { return '项目已变化，请刷新后重新操作'; }
  if (code.includes('PREPAID_LINKED')) { return '这是预付款关联账目，请到预付款项目中撤销对应流水'; }
  if (code.includes('PREPAID_UNDO')) { return '只能撤销最近一条有效流水；请先处理后续核销或回款'; }
  if (code.includes('ACCOUNT_UNAVAILABLE')) { return '请选择可用的付款／到账账户'; }
  if (code.includes('CATEGORY_UNAVAILABLE')) { return '请选择有效的分类'; }
  if (code.includes('EXPENSE_HAS_RECOVERIES')) { return '该核销已有退款或报销，请先处理关联回款'; }
  if (code.includes('PREPAID_AMOUNT') || code.includes('FX_') || code.includes('AMOUNT') || code.includes('CURRENCY')) { return '请检查金额、币种小数位和汇率'; }
  if (code.includes('PREPAID_DATE')) { return '日期格式应为 YYYY-MM-DD，且须为有效日期'; }
  if (code.includes('PREPAID_NAME')) { return '请填写项目名称，最多 40 字'; }
  return '操作未确认，请刷新检查项目流水，避免重复记录';
}
