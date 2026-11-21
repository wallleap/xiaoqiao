import { RdbFxSnapshots } from './RdbFxSnapshots';
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
import { RdbAttachmentLinks } from './RdbAttachmentLinks';
import { RdbMerchantFields } from './RdbMerchantFields';

export class RdbLedgerRepository implements LedgerRepository, ExpenseUpdateRepository, IncomeRepository {
  private readonly session: RdbSession;

  constructor(store: relationalStore.RdbStore) {
    this.session = RdbSession.forStore(store);
  }

  async saveExpense(record: ExpenseRecord): Promise<void> { await this.saveRecord(record, 'expense'); }
  async saveIncome(record: IncomeRecord): Promise<void> { await this.saveRecord(record.settlement, 'income'); }

  private async replaceTags(store: relationalStore.RdbStore, transactionId: string, bookId: string,
    tagIds: string[] | undefined): Promise<void> {
    if (tagIds === undefined) { return; }
    const values = Array.from(new Set(tagIds));
    if (values.length > 0) {
      const placeholders = Array.from({ length: values.length }, (_value: number, _index: number) => '?').join(',');
      const args: relationalStore.ValueType[] = [bookId];
      values.forEach((id: string) => { args.push(id); });
      const rows = await store.querySql(`SELECT id FROM tags WHERE book_id=? AND id IN (${placeholders}) AND ` +
        '(deleted_at_ms IS NULL OR EXISTS(SELECT 1 FROM transaction_tags linked WHERE linked.transaction_id=? AND linked.tag_id=tags.id))',
        [...args, transactionId]);
      let found = 0;
      try { while (rows.goToNextRow()) { found++; } } finally { rows.close(); }
      if (found !== values.length) { throw new Error('TAG_UNAVAILABLE'); }
    }
    await store.delete(new relationalStore.RdbPredicates('transaction_tags').equalTo('transaction_id', transactionId));
    for (const tagId of values) {
      await store.insert('transaction_tags', { transaction_id: transactionId, tag_id: tagId, book_id: bookId });
    }
  }

