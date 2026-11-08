import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { TransferRecord } from '../../domain/model/TransferRecord';
import { TransferRepository } from '../../domain/ports/TransferRepository';
import { RdbSession } from './RdbSession';

export class RdbTransferRepository implements TransferRepository {
  private readonly session: RdbSession;
  constructor(store: relationalStore.RdbStore) { this.session = RdbSession.forStore(store); }
  async saveTransfer(record: TransferRecord): Promise<void> { await this.write(record); }
  async updateTransfer(record: TransferRecord, revision: number): Promise<void> { await this.write(record, revision); }

  private async replaceTags(db: relationalStore.RdbStore, transactionId: string, bookId: string,
    tagIds: string[] | undefined): Promise<void> {
    if (tagIds === undefined) { return; }
    const values = Array.from(new Set(tagIds));
    if (values.length > 0) {
      const placeholders = Array.from({ length: values.length }, (_value: number, _index: number) => '?').join(',');
      const args: relationalStore.ValueType[] = [bookId];
      values.forEach((id: string) => { args.push(id); });
      const rows = await db.querySql(`SELECT id FROM tags WHERE book_id=? AND id IN (${placeholders}) AND ` +
        '(deleted_at_ms IS NULL OR EXISTS(SELECT 1 FROM transaction_tags linked WHERE linked.transaction_id=? AND linked.tag_id=tags.id))',
        [...args, transactionId]);
      let found = 0;
      try { while (rows.goToNextRow()) { found++; } } finally { rows.close(); }
      if (found !== values.length) { throw new Error('TAG_UNAVAILABLE'); }
    }
    await db.delete(new relationalStore.RdbPredicates('transaction_tags').equalTo('transaction_id', transactionId));
    for (const tagId of values) {
      await db.insert('transaction_tags', { transaction_id: transactionId, tag_id: tagId, book_id: bookId });
    }
  }

