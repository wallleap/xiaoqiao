import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';
import { ExpenseRecord } from '../../domain/model/ExpenseRecord';
import { LedgerRepository } from '../../domain/ports/LedgerRepository';
import { RdbSession } from './RdbSession';

export class RdbLedgerRepository implements LedgerRepository {
  private readonly session: RdbSession;

  constructor(store: relationalStore.RdbStore) {
    this.session = RdbSession.forStore(store);
  }

  async saveExpense(record: ExpenseRecord): Promise<void> {
    const command = record.command;
    await this.session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      const values: relationalStore.ValuesBucket = {
        id: command.id, book_id: command.bookId, kind: 'expense', category_id: command.categoryId,
        currency_id: record.paid.currency.id, gross_minor: command.gross.toSafeMinorNumber(),
        discount_minor: command.discount.toSafeMinorNumber(), paid_minor: record.paid.toSafeMinorNumber(),
        book_currency_id: command.bookPaid.currency.id, book_minor: command.bookPaid.toSafeMinorNumber(),
        include_in_assets: command.includeInAssets ? 1 : 0, include_in_budget: command.includeInBudget ? 1 : 0,
        balance_mode: 'apply', note: command.note, occurred_at_ms: command.occurredAtMs,
        occurred_local_date: command.localDate, occurred_timezone: command.timezone,
        occurred_offset_minutes: command.offsetMinutes, created_at_ms: Date.now(), updated_at_ms: Date.now()
      };
      await store.insert('transactions', values);
      const accountId = command.accountId;
      const accountPaid = command.accountPaid;
      if (accountId !== undefined && accountPaid !== undefined) {
        const movement: relationalStore.ValuesBucket = {
          id: util.generateRandomUUID(), transaction_id: command.id, account_id: accountId,
          currency_id: accountPaid.currency.id, leg: 'expense', delta_minor: -accountPaid.toSafeMinorNumber(),
          occurred_at_ms: command.occurredAtMs
        };
        await store.insert('account_movements', movement);
      }
      await store.executeSql("UPDATE transactions SET posting_state='posted' WHERE id=?", [command.id]);
    });
  }

  async readBalance(accountId: string, currency: CurrencyUnit): Promise<Money> {
    return this.session.read(async (store: relationalStore.RdbStore): Promise<Money> => {
      const result = await store.querySql(
        'SELECT currency_id, CAST(balance_minor AS TEXT) FROM v_account_balances WHERE account_id=?', [accountId]);
      try {
        if (!result.goToFirstRow()) {
          throw new Error('ACCOUNT_NOT_FOUND');
        }
        if (result.getString(0) !== currency.id) {
          throw new Error('CURRENCY_MISMATCH');
        }
        return Money.fromMinorText(result.getString(1), currency);
      } finally {
        result.close();
      }
    });
  }
}
