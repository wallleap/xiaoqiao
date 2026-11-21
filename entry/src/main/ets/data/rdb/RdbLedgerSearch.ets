import { relationalStore } from '@kit.ArkData';
import { SavedLedgerEntry } from '../../domain/model/LedgerSnapshot';
import { LedgerSearchCursor, LedgerSearchPageResult, LedgerFlowQuery, LedgerFlowPage, LedgerFlowDay } from '../../domain/model/LedgerSearch';
import { prepaidEntryContext } from '../../domain/model/Prepaid';

// The three branches share the same column order. No month filter, resource handles or writes.
const TRANSACTIONS = `SELECT t.id,t.occurred_at_ms AS sort_ms,t.occurred_local_date AS local_date,t.occurred_offset_minutes AS offset_minutes,t.kind,
 t.note,CASE WHEN t.kind='transfer' THEN CASE d.purpose WHEN 'credit_repayment' THEN '信用卡还款' WHEN 'loan_repayment' THEN '借款还款' WHEN 'topup' THEN '充值' WHEN 'withdrawal' THEN '提现' ELSE '转账' END ELSE c.name END AS category,
 COALESCE(c.icon_key,'other') AS icon_key,COALESCE(a.name,'不使用账户') AS account_name,COALESCE(m.account_id,d.from_account_id,'') AS account_id,COALESCE(ai.name,'') AS to_account,
 CAST(CASE WHEN t.kind='transfer' THEN d.out_minor ELSE COALESCE(t.book_minor,t.paid_minor) END AS TEXT) AS minor,
 CAST(t.gross_minor AS TEXT) AS gross,CAST(t.discount_minor AS TEXT) AS discount,t.currency_id,
 CAST(CASE WHEN t.kind='transfer' THEN d.out_minor ELSE t.paid_minor END AS TEXT) AS original_minor,
 COALESCE(m.currency_id,t.currency_id) AS cash_currency,CAST(COALESCE(ABS(m.delta_minor),t.paid_minor) AS TEXT) AS cash_minor,
 CAST(CASE WHEN d.fee_in_expense=1 THEN COALESCE(d.book_fee_minor,0) ELSE 0 END AS TEXT) AS expense_fee,
 COALESCE(d.purpose,'transfer') AS purpose,'' AS prepaid_id,'0' AS remaining,'{}' AS context_json,
 COALESCE((SELECT GROUP_CONCAT(g.name,' ') FROM transaction_tags tt JOIN tags g ON g.id=tt.tag_id WHERE tt.transaction_id=t.id AND tt.book_id=t.book_id AND g.deleted_at_ms IS NULL),'') AS tags,
 t.note || ' ' || COALESCE(c.name,'转账') || ' ' || COALESCE(a.name,'') || ' ' || COALESCE(ai.name,'') || ' ' ||
 COALESCE((SELECT GROUP_CONCAT(g.name,' ') FROM transaction_tags tt JOIN tags g ON g.id=tt.tag_id WHERE tt.transaction_id=t.id AND tt.book_id=t.book_id AND g.deleted_at_ms IS NULL),'') ||
 CASE WHEN t.kind='transfer' THEN ' ' || CASE d.purpose WHEN 'credit_repayment' THEN '信用卡还款' WHEN 'loan_repayment' THEN '借款还款' WHEN 'topup' THEN '充值' WHEN 'withdrawal' THEN '提现' ELSE '转账' END ELSE '' END AS search_text,
 CAST(COALESCE((SELECT SUM(r.amount_minor) FROM v_expense_recoveries r WHERE r.transaction_id=t.id),0) AS TEXT) AS recovered,
 CAST(COALESCE((SELECT SUM(r.amount_minor) FROM v_expense_recoveries r WHERE r.transaction_id=t.id AND r.kind='reimbursement'),0) AS TEXT) AS reimbursed,
 CAST(COALESCE((SELECT SUM(r.amount_minor) FROM v_expense_recoveries r WHERE r.transaction_id=t.id AND r.kind='refund'),0) AS TEXT) AS refunded,
 t.reimbursement_status AS pending,COALESCE(d.to_account_id,'') AS to_account_id
 FROM v_posted_transactions t LEFT JOIN v_historical_categories c ON c.id=t.category_id LEFT JOIN v_transfer_details d ON d.transaction_id=t.id
 LEFT JOIN account_movements m ON m.transaction_id=t.id AND m.leg<>'transfer_in'
 LEFT JOIN accounts a ON a.id=COALESCE(m.account_id,d.from_account_id) LEFT JOIN accounts ai ON ai.id=d.to_account_id
 WHERE t.book_id=? AND t.kind IN ('expense','income','transfer')`;

