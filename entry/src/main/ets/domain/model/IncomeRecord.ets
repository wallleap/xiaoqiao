import { Money } from '../../core/money/Money';
import { ExpenseRecord } from './ExpenseRecord';
import { LedgerAttachmentDraft } from './LedgerAttachment';

/** Manual same-currency income. No discount or expense-budget fields are accepted. */
export interface IncomeCommand {
  readonly id: string;
  readonly bookId: string;
  readonly categoryId: string;
  readonly amount: Money;
  readonly bookAmount: Money;
  readonly accountId?: string;
  readonly accountAmount?: Money;
  readonly includeInAssets: boolean;
  readonly tagIds?: string[];
  readonly attachments?: LedgerAttachmentDraft[];
  readonly note: string;
  readonly occurredAtMs: number;
  readonly localDate: string;
  readonly timezone: string;
  readonly offsetMinutes: number;
}

export class IncomeRecord {
  // Reuse exact amount/date/settlement validation; persistence still explicitly uses kind=income.
  readonly settlement: ExpenseRecord;
  constructor(command: IncomeCommand) {
    this.settlement = new ExpenseRecord({ id: command.id, bookId: command.bookId, categoryId: command.categoryId,
      gross: command.amount, discount: Money.fromMinorText('0', command.amount.currency), bookPaid: command.bookAmount,
      accountId: command.accountId, accountPaid: command.accountAmount, includeInAssets: command.includeInAssets,
      includeInBudget: false, tagIds: command.tagIds, attachments: command.attachments,
      note: command.note, occurredAtMs: command.occurredAtMs, localDate: command.localDate,
      timezone: command.timezone, offsetMinutes: command.offsetMinutes });
  }
}
