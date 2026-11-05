import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { TransferCommand } from '../../domain/model/TransferRecord';
import { TransferService } from '../../domain/services/TransferService';
import { RdbTransferRepository } from './RdbTransferRepository';
import { AccountCommand, AccountOverview } from '../../domain/model/AccountProfile';
import { RdbAccountRepository } from './RdbAccountRepository';
import { IncomeCommand } from '../../domain/model/IncomeRecord';
import { IncomeService } from '../../domain/services/IncomeService';
import { ExpenseCommand } from '../../domain/model/ExpenseRecord';
import { ExpenseCategory, LedgerAccount, LedgerSnapshot, SavedLedgerEntry } from '../../domain/model/LedgerSnapshot';
import { RecordExpense } from '../../domain/services/RecordExpense';
import { UpdateExpense } from '../../domain/services/UpdateExpense';
import { EntryDetail } from '../../domain/model/EntryDetail';
import { MonthlyBudget, DEFAULT_MONTHLY_BUDGET_MINOR } from '../../domain/model/MonthlyBudget';
import { LedgerDatabase, DEFAULT_BOOK_ID } from './LedgerDatabase';
import { RdbLedgerRepository } from './RdbLedgerRepository';
import { RdbSession } from './RdbSession';

/** Owns the store for the foreground ledger. All runtime SQL goes through its shared serial session. */
export class LedgerWorkspace {
  private static readonly instances: Map<string, Promise<LedgerWorkspace>> = new Map();
  readonly currency: CurrencyUnit = new CurrencyUnit('CNY', 'CNY', 2);
  private readonly store: relationalStore.RdbStore;
  private readonly session: RdbSession;
  private readonly writer: RecordExpense;
  private readonly updater: UpdateExpense;
  private readonly income: IncomeService;
  private readonly transfer: TransferService;
  private readonly accountRepository: RdbAccountRepository;

  private constructor(store: relationalStore.RdbStore) {
    this.store = store;
    this.session = RdbSession.forStore(store);
    this.accountRepository = new RdbAccountRepository(store);
    this.transfer = new TransferService(new RdbTransferRepository(store));
    this.income = new IncomeService(new RdbLedgerRepository(store));
    this.writer = new RecordExpense(new RdbLedgerRepository(store));
    this.updater = new UpdateExpense(new RdbLedgerRepository(store));
  }

  static async open(context: common.Context, name: string = 'xiaoqiao.db'): Promise<LedgerWorkspace> {
    const existing = LedgerWorkspace.instances.get(name);
    if (existing !== undefined) { return existing; }
    const pending = LedgerDatabase.open(context, name).then((store: relationalStore.RdbStore) => new LedgerWorkspace(store));
    LedgerWorkspace.instances.set(name, pending);
    try { return await pending; } catch (error) {
      LedgerWorkspace.instances.delete(name);
      throw error as Error;
    }
  }

  /** Test/recovery lifecycle only: caller must ensure no live UI or writes use this workspace. */
  static async close(name: string): Promise<void> {
    const instance = LedgerWorkspace.instances.get(name);
    if (instance !== undefined) {
      const workspace = await instance;
      await workspace.session.read(async (db: relationalStore.RdbStore): Promise<void> => { await db.close(); });
      LedgerWorkspace.instances.delete(name);
    }
  }

  async saveExpense(command: ExpenseCommand): Promise<void> { await this.writer.execute(command); }

  async updateExpense(command: ExpenseCommand, expectedRevision: number): Promise<void> {
    await this.updater.execute(command, expectedRevision);
  }

  async accountOverview(): Promise<AccountOverview> { return this.accountRepository.snapshot(); }
  async createAccount(command: AccountCommand): Promise<void> { await this.accountRepository.create(command); }
  async updateAccount(command: AccountCommand, revision: number): Promise<void> { await this.accountRepository.update(command, revision); }
  async archiveAccount(id: string, revision: number, archived: boolean): Promise<void> { await this.accountRepository.archive(id, revision, archived); }

  async saveTransfer(command: TransferCommand): Promise<void> { await this.transfer.save(command); }
  async updateTransfer(command: TransferCommand, revision: number): Promise<void> { await this.transfer.update(command, revision); }

  async saveIncome(command: IncomeCommand): Promise<void> { await this.income.save(command); }
  async updateIncome(command: IncomeCommand, revision: number): Promise<void> { await this.income.update(command, revision); }

