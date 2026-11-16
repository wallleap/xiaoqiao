import { Money } from '../../core/money/Money';
import { currencyUnit } from '../../core/money/Currencies';
import { validateConversion, FxConversion } from '../../core/money/FxConversion';
import { relationalStore } from '@kit.ArkData';
import { ExpenseRecovery, RecoveryCommand } from '../../domain/model/ExpenseRecovery';

/** Caller owns the RdbSession transaction. No ordinary income or fabricated balance adjustment is created. */
export class RdbRecoveryRepository {
  static async list(db: relationalStore.RdbStore, transactionId: string): Promise<ExpenseRecovery[]> {
    const result: ExpenseRecovery[] = [];
    const rows = await db.querySql("SELECT r.id,r.kind,CAST(r.amount_minor AS TEXT),COALESCE(r.account_id,''),COALESCE(a.name,'不使用账户'),r.local_date,r.occurred_at_ms,r.offset_minutes,r.note,r.revision,r.balance_mode,r.currency_id,CAST(r.book_minor AS TEXT),CAST(r.account_minor AS TEXT),r.account_currency_id,r.fx_snapshot FROM v_expense_recoveries r LEFT JOIN accounts a ON a.id=r.account_id WHERE r.transaction_id=? ORDER BY r.occurred_at_ms DESC,r.id", [transactionId]);
    try {
      while (rows.goToNextRow()) {
        result.push({ id: rows.getString(0), transactionId: transactionId,
          kind: rows.getString(1) === 'refund' ? 'refund' : 'reimbursement', amountMinor: rows.getString(2),
          accountId: rows.getString(3), accountName: rows.getString(4), localDate: rows.getString(5),
          occurredAtMs: rows.getLong(6), offsetMinutes: rows.getLong(7), note: rows.getString(8),
          revision: rows.getLong(9), balanceMode: rows.getString(10), currencyId: rows.getString(11), bookMinor: rows.getString(12),
          accountMinor: rows.getString(13), accountCurrencyId: rows.getString(14), accountFx: rows.getString(15) ? JSON.parse(rows.getString(15)) as FxConversion : undefined });
      }
    } finally { rows.close(); }
    return result;
  }

