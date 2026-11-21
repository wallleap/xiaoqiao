import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { Money } from '../../core/money/Money';
import { currencyUnit } from '../../core/money/Currencies';
import { LedgerAttachmentDraft, validateAttachmentDrafts } from '../../domain/model/LedgerAttachment';
import { PrepaidProject, PrepaidEvent, PrepaidDetail, PrepaidProjectCommand, PrepaidEventCommand,
  allocatePrepaid, validPrepaidDate, prepaidEntryContext } from '../../domain/model/Prepaid';
import { RdbAttachmentLinks } from './RdbAttachmentLinks';
import { RdbMerchantFields } from './RdbMerchantFields';
import { RdbSession } from './RdbSession';

/** Project, allocations, wallet movements and any linked expense publish in one shared transaction. */
export class RdbPrepaidRepository {
  private readonly session: RdbSession;
  constructor(store: relationalStore.RdbStore) { this.session = RdbSession.forStore(store); }

  static async projects(db: relationalStore.RdbStore, bookId: string = ''): Promise<PrepaidProject[]> {
    const result: PrepaidProject[] = [];
    const rows = await db.querySql('SELECT id,book_id,name,merchant,currency_id,expiry_date,note,include_in_net_assets,revision,' +
      'CAST(funded_minor AS TEXT),CAST(consumed_minor AS TEXT),CAST(refunded_minor AS TEXT),CAST(remaining_minor AS TEXT),CAST(remaining_book_minor AS TEXT),(SELECT base_currency_id FROM books WHERE id=v_prepaid_balances.book_id) FROM v_prepaid_balances' +
      (bookId ? ' WHERE book_id=?' : '') + ' ORDER BY created_at_ms,id', bookId ? [bookId] : []);
    try { while (rows.goToNextRow()) {
      result.push({ id: rows.getString(0), bookId: rows.getString(1), name: rows.getString(2), merchant: rows.getString(3),
        currencyId: rows.getString(4), expiryDate: rows.getString(5), note: rows.getString(6), includeInNetAssets: rows.getLong(7) === 1,
        revision: rows.getLong(8), fundedMinor: rows.getString(9), consumedMinor: rows.getString(10), refundedMinor: rows.getString(11),
        remainingMinor: rows.getString(12), remainingBookMinor: rows.getString(13), bookCurrencyId: rows.getString(14) });
    } } finally { rows.close(); }
    return result;
  }
  list(bookId: string): Promise<PrepaidProject[]> { return this.session.read((db: relationalStore.RdbStore) => RdbPrepaidRepository.projects(db, bookId)); }