const RECOVERIES = `SELECT r.id,r.occurred_at_ms,r.local_date,r.offset_minutes,r.kind,r.note,COALESCE(c.name,''),COALESCE(c.icon_key,'other'),COALESCE(a.name,'不使用账户'),COALESCE(r.account_id,''),'',
 '-' || CAST(r.book_minor AS TEXT),CAST(r.amount_minor AS TEXT),'0',r.currency_id,CAST(r.amount_minor AS TEXT),r.account_currency_id,CAST(r.account_minor AS TEXT),'0','','','0',r.transaction_id,
 COALESCE((SELECT GROUP_CONCAT(g.name,' ') FROM transaction_tags tt JOIN tags g ON g.id=tt.tag_id WHERE tt.transaction_id=r.transaction_id AND tt.book_id=r.book_id AND g.deleted_at_ms IS NULL),''),
 r.note || ' ' || COALESCE(c.name,'') || ' ' || COALESCE(a.name,'') || CASE WHEN r.kind='refund' THEN ' 退款' ELSE ' 报销到账' END || ' ' ||
 COALESCE((SELECT GROUP_CONCAT(g.name,' ') FROM transaction_tags tt JOIN tags g ON g.id=tt.tag_id WHERE tt.transaction_id=r.transaction_id AND tt.book_id=r.book_id AND g.deleted_at_ms IS NULL),''),
 '0','0','0','none',''
 FROM v_expense_recoveries r LEFT JOIN v_historical_categories c ON c.id=r.category_id LEFT JOIN accounts a ON a.id=r.account_id WHERE r.book_id=?`;

const PREPAID = `SELECT e.id,e.occurred_at_ms,e.local_date,e.offset_minutes,'prepaid_' || e.kind,
 p.name || CASE WHEN e.note<>'' THEN ' · ' || e.note ELSE '' END,CASE WHEN e.kind='refund' THEN '预付款退款' ELSE '预付款' END,'other',COALESCE(a.name,'不使用账户'),COALESCE(e.account_id,''),'',
 CAST(e.book_minor AS TEXT),CAST(e.amount_minor AS TEXT),'0',p.currency_id,CAST(e.amount_minor AS TEXT),e.account_currency_id,CAST(e.cash_minor AS TEXT),'0','',p.id,CAST(p.remaining_minor AS TEXT),e.quote_json,'',
 p.name || ' ' || e.note || ' ' || COALESCE(a.name,'') || ' ' || e.quote_json || CASE WHEN e.kind='refund' THEN ' 预付款退款' ELSE ' 预付款' END,
 '0','0','0','none',''
 FROM v_prepaid_events e JOIN v_prepaid_balances p ON p.id=e.project_id LEFT JOIN accounts a ON a.id=e.account_id WHERE p.book_id=? AND e.kind IN ('fund','refund')`;