  async entryDetail(id: string): Promise<EntryDetail> {
    if (id.trim().length === 0) { throw new Error('INVALID_TRANSACTION_ID'); }
    return this.session.read(async (db: relationalStore.RdbStore): Promise<EntryDetail> => {
      const rows = await db.querySql("SELECT t.id,t.book_id,b.name,t.kind,t.revision,COALESCE(t.category_id,''),COALESCE(c.name,'转账'),COALESCE(c.icon_key,'other'),COALESCE(m.account_id,d.from_account_id,''),COALESCE(a.name,''),t.currency_id,u.code,u.symbol,u.minor_unit,CAST(t.gross_minor AS TEXT),CAST(t.discount_minor AS TEXT),CAST(t.paid_minor AS TEXT),CAST(COALESCE(t.book_minor,t.paid_minor) AS TEXT),t.include_in_budget,t.include_in_assets,t.balance_mode,t.occurred_at_ms,t.occurred_local_date,t.occurred_timezone,t.occurred_offset_minutes,t.note,t.book_currency_id,COALESCE(m.currency_id,t.currency_id),(SELECT COUNT(*) FROM fx_snapshots WHERE transaction_id=t.id),COALESCE(mi.account_id,''),COALESCE(ai.name,''),COALESCE(mi.currency_id,t.currency_id),t.group_id,COALESCE(d.purpose,'transfer'),CAST(COALESCE(d.out_minor,t.paid_minor) AS TEXT),CAST(COALESCE(d.in_minor,t.paid_minor) AS TEXT),CAST(COALESCE(d.fee_minor,0) AS TEXT),CAST(COALESCE(d.coupon_minor,0) AS TEXT),COALESCE(d.fee_in_expense,1),COALESCE(d.fee_in_budget,1),COALESCE(a.kind,'asset'),COALESCE(ai.kind,'asset') FROM v_posted_transactions t JOIN books b ON b.id=t.book_id JOIN currencies u ON u.id=t.currency_id LEFT JOIN categories c ON c.id=t.category_id LEFT JOIN transfer_details d ON d.transaction_id=t.id LEFT JOIN account_movements m ON m.transaction_id=t.id AND m.leg<>'transfer_in' LEFT JOIN accounts a ON a.id=COALESCE(m.account_id,d.from_account_id) LEFT JOIN account_movements mi ON mi.transaction_id=t.id AND mi.leg='transfer_in' LEFT JOIN accounts ai ON ai.id=mi.account_id WHERE t.id=? AND t.book_id=?",
        [id, DEFAULT_BOOK_ID]);
      let detail: EntryDetail;
      try {
        if (!rows.goToFirstRow()) { throw new Error('TRANSACTION_NOT_FOUND'); }
        const canEdit = (rows.getString(3) === 'expense' || rows.getString(3) === 'income' || rows.getString(3) === 'transfer') && rows.getString(10) === this.currency.id &&
          rows.getString(26) === this.currency.id && rows.getString(27) === this.currency.id && rows.getLong(28) === 0 && (rows.getString(3) !== 'transfer' || (rows.getString(29).length > 0 && rows.getString(31) === this.currency.id && rows.isColumnNull(32)));
        detail = { id: rows.getString(0), bookId: rows.getString(1), bookName: rows.getString(2), kind: rows.getString(3),
          revision: rows.getLong(4), categoryId: rows.getString(5), categoryName: rows.getString(6), categoryPath: rows.getString(6),
          iconKey: rows.getString(7), accountId: rows.getString(8), accountName: rows.getString(9), currencyId: rows.getString(10),
          currencyCode: rows.getString(11), currencySymbol: rows.getString(12), currencyScale: rows.getLong(13),
          grossMinor: rows.getString(14), discountMinor: rows.getString(15), paidMinor: rows.getString(16), bookMinor: rows.getString(17),
          includeInBudget: rows.getLong(18) === 1, includeInAssets: rows.getLong(19) === 1, balanceMode: rows.getString(20),
          occurredAtMs: rows.getLong(21), localDate: rows.getString(22), timezone: rows.getString(23), offsetMinutes: rows.getLong(24),
          note: rows.getString(25), toAccountId: rows.getString(29), toAccountName: rows.getString(30), transferPurpose: rows.getString(33), transferOutMinor: rows.getString(34),
          transferInMinor: rows.getString(35), transferFeeMinor: rows.getString(36), transferCouponMinor: rows.getString(37),
          feeInExpense: rows.getLong(38) === 1, feeInBudget: rows.getLong(39) === 1, accountKind: rows.getString(40), toAccountKind: rows.getString(41), canEdit: canEdit };
      } finally { rows.close(); }
      const path: string[] = [];
      const visited: Set<string> = new Set();
      let categoryId = detail.categoryId;
      while (categoryId.length > 0 && !visited.has(categoryId)) {
        visited.add(categoryId);
        const category = await db.querySql("SELECT name,COALESCE(parent_id,'') FROM categories WHERE id=? AND book_id=?", [categoryId, detail.bookId]);
        try {
          if (!category.goToFirstRow()) { break; }
          path.unshift(category.getString(0)); categoryId = category.getString(1);
        } finally { category.close(); }
      }
      detail.categoryPath = path.length > 0 ? path.join(' / ') : detail.categoryName;
      return detail;
    });
  }