  private static async detailIn(db: relationalStore.RdbStore, bookId: string, id: string): Promise<PrepaidDetail> {
    const project = (await RdbPrepaidRepository.projects(db, bookId)).find((item: PrepaidProject) => item.id === id);
    if (project === undefined) { throw new Error('PREPAID_CHANGED'); }
    const events: PrepaidEvent[] = [];
    const rows = await db.querySql("SELECT e.id,e.kind,CAST(e.amount_minor AS TEXT),CAST(e.book_minor AS TEXT),COALESCE(e.account_id,''),COALESCE(a.name,''),e.account_currency_id,CAST(e.cash_minor AS TEXT),CAST(e.cash_book_minor AS TEXT),COALESCE(e.transaction_id,''),e.local_date,e.occurred_at_ms,e.note," +
      'CAST(e.amount_minor-COALESCE((SELECT SUM(x.amount_minor) FROM prepaid_allocations x JOIN v_prepaid_events n ON n.id=x.event_id WHERE x.fund_id=e.id),0) AS TEXT),' +
      'CAST(e.book_minor-COALESCE((SELECT SUM(x.book_minor) FROM prepaid_allocations x JOIN v_prepaid_events n ON n.id=x.event_id WHERE x.fund_id=e.id),0) AS TEXT),e.quote_json' +
      ' FROM v_prepaid_events e LEFT JOIN accounts a ON a.id=e.account_id WHERE e.project_id=? ORDER BY e.sequence_no', [id]);
    try { while (rows.goToNextRow()) {
      events.push({ id: rows.getString(0), projectId: id, kind: rows.getString(1) === 'fund' ? 'fund' : rows.getString(1) === 'consume' ? 'consume' : 'refund',
        amountMinor: rows.getString(2), bookMinor: rows.getString(3), accountId: rows.getString(4), accountName: rows.getString(5),
        accountCurrencyId: rows.getString(6), cashMinor: rows.getString(7), cashBookMinor: rows.getString(8), transactionId: rows.getString(9),
        localDate: rows.getString(10), occurredAtMs: rows.getLong(11), note: rows.getString(12), remainingMinor: rows.getString(13), remainingBookMinor: rows.getString(14), entryContext: prepaidEntryContext(rows.getString(15)), attachments: [] });
    } } finally { rows.close(); }
    for (const event of events) {
      const images = await db.querySql('SELECT a.relative_path,a.content_sha256,a.byte_size,a.mime_type FROM prepaid_event_attachments l JOIN attachments a ON a.id=l.attachment_id WHERE l.event_id=? ORDER BY l.sort_order', [event.id]);
      try { while (images.goToNextRow()) { event.attachments.push({ relativePath: images.getString(0), sha256: images.getString(1), bytes: images.getLong(2), mimeType: images.getString(3) }); } } finally { images.close(); }
    }
    return { project: project, events: events };
  }
  detail(bookId: string, id: string): Promise<PrepaidDetail> { return this.session.read((db: relationalStore.RdbStore) => RdbPrepaidRepository.detailIn(db, bookId, id)); }

  private static validateProject(command: PrepaidProjectCommand): void {
    currencyUnit(command.currencyId);
    if (!command.id || !command.bookId || !command.name.trim() || command.name.trim().length > 40 || command.merchant.length > 100 || command.note.length > 2000 ||
      (command.expiryDate && !validPrepaidDate(command.expiryDate))) { throw new Error('PREPAID_PROJECT'); }
  }
  async create(command: PrepaidProjectCommand, payment: PrepaidEventCommand): Promise<void> {
    RdbPrepaidRepository.validateProject(command);
    if (payment.kind !== 'fund' || payment.projectId !== command.id || payment.bookId !== command.bookId) { throw new Error('PREPAID_PROJECT'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const book = await db.querySql("SELECT id FROM books WHERE id=? AND archived_at_ms IS NULL AND deleted_at_ms IS NULL", [command.bookId]);
      try { if (!book.goToFirstRow()) { throw new Error('LEDGER_BOOK_UNAVAILABLE'); } } finally { book.close(); }
      const now = Date.now();
      await db.insert('prepaid_projects', { id: command.id, book_id: command.bookId, name: command.name.trim(), merchant: command.merchant.trim(),
        currency_id: command.currencyId, expiry_date: command.expiryDate, note: command.note.trim(), include_in_net_assets: command.includeInNetAssets ? 1 : 0,
        created_at_ms: now, updated_at_ms: now });
      // The project is not committed yet; a separate reader cannot reliably see it.
      const initial: PrepaidDetail = { project: {
        id: command.id, bookId: command.bookId, name: command.name.trim(), merchant: command.merchant.trim(),
        currencyId: command.currencyId, expiryDate: command.expiryDate, note: command.note.trim(),
        includeInNetAssets: command.includeInNetAssets, revision: 1,
        fundedMinor: '0', consumedMinor: '0', refundedMinor: '0', remainingMinor: '0', remainingBookMinor: '0'
      }, events: [] };
      await RdbPrepaidRepository.saveIn(db, payment, initial);
    });
  }
  async update(command: PrepaidProjectCommand): Promise<void> {
    RdbPrepaidRepository.validateProject(command);
    if (!Number.isSafeInteger(command.expectedRevision) || (command.expectedRevision || 0)<1) { throw new Error('PREPAID_CHANGED'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const changed = await db.update({ name: command.name.trim(), merchant: command.merchant.trim(), expiry_date: command.expiryDate,
        note: command.note.trim(), include_in_net_assets: command.includeInNetAssets ? 1 : 0, updated_at_ms: Date.now(), revision: (command.expectedRevision || 0)+1 },
        new relationalStore.RdbPredicates('prepaid_projects').equalTo('id',command.id).equalTo('book_id',command.bookId)
          .equalTo('currency_id',command.currencyId).equalTo('revision',command.expectedRevision || 0));
      if (changed !== 1) { throw new Error('PREPAID_CHANGED'); }
    });
  }
  save(command: PrepaidEventCommand): Promise<void> { return this.session.write((db: relationalStore.RdbStore) => RdbPrepaidRepository.saveIn(db, command)); }