  private async write(record: TransferRecord, revision: number | undefined = undefined): Promise<void> {
    const command = record.command;
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      let oldFrom: string = ''; let oldTo: string = '';
      if (revision !== undefined) {
        const source = await db.querySql("SELECT t.currency_id,t.book_currency_id,t.group_id,(SELECT COUNT(*) FROM fx_snapshots WHERE transaction_id=t.id),(SELECT COUNT(*) FROM account_movements WHERE transaction_id=t.id AND currency_id<>'CNY'),COALESCE((SELECT account_id FROM account_movements WHERE transaction_id=t.id AND leg='transfer_out'),d.from_account_id,''),COALESCE((SELECT account_id FROM account_movements WHERE transaction_id=t.id AND leg='transfer_in'),'') FROM v_posted_transactions t LEFT JOIN transfer_details d ON d.transaction_id=t.id WHERE t.id=? AND t.book_id=? AND t.kind='transfer' AND t.revision=?", [command.id, command.bookId, revision]);
        try {
          if (!source.goToFirstRow()) { throw new Error('TRANSACTION_CHANGED'); }
          if (source.getString(0) !== 'CNY' || source.getString(1) !== 'CNY' || !source.isColumnNull(2) ||
            source.getLong(3) !== 0 || source.getLong(4) !== 0) { throw new Error('UNSUPPORTED_TRANSFER_EDIT'); }
          oldFrom = source.getString(5); oldTo = source.getString(6);
        } finally { source.close(); }
      }
      const from = await db.querySql("SELECT id,kind FROM accounts WHERE id=? AND currency_id='CNY' AND deleted_at_ms IS NULL AND (archived_at_ms IS NULL OR id=?)", [command.fromAccountId, oldFrom]);
      try { if (!from.goToFirstRow()) { throw new Error('ACCOUNT_UNAVAILABLE'); } } finally { from.close(); }
      const to = await db.querySql("SELECT id,kind FROM accounts WHERE id=? AND currency_id='CNY' AND deleted_at_ms IS NULL AND (archived_at_ms IS NULL OR id=?)", [command.toAccountId, oldTo]);
      try {
        if (!to.goToFirstRow()) { throw new Error('ACCOUNT_UNAVAILABLE'); }
        if ((record.purpose === 'credit_repayment' || record.purpose === 'loan_repayment') && to.getString(1) !== 'liability') { throw new Error('REPAYMENT_ACCOUNT_REQUIRED'); }
      } finally { to.close(); }
      const minor = command.amount.toSafeMinorNumber(); const now = Date.now();
      if (revision === undefined) {
        await db.insert('transactions', { id: command.id, book_id: command.bookId, kind: 'transfer', currency_id: 'CNY',
          gross_minor: minor, discount_minor: 0, paid_minor: minor, book_currency_id: 'CNY', book_minor: minor,
          include_in_budget: 0, include_in_assets: command.includeInAssets ? 1 : 0, balance_mode: 'apply',
          note: command.note, occurred_at_ms: command.occurredAtMs, occurred_local_date: command.localDate,
          occurred_timezone: command.timezone, occurred_offset_minutes: command.offsetMinutes, created_at_ms: now, updated_at_ms: now });
      } else {
        const changed = await db.update({ posting_state: 'draft', revision: revision + 1, updated_at_ms: now },
          new relationalStore.RdbPredicates('transactions').equalTo('id', command.id).equalTo('book_id', command.bookId)
            .equalTo('kind', 'transfer').equalTo('revision', revision).equalTo('posting_state', 'posted').isNull('deleted_at_ms'));
        if (changed !== 1) { throw new Error('TRANSACTION_CHANGED'); }
        // Preserve source identity, balance_mode, creation time and untouched relations.
        await db.update({ gross_minor: minor, paid_minor: minor, book_minor: minor, include_in_assets: command.includeInAssets ? 1 : 0,
          note: command.note, occurred_at_ms: command.occurredAtMs, occurred_local_date: command.localDate,
          occurred_timezone: command.timezone, occurred_offset_minutes: command.offsetMinutes },
          new relationalStore.RdbPredicates('transactions').equalTo('id', command.id));
        await db.delete(new relationalStore.RdbPredicates('account_movements').equalTo('transaction_id', command.id));
      }
      const details: relationalStore.ValuesBucket = { purpose: record.purpose, currency_id: 'CNY',
        from_account_id: command.fromAccountId, to_account_id: command.toAccountId,
        out_minor: record.outgoing.toSafeMinorNumber(), in_minor: minor, fee_minor: record.fee.toSafeMinorNumber(),
        coupon_minor: record.coupon.toSafeMinorNumber(), fee_in_expense: record.feeInExpense ? 1 : 0, fee_in_budget: record.feeInBudget ? 1 : 0 };
      const updated = await db.update(details, new relationalStore.RdbPredicates('transfer_details').equalTo('transaction_id', command.id));
      if (updated === 0) { details.transaction_id = command.id; await db.insert('transfer_details', details); }
      if (record.outgoing.minor > BigInt(0)) {
        await db.insert('account_movements', { id: util.generateRandomUUID(), transaction_id: command.id,
          account_id: command.fromAccountId, currency_id: 'CNY', leg: 'transfer_out', delta_minor: -record.outgoing.toSafeMinorNumber(), occurred_at_ms: command.occurredAtMs });
      }
      await db.insert('account_movements', { id: util.generateRandomUUID(), transaction_id: command.id,
        account_id: command.toAccountId, currency_id: 'CNY', leg: 'transfer_in', delta_minor: minor, occurred_at_ms: command.occurredAtMs });
      await this.replaceTags(db, command.id, command.bookId, command.tagIds);
      const published = await db.update({ posting_state: 'posted' }, new relationalStore.RdbPredicates('transactions')
        .equalTo('id', command.id).equalTo('posting_state', 'draft'));
      if (published !== 1) { throw new Error('TRANSACTION_CHANGED'); }
    });
  }
}