  /** Deletes exactly one posted entry in this workspace. Movements remain as history. */
  async deleteEntry(id: string): Promise<void> {
    if (id.trim().length === 0) { throw new Error('INVALID_TRANSACTION_ID'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const rows = await db.querySql("SELECT revision,kind,group_id FROM transactions WHERE id=? AND book_id=? AND posting_state='posted' AND deleted_at_ms IS NULL",
        [id, DEFAULT_BOOK_ID]);
      let revision: number;
      try {
        if (!rows.goToFirstRow()) { throw new Error('TRANSACTION_NOT_FOUND'); }
        if (rows.getString(1) === 'transfer' && !rows.isColumnNull(2)) { throw new Error('GROUP_OPERATION_REQUIRED'); }
        revision = rows.getLong(0);
      } finally { rows.close(); }
      const now = Date.now();
      const changed = await db.update({ deleted_at_ms: now, updated_at_ms: now, revision: revision + 1 },
        new relationalStore.RdbPredicates('transactions').equalTo('id', id).equalTo('book_id', DEFAULT_BOOK_ID)
          .equalTo('posting_state', 'posted').isNull('deleted_at_ms').equalTo('revision', revision));
      if (changed !== 1) { throw new Error('TRANSACTION_CHANGED'); }
    });
  }