  private static async bookCode(db: relationalStore.RdbStore, bookId: string): Promise<string> {
    const rows = await db.querySql('SELECT base_currency_id FROM books WHERE id=? AND deleted_at_ms IS NULL', [bookId]);
    try { if (!rows.goToFirstRow()) { throw new Error('LEDGER_BOOK_UNAVAILABLE'); } return rows.getString(0); } finally { rows.close(); }
  }
  private static async writeTransaction(db: relationalStore.RdbStore, command: PrepaidEventCommand, project: PrepaidProject,
    amount: bigint, income: boolean): Promise<string> {
    if (amount <= BigInt(0)) { return ''; }
    const categoryId = income ? command.incomeCategoryId : command.categoryId;
    const category = await db.querySql('SELECT id FROM categories WHERE id=? AND book_id=? AND kind=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL', [categoryId,command.bookId,income ? 'income' : 'expense']);
    try { if (!category.goToFirstRow()) { throw new Error('PREPAID_CATEGORY'); } } finally { category.close(); }
    if (command.kind === 'consume' && command.spendingNatureId) {
      const nature = await db.querySql('SELECT id FROM spending_natures WHERE id=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL', [command.spendingNatureId]);
      try { if (!nature.goToFirstRow()) { throw new Error('PREPAID_CATEGORY'); } } finally { nature.close(); }
    }
    const bookCode = await RdbPrepaidRepository.bookCode(db, command.bookId);
    const id = util.generateRandomUUID(); const now = Date.now();
    const value = Money.fromMinor(amount,currencyUnit(bookCode)).toSafeMinorNumber();
    await db.insert('transactions', { id: id, book_id: command.bookId, kind: income ? 'income' : 'expense', category_id: categoryId,
      currency_id: bookCode, gross_minor: value, discount_minor: 0, paid_minor: value, book_currency_id: bookCode, book_minor: value,
      include_in_assets: 0, include_in_budget: command.kind === 'consume' && command.includeInBudget ? 1 : 0,
      spending_nature_id: command.kind === 'consume' ? command.spendingNatureId || null : null,
      balance_mode: 'apply', note: (command.kind === 'consume' ? '预付款核销 · ' : '预付款退款差额 · ') + project.name +
        ' · ' + command.amount.toDecimalString() + ' ' + project.currencyId + (command.note ? '\n' + command.note.trim() : ''),
      occurred_at_ms: command.occurredAtMs, occurred_local_date: command.localDate, occurred_timezone: 'UTC' + (command.offsetMinutes >= 0 ? '+' : '') + (command.offsetMinutes/60).toString(),
      occurred_offset_minutes: command.offsetMinutes, created_at_ms: now, updated_at_ms: now });
    await RdbMerchantFields.apply(db,id,project.merchant,'',null);
    await RdbAttachmentLinks.replace(db,id,command.attachments);
    await db.executeSql("UPDATE transactions SET posting_state='posted' WHERE id=?",[id]);
    return id;
  }
  private static async attachments(db: relationalStore.RdbStore, id: string, values?: LedgerAttachmentDraft[]): Promise<void> {
    let order = 0;
    for (const item of validateAttachmentDrafts(values) || []) {
      const rows = await db.querySql('SELECT id,relative_path,byte_size,mime_type FROM attachments WHERE content_sha256=? AND deleted_at_ms IS NULL',[item.sha256]);
      let attachmentId = '';
      try { if (rows.goToFirstRow()) {
        attachmentId = rows.getString(0);
        if (rows.getString(1) !== item.relativePath || rows.getLong(2) !== item.bytes || rows.getString(3) !== item.mimeType) { throw new Error('ATTACHMENT_METADATA_MISMATCH'); }
      } } finally { rows.close(); }
      if (!attachmentId) {
        attachmentId = util.generateRandomUUID();
        await db.insert('attachments',{ id: attachmentId, relative_path: item.relativePath, content_sha256: item.sha256, byte_size: item.bytes, mime_type: item.mimeType, state: 'ready', created_at_ms: Date.now() });
      }
      await db.insert('prepaid_event_attachments',{ event_id: id, attachment_id: attachmentId, sort_order: order++ });
    }
  }
  private static async saveIn(db: relationalStore.RdbStore, command: PrepaidEventCommand,
    initial: PrepaidDetail | undefined = undefined): Promise<void> {
    const detail = initial === undefined ? await RdbPrepaidRepository.detailIn(db, command.bookId, command.projectId) : initial;
    const project = detail.project;
    const bookCode = await RdbPrepaidRepository.bookCode(db, command.bookId);
    if (project.revision !== command.expectedRevision || !command.id || !['fund','consume','refund'].includes(command.kind)) { throw new Error('PREPAID_CHANGED'); }
    if (!command.amount.currency.matches(currencyUnit(project.currencyId)) || command.amount.minor <= BigInt(0) || !validPrepaidDate(command.localDate) ||
      !Number.isSafeInteger(command.occurredAtMs) || !Number.isInteger(command.offsetMinutes) || Math.abs(command.offsetMinutes)>840 ||
      new Date(command.occurredAtMs + command.offsetMinutes*60000).toISOString().substring(0,10) !== command.localDate || command.note.length>2000) { throw new Error('PREPAID_AMOUNT'); }
    command.amount.toSafeMinorNumber(); validateAttachmentDrafts(command.attachments);
    let bookMinor = BigInt(0); let transactionId = ''; let accountCode = project.currencyId;
    const allocations = command.kind === 'fund' ? [] : allocatePrepaid(detail.events,command.amount.minor);
    if (command.kind !== 'consume') {
      if (!['manual','ECB','ECB_CACHE'].includes(command.rateSource) || !validPrepaidDate(command.rateDate)) { throw new Error('PREPAID_CASH'); }
      if (!command.accountId || command.cash === undefined || command.cashBook === undefined || command.cash.minor<=BigInt(0) || command.cashBook.minor<BigInt(0) ||
        !command.cashBook.currency.matches(currencyUnit(bookCode))) { throw new Error('PREPAID_CASH'); }
      command.cash.toSafeMinorNumber(); command.cashBook.toSafeMinorNumber(); accountCode = command.cash.currency.id;
      const account = await db.querySql('SELECT id FROM accounts WHERE id=? AND currency_id=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL',[command.accountId,accountCode]);
      try { if (!account.goToFirstRow()) { throw new Error('ACCOUNT_UNAVAILABLE'); } } finally { account.close(); }
      if (project.currencyId === accountCode && command.cash.minor !== command.amount.minor) { throw new Error('PREPAID_CASH'); }
      if (accountCode === bookCode && command.cash.minor !== command.cashBook.minor) { throw new Error('PREPAID_CASH'); }
    }
    if (command.kind === 'fund') {
      bookMinor = command.cashBook?.minor || BigInt(0);
      let fundedBook=BigInt(0);
      for (const event of detail.events) { if (event.kind==='fund') { fundedBook+=BigInt(event.bookMinor); } }
      if (fundedBook+bookMinor>BigInt('9007199254740991')) { throw new Error('PREPAID_AMOUNT'); }
      if (BigInt(project.fundedMinor)+command.amount.minor>BigInt('9007199254740991') || BigInt(project.remainingBookMinor)+bookMinor>BigInt('9007199254740991')) { throw new Error('PREPAID_AMOUNT'); }
    } else {
      for (const allocation of allocations) { bookMinor += BigInt(allocation.bookMinor); }
      if (command.kind === 'consume') { transactionId = await RdbPrepaidRepository.writeTransaction(db,command,project,bookMinor,false); }
      else {
        const difference = (command.cashBook?.minor || BigInt(0))-bookMinor;
        if (difference !== BigInt(0)) { transactionId = await RdbPrepaidRepository.writeTransaction(db,command,project,difference>BigInt(0) ? difference : -difference,difference>BigInt(0)); }
      }
    }
    const sequence = await db.querySql('SELECT COALESCE(MAX(sequence_no),0)+1 FROM prepaid_events WHERE project_id=?',[project.id]);
    let next = 1; try { sequence.goToFirstRow(); next=sequence.getLong(0); } finally { sequence.close(); }
    await db.insert('prepaid_events',{ id: command.id, project_id: project.id, sequence_no: next, kind: command.kind,
      amount_minor: command.amount.toSafeMinorNumber(), book_minor: Money.fromMinor(bookMinor,currencyUnit(bookCode)).toSafeMinorNumber(),
      account_id: command.kind === 'consume' ? null : command.accountId, account_currency_id: accountCode,
      cash_minor: command.kind === 'consume' ? 0 : command.cash?.toSafeMinorNumber() || 0,
      cash_book_minor: command.kind === 'consume' ? 0 : command.cashBook?.toSafeMinorNumber() || 0,
      quote_json: JSON.stringify({ source: command.rateSource, date: command.rateDate, bookRate: command.bookRate, cashRate: command.cashRate, entry: command.entryContext }),
      transaction_id: transactionId || null, local_date: command.localDate, occurred_at_ms: command.occurredAtMs, offset_minutes: command.offsetMinutes,
      note: command.note.trim(), created_at_ms: Date.now() });
    for (const allocation of allocations) { await db.insert('prepaid_allocations',{ event_id: command.id, fund_id: allocation.fundId, amount_minor: Number(allocation.amountMinor), book_minor: Number(allocation.bookMinor) }); }
    await RdbPrepaidRepository.attachments(db,command.id,command.attachments);
    await db.executeSql("UPDATE prepaid_events SET posting_state='posted' WHERE id=?",[command.id]);
    const changed = await db.update({ revision: project.revision+1, updated_at_ms: Date.now() },new relationalStore.RdbPredicates('prepaid_projects').equalTo('id',project.id).equalTo('revision',project.revision));
    if (changed!==1) { throw new Error('PREPAID_CHANGED'); }
  }
  async undo(bookId: string, projectId: string, eventId: string, revision: number): Promise<void> {
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const detail = await RdbPrepaidRepository.detailIn(db,bookId,projectId);
      const event = detail.events[detail.events.length-1];
      if (detail.project.revision!==revision || event === undefined || event.id!==eventId) { throw new Error('PREPAID_UNDO_ORDER'); }
      await db.update({ deleted_at_ms: Date.now() },new relationalStore.RdbPredicates('prepaid_events').equalTo('id',event.id).isNull('deleted_at_ms'));
      if (event.transactionId) {
        await db.executeSql('UPDATE transactions SET deleted_at_ms=?,updated_at_ms=?,revision=revision+1 WHERE id=?',[Date.now(),Date.now(),event.transactionId]);
      }
      const changed = await db.update({ revision: revision+1,updated_at_ms:Date.now() },new relationalStore.RdbPredicates('prepaid_projects').equalTo('id',projectId).equalTo('revision',revision));
      if (changed!==1) { throw new Error('PREPAID_CHANGED'); }
    });
  }
}