export class RdbLedgerSearch {
  private static entry(rows: relationalStore.ResultSet): SavedLedgerEntry {
    const kind = rows.getString(4);
    const prepaid = kind.startsWith('prepaid_');
    const recovery = kind === 'refund' || kind === 'reimbursement';
    const entry: SavedLedgerEntry = {
      id: rows.getString(0), occurredAtMs: rows.getLong(1), date: rows.getString(2), offsetMinutes: rows.getLong(3),
      note: rows.getString(5), category: rows.getString(6), iconKey: rows.getString(7), account: rows.getString(8), accountId: rows.getString(9),
      toAccount: rows.getString(10), minor: rows.getString(11), grossMinor: rows.getString(12), discountMinor: rows.getString(13),
      income: kind === 'income', transfer: kind === 'transfer', expenseMinor: rows.getString(18), transferPurpose: rows.getString(19),
      reimbursementPending: rows.getString(28) === 'pending', recoveredMinor: rows.getString(25), reimbursedMinor: rows.getString(26), refundedMinor: rows.getString(27),
      tagNames: rows.getString(23) ? [rows.getString(23)] : [],
      fx: { currencyId: rows.getString(14), paidMinor: rows.getString(15), grossMinor: rows.getString(12), discountMinor: rows.getString(13),
        bookMinor: rows.getString(11), accountCurrencyId: rows.getString(16), accountMinor: rows.getString(17) }
    };
    if (recovery) { entry.recoveryKind = kind; entry.originalEntryId = rows.getString(22); }
    if (prepaid) {
      entry.prepaidId = rows.getString(20); entry.prepaidKind = kind === 'prepaid_refund' ? 'refund' : 'fund';
      entry.prepaidStatus = entry.prepaidKind === 'refund' ? '预付款退款' : BigInt(rows.getString(21)) === BigInt(0) ? '已结清' : '待核销';
      const context = prepaidEntryContext(rows.getString(22));
      entry.tagNames = context?.tagNames || [];
    }
    return entry;
  }

  /** Range paging shares the same posted-entry projection as keyword search. No writes. */
  static async flow(db: relationalStore.RdbStore, bookId: string, query: LedgerFlowQuery,
    cursor: LedgerSearchCursor | undefined = undefined): Promise<LedgerFlowPage> {
    if (![0, 1, 2].includes(query.kind) ||
      (query.startDate !== '' && !/^\d{4}-\d{2}-\d{2}$/.test(query.startDate)) ||
      (query.endDateExclusive !== '' && !/^\d{4}-\d{2}-\d{2}$/.test(query.endDateExclusive)) ||
      (query.startDate && query.endDateExclusive && query.startDate >= query.endDateExclusive) ||
      (cursor !== undefined && (!Number.isSafeInteger(cursor.occurredAtMs) || !cursor.id))) {
      throw new Error('INVALID_FLOW_QUERY');
    }
    const cte = 'WITH entries AS (' + TRANSACTIONS + ' UNION ALL ' + RECOVERIES + ' UNION ALL ' + PREPAID + ') ';
    const args: relationalStore.ValueType[] = [bookId, bookId, bookId];
    let where = ' WHERE 1=1';
    if (query.startDate) { where += ' AND local_date>=?'; args.push(query.startDate); }
    if (query.endDateExclusive) { where += ' AND local_date<?'; args.push(query.endDateExclusive); }
    if (query.kind === 1) { where += " AND (kind IN ('expense','refund','reimbursement') OR (kind='transfer' AND CAST(expense_fee AS INTEGER)>0))"; }
    if (query.kind === 2) { where += " AND kind='income'"; }
    const pageArgs = args.slice();
    let after = '';
    if (cursor !== undefined) {
      after = ' AND (sort_ms<? OR (sort_ms=? AND id<?))';
      pageArgs.push(cursor.occurredAtMs, cursor.occurredAtMs, cursor.id);
    }
    const entries: SavedLedgerEntry[] = [];
    const rows = await db.querySql(cte + 'SELECT * FROM entries' + where + after + ' ORDER BY sort_ms DESC,id DESC LIMIT 51', pageArgs);
    try { while (rows.goToNextRow()) { entries.push(RdbLedgerSearch.entry(rows)); } } finally { rows.close(); }
    const hasMore = entries.length > 50;
    if (hasMore) { entries.pop(); }
    const dates = Array.from(new Set(entries.map((entry: SavedLedgerEntry) => entry.date)));
    const days: LedgerFlowDay[] = [];
    if (dates.length > 0) {
      const dayArgs = args.slice();
      dates.forEach((date: string) => { dayArgs.push(date); });
      // Aggregate each returned day without the page cursor, including unseen entries on that day.
      const totals = await db.querySql(cte + "SELECT local_date,kind,minor,expense_fee FROM entries" +
        where + ' AND local_date IN (' + dates.map(() => '?').join(',') + ')', dayArgs);
      const byDate = new Map<string, LedgerFlowDay>();
      try {
        while (totals.goToNextRow()) {
          const date = totals.getString(0);
          const day: LedgerFlowDay = byDate.get(date) || { date: date, incomeMinor: '0', expenseMinor: '0' };
          const kind = totals.getString(1);
          if (kind === 'income') { day.incomeMinor = (BigInt(day.incomeMinor) + BigInt(totals.getString(2))).toString(); }
          else if (kind === 'transfer') { day.expenseMinor = (BigInt(day.expenseMinor) + BigInt(totals.getString(3))).toString(); }
          else if (kind === 'expense' || kind === 'refund' || kind === 'reimbursement') {
            day.expenseMinor = (BigInt(day.expenseMinor) + BigInt(totals.getString(2))).toString();
          }
          byDate.set(date, day);
        }
        byDate.forEach((day: LedgerFlowDay) => { days.push(day); });
      } finally { totals.close(); }
    }
    const result: LedgerFlowPage = { entries: entries, days: days, hasMore: hasMore };
    const last = entries[entries.length - 1];
    if (hasMore && last !== undefined) { result.nextCursor = { occurredAtMs: last.occurredAtMs, id: last.id }; }
    return result;
  }

