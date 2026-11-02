import { Money } from '../../core/money/Money';

/** New manual expense. Imports use a separate batch command, not this entry point. */
export interface ExpenseCommand {
  readonly id: string;
  readonly bookId: string;
  readonly categoryId: string;
  readonly gross: Money;
  readonly discount: Money;
  readonly bookPaid: Money;
  readonly accountId?: string;
  readonly accountPaid?: Money;
  readonly includeInAssets: boolean;
  readonly includeInBudget: boolean;
  readonly note: string;
  readonly occurredAtMs: number;
  readonly localDate: string;
  readonly timezone: string;
  readonly offsetMinutes: number;
}

export class ExpenseRecord {
  readonly command: ExpenseCommand;
  readonly paid: Money;

  constructor(command: ExpenseCommand) {
    if (command.id.trim().length === 0 || command.bookId.trim().length === 0 ||
      command.categoryId.trim().length === 0 || !Number.isSafeInteger(command.occurredAtMs) ||
      !/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(command.localDate) || command.timezone.trim().length === 0 ||
      !Number.isInteger(command.offsetMinutes) || command.offsetMinutes < -840 || command.offsetMinutes > 840) {
      throw new Error('INVALID_EXPENSE');
    }
    if (command.gross.minor <= BigInt(0) || command.discount.minor < BigInt(0)) {
      throw new Error('INVALID_EXPENSE_AMOUNT');
    }
    this.paid = command.gross.subtract(command.discount);
    if (this.paid.minor <= BigInt(0) || command.bookPaid.minor < BigInt(0)) {
      throw new Error('INVALID_EXPENSE_AMOUNT');
    }
    if ((command.accountId === undefined) !== (command.accountPaid === undefined) ||
      (command.accountId !== undefined && command.accountId.trim().length === 0) ||
      (command.accountPaid !== undefined && command.accountPaid.minor <= BigInt(0))) {
      throw new Error('INVALID_SETTLEMENT');
    }
    // P0 manual command intentionally handles only same-currency settlement.
    // Foreign-currency persistence requires explicit FX snapshot commands first.
    if (!this.paid.currency.matches(command.bookPaid.currency) || this.paid.minor !== command.bookPaid.minor ||
      (command.accountPaid !== undefined && (!command.accountPaid.currency.matches(this.paid.currency) ||
      command.accountPaid.minor !== this.paid.minor))) {
      throw new Error('FX_SNAPSHOT_COMMAND_REQUIRED');
    }
    command.gross.toSafeMinorNumber();
    command.discount.toSafeMinorNumber();
    command.bookPaid.toSafeMinorNumber();
    if (command.accountPaid !== undefined) {
      command.accountPaid.toSafeMinorNumber();
    }
    const localDay = new Date(command.occurredAtMs + command.offsetMinutes * 60000);
    if (!Number.isFinite(localDay.getTime()) || localDay.toISOString().substring(0, 10) !== command.localDate) {
      throw new Error('INVALID_LOCAL_DATE');
    }
    this.command = {
      id: command.id, bookId: command.bookId, categoryId: command.categoryId,
      gross: command.gross, discount: command.discount, bookPaid: command.bookPaid,
      accountId: command.accountId, accountPaid: command.accountPaid,
      includeInAssets: command.includeInAssets, includeInBudget: command.includeInBudget,
      note: command.note, occurredAtMs: command.occurredAtMs, localDate: command.localDate,
      timezone: command.timezone, offsetMinutes: command.offsetMinutes
    };
  }
}
