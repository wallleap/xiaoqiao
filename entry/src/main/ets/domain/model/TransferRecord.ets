import { LedgerLocation } from './LedgerLocation';
import { Money } from '../../core/money/Money';
import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { ExpenseRecord } from './ExpenseRecord';
import { LedgerAttachmentDraft } from './LedgerAttachment';

export interface TransferPurpose { key: string; label: string; repayment: boolean; }
export const TRANSFER_PURPOSES: TransferPurpose[] = [
  { key: 'transfer', label: '普通转账', repayment: false },
  { key: 'credit_repayment', label: '信用卡还款', repayment: true },
  { key: 'loan_repayment', label: '借款还款', repayment: true },
  { key: 'topup', label: '充值', repayment: false },
  { key: 'withdrawal', label: '提现', repayment: false }
];
export function transferPurposeLabel(key: string): string { return TRANSFER_PURPOSES.find((value: TransferPurpose) => value.key === key)?.label || '普通转账'; }

export interface TransferCommand {
  id: string;
  bookId: string;
  fromAccountId: string;
  toAccountId: string;
  amount: Money;
  purpose?: string;
  fee?: Money;
  coupon?: Money;
  feeInBudget?: boolean;
  includeInAssets: boolean;
  tagIds?: string[];
  attachments?: LedgerAttachmentDraft[];
  /** Undefined preserves existing text on update; empty text clears it. */
  merchantName?: string;
  addressText?: string;
  /** Undefined preserves coordinates; null clears them. */
  location?: LedgerLocation | null;
  note: string;
  occurredAtMs: number;
  localDate: string;
  timezone: string;
  offsetMinutes: number;
}

export class TransferRecord {
  readonly command: TransferCommand;
  readonly outgoing: Money;
  readonly fee: Money;
  readonly coupon: Money;
  readonly purpose: string;
  readonly feeInExpense: boolean;
  readonly feeInBudget: boolean;
  constructor(command: TransferCommand) {
    if (command.fromAccountId.trim().length === 0 || command.toAccountId.trim().length === 0 ||
      command.fromAccountId === command.toAccountId) { throw new Error('INVALID_TRANSFER_ACCOUNTS'); }
    if (!command.amount.currency.matches(new CurrencyUnit('CNY', 'CNY', 2))) { throw new Error('UNSUPPORTED_TRANSFER_CURRENCY'); }
    // Reuse exact positive amount, persistence-boundary and captured-local-date validation.
    const validated = new ExpenseRecord({ id: command.id, bookId: command.bookId, categoryId: 'transfer',
      gross: command.amount, discount: Money.fromMinorText('0', command.amount.currency), bookPaid: command.amount,
      includeInAssets: command.includeInAssets, includeInBudget: false, tagIds: command.tagIds, note: command.note,
      attachments: command.attachments, merchantName: command.merchantName, addressText: command.addressText, location: command.location,
      occurredAtMs: command.occurredAtMs, localDate: command.localDate, timezone: command.timezone, offsetMinutes: command.offsetMinutes }).command;
    const purpose = TRANSFER_PURPOSES.find((value: TransferPurpose) => value.key === (command.purpose || 'transfer'));
    if (purpose === undefined) { throw new Error('INVALID_TRANSFER_PURPOSE'); }
    this.purpose = purpose.key;
    this.fee = command.fee || Money.fromMinorText('0', command.amount.currency);
    this.coupon = command.coupon || Money.fromMinorText('0', command.amount.currency);
    if (this.fee.minor < BigInt(0) || this.coupon.minor < BigInt(0) || this.coupon.minor > command.amount.minor ||
      (this.coupon.minor > BigInt(0) && !purpose.repayment)) { throw new Error('INVALID_TRANSFER_EXTRAS'); }
    this.outgoing = command.amount.add(this.fee).subtract(this.coupon);
    this.fee.toSafeMinorNumber(); this.coupon.toSafeMinorNumber(); this.outgoing.toSafeMinorNumber();
    this.feeInExpense = true;
    this.feeInBudget = this.feeInExpense && command.feeInBudget !== false;
    this.command = { id: validated.id, bookId: validated.bookId, fromAccountId: command.fromAccountId,
      toAccountId: command.toAccountId, amount: validated.gross, purpose: this.purpose, fee: this.fee, coupon: this.coupon,
      feeInBudget: this.feeInBudget, includeInAssets: validated.includeInAssets,
      tagIds: validated.tagIds,
      attachments: validated.attachments,
      merchantName: validated.merchantName, addressText: validated.addressText, location: validated.location,
      note: validated.note, occurredAtMs: validated.occurredAtMs, localDate: validated.localDate,
      timezone: validated.timezone, offsetMinutes: validated.offsetMinutes };
  }
}