  static async save(db: relationalStore.RdbStore, command: RecoveryCommand,
    batchId: string = '', sourceId: string = '', applyBalance: boolean = true, importRowId: string = ''): Promise<void> {
    let amount: bigint;
    try { amount = BigInt(command.amountMinor); } catch (_) { throw new Error('INVALID_RECOVERY'); }
    const date = new Date(command.localDate + 'T12:00:00');
    const local = new Date(command.occurredAtMs + command.offsetMinutes * 60000);
    const actualDate = `${local.getUTCFullYear()}-${String(local.getUTCMonth() + 1).padStart(2, '0')}-${String(local.getUTCDate()).padStart(2, '0')}`;
    if (command.id.length === 0 || command.transactionId.length === 0 || amount <= BigInt(0) || amount > BigInt('9007199254740991') ||
      !['refund', 'reimbursement'].includes(command.kind) || !Number.isSafeInteger(command.occurredAtMs) ||
      !Number.isInteger(command.offsetMinutes) || Math.abs(command.offsetMinutes) > 840 ||
      !/^\d{4}-\d{2}-\d{2}$/.test(command.localDate) || !Number.isFinite(date.getTime()) || actualDate !== command.localDate) {
      throw new Error('INVALID_RECOVERY');
    }
    const parent = await db.querySql("SELECT revision,currency_id,CAST(paid_minor AS TEXT),CAST(book_minor AS TEXT) FROM transactions t WHERE id=? AND book_id=? AND kind='expense' AND posting_state='posted' AND deleted_at_ms IS NULL AND (import_batch_id IS NULL OR import_batch_id=? OR EXISTS(SELECT 1 FROM import_batches b WHERE b.id=t.import_batch_id AND b.status='committed'))", [command.transactionId, command.bookId, batchId]);
    let parentRevision: number; let sourceCurrency: string; let paid: bigint; let bookPaid: bigint;
    try {
      if (!parent.goToFirstRow()) { throw new Error('RECOVERY_SOURCE_INVALID'); }
      parentRevision = parent.getLong(0); sourceCurrency = parent.getString(1); paid = BigInt(parent.getString(2)); bookPaid = BigInt(parent.getString(3));
    } finally { parent.close(); }
    const others = await db.querySql('SELECT CAST(amount_minor AS TEXT),CAST(COALESCE(book_minor,amount_minor) AS TEXT) FROM expense_recoveries WHERE transaction_id=? AND deleted_at_ms IS NULL AND id<>?', [command.transactionId, command.id]);
    let otherOriginal = BigInt(0); let otherBook = BigInt(0);
    try { while (others.goToNextRow()) { otherOriginal += BigInt(others.getString(0)); otherBook += BigInt(others.getString(1)); } } finally { others.close(); }
    if (otherOriginal + amount > paid) { throw new Error('RECOVERY_EXCEEDS_PAID'); }
    const numerator = bookPaid * (otherOriginal + amount);
    const cumulative = numerator / paid + (numerator % paid * BigInt(2) >= paid ? BigInt(1) : BigInt(0));
    const bookAmount = command.bookMinor === undefined ? cumulative - otherBook : BigInt(command.bookMinor);
    if (bookAmount < BigInt(0) || bookAmount + otherBook > bookPaid) { throw new Error('INVALID_RECOVERY'); }
    let accountCurrency = sourceCurrency;
    if (command.accountId) {
      const account = await db.querySql('SELECT currency_id FROM accounts WHERE id=? AND deleted_at_ms IS NULL', [command.accountId]);
      try { if (!account.goToFirstRow()) { throw new Error('ACCOUNT_UNAVAILABLE'); } accountCurrency = account.getString(0); } finally { account.close(); }
    }
    if (command.currencyId !== undefined && command.currencyId !== sourceCurrency) { throw new Error('INVALID_RECOVERY'); }
    const accountAmount = Money.fromMinorText(command.accountMinor || command.amountMinor, currencyUnit(accountCurrency));
    validateConversion(Money.fromMinorText(command.amountMinor, currencyUnit(sourceCurrency)), accountAmount, command.accountFx);
    const now = Date.now();
    const values: relationalStore.ValuesBucket = { book_minor: Number(bookAmount), account_minor: accountAmount.toSafeMinorNumber(),
      account_currency_id: accountCurrency, fx_snapshot: command.accountFx === undefined ? '' : JSON.stringify(command.accountFx), kind: command.kind, amount_minor: Number(amount),
      account_id: command.accountId || null, occurred_at_ms: command.occurredAtMs, local_date: command.localDate,
      offset_minutes: command.offsetMinutes, note: command.note.trim(), updated_at_ms: now };
    if (command.expectedRevision !== undefined) {
      values.revision = command.expectedRevision + 1;
      const changed = await db.update(values, new relationalStore.RdbPredicates('expense_recoveries')
        .equalTo('id', command.id).equalTo('transaction_id', command.transactionId).equalTo('book_id', command.bookId)
        .equalTo('revision', command.expectedRevision).isNull('deleted_at_ms'));
      if (changed !== 1) { throw new Error('RECOVERY_CHANGED'); }
    } else {
      values.id = command.id; values.transaction_id = command.transactionId; values.book_id = command.bookId;
      values.balance_mode = applyBalance ? 'apply' : 'preserve'; values.created_at_ms = now;
      values.import_row_id = importRowId || null; values.import_batch_id = batchId || null; values.source_record_id = sourceId || null;
      await db.insert('expense_recoveries', values);
    }
    const parentChanged = await db.update({ revision: parentRevision + 1, updated_at_ms: now },
      new relationalStore.RdbPredicates('transactions').equalTo('id', command.transactionId).equalTo('revision', parentRevision));
    if (parentChanged !== 1) { throw new Error('TRANSACTION_CHANGED'); }
  }

  static async remove(db: relationalStore.RdbStore, bookId: string, id: string, revision: number): Promise<void> {
    const row = await db.querySql('SELECT transaction_id FROM v_expense_recoveries WHERE id=? AND book_id=? AND revision=?', [id, bookId, revision]);
    let parent: string;
    try { if (!row.goToFirstRow()) { throw new Error('RECOVERY_CHANGED'); } parent = row.getString(0); } finally { row.close(); }
    const changed = await db.update({ deleted_at_ms: Date.now(), updated_at_ms: Date.now(), revision: revision + 1 },
      new relationalStore.RdbPredicates('expense_recoveries').equalTo('id', id).equalTo('book_id', bookId).equalTo('revision', revision).isNull('deleted_at_ms'));
    if (changed !== 1) { throw new Error('RECOVERY_CHANGED'); }
    await db.executeSql('UPDATE transactions SET revision=revision+1,updated_at_ms=? WHERE id=?', [Date.now(), parent]);
  }
}
