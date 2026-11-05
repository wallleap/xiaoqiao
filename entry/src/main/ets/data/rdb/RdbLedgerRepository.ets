import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';
import { ExpenseRecord } from '../../domain/model/ExpenseRecord';
import { LedgerRepository } from '../../domain/ports/LedgerRepository';
import { ExpenseUpdateRepository } from '../../domain/ports/ExpenseUpdateRepository';
import { IncomeRecord } from '../../domain/model/IncomeRecord';
import { IncomeRepository } from '../../domain/ports/IncomeRepository';
import { RdbSession } from './RdbSession';

export class RdbLedgerRepository implements LedgerRepository, ExpenseUpdateRepository, IncomeRepository {
  private readonly session: RdbSession;

  constructor(store: relationalStore.RdbStore) {
    this.session = RdbSession.forStore(store);
  }

  async saveExpense(record: ExpenseRecord): Promise<void> { await this.saveRecord(record, 'expense'); }
  async saveIncome(record: IncomeRecord): Promise<void> { await this.saveRecord(record.settlement, 'income'); }

  private async saveRecord(record: ExpenseRecord, kind: string): Promise<void> {
    const command = record.command;
    await this.session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      const values: relationalStore.ValuesBucket = {
        id: command.id, book_id: command.bookId, kind: kind, category_id: command.categoryId,
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
          currency_id: accountPaid.currency.id, leg: kind, delta_minor: (kind === 'income' ? 1 : -1) * accountPaid.toSafeMinorNumber(),
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

  async updateExpense(record: ExpenseRecord, expectedRevision: number): Promise<void> {
    await this.updateRecord(record, expectedRevision, 'expense');
  }
  async updateIncome(record: IncomeRecord, expectedRevision: number): Promise<void> {
    await this.updateRecord(record.settlement, expectedRevision, 'income');
  }

  private async updateRecord(record: ExpenseRecord, expectedRevision: number, kind: string): Promise<void> {
    const command = record.command;
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const source = await db.querySql("SELECT category_id,currency_id,book_currency_id,(SELECT COUNT(*) FROM fx_snapshots WHERE transaction_id=t.id),(SELECT COUNT(*) FROM account_movements WHERE transaction_id=t.id AND currency_id<>t.currency_id),COALESCE((SELECT account_id FROM account_movements WHERE transaction_id=t.id LIMIT 1),'') FROM v_posted_transactions t WHERE id=? AND book_id=? AND kind=? AND revision=?",
        [command.id, command.bookId, kind, expectedRevision]);
      let oldCategory: string;
      let oldAccount: string;
      try {
        if (!source.goToFirstRow()) { throw new Error('TRANSACTION_CHANGED'); }
        if (source.getString(1) !== record.paid.currency.id || source.getString(2) !== command.bookPaid.currency.id ||
          source.getLong(3) !== 0 || source.getLong(4) !== 0) { throw new Error('UNSUPPORTED_EXPENSE_EDIT'); }
        oldCategory = source.getString(0); oldAccount = source.getString(5);
      } finally { source.close(); }
      const category = await db.querySql("SELECT id FROM categories WHERE id=? AND book_id=? AND kind=? AND deleted_at_ms IS NULL AND (archived_at_ms IS NULL OR id=?)",
        [command.categoryId, command.bookId, kind, oldCategory]);
      try { if (!category.goToFirstRow()) { throw new Error('CATEGORY_UNAVAILABLE'); } }
      finally { category.close(); }
      if (command.accountId !== undefined) {
        const account = await db.querySql('SELECT currency_id FROM accounts WHERE id=? AND deleted_at_ms IS NULL AND (archived_at_ms IS NULL OR id=?)',
          [command.accountId, oldAccount]);
        try {
          if (!account.goToFirstRow() || account.getString(0) !== record.paid.currency.id) { throw new Error('ACCOUNT_UNAVAILABLE'); }
        } finally { account.close(); }
      }
      const changed = await db.update({ posting_state: 'draft', revision: expectedRevision + 1, updated_at_ms: Date.now() },
        new relationalStore.RdbPredicates('transactions').equalTo('id', command.id).equalTo('book_id', command.bookId)
          .equalTo('kind', kind).equalTo('revision', expectedRevision).equalTo('posting_state', 'posted').isNull('deleted_at_ms'));
      if (changed !== 1) { throw new Error('TRANSACTION_CHANGED'); }
      // Leave import identity, balance_mode, attachments, tags and other unedited fields intact.
      await db.update({ category_id: command.categoryId, gross_minor: command.gross.toSafeMinorNumber(),
        discount_minor: command.discount.toSafeMinorNumber(), paid_minor: record.paid.toSafeMinorNumber(),
        book_minor: command.bookPaid.toSafeMinorNumber(), include_in_assets: command.includeInAssets ? 1 : 0,
        include_in_budget: command.includeInBudget ? 1 : 0, note: command.note, occurred_at_ms: command.occurredAtMs,
        occurred_local_date: command.localDate, occurred_timezone: command.timezone,
        occurred_offset_minutes: command.offsetMinutes }, new relationalStore.RdbPredicates('transactions').equalTo('id', command.id));
      await db.delete(new relationalStore.RdbPredicates('account_movements').equalTo('transaction_id', command.id));
      if (command.accountId !== undefined && command.accountPaid !== undefined) {
        await db.insert('account_movements', { id: util.generateRandomUUID(), transaction_id: command.id,
          account_id: command.accountId, currency_id: command.accountPaid.currency.id, leg: kind,
          delta_minor: (kind === 'income' ? 1 : -1) * command.accountPaid.toSafeMinorNumber(), occurred_at_ms: command.occurredAtMs });
      }
      const published = await db.update({ posting_state: 'posted' }, new relationalStore.RdbPredicates('transactions')
        .equalTo('id', command.id).equalTo('revision', expectedRevision + 1).equalTo('posting_state', 'draft'));
      if (published !== 1) { throw new Error('TRANSACTION_CHANGED'); }
    });
  }
}