  async setMonthlyBudget(month: string, decimal: string): Promise<void> {
    const period = MonthlyBudget.period(month);
    const amount = MonthlyBudget.parse(decimal, this.currency);
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const rows = await db.querySql('SELECT id,currency_id FROM budgets WHERE book_id=? AND period_start_date=? AND period_end_date_exclusive=? AND deleted_at_ms IS NULL',
        [DEFAULT_BOOK_ID, period.start, period.endExclusive]);
      let id: string = '';
      try {
        if (rows.goToFirstRow()) {
          if (rows.getString(1) !== this.currency.id) { throw new Error('CURRENCY_MISMATCH'); }
          id = rows.getString(0);
        }
      } finally { rows.close(); }
      const now = Date.now();
      if (id.length > 0) {
        await db.executeSql('UPDATE budgets SET total_minor=?,updated_at_ms=?,revision=revision+1 WHERE id=?',
          [amount.toSafeMinorNumber(), now, id]);
      } else {
        await db.insert('budgets', { id: util.generateRandomUUID(), book_id: DEFAULT_BOOK_ID, currency_id: this.currency.id,
          period_start_date: period.start, period_end_date_exclusive: period.endExclusive,
          total_minor: amount.toSafeMinorNumber(), created_at_ms: now, updated_at_ms: now });
      }
    });
  }

  async snapshot(month: string): Promise<LedgerSnapshot> {
    const period = MonthlyBudget.period(month);
    return this.session.read(async (db: relationalStore.RdbStore): Promise<LedgerSnapshot> => {
      const book = await db.querySql('SELECT name,base_currency_id FROM books WHERE id=? AND deleted_at_ms IS NULL', [DEFAULT_BOOK_ID]);
      let bookName: string = '';
      try {
        if (!book.goToFirstRow() || book.getString(1) !== 'CNY') { throw new Error('DEFAULT_BOOK_UNAVAILABLE'); }
        bookName = book.getString(0);
      } finally { book.close(); }
      const categories: ExpenseCategory[] = [];
      const incomeCategories: ExpenseCategory[] = [];
      const categoryRows = await db.querySql("SELECT id,name,COALESCE(parent_id,''),COALESCE(icon_key,'other'),kind FROM categories WHERE book_id=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL ORDER BY sort_order,id", [DEFAULT_BOOK_ID]);
      try {
        while (categoryRows.goToNextRow()) {
          const target = categoryRows.getString(4) === 'income' ? incomeCategories : categories;
          target.push({ id: categoryRows.getString(0), name: categoryRows.getString(1),
            parentId: categoryRows.getString(2), iconKey: categoryRows.getString(3) });
        }
      } finally { categoryRows.close(); }
      const accounts: LedgerAccount[] = [];
      const accountRows = await db.querySql("SELECT id,name,currency_id,kind FROM accounts WHERE deleted_at_ms IS NULL AND archived_at_ms IS NULL ORDER BY sort_order,id");
      try {
        while (accountRows.goToNextRow()) {
          accounts.push({ id: accountRows.getString(0), name: accountRows.getString(1), currencyId: accountRows.getString(2), kind: accountRows.getString(3) });
        }
      } finally { accountRows.close(); }
      const entries: SavedLedgerEntry[] = [];
      let income: bigint = BigInt(0);
      let expense: bigint = BigInt(0);
      let budgetUsed: bigint = BigInt(0);
      const rows = await db.querySql("SELECT t.id,t.note,CASE WHEN t.kind='transfer' THEN CASE d.purpose WHEN 'credit_repayment' THEN '信用卡还款' WHEN 'loan_repayment' THEN '借款还款' WHEN 'topup' THEN '充值' WHEN 'withdrawal' THEN '提现' ELSE '转账' END ELSE c.name END,COALESCE(c.icon_key,'transfer'),COALESCE(a.name,'不使用账户'),t.occurred_local_date,t.occurred_at_ms,t.occurred_offset_minutes,t.kind,CAST(COALESCE(t.book_minor,t.paid_minor) AS TEXT),t.include_in_budget,CAST(t.gross_minor AS TEXT),CAST(t.discount_minor AS TEXT),COALESCE(ai.name,''),CAST(COALESCE(d.out_minor,t.paid_minor) AS TEXT),CAST(COALESCE(d.fee_minor,0) AS TEXT),CAST(COALESCE(d.coupon_minor,0) AS TEXT),COALESCE(d.purpose,'transfer'),COALESCE(d.fee_in_expense,1),COALESCE(d.fee_in_budget,1) FROM transactions t LEFT JOIN categories c ON c.id=t.category_id LEFT JOIN transfer_details d ON d.transaction_id=t.id LEFT JOIN account_movements m ON m.transaction_id=t.id AND m.leg<>'transfer_in' LEFT JOIN accounts a ON a.id=COALESCE(m.account_id,d.from_account_id) LEFT JOIN account_movements mi ON mi.transaction_id=t.id AND mi.leg='transfer_in' LEFT JOIN accounts ai ON ai.id=mi.account_id WHERE t.book_id=? AND t.posting_state='posted' AND t.deleted_at_ms IS NULL AND (t.import_batch_id IS NULL OR EXISTS(SELECT 1 FROM import_batches b WHERE b.id=t.import_batch_id AND b.status='committed')) AND (t.kind IN ('expense','income') OR (t.kind='transfer' AND t.currency_id='CNY' AND NOT EXISTS(SELECT 1 FROM account_movements x WHERE x.transaction_id=t.id AND x.currency_id<>'CNY'))) AND substr(t.occurred_local_date,1,7)=? ORDER BY t.occurred_at_ms DESC,t.created_at_ms DESC,t.id DESC", [DEFAULT_BOOK_ID, month]);
      try {
        while (rows.goToNextRow()) {
          const isIncome = rows.getString(8) === 'income';
          const isTransfer = rows.getString(8) === 'transfer';
          const minor = rows.getString(9);
          const feeExpense = isTransfer && rows.getLong(18) === 1 ? rows.getString(15) : '0';
          if (isTransfer) { expense += BigInt(feeExpense); if (rows.getLong(19) === 1) { budgetUsed += BigInt(feeExpense); } }
          if (isIncome) { income += BigInt(minor); } else if (!isTransfer) { expense += BigInt(minor); }
          if (!isIncome && !isTransfer && rows.getLong(10) === 1) { budgetUsed += BigInt(minor); }
          entries.push({ id: rows.getString(0), note: rows.getString(1), category: rows.getString(2),
            iconKey: rows.getString(3), account: rows.getString(4), date: rows.getString(5), occurredAtMs: rows.getLong(6),
            offsetMinutes: rows.getLong(7), income: isIncome, transfer: isTransfer, toAccount: rows.getString(13), minor: isTransfer ? rows.getString(14) : minor, expenseMinor: feeExpense,
            transferFeeMinor: rows.getString(15), transferCouponMinor: rows.getString(16),
            grossMinor: rows.getString(11), discountMinor: rows.getString(12) });
        }
      } finally { rows.close(); }
      let budgetTotal: string = DEFAULT_MONTHLY_BUDGET_MINOR;
      const budget = await db.querySql('SELECT CAST(total_minor AS TEXT),currency_id FROM budgets WHERE book_id=? AND period_start_date=? AND period_end_date_exclusive=? AND deleted_at_ms IS NULL',
        [DEFAULT_BOOK_ID, period.start, period.endExclusive]);
      try {
        if (budget.goToFirstRow()) {
          if (budget.getString(1) !== this.currency.id) { throw new Error('CURRENCY_MISMATCH'); }
          budgetTotal = budget.getString(0);
        }
      } finally { budget.close(); }
      return { bookId: DEFAULT_BOOK_ID, bookName: bookName, categories: categories, incomeCategories: incomeCategories, accounts: accounts,
        entries: entries, incomeMinor: income.toString(), expenseMinor: expense.toString(),
        budgetTotalMinor: budgetTotal, budgetUsedMinor: budgetUsed.toString() };
    });
  }
}