  static async search(db: relationalStore.RdbStore, bookId: string, keyword: string,
    cursor: LedgerSearchCursor | undefined = undefined, pageSize: number = 50, accountId: string = ''): Promise<LedgerSearchPageResult> {
    const query = keyword.trim();
    if (query.length > 200 || !Number.isInteger(pageSize) || pageSize < 1 || pageSize > 100 ||
      (cursor !== undefined && (!Number.isSafeInteger(cursor.occurredAtMs) || !cursor.id))) { throw new Error('INVALID_SEARCH_QUERY'); }
    const entries: SavedLedgerEntry[] = [];
    if (!query) { return { entries: entries, hasMore: false }; }
    let scan = cursor;
    let exhausted = false;
    // Scan small chunks to exclude JSON metadata false positives in prepaid tag searches.
    while (entries.length <= pageSize && !exhausted) {
      const args: relationalStore.ValueType[] = [bookId, bookId, bookId, query];
      let after = '';
      if (scan !== undefined) { after = ' AND (sort_ms<? OR (sort_ms=? AND id<?))'; args.push(scan.occurredAtMs, scan.occurredAtMs, scan.id); }
      if (accountId) { after += ' AND (account_id=? OR to_account_id=?)'; args.push(accountId, accountId); }
      const rows = await db.querySql('WITH entries AS (' + TRANSACTIONS + ' UNION ALL ' + RECOVERIES + ' UNION ALL ' + PREPAID +
        ') SELECT * FROM entries WHERE instr(lower(search_text),lower(?))>0' + after + ' ORDER BY sort_ms DESC,id DESC LIMIT 100', args);
      try {
        let scanned = 0;
        while (rows.goToNextRow()) {
          scanned++;
          const entry = RdbLedgerSearch.entry(rows);
          scan = { occurredAtMs: entry.occurredAtMs, id: entry.id };
          if (entry.prepaidId) {
            const context = prepaidEntryContext(rows.getString(22));
            const text = [entry.note, entry.category, entry.account, context?.categoryName || '', ...(entry.tagNames || [])].join(' ').toLowerCase();
            if (!text.includes(query.toLowerCase())) { continue; }
          }
          entries.push(entry);
          if (entries.length > pageSize) { break; }
        }
        exhausted = scanned < 100;
      } finally { rows.close(); }
    }
    const hasMore = entries.length > pageSize;
    if (hasMore) { entries.pop(); }
    const last = entries.length > 0 ? entries[entries.length - 1] : undefined;
    let nextCursor: LedgerSearchCursor | undefined = undefined;
    if (hasMore && last !== undefined) { nextCursor = { occurredAtMs: last.occurredAtMs, id: last.id }; }
    return { entries: entries, hasMore: hasMore, nextCursor: nextCursor };
  }
}