  private async saveRecord(record: ExpenseRecord, kind: string): Promise<void> {
    const command = record.command;
    await this.session.write(async (store: relationalStore.RdbStore): Promise<void> => {
      if (command.accountId !== undefined) {
        const account = await store.querySql('SELECT currency_id FROM accounts WHERE id=? AND archived_at_ms IS NULL AND deleted_at_ms IS NULL', [command.accountId]);
        try {
          if (!account.goToFirstRow() || account.getString(0) !== command.accountPaid?.currency.id) { throw new Error('ACCOUNT_UNAVAILABLE'); }
        } finally { account.close(); }
      }
      const values: relationalStore.ValuesBucket = {
        id: command.id, book_id: command.bookId, kind: kind, category_id: command.categoryId,
        currency_id: record.paid.currency.id, gross_minor: command.gross.toSafeMinorNumber(),
        discount_minor: command.discount.toSafeMinorNumber(), paid_minor: record.paid.toSafeMinorNumber(),
        book_currency_id: command.bookPaid.currency.id, book_minor: command.bookPaid.toSafeMinorNumber(),
        include_in_assets: command.includeInAssets ? 1 : 0, include_in_budget: command.includeInBudget ? 1 : 0,
        reimbursement_status: kind === 'expense' && command.reimbursementPending ? 'pending' : 'none',
        balance_mode: 'apply', note: command.note, occurred_at_ms: command.occurredAtMs,
        occurred_local_date: command.localDate, occurred_timezone: command.timezone,
        occurred_offset_minutes: command.offsetMinutes, created_at_ms: Date.now(), updated_at_ms: Date.now()
      };
      if (command.spendingNatureId !== undefined) { values.spending_nature_id = command.spendingNatureId; }
      await store.insert('transactions', values);
      await RdbMerchantFields.apply(store, command.id, command.merchantName, command.addressText, command.location);
      await RdbFxSnapshots.insert(store, command.id, record.paid, command.bookPaid, command.bookFx);
      const accountId = command.accountId;
      const accountPaid = command.accountPaid;
      if (accountId !== undefined && accountPaid !== undefined) {
        const movement: relationalStore.ValuesBucket = {
          id: util.generateRandomUUID(), transaction_id: command.id, account_id: accountId,
          currency_id: accountPaid.currency.id, leg: kind, delta_minor: (kind === 'income' ? 1 : -1) * accountPaid.toSafeMinorNumber(),
          occurred_at_ms: command.occurredAtMs
        };
        await store.insert('account_movements', movement);
        await RdbFxSnapshots.insert(store, command.id, record.paid, accountPaid, command.accountFx, movement.id as string);
      }
      await this.replaceTags(store, command.id, command.bookId, command.tagIds);
      await RdbAttachmentLinks.replace(store, command.id, command.attachments);
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
      const source = await db.querySql("SELECT t.category_id,t.currency_id,t.book_currency_id,(SELECT COUNT(*) FROM fx_snapshots WHERE transaction_id=t.id),(SELECT COUNT(*) FROM account_movements WHERE transaction_id=t.id AND currency_id<>t.currency_id),COALESCE((SELECT account_id FROM account_movements WHERE transaction_id=t.id LIMIT 1),''),COALESCE(tx.spending_nature_id,'') FROM v_posted_transactions t JOIN transactions tx ON tx.id=t.id WHERE t.id=? AND t.book_id=? AND t.kind=? AND t.revision=?",
        [command.id, command.bookId, kind, expectedRevision]);
      let oldCategory: string;
      let oldAccount: string;
      let oldNature: string;
      try {
        if (!source.goToFirstRow()) { throw new Error('TRANSACTION_CHANGED'); }
        if (source.getString(1) !== record.paid.currency.id || source.getString(2) !== command.bookPaid.currency.id) { throw new Error('UNSUPPORTED_EXPENSE_EDIT'); }
        oldCategory = source.getString(0); oldAccount = source.getString(5); oldNature = source.getString(6);
      } finally { source.close(); }
      if (kind === 'expense') {
        const received = await db.querySql('SELECT CAST(COALESCE(SUM(amount_minor),0) AS TEXT) FROM expense_recoveries WHERE transaction_id=? AND deleted_at_ms IS NULL', [command.id]);
        try { received.goToFirstRow(); if (BigInt(received.getString(0)) > record.paid.minor) { throw new Error('RECOVERY_EXCEEDS_PAID'); } } finally { received.close(); }
      }
      const category = await db.querySql("SELECT id FROM categories WHERE id=? AND book_id=? AND kind=? AND deleted_at_ms IS NULL AND (archived_at_ms IS NULL OR id=?) UNION ALL SELECT id FROM category_history WHERE id=? AND id=? AND book_id=? AND kind=?",
        [command.categoryId, command.bookId, kind, oldCategory, command.categoryId, oldCategory, command.bookId, kind]);
      try { if (!category.goToFirstRow()) { throw new Error('CATEGORY_UNAVAILABLE'); } }
      finally { category.close(); }
      if (command.spendingNatureId !== undefined) {
        const nature = await db.querySql('SELECT id FROM spending_natures WHERE id=? AND deleted_at_ms IS NULL AND (archived_at_ms IS NULL OR id=?)',
          [command.spendingNatureId, oldNature]);
        try { if (!nature.goToFirstRow()) { throw new Error('SPENDING_NATURE_UNAVAILABLE'); } }
        finally { nature.close(); }
      }
      if (command.accountId !== undefined) {
        const account = await db.querySql('SELECT currency_id FROM accounts WHERE id=? AND deleted_at_ms IS NULL AND (archived_at_ms IS NULL OR id=?)',
          [command.accountId, oldAccount]);
        try {
          if (!account.goToFirstRow() || account.getString(0) !== command.accountPaid?.currency.id) { throw new Error('ACCOUNT_UNAVAILABLE'); }
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
        include_in_budget: command.includeInBudget ? 1 : 0, spending_nature_id: command.spendingNatureId || null,
        note: command.note, occurred_at_ms: command.occurredAtMs,
        occurred_local_date: command.localDate, occurred_timezone: command.timezone,
        occurred_offset_minutes: command.offsetMinutes }, new relationalStore.RdbPredicates('transactions').equalTo('id', command.id));
      if (kind === 'expense' && command.reimbursementPending !== undefined) {
        await db.update({ reimbursement_status: command.reimbursementPending ? 'pending' : 'none' }, new relationalStore.RdbPredicates('transactions').equalTo('id', command.id));
      }
      await RdbMerchantFields.apply(db, command.id, command.merchantName, command.addressText, command.location);
      await db.delete(new relationalStore.RdbPredicates('fx_snapshots').equalTo('transaction_id', command.id));
      await RdbFxSnapshots.insert(db, command.id, record.paid, command.bookPaid, command.bookFx);
      await db.delete(new relationalStore.RdbPredicates('account_movements').equalTo('transaction_id', command.id));
      if (command.accountId !== undefined && command.accountPaid !== undefined) {
        const movementId = util.generateRandomUUID();
        await db.insert('account_movements', { id: movementId, transaction_id: command.id,
          account_id: command.accountId, currency_id: command.accountPaid.currency.id, leg: kind,
          delta_minor: (kind === 'income' ? 1 : -1) * command.accountPaid.toSafeMinorNumber(), occurred_at_ms: command.occurredAtMs });
        await RdbFxSnapshots.insert(db, command.id, record.paid, command.accountPaid, command.accountFx, movementId);
      }
      await this.replaceTags(db, command.id, command.bookId, command.tagIds);
      await RdbAttachmentLinks.replace(db, command.id, command.attachments);
      const published = await db.update({ posting_state: 'posted' }, new relationalStore.RdbPredicates('transactions')
        .equalTo('id', command.id).equalTo('revision', expectedRevision + 1).equalTo('posting_state', 'draft'));
      if (published !== 1) { throw new Error('TRANSACTION_CHANGED'); }
    });
  }
}
