import { RdbPrepaidRepository } from './RdbPrepaidRepository';
import { PrepaidProject, PrepaidDetail, PrepaidProjectCommand, PrepaidEventCommand, prepaidEntryContext } from '../../domain/model/Prepaid';
import { FxConversion } from '../../core/money/FxConversion';
import { parseFxEntry } from '../../domain/model/FxEntrySnapshot';
import { validateConversion } from '../../core/money/FxConversion';
import { RdbFxSnapshots } from './RdbFxSnapshots';
import { OfficialExchangeRates } from '../exchange/OfficialExchangeRates';
import { currencyUnit } from '../../core/money/Currencies';
import { ExchangeRate } from '../../core/money/ExchangeRate';
import { RecoveryCommand } from '../../domain/model/ExpenseRecovery';
import { RdbRecoveryRepository } from './RdbRecoveryRepository';
import { LedgerBackupPackage } from '../backup/LedgerBackupPackage';
import { LedgerResources } from '../backup/LedgerResources';
import { AccountCalibrationCommand, AdjustmentCursor, AdjustmentPage } from '../../domain/model/AccountCalibration';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';
import { TransferCommand } from '../../domain/model/TransferRecord';
import { TransferService } from '../../domain/services/TransferService';
import { RdbTransferRepository } from './RdbTransferRepository';
import { AccountCommand, AccountOverview } from '../../domain/model/AccountProfile';
import { RdbAccountRepository } from './RdbAccountRepository';
import { IncomeCommand } from '../../domain/model/IncomeRecord';
import { IncomeService } from '../../domain/services/IncomeService';
import { ExpenseCommand } from '../../domain/model/ExpenseRecord';
import { ExpenseCategory, LedgerAccount, LedgerSnapshot, SavedLedgerEntry, SpendingNatureChoice,
  TagChoice, LedgerUsageSummary } from '../../domain/model/LedgerSnapshot';
import { RecordExpense } from '../../domain/services/RecordExpense';
import { UpdateExpense } from '../../domain/services/UpdateExpense';
import { EntryDetail } from '../../domain/model/EntryDetail';
import { validateLedgerLocation } from '../../domain/model/LedgerLocation';
import { MonthlyBudget, DEFAULT_MONTHLY_BUDGET_MINOR } from '../../domain/model/MonthlyBudget';
import { LedgerBook, ValidatedLedgerBook } from '../../domain/model/LedgerBook';
import { BudgetNatureLine, SpendingNatureCommand, SpendingNatureProfile, ValidatedSpendingNature, isCustomNatureColor } from '../../domain/model/SpendingNature';
import { CategoryCommand, CategoryOrderItem, CategoryProfile, ValidatedCategory } from '../../domain/model/CategoryProfile';
import { TagCommand, TagProfile, ValidatedTag } from '../../domain/model/TagProfile';
import { LedgerDatabase, DEFAULT_BOOK_ID } from './LedgerDatabase';
import { RdbLedgerRepository } from './RdbLedgerRepository';
import { RdbSession } from './RdbSession';
import { LocalLedgerBackup } from './LocalLedgerBackup';
import { RdbStatisticsRepository } from './RdbStatisticsRepository';
import { LedgerStatistics, StatisticsBucketUnit, StatisticsEntry, StatisticsKind } from '../../domain/model/LedgerStatistics';
import { CsvPreviewRow } from '../exchange/LedgerCsvImport';
import { CsvColumnMapping } from '../exchange/LedgerCsvImport';
import { CsvImportMetadata, ImportBatchRowDetail, ImportBatchSummary, ImportProfile,
  ImportProfileOptions } from '../exchange/ImportProfile';
import { LedgerAttachment, LedgerAttachmentDraft } from '../../domain/model/LedgerAttachment';
import { RdbAttachmentLinks } from './RdbAttachmentLinks';
import { BackupFiles } from '../backup/BackupFiles';

interface StoredImportParseOptions {
  headerRow: number;
  delimiter: string;
}

interface StoredImportValueMapping {
  createMissingCategories: boolean;
  createMissingAccounts: boolean;
  feeInBudget: boolean;
}

/** Owns the store for the foreground ledger. All runtime SQL goes through its shared serial session. */
export class LedgerWorkspace {
  private static readonly ACTIVE_BOOK_KEY: string = 'active_book_id';
  private static readonly instances: Map<string, Promise<LedgerWorkspace>> = new Map();
  readonly currency: CurrencyUnit = new CurrencyUnit('CNY', 'CNY', 2);
  private readonly store: relationalStore.RdbStore;
  private readonly session: RdbSession;
  readonly backup: LedgerBackupPackage;
  readonly localBackup: LocalLedgerBackup;
  private readonly writer: RecordExpense;
  private readonly updater: UpdateExpense;
  private readonly income: IncomeService;
  private readonly transfer: TransferService;
  private readonly accountRepository: RdbAccountRepository;
  private readonly statisticsRepository: RdbStatisticsRepository;
  private activeBookId: string = DEFAULT_BOOK_ID;

  private constructor(context: common.Context, name: string, store: relationalStore.RdbStore) {
    OfficialExchangeRates.initialize(context);
    this.store = store;
    this.session = RdbSession.forStore(store);
    this.localBackup = new LocalLedgerBackup(context, name, this.session);
    this.backup = new LedgerBackupPackage(context, name, this.localBackup);
    this.accountRepository = new RdbAccountRepository(store);
    this.statisticsRepository = new RdbStatisticsRepository(store);
    this.transfer = new TransferService(new RdbTransferRepository(store));
    this.income = new IncomeService(new RdbLedgerRepository(store));
    this.writer = new RecordExpense(new RdbLedgerRepository(store));
    this.updater = new UpdateExpense(new RdbLedgerRepository(store));
  }

  static async open(context: common.Context, name: string = 'xiaoqiao.db'): Promise<LedgerWorkspace> {
    const existing = LedgerWorkspace.instances.get(name);
    if (existing !== undefined) { return existing; }
    const pending = LedgerDatabase.open(context, name).then(async (store: relationalStore.RdbStore) => {
      const workspace = new LedgerWorkspace(context, name, store);
      await workspace.initializeActiveBook();
      return workspace;
    });
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

  async saveExpense(command: ExpenseCommand): Promise<void> {
    await this.validateAttachmentFiles(command.attachments);
    await this.writer.execute(command);
  }

  bookId(): string { return this.activeBookId; }

  private async activeBookFromMeta(db: relationalStore.RdbStore): Promise<string> {
    const selected = await db.querySql("SELECT b.id FROM db_meta m JOIN books b ON b.id=m.value WHERE m.key=? AND b.deleted_at_ms IS NULL AND b.archived_at_ms IS NULL",
      [LedgerWorkspace.ACTIVE_BOOK_KEY]);
    try {
      if (selected.goToFirstRow()) { return selected.getString(0); }
    } finally { selected.close(); }
    const fallback = await db.querySql('SELECT id FROM books WHERE deleted_at_ms IS NULL AND archived_at_ms IS NULL ORDER BY sort_order,created_at_ms,id LIMIT 1');
    try {
      if (!fallback.goToFirstRow()) { throw new Error('LEDGER_BOOK_UNAVAILABLE'); }
      return fallback.getString(0);
    } finally { fallback.close(); }
  }

  private async saveActiveBook(db: relationalStore.RdbStore, id: string): Promise<void> {
    await db.executeSql('INSERT OR REPLACE INTO db_meta(key,value) VALUES(?,?)', [LedgerWorkspace.ACTIVE_BOOK_KEY, id]);
  }

  private async initializeActiveBook(): Promise<void> {
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const id = await this.activeBookFromMeta(db);
      await this.saveActiveBook(db, id);
      this.activeBookId = id;
    });
  }

  async books(): Promise<LedgerBook[]> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<LedgerBook[]> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const values: LedgerBook[] = [];
      const rows = await db.querySql('SELECT id,name,revision,archived_at_ms FROM books WHERE deleted_at_ms IS NULL ORDER BY archived_at_ms IS NOT NULL,sort_order,created_at_ms,id');
      try {
        while (rows.goToNextRow()) {
          values.push({ id: rows.getString(0), name: rows.getString(1), revision: rows.getLong(2), archived: !rows.isColumnNull(3) });
        }
      } finally { rows.close(); }
      return values;
    });
  }

  async selectBook(id: string): Promise<void> {
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const rows = await db.querySql('SELECT id FROM books WHERE id=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL', [id]);
      try {
        if (!rows.goToFirstRow()) { throw new Error('LEDGER_BOOK_UNAVAILABLE'); }
      } finally { rows.close(); }
      await this.saveActiveBook(db, id);
      this.activeBookId = id;
    });
  }

  async createBook(name: string, id: string): Promise<void> {
    const draft = new ValidatedLedgerBook({ id: id, name: name }).draft;
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const duplicate = await db.querySql('SELECT id FROM books WHERE deleted_at_ms IS NULL AND name=? LIMIT 1', [draft.name]);
      try { if (duplicate.goToFirstRow()) { throw new Error('LEDGER_BOOK_NAME_EXISTS'); } } finally { duplicate.close(); }
      const order = await db.querySql('SELECT COALESCE(MAX(sort_order),-1)+1 FROM books');
      let sortOrder: number = 0;
      try { if (order.goToFirstRow()) { sortOrder = order.getLong(0); } } finally { order.close(); }
      const now = Date.now();
      await db.insert('books', { id: draft.id, name: draft.name, base_currency_id: 'CNY', timezone: 'Asia/Shanghai',
        sort_order: sortOrder, created_at_ms: now, updated_at_ms: now });
      const source = await db.querySql('SELECT id FROM books WHERE id=? AND deleted_at_ms IS NULL', [DEFAULT_BOOK_ID]);
      let sourceBook: string;
      try { sourceBook = source.goToFirstRow() ? source.getString(0) : this.activeBookId; } finally { source.close(); }
      const templates = await db.querySql("SELECT id,parent_id FROM categories WHERE book_id=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL", [sourceBook]);
      const ids: Map<string, string> = new Map<string, string>();
      try {
        while (templates.goToNextRow()) { ids.set(templates.getString(0), util.generateRandomUUID()); }
      } finally { templates.close(); }
      const rows = await db.querySql("SELECT id,kind,parent_id,name,name_key,icon_key,sort_order FROM categories WHERE book_id=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL ORDER BY kind DESC,sort_order,id",
        [sourceBook]);
      try {
        while (rows.goToNextRow()) {
          const parent = rows.isColumnNull(2) ? undefined : ids.get(rows.getString(2));
          await db.insert('categories', { id: ids.get(rows.getString(0)), book_id: draft.id, kind: rows.getString(1), parent_id: parent,
            name: rows.getString(3), name_key: rows.getString(4), icon_key: rows.getString(5), sort_order: rows.getLong(6),
            created_at_ms: now, updated_at_ms: now });
        }
      } finally { rows.close(); }
      await this.saveActiveBook(db, draft.id);
      this.activeBookId = draft.id;
    });
  }

  async updateBook(id: string, name: string, revision: number): Promise<void> {
    const draft = new ValidatedLedgerBook({ id: id, name: name }).draft;
    if (!Number.isSafeInteger(revision) || revision < 1 || revision >= Number.MAX_SAFE_INTEGER) { throw new Error('INVALID_EXPECTED_REVISION'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const duplicate = await db.querySql('SELECT id FROM books WHERE id<>? AND deleted_at_ms IS NULL AND name=? LIMIT 1', [id, draft.name]);
      try { if (duplicate.goToFirstRow()) { throw new Error('LEDGER_BOOK_NAME_EXISTS'); } } finally { duplicate.close(); }
      const changed = await db.update({ name: draft.name, updated_at_ms: Date.now(), revision: revision + 1 },
        new relationalStore.RdbPredicates('books').equalTo('id', id).equalTo('revision', revision).isNull('deleted_at_ms'));
      if (changed !== 1) { throw new Error('LEDGER_BOOK_CHANGED'); }
    });
  }

  async archiveBook(id: string, revision: number, archived: boolean): Promise<void> {
    if (!Number.isSafeInteger(revision) || revision < 1 || revision >= Number.MAX_SAFE_INTEGER) { throw new Error('INVALID_EXPECTED_REVISION'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      let fallback: string = '';
      let wasActive: boolean = false;
      if (archived) {
        const other = await db.querySql('SELECT id FROM books WHERE id<>? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL LIMIT 1', [id]);
        try {
          if (!other.goToFirstRow()) { throw new Error('LAST_ACTIVE_LEDGER_BOOK'); }
          fallback = other.getString(0);
        } finally { other.close(); }
        const selected = await db.querySql('SELECT value FROM db_meta WHERE key=?', [LedgerWorkspace.ACTIVE_BOOK_KEY]);
        try { wasActive = selected.goToFirstRow() && selected.getString(0) === id; } finally { selected.close(); }
      }
      const changed = await db.update({ archived_at_ms: archived ? Date.now() : null, updated_at_ms: Date.now(), revision: revision + 1 },
        new relationalStore.RdbPredicates('books').equalTo('id', id).equalTo('revision', revision).isNull('deleted_at_ms'));
      if (changed !== 1) { throw new Error('LEDGER_BOOK_CHANGED'); }
      if (archived && wasActive) {
        await this.saveActiveBook(db, fallback);
        this.activeBookId = fallback;
      }
    });
  }

  async spendingNatures(): Promise<SpendingNatureProfile[]> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<SpendingNatureProfile[]> => {
      const values: SpendingNatureProfile[] = [];
      const rows = await db.querySql('SELECT id,name,COALESCE(custom_color,color_token),built_in,sort_order,revision,archived_at_ms FROM spending_natures WHERE deleted_at_ms IS NULL ORDER BY archived_at_ms IS NOT NULL,sort_order,created_at_ms,id');
      try {
        while (rows.goToNextRow()) {
          values.push({ id: rows.getString(0), name: rows.getString(1), colorKey: rows.getString(2), builtIn: rows.getLong(3) === 1,
            sortOrder: rows.getLong(4), revision: rows.getLong(5), archived: !rows.isColumnNull(6) });
        }
      } finally { rows.close(); }
      return values;
    });
  }

  async createSpendingNature(command: SpendingNatureCommand): Promise<void> {
    const draft = new ValidatedSpendingNature(command).command;
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const duplicate = await db.querySql('SELECT id FROM spending_natures WHERE deleted_at_ms IS NULL AND name_key=? LIMIT 1', [draft.name]);
      try { if (duplicate.goToFirstRow()) { throw new Error('SPENDING_NATURE_NAME_EXISTS'); } } finally { duplicate.close(); }
      const order = await db.querySql('SELECT COALESCE(MAX(sort_order),-1)+1 FROM spending_natures');
      let sortOrder: number = 0;
      try { if (order.goToFirstRow()) { sortOrder = order.getLong(0); } } finally { order.close(); }
      const now = Date.now();
      await db.insert('spending_natures', { id: draft.id, name: draft.name, name_key: draft.name, color_token: isCustomNatureColor(draft.colorKey) ? 'neutral' : draft.colorKey,
        custom_color: isCustomNatureColor(draft.colorKey) ? draft.colorKey : null, built_in: 0, sort_order: sortOrder, created_at_ms: now, updated_at_ms: now });
    });
  }

  async updateSpendingNature(command: SpendingNatureCommand, revision: number): Promise<void> {
    const draft = new ValidatedSpendingNature(command).command;
    if (!Number.isSafeInteger(revision) || revision < 1 || revision >= Number.MAX_SAFE_INTEGER) { throw new Error('INVALID_EXPECTED_REVISION'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const duplicate = await db.querySql('SELECT id FROM spending_natures WHERE id<>? AND deleted_at_ms IS NULL AND name_key=? LIMIT 1',
        [draft.id, draft.name]);
      try { if (duplicate.goToFirstRow()) { throw new Error('SPENDING_NATURE_NAME_EXISTS'); } } finally { duplicate.close(); }
      const changed = await db.update({ name: draft.name, name_key: draft.name, color_token: isCustomNatureColor(draft.colorKey) ? 'neutral' : draft.colorKey,
        custom_color: isCustomNatureColor(draft.colorKey) ? draft.colorKey : null, updated_at_ms: Date.now(), revision: revision + 1 }, new relationalStore.RdbPredicates('spending_natures')
        .equalTo('id', draft.id).equalTo('revision', revision).isNull('deleted_at_ms'));
      if (changed !== 1) { throw new Error('SPENDING_NATURE_CHANGED'); }
    });
  }

  async archiveSpendingNature(id: string, revision: number, archived: boolean): Promise<void> {
    if (!Number.isSafeInteger(revision) || revision < 1 || revision >= Number.MAX_SAFE_INTEGER) { throw new Error('INVALID_EXPECTED_REVISION'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      if (archived) {
        const other = await db.querySql('SELECT id FROM spending_natures WHERE id<>? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL LIMIT 1', [id]);
        try { if (!other.goToFirstRow()) { throw new Error('LAST_ACTIVE_SPENDING_NATURE'); } } finally { other.close(); }
      }
      const changed = await db.update({ archived_at_ms: archived ? Date.now() : null, updated_at_ms: Date.now(), revision: revision + 1 },
        new relationalStore.RdbPredicates('spending_natures').equalTo('id', id).equalTo('revision', revision).isNull('deleted_at_ms'));
      if (changed !== 1) { throw new Error('SPENDING_NATURE_CHANGED'); }
    });
  }

  async tags(): Promise<TagProfile[]> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<TagProfile[]> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const values: TagProfile[] = [];
      const rows = await db.querySql("SELECT id,name,COALESCE(color_token,'neutral'),sort_order,revision FROM tags " +
        "WHERE book_id=? AND deleted_at_ms IS NULL ORDER BY sort_order,created_at_ms,id", [this.activeBookId]);
      try {
        while (rows.goToNextRow()) {
          values.push({ id: rows.getString(0), name: rows.getString(1), colorKey: rows.getString(2),
            sortOrder: rows.getLong(3), revision: rows.getLong(4) });
        }
      } finally { rows.close(); }
      return values;
    });
  }

  async createTag(command: TagCommand): Promise<void> {
    const draft = new ValidatedTag(command).command;
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const duplicate = await db.querySql('SELECT id FROM tags WHERE book_id=? AND name_key=? AND deleted_at_ms IS NULL',
        [this.activeBookId, draft.name]);
      try { if (duplicate.goToFirstRow()) { throw new Error('TAG_NAME_EXISTS'); } } finally { duplicate.close(); }
      const order = await db.querySql('SELECT COALESCE(MAX(sort_order),-1)+1 FROM tags WHERE book_id=?',
        [this.activeBookId]);
      let sortOrder: number = 0;
      try { if (order.goToFirstRow()) { sortOrder = order.getLong(0); } } finally { order.close(); }
      const now = Date.now();
      await db.insert('tags', { id: draft.id, book_id: this.activeBookId, name: draft.name, name_key: draft.name,
        color_token: draft.colorKey, sort_order: sortOrder, created_at_ms: now, updated_at_ms: now });
    });
  }

  async updateTag(command: TagCommand, revision: number): Promise<void> {
    const draft = new ValidatedTag(command).command;
    if (!Number.isSafeInteger(revision) || revision < 1 || revision >= Number.MAX_SAFE_INTEGER) {
      throw new Error('INVALID_EXPECTED_REVISION');
    }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const duplicate = await db.querySql('SELECT id FROM tags WHERE book_id=? AND id<>? AND name_key=? AND deleted_at_ms IS NULL',
        [this.activeBookId, draft.id, draft.name]);
      try { if (duplicate.goToFirstRow()) { throw new Error('TAG_NAME_EXISTS'); } } finally { duplicate.close(); }
      const changed = await db.update({ name: draft.name, name_key: draft.name, color_token: draft.colorKey,
        updated_at_ms: Date.now(), revision: revision + 1 }, new relationalStore.RdbPredicates('tags')
        .equalTo('id', draft.id).equalTo('book_id', this.activeBookId).equalTo('revision', revision)
        .isNull('deleted_at_ms'));
      if (changed !== 1) { throw new Error('TAG_CHANGED'); }
    });
  }

  async deleteTag(id: string, revision: number): Promise<void> {
    if (!Number.isSafeInteger(revision) || revision < 1 || revision >= Number.MAX_SAFE_INTEGER) {
      throw new Error('INVALID_EXPECTED_REVISION');
    }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const changed = await db.update({ deleted_at_ms: Date.now(), updated_at_ms: Date.now(), revision: revision + 1 },
        new relationalStore.RdbPredicates('tags').equalTo('id', id).equalTo('book_id', this.activeBookId)
          .equalTo('revision', revision).isNull('deleted_at_ms'));
      if (changed !== 1) { throw new Error('TAG_CHANGED'); }
    });
  }

  async importCsvBatch(fileName: string, fileSha256: string, rows: CsvPreviewRow[],
    delimiter: string, applyBalance: boolean = false,
    onProgress: (completed: number, total: number) => void = () => {},
    metadata: CsvImportMetadata = { headerRow: 1, sheetName: '', sourceKind: '', encoding: 'utf-8',
      profileSnapshot: '{"source":"csv","version":1}', feeInBudget: false }): Promise<number> {
    if (fileName.trim().length === 0 || fileSha256.trim().length === 0 || rows.length === 0) {
      throw new Error('INVALID_CSV_BATCH');
    }
    const validRows = rows.filter((row: CsvPreviewRow) => row.valid && row.selected);
    if (validRows.length === 0) { throw new Error('CSV_NO_VALID_ROWS'); }
    const provider = metadata.sourceKind.trim().length > 0 ? metadata.sourceKind :
      /微信|wechat|weixin/i.test(fileName) ? 'wechat' :
      /支付宝|alipay/i.test(fileName) ? 'alipay' : /\.xlsx$/i.test(fileName) ? 'xlsx' : 'csv';
    return this.session.write(async (db: relationalStore.RdbStore): Promise<number> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const batchId = util.generateRandomUUID();
      const now = Date.now();
      const createdCategories: Map<string, string> = new Map();
      const createdAccounts: Map<string, string> = new Map();
      const insertedAccountTypes: Map<string, string> = new Map();
      const createdMerchants: Map<string, string> = new Map();
      await db.insert('import_batches', { id: batchId, book_id: this.activeBookId, file_sha256: fileSha256,
        file_name: fileName, sheet_name: metadata.sheetName, header_row: Math.max(1, metadata.headerRow),
        encoding: metadata.encoding, delimiter: delimiter,
        profile_snapshot_json: metadata.profileSnapshot ||
          JSON.stringify({ source: provider, version: 1, headerRow: metadata.headerRow, delimiter: delimiter }),
        balance_mode: applyBalance ? 'apply' : 'preserve',
        status: 'committing',
        total_count: rows.length, selected_count: validRows.length, skipped_count: rows.length - validRows.length,
        confirmed_at_ms: now, created_at_ms: now });
      onProgress(0, validRows.length);
      const importRowIds: Map<number, string> = new Map();
      for (const row of rows) {
        const rowId = util.generateRandomUUID();
        importRowIds.set(row.rowNumber, rowId);
        await db.insert('import_rows', { id: rowId, batch_id: batchId, sheet_name: metadata.sheetName,
          row_number: row.rowNumber,
          raw_json: JSON.stringify(row.raw), normalized_json: JSON.stringify(row),
          validation_status: !row.valid ? 'invalid' : row.duplicate ? 'duplicate' : 'valid',
          issue_codes_json: JSON.stringify(row.issues),
          duplicate_candidate_ids_json: row.duplicate && row.sourceId.length > 0 ?
            JSON.stringify([row.sourceId]) : '[]',
          selected: row.selected ? 1 : 0 });
      }
      const importedExpenses: Map<string, string> = new Map();
      const orderedRows = validRows.filter((row: CsvPreviewRow) => row.type !== 'refund' && row.type !== 'reimbursement')
        .concat(validRows.filter((row: CsvPreviewRow) => row.type === 'refund' || row.type === 'reimbursement'));
      let processed = 0;
      for (const row of orderedRows) {
        const fx = row.fx === undefined ? undefined : parseFxEntry(JSON.stringify(row.fx));
        const code = fx?.currencyId || 'CNY';
        const accountCode = row.type === 'transfer' ? code : fx?.accountCurrencyId || code;
        const incomingCode = fx?.receivedCurrencyId || code;
        let categoryId = row.categoryId;
        let accountId = row.accountId;
        if (accountId.length === 0 && row.createAccount) {
          const key = accountCode + ":" + row.accountName.trim().toLowerCase();
          accountId = createdAccounts.get(key) || '';
          if (accountId.length === 0) {
            accountId = await this.ensureCsvAccount(db, row.accountName, accountCode, insertedAccountTypes);
            createdAccounts.set(key, accountId);
          }
        }
        if (row.type === 'refund' || row.type === 'reimbursement') {
          const sourceId = row.originalEntryId || '';
          let parentId = importedExpenses.get(sourceId) || '';
          if (parentId === 'AMBIGUOUS') { throw new Error('RECOVERY_SOURCE_AMBIGUOUS'); }
          if (parentId.length === 0) {
            const exact = await db.querySql("SELECT id FROM v_posted_transactions WHERE book_id=? AND kind='expense' AND id=?", [this.activeBookId, sourceId]);
            try { if (exact.goToFirstRow()) { parentId = exact.getString(0); } } finally { exact.close(); }
          }
          if (parentId.length === 0 && sourceId.length > 0) {
            const matches = await db.querySql("SELECT id FROM v_posted_transactions WHERE book_id=? AND kind='expense' AND source_record_id=? LIMIT 2", [this.activeBookId, sourceId]);
            try {
              if (matches.rowCount !== 1 || !matches.goToFirstRow()) { throw new Error('RECOVERY_SOURCE_INVALID'); }
              parentId = matches.getString(0);
            } finally { matches.close(); }
          }
          const date = new Date(row.date + 'T' + (row.timeKnown ? row.time + ':00' : '12:00:00'));
          await RdbRecoveryRepository.save(db, { id: util.generateRandomUUID(), transactionId: parentId, bookId: this.activeBookId,
            kind: row.type === 'refund' ? 'refund' : 'reimbursement', currencyId: code, amountMinor: Money.parse(row.amount, currencyUnit(code)).minor.toString(), accountMinor: fx?.accountMinor, accountFx: fx?.accountFx,
            accountId: accountId, bookMinor: fx?.bookMinor, occurredAtMs: date.getTime(), localDate: row.date,
            offsetMinutes: -date.getTimezoneOffset(), note: row.note }, batchId, row.sourceId || String(row.rowNumber), applyBalance,
            importRowIds.get(row.rowNumber) || '');
          processed++; onProgress(processed, validRows.length);
          continue;
        }
        let toAccountId = row.toAccountId || '';
        if (toAccountId.length === 0 && row.createToAccount === true && (row.toAccountName || '').trim().length > 0) {
          const key = incomingCode + ':' + (row.toAccountName || '').trim().toLowerCase();
          toAccountId = createdAccounts.get(key) || '';
          if (toAccountId.length === 0) {
            toAccountId = await this.ensureCsvAccount(db, row.toAccountName || '', incomingCode, insertedAccountTypes);
            createdAccounts.set(key, toAccountId);
          }
        }
        await this.validateCsvAccount(db, accountId, false, row.type === 'transfer', accountCode, insertedAccountTypes);
        await this.validateCsvAccount(db, toAccountId,
          row.type === 'transfer' &&
            (row.transferPurpose === 'credit_repayment' || row.transferPurpose === 'loan_repayment'),
          row.type === 'transfer', incomingCode, insertedAccountTypes);
        if (row.type === 'transfer') {
          if (accountId.length === 0 || toAccountId.length === 0 || accountId === toAccountId) {
            throw new Error('CSV_TRANSFER_ACCOUNT_INVALID');
          }
        } else {
          let createdCategory = false;
          if (categoryId.length === 0 && row.createCategory) {
            const key = row.type + ':' + row.categoryName.trim().toLowerCase().replace(/\s+/g, '');
            categoryId = createdCategories.get(key) || '';
            if (categoryId.length === 0) {
              categoryId = await this.ensureCsvCategory(db, this.activeBookId, row.type, row.categoryName);
              createdCategories.set(key, categoryId);
            }
            createdCategory = true;
          }
          if (categoryId.length === 0) { throw new Error('CSV_CATEGORY_INVALID'); }
          if (!createdCategory) {
            const category = await db.querySql('SELECT kind FROM categories WHERE id=? AND book_id=? AND deleted_at_ms IS NULL',
              [categoryId, this.activeBookId]);
            try {
              const actualKind = category.goToFirstRow() ? category.getString(0) : 'missing';
              if (actualKind !== row.type) { throw new Error('CSV_CATEGORY_INVALID'); }
            } finally { category.close(); }
          }
        }
        const occurred = new Date(row.date + 'T' + (row.timeKnown ? (row.time + ':00') : '12:00:00'));
        const transactionId = util.generateRandomUUID();
        const amount = Money.parse(row.amount, currencyUnit(code)).toSafeMinorNumber();
        let merchantId: string | null = null;
        if (row.merchant.trim().length > 0) {
          const merchantKey = row.merchant.trim().toLowerCase().replace(/\s+/g, '');
          merchantId = createdMerchants.get(merchantKey) || '';
          if (merchantId.length === 0) {
            merchantId = await this.ensureCsvMerchant(db, row.merchant, row.address);
            createdMerchants.set(merchantKey, merchantId);
          }
        }
        const location = validateLedgerLocation(row.location);
        await db.insert('transactions', { id: transactionId, book_id: this.activeBookId, kind: row.type,
          category_id: row.type === 'transfer' ? null : categoryId,
          currency_id: code, gross_minor: fx === undefined ? amount : Number(fx.grossMinor), discount_minor: fx === undefined ? 0 : Number(fx.discountMinor),
          paid_minor: amount, book_currency_id: 'CNY', book_minor: fx === undefined ? amount : Number(fx.bookMinor), include_in_budget: row.type === 'expense' && row.includeInBudget ? 1 : 0,
          spending_nature_id: row.type === 'expense' ? row.spendingNatureId || null : null,
          include_in_assets: accountId.length > 0 ? 1 : 0, balance_mode: applyBalance ? 'apply' : 'preserve',
          reimbursement_status: row.type === 'expense' && row.reimbursementPending ? 'pending' : 'none',
          merchant_id: merchantId,
          merchant_name_snapshot: row.merchant.length > 0 ? row.merchant : null,
          address_text: row.address.length > 0 ? row.address : null, note: row.note,
          latitude_e6: location === undefined || location === null ? null : location.latitudeE6,
          longitude_e6: location === undefined || location === null ? null : location.longitudeE6,
          import_batch_id: batchId, import_row_id: importRowIds.get(row.rowNumber),
          source_provider: provider, source_namespace: fileSha256, source_record_id: row.sourceId || String(row.rowNumber),
          duplicate_override: row.duplicate ? 1 : 0,
          occurred_at_ms: occurred.getTime(), occurred_local_date: row.date,
          occurred_timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
          occurred_offset_minutes: -occurred.getTimezoneOffset(), created_at_ms: now, updated_at_ms: now });
        if (row.type === 'transfer') {
          const fee = Money.parse(row.transferFee || '0', currencyUnit(code));
          const coupon = Money.parse(row.transferCoupon || '0', currencyUnit(code));
          const outgoing = Money.fromMinorText(String(amount), currencyUnit(code)).add(fee).subtract(coupon);
          if (fx !== undefined) {
            const bookFee = Money.fromMinorText(fx.bookFeeMinor || '0', this.currency);
            if (fee.minor > BigInt(0)) { validateConversion(fee, bookFee, fx.bookFx); }
            else if (bookFee.minor !== BigInt(0)) { throw new Error('FX_AMOUNT_MISMATCH'); }
          }
          await db.insert('fx_transfer_details', { transaction_id: transactionId,
            to_currency_id: incomingCode, principal_minor: amount, book_fee_minor: fx === undefined ? fee.toSafeMinorNumber() : Number(fx.bookFeeMinor || '0'),
            purpose: row.transferPurpose || 'transfer', currency_id: code,
            from_account_id: accountId, to_account_id: toAccountId,
            out_minor: outgoing.toSafeMinorNumber(), in_minor: fx === undefined ? amount : Number(fx.receivedMinor || fx.paidMinor),
            fee_minor: fee.toSafeMinorNumber(), coupon_minor: coupon.toSafeMinorNumber(),
            fee_in_expense: 1, fee_in_budget: row.feeInBudget === true || metadata.feeInBudget ? 1 : 0 });
          if (outgoing.minor > BigInt(0)) {
            await db.insert('account_movements', { id: util.generateRandomUUID(), transaction_id: transactionId,
              account_id: accountId, currency_id: code, leg: 'transfer_out',
              delta_minor: -outgoing.toSafeMinorNumber(), occurred_at_ms: occurred.getTime() });
          }
          await db.insert('account_movements', { id: util.generateRandomUUID(), transaction_id: transactionId,
            account_id: toAccountId, currency_id: incomingCode, leg: 'transfer_in',
            delta_minor: fx === undefined ? amount : Number(fx.receivedMinor || fx.paidMinor), occurred_at_ms: occurred.getTime() });
        } else if (accountId.length > 0) {
          await db.insert('account_movements', { id: util.generateRandomUUID(), transaction_id: transactionId,
            account_id: accountId, currency_id: accountCode, leg: row.type,
            delta_minor: (row.type === 'income' ? 1 : -1) * (fx === undefined ? amount : Number(fx.accountMinor)), occurred_at_ms: occurred.getTime() });
        }
        if (fx !== undefined) {
          const original = Money.fromMinorText(fx.paidMinor, currencyUnit(code));
          await RdbFxSnapshots.insert(db, transactionId, original, Money.fromMinorText(fx.bookMinor, this.currency), fx.bookFx);
          const movement = await db.querySql('SELECT id,currency_id,CAST(abs(delta_minor) AS TEXT) FROM account_movements WHERE transaction_id=? AND leg=?', [transactionId, row.type === 'transfer' ? 'transfer_in' : row.type]);
          try { if (movement.goToFirstRow()) { await RdbFxSnapshots.insert(db, transactionId, original, Money.fromMinorText(movement.getString(2), currencyUnit(movement.getString(1))), fx.accountFx, movement.getString(0)); } } finally { movement.close(); }
        }
        await db.executeSql("UPDATE transactions SET posting_state='posted' WHERE id=?", [transactionId]);
        if (row.type === 'expense' && row.sourceId.length > 0) {
          importedExpenses.set(row.sourceId, importedExpenses.has(row.sourceId) ? 'AMBIGUOUS' : transactionId);
        }
        processed++;
        onProgress(processed, validRows.length);
      }
      const committed = await db.update({ status: 'committed', committed_at_ms: Date.now() },
        new relationalStore.RdbPredicates('import_batches').equalTo('id', batchId).equalTo('status', 'committing'));
      if (committed !== 1) { throw new Error('CSV_BATCH_COMMIT_FAILED'); }
      return validRows.length;
    });
  }

  async existingImportIds(): Promise<string[]> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<string[]> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const values: string[] = [];
      const rows = await db.querySql("SELECT id,COALESCE(source_record_id,''),COALESCE(import_row_id,'') " +
        'FROM transactions WHERE book_id=?', [this.activeBookId]);
      try {
        while (rows.goToNextRow()) {
          values.push(rows.getString(0));
          if (rows.getString(1).length > 0) { values.push(rows.getString(1)); }
          if (rows.getString(2).length > 0) { values.push(rows.getString(2)); }
        }
      } finally { rows.close(); }
      const recovered = await db.querySql("SELECT id,COALESCE(source_record_id,'') FROM expense_recoveries WHERE book_id=?", [this.activeBookId]);
      try { while (recovered.goToNextRow()) { values.push(recovered.getString(0)); if (recovered.getString(1)) { values.push(recovered.getString(1)); } } } finally { recovered.close(); }
      return values;
    });
  }

  async saveImageAttachment(uri: string, qualityKey: string = 'standard'): Promise<LedgerAttachmentDraft> {
    const stored = await this.backup.resources.putImage(uri, qualityKey);
    return { relativePath: stored.relativePath, sha256: stored.sha256, bytes: stored.bytes,
      mimeType: stored.mimeType };
  }

  async discardUnpersistedImage(attachment: LedgerAttachmentDraft): Promise<void> {
    const referenced = await this.session.read(async (db: relationalStore.RdbStore): Promise<boolean> => {
      const rows = await db.querySql("SELECT COUNT(*) FROM attachments WHERE content_sha256=? AND state='ready' AND deleted_at_ms IS NULL",
        [attachment.sha256]);
      try { return rows.goToFirstRow() && rows.getLong(0) > 0; } finally { rows.close(); }
    });
    if (!referenced) { await this.backup.resources.remove('images', attachment.relativePath); }
  }

  private async validateAttachmentFiles(attachments: LedgerAttachmentDraft[] | undefined): Promise<void> {
    for (const attachment of attachments || []) {
      const path = this.backup.resources.root + '/' + attachment.relativePath;
      await LedgerResources.validate(attachment.relativePath, path);
      const info = await BackupFiles.info(path, attachment.relativePath);
      if (info.sha256 !== attachment.sha256 || info.bytes !== attachment.bytes) {
        throw new Error('ATTACHMENT_RESOURCE_MISMATCH');
      }
    }
  }

  async importProfiles(): Promise<ImportProfile[]> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<ImportProfile[]> => {
      const profiles: ImportProfile[] = [];
      const rows = await db.querySql('SELECT id,name,source_kind,profile_version,parse_options_json,' +
        'column_mapping_json,value_mapping_json,updated_at_ms FROM import_profiles ORDER BY updated_at_ms DESC,id');
      try {
        while (rows.goToNextRow()) {
          const parse = JSON.parse(rows.getString(4)) as StoredImportParseOptions;
          const rawMapping = JSON.parse(rows.getString(5)) as CsvColumnMapping;
          const values = JSON.parse(rows.getString(6)) as StoredImportValueMapping;
          const options: ImportProfileOptions = {
            headerRow: Number.isInteger(parse.headerRow) ? parse.headerRow : 1,
            delimiter: parse.delimiter || ',',
            createMissingCategories: values.createMissingCategories === true,
            createMissingAccounts: values.createMissingAccounts === true,
            feeInBudget: values.feeInBudget === true
          };
          profiles.push({ id: rows.getString(0), name: rows.getString(1), sourceKind: rows.getString(2),
            profileVersion: rows.getLong(3), mapping: this.normalizeImportMapping(rawMapping),
            options: options, updatedAtMs: rows.getLong(7) });
        }
      } finally { rows.close(); }
      return profiles;
    });
  }

  async saveImportProfile(id: string, name: string, sourceKind: string, mapping: CsvColumnMapping,
    options: ImportProfileOptions): Promise<string> {
    const profileName = name.trim();
    if (profileName.length === 0) { throw new Error('IMPORT_PROFILE_NAME_REQUIRED'); }
    return this.session.write(async (db: relationalStore.RdbStore): Promise<string> => {
      const now = Date.now();
      const profileId = id.trim().length > 0 ? id : util.generateRandomUUID();
      const parse: StoredImportParseOptions = { headerRow: Math.max(1, options.headerRow),
        delimiter: options.delimiter || ',' };
      const values: StoredImportValueMapping = {
        createMissingCategories: options.createMissingCategories,
        createMissingAccounts: options.createMissingAccounts,
        feeInBudget: options.feeInBudget
      };
      const changed = await db.update({ name: profileName, source_kind: sourceKind,
        profile_version: 1, parse_options_json: JSON.stringify(parse),
        column_mapping_json: JSON.stringify(this.normalizeImportMapping(mapping)),
        value_mapping_json: JSON.stringify(values), updated_at_ms: now },
        new relationalStore.RdbPredicates('import_profiles').equalTo('id', profileId));
      if (changed === 0) {
        await db.insert('import_profiles', { id: profileId, name: profileName, source_kind: sourceKind,
          profile_version: 1, parse_options_json: JSON.stringify(parse),
          column_mapping_json: JSON.stringify(this.normalizeImportMapping(mapping)),
          value_mapping_json: JSON.stringify(values), created_at_ms: now, updated_at_ms: now });
      }
      return profileId;
    });
  }

  async deleteImportProfile(id: string): Promise<void> {
    if (id.trim().length === 0) { return; }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      await db.delete(new relationalStore.RdbPredicates('import_profiles').equalTo('id', id));
    });
  }

  async recentImportBatches(limit: number = 20): Promise<ImportBatchSummary[]> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<ImportBatchSummary[]> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const batchLimit = Math.max(1, Math.min(100, Math.floor(limit)));
      const batches: ImportBatchSummary[] = [];
      const rows = await db.querySql('SELECT b.id,b.file_name,COALESCE(b.sheet_name,\'\'),b.status,b.balance_mode,' +
        'b.total_count,b.selected_count,b.skipped_count,COALESCE(b.committed_at_ms,0),' +
        "(SELECT COUNT(*) FROM import_rows r WHERE r.batch_id=b.id AND r.validation_status IN ('invalid','duplicate')) " +
        'FROM import_batches b WHERE b.book_id=? ORDER BY b.created_at_ms DESC,b.id DESC LIMIT ' + batchLimit,
        [this.activeBookId]);
      try {
        while (rows.goToNextRow()) {
          batches.push({ id: rows.getString(0), fileName: rows.getString(1), sheetName: rows.getString(2),
            status: rows.getString(3), balanceMode: rows.getString(4), totalCount: rows.getLong(5),
            selectedCount: rows.getLong(6), skippedCount: rows.getLong(7), committedAtMs: rows.getLong(8),
            issueCount: rows.getLong(9) });
        }
      } finally { rows.close(); }
      return batches;
    });
  }

  async importBatchRows(batchId: string): Promise<ImportBatchRowDetail[]> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<ImportBatchRowDetail[]> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const details: ImportBatchRowDetail[] = [];
      const rows = await db.querySql('SELECT r.row_number,r.validation_status,r.selected,r.issue_codes_json,' +
        'r.raw_json,COALESCE(r.normalized_json,\'{}\') FROM import_rows r JOIN import_batches b ON b.id=r.batch_id ' +
        'WHERE b.id=? AND b.book_id=? ORDER BY r.row_number', [batchId, this.activeBookId]);
      try {
        while (rows.goToNextRow()) {
          let rawPreview = '';
          let normalizedType = '';
          let normalizedDate = '';
          let normalizedAmount = '';
          try {
            const raw = JSON.parse(rows.getString(4)) as string[];
            rawPreview = raw.filter((value: string) => value.trim().length > 0).slice(0, 8).join(' | ');
          } catch (_) { rawPreview = ''; }
          try {
            const normalized = JSON.parse(rows.getString(5)) as CsvPreviewRow;
            normalizedType = normalized.type || '';
            normalizedDate = normalized.date || '';
            normalizedAmount = normalized.amount || '';
          } catch (_) { /* Keep partial history readable for older batches. */ }
          let issues: string[] = [];
          try { issues = JSON.parse(rows.getString(3)) as string[]; } catch (_) { issues = []; }
          details.push({ rowNumber: rows.getLong(0), validationStatus: rows.getString(1),
            selected: rows.getLong(2) === 1, issues: issues, rawPreview: rawPreview,
            normalizedType: normalizedType, normalizedDate: normalizedDate, normalizedAmount: normalizedAmount });
        }
      } finally { rows.close(); }
      return details;
    });
  }

  private normalizeImportMapping(mapping: CsvColumnMapping): CsvColumnMapping {
    const index = (value: number): number => Number.isInteger(value) && value >= 0 ? value : -1;
    return {
      date: index(mapping.date), time: index(mapping.time), type: index(mapping.type),
      amount: index(mapping.amount), transferAmount: index(mapping.transferAmount),
      category: index(mapping.category), account: index(mapping.account),
      toAccount: index(mapping.toAccount), purpose: index(mapping.purpose), fee: index(mapping.fee),
      coupon: index(mapping.coupon), feeBudget: index(mapping.feeBudget), note: index(mapping.note),
      sourceId: index(mapping.sourceId), merchant: index(mapping.merchant),
      address: index(mapping.address), latitude: index(mapping.latitude ?? -1),
      longitude: index(mapping.longitude ?? -1), includeInBudget: index(mapping.includeInBudget ?? -1),
      spendingNature: index(mapping.spendingNature ?? -1), originalEntryId: index(mapping.originalEntryId ?? -1),
      reimbursementPending: index(mapping.reimbursementPending ?? -1), fx: index(mapping.fx ?? -1), currency: index(mapping.currency ?? -1), status: index(mapping.status)
    };
  }

  private async ensureCsvCategory(db: relationalStore.RdbStore, bookId: string, kind: string,
    path: string): Promise<string> {
    const parts = path.split(/\s*[\/>]\s*/).map((part: string) => part.trim())
      .filter((part: string) => part.length > 0);
    const names = parts.length > 0 ? parts : ['未分类'];
    let parentId: string | null = null;
    for (const name of names) {
      let id = '';
      let revision = 0;
      let archived = false;
      const existing = await db.querySql('SELECT id,revision,archived_at_ms FROM categories ' +
        'WHERE book_id=? AND kind=? AND COALESCE(parent_id,\'\')=? AND name_key=? AND deleted_at_ms IS NULL LIMIT 1',
        [bookId, kind, parentId || '', name]);
      try {
        if (existing.goToFirstRow()) {
          id = existing.getString(0); revision = existing.getLong(1); archived = !existing.isColumnNull(2);
        }
      } finally { existing.close(); }
      if (id.length > 0) {
        if (archived) {
          await db.update({ archived_at_ms: null, revision: revision + 1, updated_at_ms: Date.now() },
            new relationalStore.RdbPredicates('categories').equalTo('id', id).equalTo('revision', revision));
        }
        parentId = id;
        continue;
      }
      const order = await db.querySql('SELECT COALESCE(MAX(sort_order),-1)+1 FROM categories ' +
        'WHERE book_id=? AND kind=? AND COALESCE(parent_id,\'\')=? AND deleted_at_ms IS NULL',
        [bookId, kind, parentId || '']);
      let sortOrder = 0;
      try { if (order.goToFirstRow()) { sortOrder = order.getLong(0); } } finally { order.close(); }
      const now = Date.now();
      id = util.generateRandomUUID();
      await db.insert('categories', { id: id, book_id: bookId, kind: kind, parent_id: parentId,
        name: name, name_key: name, icon_key: 'other', sort_order: sortOrder, created_at_ms: now, updated_at_ms: now });
      parentId = id;
    }
    return parentId || '';
  }

  private async ensureCsvAccount(db: relationalStore.RdbStore, name: string, currency: string,
    insertedAccountTypes: Map<string, string>): Promise<string> {
    const accountName = name.trim();
    if (accountName.length === 0) { return ''; }
    let id = '';
    let revision = 0;
    let archived = false;
    const existing = await db.querySql("SELECT id,revision,archived_at_ms FROM accounts WHERE name=? AND currency_id=? " +
      'AND deleted_at_ms IS NULL LIMIT 1', [accountName, currency]);
    try {
      if (existing.goToFirstRow()) {
        id = existing.getString(0); revision = existing.getLong(1); archived = !existing.isColumnNull(2);
      }
    } finally { existing.close(); }
    if (id.length > 0) {
      if (archived) {
        await db.update({ archived_at_ms: null, revision: revision + 1, updated_at_ms: Date.now() },
          new relationalStore.RdbPredicates('accounts').equalTo('id', id).equalTo('revision', revision));
      }
      return id;
    }
    const liability = /信用卡|花呗|借呗|贷款|待还/.test(accountName);
    const order = await db.querySql('SELECT COALESCE(MAX(sort_order),-1)+1 FROM accounts WHERE deleted_at_ms IS NULL');
    let sortOrder = 0;
    try { if (order.goToFirstRow()) { sortOrder = order.getLong(0); } } finally { order.close(); }
    const now = Date.now();
    id = util.generateRandomUUID();
    await db.insert('accounts', { id: id, name: accountName, kind: liability ? 'liability' : 'asset',
      currency_id: currency, brand: 'cash', icon_key: 'cash', icon_variant: 'monochrome',
      brand_color: '#D49A38', include_in_net_assets: 1, sort_order: sortOrder, created_at_ms: now, updated_at_ms: now });
    insertedAccountTypes.set(id, currency + ':' + (liability ? 'liability' : 'asset'));
    return id;
  }

  private async validateCsvAccount(db: relationalStore.RdbStore, id: string, requireLiability: boolean,
    required: boolean, currency: string, insertedAccountTypes: Map<string, string>): Promise<void> {
    if (id.length === 0) {
      if (required) { throw new Error('CSV_ACCOUNT_INVALID'); }
      return;
    }
    // Only successful inserts in this transaction enter the cache. Separate readers may
    // not see those rows until commit, so validate against their exact inserted metadata.
    const inserted = insertedAccountTypes.get(id);
    if (inserted !== undefined) {
      if (inserted !== currency + ':asset' && inserted !== currency + ':liability') {
        throw new Error('CSV_ACCOUNT_INVALID');
      }
      if (requireLiability && inserted !== currency + ':liability') {
        throw new Error('CSV_TRANSFER_REPAYMENT_ACCOUNT_INVALID');
      }
      return;
    }
    const account = await db.querySql('SELECT kind FROM accounts WHERE id=? AND currency_id=? AND deleted_at_ms IS NULL', [id, currency]);
    try {
      if (!account.goToFirstRow() || (requireLiability && account.getString(0) !== 'liability')) {
        throw new Error(requireLiability ? 'CSV_TRANSFER_REPAYMENT_ACCOUNT_INVALID' : 'CSV_ACCOUNT_INVALID');
      }
    } finally { account.close(); }
  }

  private async ensureCsvMerchant(db: relationalStore.RdbStore, name: string, address: string): Promise<string> {
    const merchantName = name.trim();
    const normalized = merchantName.toLowerCase().replace(/\s+/g, '');
    if (normalized.length === 0) { return ''; }
    let id = '';
    let revision = 0;
    let existingAddress = '';
    const existing = await db.querySql("SELECT id,revision,COALESCE(default_address,'') FROM merchants " +
      'WHERE normalized_name=? AND deleted_at_ms IS NULL LIMIT 1', [normalized]);
    try {
      if (existing.goToFirstRow()) {
        id = existing.getString(0); revision = existing.getLong(1); existingAddress = existing.getString(2);
      }
    } finally { existing.close(); }
    const now = Date.now();
    if (id.length > 0) {
      if (existingAddress.length === 0 && address.trim().length > 0) {
        await db.update({ default_address: address.trim(), updated_at_ms: now, revision: revision + 1 },
          new relationalStore.RdbPredicates('merchants').equalTo('id', id).equalTo('revision', revision));
      }
      return id;
    }
    id = util.generateRandomUUID();
    await db.insert('merchants', { id: id, name: merchantName, normalized_name: normalized,
      default_address: address.trim().length > 0 ? address.trim() : null,
      created_at_ms: now, updated_at_ms: now });
    return id;
  }

  async usageSummary(): Promise<LedgerUsageSummary> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<LedgerUsageSummary> => {
      const rows = await db.querySql("SELECT MIN(local_day),CAST(COUNT(*) AS TEXT) FROM (SELECT occurred_local_date AS local_day FROM v_posted_transactions WHERE kind IN ('expense','income','transfer') UNION ALL SELECT local_date AS local_day FROM v_prepaid_events WHERE kind IN ('fund','refund'))");
      try {
        if (!rows.goToFirstRow()) { return { firstEntryDate: '', entryCount: '0' }; }
        return { firstEntryDate: rows.isColumnNull(0) ? '' : rows.getString(0), entryCount: rows.getString(1) };
      } finally { rows.close(); }
    });
  }

  async categories(): Promise<CategoryProfile[]> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<CategoryProfile[]> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const values: CategoryProfile[] = [];
      const rows = await db.querySql('SELECT id,kind,COALESCE(parent_id,\'\'),name,COALESCE(icon_key,\'other\'),sort_order,revision,archived_at_ms ' +
        'FROM categories WHERE book_id=? AND deleted_at_ms IS NULL ORDER BY kind DESC,archived_at_ms IS NOT NULL,sort_order,created_at_ms,id',
        [this.activeBookId]);
      try {
        while (rows.goToNextRow()) {
          values.push({ id: rows.getString(0), kind: rows.getString(1), parentId: rows.getString(2), name: rows.getString(3),
            iconKey: rows.getString(4), sortOrder: rows.getLong(5), revision: rows.getLong(6), archived: !rows.isColumnNull(7) });
        }
      } finally { rows.close(); }
      return values;
    });
  }

  async createCategory(command: CategoryCommand): Promise<void> {
    const draft = new ValidatedCategory(command).command;
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      if (draft.parentId !== undefined) {
        const parent = await db.querySql('SELECT id FROM categories WHERE id=? AND book_id=? AND kind=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL',
          [draft.parentId, this.activeBookId, draft.kind]);
        try { if (!parent.goToFirstRow()) { throw new Error('CATEGORY_PARENT_UNAVAILABLE'); } } finally { parent.close(); }
      }
      const duplicate = await db.querySql('SELECT id FROM categories WHERE book_id=? AND kind=? AND COALESCE(parent_id,\'\')=? AND name_key=? AND deleted_at_ms IS NULL',
        [this.activeBookId, draft.kind, draft.parentId || '', draft.name]);
      try { if (duplicate.goToFirstRow()) { throw new Error('CATEGORY_NAME_EXISTS'); } } finally { duplicate.close(); }
      const order = await db.querySql('SELECT COALESCE(MAX(sort_order),-1)+1 FROM categories WHERE book_id=? AND kind=? AND COALESCE(parent_id,\'\')=? AND deleted_at_ms IS NULL',
        [this.activeBookId, draft.kind, draft.parentId || '']);
      let sortOrder: number = 0;
      try { if (order.goToFirstRow()) { sortOrder = order.getLong(0); } } finally { order.close(); }
      const now = Date.now();
      await db.insert('categories', { id: draft.id, book_id: this.activeBookId, kind: draft.kind,
        parent_id: draft.parentId, name: draft.name, name_key: draft.name, icon_key: draft.iconKey,
        sort_order: sortOrder, created_at_ms: now, updated_at_ms: now });
    });
  }

  async updateCategory(command: CategoryCommand, revision: number): Promise<void> {
    const draft = new ValidatedCategory(command).command;
    if (!Number.isSafeInteger(revision) || revision < 1 || revision >= Number.MAX_SAFE_INTEGER) { throw new Error('INVALID_EXPECTED_REVISION'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const source = await db.querySql('SELECT kind,COALESCE(parent_id,\'\'),sort_order,archived_at_ms FROM categories WHERE id=? AND book_id=? AND revision=? AND deleted_at_ms IS NULL',
        [draft.id, this.activeBookId, revision]);
      let oldParent: string = '';
      let sortOrder: number = 0;
      try {
        if (!source.goToFirstRow() || source.getString(0) !== draft.kind) { throw new Error('CATEGORY_CHANGED'); }
        oldParent = source.getString(1); sortOrder = source.getLong(2);
      } finally { source.close(); }
      if (draft.parentId !== undefined) {
        const parent = await db.querySql('SELECT id FROM categories WHERE id=? AND book_id=? AND kind=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL',
          [draft.parentId, this.activeBookId, draft.kind]);
        try { if (!parent.goToFirstRow()) { throw new Error('CATEGORY_PARENT_UNAVAILABLE'); } } finally { parent.close(); }
        const cycle = await db.querySql('SELECT ancestor_id FROM category_closure WHERE ancestor_id=? AND descendant_id=?',
          [draft.id, draft.parentId]);
        try { if (cycle.goToFirstRow()) { throw new Error('CATEGORY_CYCLE'); } } finally { cycle.close(); }
      }
      if ((draft.parentId || '') !== oldParent) {
        const order = await db.querySql('SELECT COALESCE(MAX(sort_order),-1)+1 FROM categories WHERE book_id=? AND kind=? AND COALESCE(parent_id,\'\')=? AND deleted_at_ms IS NULL',
          [this.activeBookId, draft.kind, draft.parentId || '']);
        try { if (order.goToFirstRow()) { sortOrder = order.getLong(0); } } finally { order.close(); }
      }
      const duplicate = await db.querySql('SELECT id FROM categories WHERE id<>? AND book_id=? AND kind=? AND COALESCE(parent_id,\'\')=? AND name_key=? AND deleted_at_ms IS NULL',
        [draft.id, this.activeBookId, draft.kind, draft.parentId || '', draft.name]);
      try { if (duplicate.goToFirstRow()) { throw new Error('CATEGORY_NAME_EXISTS'); } } finally { duplicate.close(); }
      const changed = await db.update({ parent_id: draft.parentId || null, name: draft.name, name_key: draft.name,
        icon_key: draft.iconKey, sort_order: sortOrder, updated_at_ms: Date.now(), revision: revision + 1 },
        new relationalStore.RdbPredicates('categories').equalTo('id', draft.id).equalTo('book_id', this.activeBookId)
          .equalTo('kind', draft.kind).equalTo('revision', revision).isNull('deleted_at_ms'));
      if (changed !== 1) { throw new Error('CATEGORY_CHANGED'); }
    });
  }

  /** Save a complete active sibling permutation atomically; never reparent categories. */
  async reorderCategories(kind: string, parentId: string, order: CategoryOrderItem[]): Promise<void> {
    if ((kind !== 'expense' && kind !== 'income') || order.length === 0 ||
      new Set<string>(order.map((item: CategoryOrderItem) => item.id)).size !== order.length ||
      order.some((item: CategoryOrderItem) => item.id.length === 0 || !Number.isSafeInteger(item.revision) ||
        item.revision < 1 || item.revision >= Number.MAX_SAFE_INTEGER)) {
      throw new Error('INVALID_CATEGORY_ORDER');
    }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const bookId = await this.activeBookFromMeta(db);
      const rows = await db.querySql("SELECT id,revision FROM categories WHERE book_id=? AND kind=? AND COALESCE(parent_id,'')=? " +
        'AND deleted_at_ms IS NULL AND archived_at_ms IS NULL', [bookId, kind, parentId]);
      const current: Map<string, number> = new Map<string, number>();
      try { while (rows.goToNextRow()) { current.set(rows.getString(0), rows.getLong(1)); } }
      finally { rows.close(); }
      // Check membership as well as revisions: adding, archiving or moving a sibling invalidates this drag.
      if (current.size !== order.length || order.some((item: CategoryOrderItem) => current.get(item.id) !== item.revision)) {
        throw new Error('CATEGORY_CHANGED');
      }
      const now = Date.now();
      for (let index = 0; index < order.length; index++) {
        const item = order[index];
        const changed = await db.update({ sort_order: index, updated_at_ms: now, revision: item.revision + 1 },
          new relationalStore.RdbPredicates('categories').equalTo('id', item.id).equalTo('book_id', bookId)
            .equalTo('kind', kind).equalTo('revision', item.revision).isNull('deleted_at_ms').isNull('archived_at_ms'));
        if (changed !== 1) { throw new Error('CATEGORY_CHANGED'); }
      }
    });
  }

  async moveCategory(id: string, revision: number, direction: number): Promise<void> {
    if (direction !== -1 && direction !== 1) { throw new Error('INVALID_CATEGORY_DIRECTION'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const current = await db.querySql('SELECT kind,COALESCE(parent_id,\'\'),sort_order FROM categories WHERE id=? AND book_id=? AND revision=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL',
        [id, this.activeBookId, revision]);
      let kind: string = '';
      let parent: string = '';
      let sortOrder: number = 0;
      try {
        if (!current.goToFirstRow()) { throw new Error('CATEGORY_CHANGED'); }
        kind = current.getString(0); parent = current.getString(1); sortOrder = current.getLong(2);
      } finally { current.close(); }
      const comparator = direction < 0 ? '<' : '>';
      const ordering = direction < 0 ? 'DESC' : 'ASC';
      const neighbor = await db.querySql('SELECT id,sort_order,revision FROM categories WHERE book_id=? AND kind=? AND COALESCE(parent_id,\'\')=? ' +
        'AND archived_at_ms IS NULL AND deleted_at_ms IS NULL AND (sort_order ' + comparator + ' ? OR (sort_order=? AND id ' + comparator + ' ?)) ' +
        'ORDER BY sort_order ' + ordering + ',id ' + ordering + ' LIMIT 1',
        [this.activeBookId, kind, parent, sortOrder, sortOrder, id]);
      let neighborId: string = '';
      let neighborSort: number = 0;
      let neighborRevision: number = 0;
      try {
        if (neighbor.goToFirstRow()) {
          neighborId = neighbor.getString(0); neighborSort = neighbor.getLong(1); neighborRevision = neighbor.getLong(2);
        }
      } finally { neighbor.close(); }
      if (neighborId.length === 0) { return; }
      const now = Date.now();
      const first = await db.update({ sort_order: neighborSort, updated_at_ms: now, revision: revision + 1 },
        new relationalStore.RdbPredicates('categories').equalTo('id', id).equalTo('revision', revision));
      const second = await db.update({ sort_order: sortOrder, updated_at_ms: now, revision: neighborRevision + 1 },
        new relationalStore.RdbPredicates('categories').equalTo('id', neighborId).equalTo('revision', neighborRevision));
      if (first !== 1 || second !== 1) { throw new Error('CATEGORY_CHANGED'); }
    });
  }

  async archiveCategory(id: string, revision: number, archived: boolean): Promise<void> {
    if (!Number.isSafeInteger(revision) || revision < 1 || revision >= Number.MAX_SAFE_INTEGER) { throw new Error('INVALID_EXPECTED_REVISION'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const source = await db.querySql('SELECT kind,COALESCE(parent_id,\'\') FROM categories WHERE id=? AND book_id=? AND revision=? AND deleted_at_ms IS NULL',
        [id, this.activeBookId, revision]);
      let kind: string = '';
      let parentId: string = '';
      try {
        if (!source.goToFirstRow()) { throw new Error('CATEGORY_CHANGED'); }
        kind = source.getString(0); parentId = source.getString(1);
      } finally { source.close(); }
      if (archived) {
        const children = await db.querySql('SELECT id FROM categories WHERE parent_id=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL LIMIT 1',
          [id]);
        try { if (children.goToFirstRow()) { throw new Error('CATEGORY_HAS_CHILDREN'); } } finally { children.close(); }
        const other = await db.querySql('SELECT id FROM categories WHERE id<>? AND book_id=? AND kind=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL LIMIT 1',
          [id, this.activeBookId, kind]);
        try { if (!other.goToFirstRow()) { throw new Error('LAST_ACTIVE_CATEGORY'); } } finally { other.close(); }
      } else if (parentId.length > 0) {
        const parent = await db.querySql('SELECT id FROM categories WHERE id=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL', [parentId]);
        try { if (!parent.goToFirstRow()) { throw new Error('CATEGORY_PARENT_UNAVAILABLE'); } } finally { parent.close(); }
      }
      const changed = await db.update({ archived_at_ms: archived ? Date.now() : null, updated_at_ms: Date.now(), revision: revision + 1 },
        new relationalStore.RdbPredicates('categories').equalTo('id', id).equalTo('book_id', this.activeBookId)
          .equalTo('revision', revision).isNull('deleted_at_ms'));
      if (changed !== 1) { throw new Error('CATEGORY_CHANGED'); }
    });
  }

  async setBudgetNatureAmount(month: string, natureId: string, decimal: string): Promise<void> {
    const period = MonthlyBudget.period(month);
    const amount = MonthlyBudget.parse(decimal, this.currency);
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const nature = await db.querySql('SELECT id FROM spending_natures WHERE id=? AND deleted_at_ms IS NULL', [natureId]);
      try { if (!nature.goToFirstRow()) { throw new Error('SPENDING_NATURE_UNAVAILABLE'); } } finally { nature.close(); }
      const rows = await db.querySql('SELECT id,currency_id,CAST(total_minor AS TEXT) FROM budgets WHERE book_id=? AND period_start_date=? AND period_end_date_exclusive=? AND deleted_at_ms IS NULL',
        [this.activeBookId, period.start, period.endExclusive]);
      let budgetId: string = '';
      let totalMinor: string = DEFAULT_MONTHLY_BUDGET_MINOR;
      try {
        if (rows.goToFirstRow()) {
          if (rows.getString(1) !== this.currency.id) { throw new Error('CURRENCY_MISMATCH'); }
          budgetId = rows.getString(0); totalMinor = rows.getString(2);
        }
      } finally { rows.close(); }
      const now = Date.now();
      if (budgetId.length === 0) {
        budgetId = util.generateRandomUUID();
        await db.insert('budgets', { id: budgetId, book_id: this.activeBookId, currency_id: this.currency.id,
          period_start_date: period.start, period_end_date_exclusive: period.endExclusive,
          total_minor: Number(totalMinor), created_at_ms: now, updated_at_ms: now });
      }
      const existing = await db.querySql('SELECT id,revision FROM budget_nature_lines WHERE budget_id=? AND spending_nature_id=?',
        [budgetId, natureId]);
      let lineId: string = '';
      let revision: number = 0;
      try {
        if (existing.goToFirstRow()) { lineId = existing.getString(0); revision = existing.getLong(1); }
      } finally { existing.close(); }
      if (amount.minor === BigInt(0)) {
        if (lineId.length > 0) {
          await db.delete(new relationalStore.RdbPredicates('budget_nature_lines').equalTo('id', lineId));
        }
        return;
      }
      const allocated = await db.querySql('SELECT COALESCE(SUM(amount_minor),0) FROM budget_nature_lines WHERE budget_id=? AND id<>?',
        [budgetId, lineId]);
      let otherAllocated: number = 0;
      try { if (allocated.goToFirstRow()) { otherAllocated = allocated.getLong(0); } } finally { allocated.close(); }
      if (BigInt(otherAllocated) + amount.minor > BigInt(totalMinor)) { throw new Error('BUDGET_ALLOCATION_EXCEEDS_TOTAL'); }
      if (lineId.length > 0) {
        const changed = await db.update({ amount_minor: amount.toSafeMinorNumber(), updated_at_ms: now, revision: revision + 1 },
          new relationalStore.RdbPredicates('budget_nature_lines').equalTo('id', lineId).equalTo('revision', revision));
        if (changed !== 1) { throw new Error('BUDGET_LINE_CHANGED'); }
      } else {
        await db.insert('budget_nature_lines', { id: util.generateRandomUUID(), budget_id: budgetId, book_id: this.activeBookId,
          spending_nature_id: natureId, amount_minor: amount.toSafeMinorNumber(), created_at_ms: now, updated_at_ms: now });
      }
    });
  }

  async updateExpense(command: ExpenseCommand, expectedRevision: number): Promise<void> {
    await this.validateAttachmentFiles(command.attachments);
    await this.updater.execute(command, expectedRevision);
  }

  async prepaidProjects(): Promise<PrepaidProject[]> { return new RdbPrepaidRepository(this.store).list(this.activeBookId); }
  async prepaidDetail(id: string): Promise<PrepaidDetail> { return new RdbPrepaidRepository(this.store).detail(this.activeBookId,id); }
  async createPrepaid(project: PrepaidProjectCommand, payment: PrepaidEventCommand): Promise<void> {
    await this.validateAttachmentFiles(payment.attachments);
    if (project.bookId!==this.activeBookId) { throw new Error('PREPAID_CHANGED'); }
    await new RdbPrepaidRepository(this.store).create(project,payment);
  }
  async editPrepaid(project: PrepaidProjectCommand): Promise<void> {
    if (project.bookId!==this.activeBookId) { throw new Error('PREPAID_CHANGED'); }
    await new RdbPrepaidRepository(this.store).update(project);
  }
  async savePrepaidEvent(command: PrepaidEventCommand): Promise<void> {
    await this.validateAttachmentFiles(command.attachments);
    if (command.bookId!==this.activeBookId) { throw new Error('PREPAID_CHANGED'); }
    await new RdbPrepaidRepository(this.store).save(command);
  }
  async undoPrepaid(id: string, eventId: string, revision: number): Promise<void> { await new RdbPrepaidRepository(this.store).undo(this.activeBookId,id,eventId,revision); }

  async accountOverview(): Promise<AccountOverview> {
    const result = await this.accountRepository.snapshot();
    let assets = BigInt(result.assetsMinor); let liabilities = BigInt(result.liabilitiesMinor);
    const prepaid = await this.session.read((db: relationalStore.RdbStore) => RdbPrepaidRepository.projects(db));
    let prepaidMinor = BigInt(0);
    for (const project of prepaid) { if (project.includeInNetAssets) { prepaidMinor += BigInt(project.remainingBookMinor); } }
    assets += prepaidMinor;
    result.prepaidMinor = prepaidMinor.toString();
    const missing: string[] = [];
    const now = new Date();
    const date = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}`;
    for (const account of result.accounts) {
      if (!account.includeInNetAssets || account.currencyId === 'CNY' || account.balanceMinor === '0') { continue; }
      try {
        const quote = await OfficialExchangeRates.quote(account.currencyId, 'CNY', date);
        const converted = new ExchangeRate(currencyUnit(account.currencyId), this.currency, quote.rate)
          .convert(Money.fromMinorText(account.balanceMinor, currencyUnit(account.currencyId))).minor;
        if (converted >= BigInt(0)) { assets += converted; } else { liabilities -= converted; }
        result.valuationDate = quote.date;
      } catch (_) { if (!missing.includes(account.currencyId)) { missing.push(account.currencyId); } }
    }
    result.valuationMissing = missing;
    result.assetsMinor = missing.length > 0 ? '' : assets.toString();
    result.liabilitiesMinor = missing.length > 0 ? '' : liabilities.toString();
    result.netMinor = missing.length > 0 ? '' : (assets-liabilities).toString();
    return result;
  }
  async calibrateAccount(command: AccountCalibrationCommand): Promise<void> { await this.accountRepository.calibrate(command); }
  async accountAdjustments(id: string, cursor: AdjustmentCursor | undefined = undefined): Promise<AdjustmentPage> { return this.accountRepository.adjustmentHistory(id, cursor); }
  async createAccount(command: AccountCommand): Promise<void> { await this.accountRepository.create(command); }
  async updateAccount(command: AccountCommand, revision: number): Promise<void> { await this.accountRepository.update(command, revision); }
  async archiveAccount(id: string, revision: number, archived: boolean): Promise<void> { await this.accountRepository.archive(id, revision, archived); }

  async saveTransfer(command: TransferCommand): Promise<void> {
    await this.validateAttachmentFiles(command.attachments);
    await this.transfer.save(command);
  }
  async updateTransfer(command: TransferCommand, revision: number): Promise<void> {
    await this.validateAttachmentFiles(command.attachments);
    await this.transfer.update(command, revision);
  }

  async saveIncome(command: IncomeCommand): Promise<void> {
    await this.validateAttachmentFiles(command.attachments);
    await this.income.save(command);
  }
  async updateIncome(command: IncomeCommand, revision: number): Promise<void> {
    await this.validateAttachmentFiles(command.attachments);
    await this.income.update(command, revision);
  }

  async statistics(startDate: string, endDateExclusive: string, kind: StatisticsKind,
    unit: StatisticsBucketUnit): Promise<LedgerStatistics> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<LedgerStatistics> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      return this.statisticsRepository.snapshot(this.activeBookId, startDate, endDateExclusive, kind, unit);
    });
  }

  async statisticsEntries(startDate: string, endDateExclusive: string, kind: StatisticsKind,
    categoryKey: string, tagId: string = ''): Promise<StatisticsEntry[]> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<StatisticsEntry[]> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      return this.statisticsRepository.entries(this.activeBookId, startDate, endDateExclusive, kind, categoryKey, tagId);
    });
  }

  async entryDetail(id: string): Promise<EntryDetail> {
    if (id.trim().length === 0) { throw new Error('INVALID_TRANSACTION_ID'); }
    return this.session.read(async (db: relationalStore.RdbStore): Promise<EntryDetail> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const linked = await db.querySql('SELECT transaction_id FROM v_expense_recoveries WHERE id=? AND book_id=?', [id, this.activeBookId]);
      try { if (linked.goToFirstRow()) { id = linked.getString(0); } } finally { linked.close(); }
      const rows = await db.querySql("SELECT t.id,t.book_id,b.name,t.kind,t.revision,COALESCE(t.category_id,''),COALESCE(c.name,'转账'),COALESCE(c.icon_key,'other'),COALESCE(m.account_id,d.from_account_id,''),COALESCE(a.name,''),t.currency_id,u.code,u.symbol,u.minor_unit,CAST(t.gross_minor AS TEXT),CAST(t.discount_minor AS TEXT),CAST(t.paid_minor AS TEXT),CAST(COALESCE(t.book_minor,t.paid_minor) AS TEXT),t.include_in_budget,t.include_in_assets,t.balance_mode,t.occurred_at_ms,t.occurred_local_date,t.occurred_timezone,t.occurred_offset_minutes,t.note,t.book_currency_id,COALESCE(m.currency_id,t.currency_id),(SELECT COUNT(*) FROM fx_snapshots WHERE transaction_id=t.id),COALESCE(mi.account_id,''),COALESCE(ai.name,''),COALESCE(mi.currency_id,t.currency_id),t.group_id,COALESCE(d.purpose,'transfer'),CAST(COALESCE(d.out_minor,t.paid_minor) AS TEXT),CAST(COALESCE(d.in_minor,t.paid_minor) AS TEXT),CAST(COALESCE(d.fee_minor,0) AS TEXT),CAST(COALESCE(d.coupon_minor,0) AS TEXT),COALESCE(d.fee_in_expense,1),COALESCE(d.fee_in_budget,1),COALESCE(a.kind,'asset'),COALESCE(ai.kind,'asset'),COALESCE(nt.spending_nature_id,''),COALESCE(n.name,''),COALESCE(n.custom_color,n.color_token,'') FROM v_posted_transactions t JOIN transactions nt ON nt.id=t.id JOIN books b ON b.id=t.book_id JOIN currencies u ON u.id=t.currency_id LEFT JOIN categories c ON c.id=t.category_id LEFT JOIN spending_natures n ON n.id=nt.spending_nature_id LEFT JOIN v_transfer_details d ON d.transaction_id=t.id LEFT JOIN account_movements m ON m.transaction_id=t.id AND m.leg<>'transfer_in' LEFT JOIN accounts a ON a.id=COALESCE(m.account_id,d.from_account_id) LEFT JOIN account_movements mi ON mi.transaction_id=t.id AND mi.leg='transfer_in' LEFT JOIN accounts ai ON ai.id=mi.account_id WHERE t.id=? AND t.book_id=?",
        [id, this.activeBookId]);
      let detail: EntryDetail;
      try {
        if (!rows.goToFirstRow()) { throw new Error('TRANSACTION_NOT_FOUND'); }
        const canEdit = ['expense','income','transfer'].includes(rows.getString(3)) && rows.isColumnNull(32);
        detail = { id: rows.getString(0), bookId: rows.getString(1), bookName: rows.getString(2), kind: rows.getString(3),
          revision: rows.getLong(4), categoryId: rows.getString(5), categoryName: rows.getString(6), categoryPath: rows.getString(6),
          iconKey: rows.getString(7), accountId: rows.getString(8), accountName: rows.getString(9), currencyId: rows.getString(10),
          currencyCode: rows.getString(11), currencySymbol: rows.getString(12), currencyScale: rows.getLong(13),
          grossMinor: rows.getString(14), discountMinor: rows.getString(15), paidMinor: rows.getString(16), bookMinor: rows.getString(17),
          includeInBudget: rows.getLong(18) === 1, includeInAssets: rows.getLong(19) === 1, balanceMode: rows.getString(20),
          occurredAtMs: rows.getLong(21), localDate: rows.getString(22), timezone: rows.getString(23), offsetMinutes: rows.getLong(24),
          note: rows.getString(25), toAccountId: rows.getString(29), toAccountName: rows.getString(30), transferPurpose: rows.getString(33), transferOutMinor: rows.getString(34),
          transferInMinor: rows.getString(35), transferFeeMinor: rows.getString(36), transferCouponMinor: rows.getString(37),
          feeInExpense: rows.getLong(38) === 1, feeInBudget: rows.getLong(39) === 1, accountKind: rows.getString(40), toAccountKind: rows.getString(41),
          spendingNatureId: rows.getString(42), spendingNatureName: rows.getString(43), spendingNatureColor: rows.getString(44), canEdit: canEdit };
      } finally { rows.close(); }
      const prepaidLink = await db.querySql('SELECT id FROM v_prepaid_events WHERE transaction_id=?',[detail.id]);
      try { if (prepaidLink.goToFirstRow()) { detail.canEdit=false; detail.prepaidLinked=true; } } finally { prepaidLink.close(); }
      detail.bookFx = await RdbFxSnapshots.read(db, detail.id, 'book');
      detail.accountFx = await RdbFxSnapshots.read(db, detail.id, 'settlement');
      const settlement = await db.querySql("SELECT currency_id,CAST(abs(delta_minor) AS TEXT) FROM account_movements WHERE transaction_id=? AND leg=?", [detail.id, detail.kind === 'transfer' ? 'transfer_in' : detail.kind]);
      try { if (settlement.goToFirstRow()) { detail.accountCurrencyId = settlement.getString(0); detail.accountMinor = settlement.getString(1); } } finally { settlement.close(); }
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
      const tags: TagChoice[] = [];
      const tagRows = await db.querySql('SELECT g.id,g.name,COALESCE(g.color_token,\'neutral\') FROM transaction_tags tt ' +
        'JOIN tags g ON g.id=tt.tag_id WHERE tt.transaction_id=? ORDER BY g.sort_order,g.created_at_ms,g.id', [detail.id]);
      try {
        while (tagRows.goToNextRow()) {
          tags.push({ id: tagRows.getString(0), name: tagRows.getString(1), colorKey: tagRows.getString(2) });
        }
      } finally { tagRows.close(); }
      detail.tags = tags;
      const attachments: LedgerAttachment[] = [];
      for (const attachment of await RdbAttachmentLinks.load(db, detail.id)) {
        attachments.push({ id: attachment.id, relativePath: attachment.relativePath,
          sha256: attachment.sha256, bytes: attachment.bytes, mimeType: attachment.mimeType,
          filePath: this.backup.resources.root + '/' + attachment.relativePath });
      }
      detail.attachments = attachments;
      const extras = await db.querySql("SELECT COALESCE(t.merchant_name_snapshot,m.name,'')," +
        "COALESCE(t.address_text,''),t.latitude_e6,t.longitude_e6,t.reimbursement_status FROM transactions t LEFT JOIN merchants m ON m.id=t.merchant_id WHERE t.id=?",
      [detail.id]);
      try {
        if (extras.goToFirstRow()) {
          detail.merchantName = extras.getString(0);
          detail.addressText = extras.getString(1);
          detail.reimbursementPending = extras.getString(4) === 'pending';
          if (!extras.isColumnNull(2) && !extras.isColumnNull(3)) {
            detail.location = { latitudeE6: extras.getLong(2), longitudeE6: extras.getLong(3) };
          }
        }
      } finally { extras.close(); }
      detail.recoveries = await RdbRecoveryRepository.list(db, detail.id);
      return detail;
    });
  }

  async saveRecovery(command: RecoveryCommand): Promise<void> {
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      if (command.bookId !== await this.activeBookFromMeta(db)) { throw new Error('RECOVERY_SOURCE_INVALID'); }
      await RdbRecoveryRepository.save(db, command);
    });
  }

  async deleteRecovery(id: string, revision: number): Promise<void> {
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      await RdbRecoveryRepository.remove(db, await this.activeBookFromMeta(db), id, revision);
    });
  }

  async setReimbursementPending(id: string, revision: number, pending: boolean): Promise<void> {
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const changed = await db.update({ reimbursement_status: pending ? 'pending' : 'none', revision: revision + 1, updated_at_ms: Date.now() },
        new relationalStore.RdbPredicates('transactions').equalTo('id', id).equalTo('book_id', await this.activeBookFromMeta(db))
          .equalTo('kind', 'expense').equalTo('revision', revision).equalTo('posting_state', 'posted').isNull('deleted_at_ms'));
      if (changed !== 1) { throw new Error('TRANSACTION_CHANGED'); }
    });
  }

  /** Deletes exactly one posted entry in this workspace. Movements remain as history. */
  async deleteEntry(id: string): Promise<void> {
    if (id.trim().length === 0) { throw new Error('INVALID_TRANSACTION_ID'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const receipt = await db.querySql('SELECT revision FROM v_expense_recoveries WHERE id=? AND book_id=?', [id, this.activeBookId]);
      try {
        if (receipt.goToFirstRow()) { await RdbRecoveryRepository.remove(db, this.activeBookId, id, receipt.getLong(0)); return; }
      } finally { receipt.close(); }
      const linked = await db.querySql('SELECT id FROM expense_recoveries WHERE transaction_id=? AND deleted_at_ms IS NULL LIMIT 1', [id]);
      try { if (linked.goToFirstRow()) { throw new Error('EXPENSE_HAS_RECOVERIES'); } } finally { linked.close(); }
      const rows = await db.querySql("SELECT revision,kind,group_id FROM transactions WHERE id=? AND book_id=? AND posting_state='posted' AND deleted_at_ms IS NULL",
        [id, this.activeBookId]);
      let revision: number;
      try {
        if (!rows.goToFirstRow()) { throw new Error('TRANSACTION_NOT_FOUND'); }
        if (rows.getString(1) === 'transfer' && !rows.isColumnNull(2)) { throw new Error('GROUP_OPERATION_REQUIRED'); }
        revision = rows.getLong(0);
      } finally { rows.close(); }
      const now = Date.now();
      const changed = await db.update({ deleted_at_ms: now, updated_at_ms: now, revision: revision + 1 },
        new relationalStore.RdbPredicates('transactions').equalTo('id', id).equalTo('book_id', this.activeBookId)
          .equalTo('posting_state', 'posted').isNull('deleted_at_ms').equalTo('revision', revision));
      if (changed !== 1) { throw new Error('TRANSACTION_CHANGED'); }
    });
  }

  async setMonthlyBudget(month: string, decimal: string): Promise<void> {
    const period = MonthlyBudget.period(month);
    const amount = MonthlyBudget.parse(decimal, this.currency);
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const rows = await db.querySql('SELECT id,currency_id FROM budgets WHERE book_id=? AND period_start_date=? AND period_end_date_exclusive=? AND deleted_at_ms IS NULL',
        [this.activeBookId, period.start, period.endExclusive]);
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
        await db.insert('budgets', { id: util.generateRandomUUID(), book_id: this.activeBookId, currency_id: this.currency.id,
          period_start_date: period.start, period_end_date_exclusive: period.endExclusive,
          total_minor: amount.toSafeMinorNumber(), created_at_ms: now, updated_at_ms: now });
      }
    });
  }

  async snapshot(month: string): Promise<LedgerSnapshot> {
    const period = MonthlyBudget.period(month);
    return this.session.read(async (db: relationalStore.RdbStore): Promise<LedgerSnapshot> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const book = await db.querySql('SELECT name,base_currency_id FROM books WHERE id=? AND deleted_at_ms IS NULL', [this.activeBookId]);
      let bookName: string = '';
      try {
        if (!book.goToFirstRow() || book.getString(1) !== 'CNY') { throw new Error('LEDGER_BOOK_UNAVAILABLE'); }
        bookName = book.getString(0);
      } finally { book.close(); }
      const categories: ExpenseCategory[] = [];
      const incomeCategories: ExpenseCategory[] = [];
      const categoryRows = await db.querySql("SELECT id,name,COALESCE(parent_id,''),COALESCE(icon_key,'other'),kind FROM categories WHERE book_id=? AND deleted_at_ms IS NULL AND archived_at_ms IS NULL ORDER BY sort_order,id", [this.activeBookId]);
      try {
        while (categoryRows.goToNextRow()) {
          const target = categoryRows.getString(4) === 'income' ? incomeCategories : categories;
          target.push({ id: categoryRows.getString(0), name: categoryRows.getString(1),
            parentId: categoryRows.getString(2), iconKey: categoryRows.getString(3) });
        }
      } finally { categoryRows.close(); }
      const spendingNatures: SpendingNatureChoice[] = [];
      const natureRows = await db.querySql('SELECT id,name,COALESCE(custom_color,color_token) FROM spending_natures WHERE deleted_at_ms IS NULL AND archived_at_ms IS NULL ORDER BY sort_order,created_at_ms,id');
      try {
        while (natureRows.goToNextRow()) {
          spendingNatures.push({ id: natureRows.getString(0), name: natureRows.getString(1), colorKey: natureRows.getString(2) });
        }
      } finally { natureRows.close(); }
      const tags: TagChoice[] = [];
      const tagRows = await db.querySql("SELECT id,name,COALESCE(color_token,'neutral') FROM tags " +
        'WHERE book_id=? AND deleted_at_ms IS NULL ORDER BY sort_order,created_at_ms,id', [this.activeBookId]);
      try {
        while (tagRows.goToNextRow()) {
          tags.push({ id: tagRows.getString(0), name: tagRows.getString(1), colorKey: tagRows.getString(2) });
        }
      } finally { tagRows.close(); }
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
      const rows = await db.querySql("SELECT t.id,t.note,CASE WHEN t.kind='transfer' THEN CASE d.purpose WHEN 'credit_repayment' THEN '信用卡还款' WHEN 'loan_repayment' THEN '借款还款' WHEN 'topup' THEN '充值' WHEN 'withdrawal' THEN '提现' ELSE '转账' END ELSE c.name END,COALESCE(c.icon_key,'transfer'),COALESCE(a.name,'不使用账户'),t.occurred_local_date,t.occurred_at_ms,t.occurred_offset_minutes,t.kind,CAST(COALESCE(t.book_minor,t.paid_minor) AS TEXT),t.include_in_budget,CAST(t.gross_minor AS TEXT),CAST(t.discount_minor AS TEXT),COALESCE(ai.name,''),CAST(COALESCE(d.out_minor,t.paid_minor) AS TEXT),CAST(COALESCE(d.fee_minor,0) AS TEXT),CAST(COALESCE(d.coupon_minor,0) AS TEXT),COALESCE(d.purpose,'transfer'),COALESCE(d.fee_in_expense,1),COALESCE(d.fee_in_budget,1),COALESCE(t.merchant_name_snapshot,mc.name,''),COALESCE(t.address_text,''),COALESCE(m.account_id,d.from_account_id,''),COALESCE(t.merchant_id,''),t.latitude_e6,t.longitude_e6,t.reimbursement_status,CAST(COALESCE((SELECT SUM(r.amount_minor) FROM v_expense_recoveries r WHERE r.transaction_id=t.id),0) AS TEXT),COALESCE((SELECT name FROM spending_natures WHERE id=t.spending_nature_id),''),CAST(COALESCE((SELECT SUM(r.amount_minor) FROM v_expense_recoveries r WHERE r.transaction_id=t.id AND r.kind='reimbursement'),0) AS TEXT),CAST(COALESCE((SELECT SUM(r.amount_minor) FROM v_expense_recoveries r WHERE r.transaction_id=t.id AND r.kind='refund'),0) AS TEXT),COALESCE((SELECT COALESCE(custom_color,color_token) FROM spending_natures WHERE id=t.spending_nature_id),''),t.currency_id,CAST(t.paid_minor AS TEXT),CAST(COALESCE(d.book_fee_minor,0) AS TEXT) FROM transactions t LEFT JOIN categories c ON c.id=t.category_id LEFT JOIN v_transfer_details d ON d.transaction_id=t.id LEFT JOIN account_movements m ON m.transaction_id=t.id AND m.leg<>'transfer_in' LEFT JOIN accounts a ON a.id=COALESCE(m.account_id,d.from_account_id) LEFT JOIN account_movements mi ON mi.transaction_id=t.id AND mi.leg='transfer_in' LEFT JOIN accounts ai ON ai.id=mi.account_id LEFT JOIN merchants mc ON mc.id=t.merchant_id WHERE t.book_id=? AND t.posting_state='posted' AND t.deleted_at_ms IS NULL AND (t.import_batch_id IS NULL OR EXISTS(SELECT 1 FROM import_batches b WHERE b.id=t.import_batch_id AND b.status='committed')) AND t.kind IN ('expense','income','transfer') AND substr(t.occurred_local_date,1,7)=? ORDER BY t.occurred_at_ms DESC,t.created_at_ms DESC,t.id DESC", [this.activeBookId, month]);
      try {
        while (rows.goToNextRow()) {
          const isIncome = rows.getString(8) === 'income';
          const isTransfer = rows.getString(8) === 'transfer';
          const minor = rows.getString(9);
          const feeExpense = isTransfer && rows.getLong(18) === 1 ? rows.getString(34) : '0';
          if (isTransfer) { expense += BigInt(feeExpense); if (rows.getLong(19) === 1) { budgetUsed += BigInt(feeExpense); } }
          if (isIncome) { income += BigInt(minor); } else if (!isTransfer) { expense += BigInt(minor); }
          if (!isIncome && !isTransfer && rows.getLong(10) === 1) { budgetUsed += BigInt(minor); }
          entries.push({ id: rows.getString(0), note: rows.getString(1), category: rows.getString(2),
            iconKey: rows.getString(3), account: rows.getString(4), accountId: rows.getString(22),
            date: rows.getString(5), occurredAtMs: rows.getLong(6),
            offsetMinutes: rows.getLong(7), income: isIncome, transfer: isTransfer, toAccount: rows.getString(13), minor: isTransfer ? rows.getString(14) : minor, expenseMinor: feeExpense,
            transferFeeMinor: rows.getString(15), transferCouponMinor: rows.getString(16),
            transferPurpose: isTransfer ? rows.getString(17) : '', feeInBudget: rows.getLong(19) === 1,
            grossMinor: rows.getString(11), discountMinor: rows.getString(12),
            merchant: rows.getString(20), address: rows.getString(21), merchantId: rows.getString(23), reimbursementPending: rows.getString(26) === 'pending', recoveredMinor: rows.getString(27),
            includeInBudget: rows.getLong(10) === 1, spendingNatureName: rows.getString(28), reimbursedMinor: rows.getString(29), refundedMinor: rows.getString(30), spendingNatureColor: rows.getString(31),
            location: rows.isColumnNull(24) || rows.isColumnNull(25) ? undefined :
              { latitudeE6: rows.getLong(24), longitudeE6: rows.getLong(25) } });
        }
      } finally { rows.close(); }
      const receipts = await db.querySql("SELECT r.id,r.transaction_id,r.kind,CAST(r.book_minor AS TEXT),COALESCE(a.name,'不使用账户'),COALESCE(r.account_id,''),r.local_date,r.occurred_at_ms,r.offset_minutes,r.note,c.name,COALESCE(c.icon_key,'other'),COALESCE(r.merchant_name_snapshot,''),COALESCE(r.address_text,''),r.latitude_e6,r.longitude_e6 FROM v_expense_recoveries r LEFT JOIN accounts a ON a.id=r.account_id LEFT JOIN categories c ON c.id=r.category_id WHERE r.book_id=? AND substr(r.local_date,1,7)=?", [this.activeBookId, month]);
      try {
        while (receipts.goToNextRow()) {
          const value = receipts.getString(3);
          expense -= BigInt(value);
          entries.push({ id: receipts.getString(0), originalEntryId: receipts.getString(1), recoveryKind: receipts.getString(2),
            note: receipts.getString(9),
            category: receipts.getString(10), iconKey: receipts.getString(11), account: receipts.getString(4), accountId: receipts.getString(5),
            date: receipts.getString(6), occurredAtMs: receipts.getLong(7), offsetMinutes: receipts.getLong(8),
            income: false, minor: '-' + value, grossMinor: '-' + value, discountMinor: '0',
            merchant: receipts.getString(12), address: receipts.getString(13),
            location: receipts.isColumnNull(14) || receipts.isColumnNull(15) ? undefined : { latitudeE6: receipts.getLong(14), longitudeE6: receipts.getLong(15) } });
        }
      } finally { receipts.close(); }
      const prepaidRows=await db.querySql("SELECT e.id,p.id,e.kind,p.name,p.currency_id,CAST(e.amount_minor AS TEXT),CAST(e.book_minor AS TEXT),COALESCE(e.account_id,''),COALESCE(a.name,''),e.local_date,e.occurred_at_ms,e.offset_minutes,p.merchant,e.quote_json,CAST(p.remaining_minor AS TEXT),e.account_currency_id,CAST(e.cash_minor AS TEXT) FROM v_prepaid_events e JOIN v_prepaid_balances p ON p.id=e.project_id LEFT JOIN accounts a ON a.id=e.account_id WHERE p.book_id=? AND e.kind IN ('fund','refund') AND substr(e.local_date,1,7)=?",[this.activeBookId,month]);
      try { while (prepaidRows.goToNextRow()) {
        const context=prepaidEntryContext(prepaidRows.getString(13));
        const original=prepaidRows.getString(5); const book=prepaidRows.getString(6); const code=prepaidRows.getString(4);
        entries.push({ id:prepaidRows.getString(0),prepaidId:prepaidRows.getString(1),prepaidKind:prepaidRows.getString(2),
          prepaidStatus:prepaidRows.getString(2)==='refund' ? '预付款退款' : BigInt(prepaidRows.getString(14))===BigInt(0) ? '已结清' : '待核销',
          note:prepaidRows.getString(3),category:prepaidRows.getString(2)==='refund' ? '预付款退款' : '预付款',iconKey:'other',
          account:prepaidRows.getString(8),accountId:prepaidRows.getString(7),date:prepaidRows.getString(9),occurredAtMs:prepaidRows.getLong(10),offsetMinutes:prepaidRows.getLong(11),
          income:false,minor:book,grossMinor:context?.grossMinor || original,discountMinor:context?.discountMinor || '0',merchant:prepaidRows.getString(12),
          tagIds:context?.tagIds || [],tagNames:context?.tagNames || [],address:context?.addressText || '',location:context?.location,
          fx:{ currencyId:code,paidMinor:original,grossMinor:context?.grossMinor || original,discountMinor:context?.discountMinor || '0',bookMinor:book,
            accountCurrencyId:prepaidRows.getString(15),accountMinor:prepaidRows.getString(16) }
        });
      } } finally { prepaidRows.close(); }
      for (const entry of entries) {
        if (entry.prepaidId) { continue; }
        if (entry.recoveryKind) {
          const recovery = await db.querySql('SELECT transaction_id,currency_id,CAST(amount_minor AS TEXT),CAST(book_minor AS TEXT),account_currency_id,CAST(account_minor AS TEXT),fx_snapshot FROM v_expense_recoveries WHERE id=?', [entry.id]);
          try { if (recovery.goToFirstRow()) {
            const original = recovery.getString(2);
            const parentQuote = await RdbFxSnapshots.read(db,recovery.getString(0),'book');
            entry.fx = { currencyId: recovery.getString(1), paidMinor: original, grossMinor: original, discountMinor: '0',
              bookMinor: recovery.getString(3), accountCurrencyId: recovery.getString(4), accountMinor: recovery.getString(5),
              bookFx: parentQuote === undefined ? undefined : { rate: parentQuote.rate, source: parentQuote.source, date: parentQuote.date, actual: true },
              accountFx: recovery.getString(6) ? JSON.parse(recovery.getString(6)) as FxConversion : undefined };
          } } finally { recovery.close(); }
          continue;
        }
        const monetary = await db.querySql("SELECT t.currency_id,CAST(t.paid_minor AS TEXT),CAST(t.book_minor AS TEXT),COALESCE(m.currency_id,t.currency_id),CAST(COALESCE(abs(m.delta_minor),t.paid_minor) AS TEXT),COALESCE(d.to_currency_id,t.currency_id),CAST(COALESCE(d.in_minor,t.paid_minor) AS TEXT),CAST(COALESCE(d.book_fee_minor,0) AS TEXT) FROM transactions t LEFT JOIN account_movements m ON m.transaction_id=t.id AND m.leg=t.kind LEFT JOIN v_transfer_details d ON d.transaction_id=t.id WHERE t.id=?", [entry.id]);
        try {
          if (monetary.goToFirstRow()) {
            entry.fx = { currencyId: monetary.getString(0), paidMinor: monetary.getString(1), grossMinor: entry.grossMinor, discountMinor: entry.discountMinor,
              bookMinor: monetary.getString(2), accountCurrencyId: monetary.getString(3), accountMinor: monetary.getString(4),
              receivedCurrencyId: entry.transfer ? monetary.getString(5) : undefined, receivedMinor: entry.transfer ? monetary.getString(6) : undefined,
              bookFeeMinor: monetary.getString(7), bookFx: await RdbFxSnapshots.read(db,entry.id,'book'), accountFx: await RdbFxSnapshots.read(db,entry.id,'settlement') };
          }
        } finally { monetary.close(); }
      }
      entries.sort((a: SavedLedgerEntry, b: SavedLedgerEntry) => b.occurredAtMs - a.occurredAtMs || a.id.localeCompare(b.id));
      const usage = await db.querySql('SELECT CAST(COALESCE(SUM(amount_minor),0) AS TEXT) FROM v_budget_expense_flows WHERE book_id=? AND substr(local_date,1,7)=?', [this.activeBookId, month]);
      try { usage.goToFirstRow(); budgetUsed = BigInt(usage.getString(0)); } finally { usage.close(); }
      const tagNames: Map<string, string[]> = new Map();
      const tagIds: Map<string, string[]> = new Map();
      const entryTagRows = await db.querySql('SELECT tt.transaction_id,g.id,g.name FROM transaction_tags tt ' +
        'JOIN tags g ON g.id=tt.tag_id JOIN v_posted_transactions tx ON tx.id=tt.transaction_id ' +
        'WHERE tt.book_id=? AND (substr(tx.occurred_local_date,1,7)=? OR EXISTS(SELECT 1 FROM v_expense_recoveries r WHERE r.transaction_id=tx.id AND substr(r.local_date,1,7)=?)) ORDER BY g.sort_order,g.created_at_ms,g.id',
        [this.activeBookId, month, month]);
      try {
        while (entryTagRows.goToNextRow()) {
          const transactionId = entryTagRows.getString(0);
          const ids = tagIds.get(transactionId) || [];
          const names = tagNames.get(transactionId) || [];
          ids.push(entryTagRows.getString(1));
          names.push(entryTagRows.getString(2));
          tagIds.set(transactionId, ids);
          tagNames.set(transactionId, names);
        }
      } finally { entryTagRows.close(); }
      for (const entry of entries) {
        if (entry.prepaidId) { continue; }
        entry.tagIds = tagIds.get(entry.originalEntryId || entry.id) || [];
        entry.tagNames = tagNames.get(entry.originalEntryId || entry.id) || [];
        entry.attachments = [];
      }
      const entryAttachments: Map<string, LedgerAttachmentDraft[]> = new Map();
      const attachmentRows = await db.querySql('SELECT ta.transaction_id,a.relative_path,a.content_sha256,' +
        'a.byte_size,a.mime_type FROM transaction_attachments ta JOIN attachments a ON a.id=ta.attachment_id ' +
        'JOIN v_posted_transactions tx ON tx.id=ta.transaction_id WHERE tx.book_id=? ' +
        'AND substr(tx.occurred_local_date,1,7)=? AND a.state=\'ready\' AND a.deleted_at_ms IS NULL ' +
        'ORDER BY ta.transaction_id,ta.sort_order', [this.activeBookId, month]);
      try {
        while (attachmentRows.goToNextRow()) {
          const transactionId = attachmentRows.getString(0);
          const values = entryAttachments.get(transactionId) || [];
          values.push({ relativePath: attachmentRows.getString(1), sha256: attachmentRows.getString(2),
            bytes: attachmentRows.getLong(3), mimeType: attachmentRows.getString(4) });
          entryAttachments.set(transactionId, values);
        }
      } finally { attachmentRows.close(); }
      for (const entry of entries) {
        entry.attachments = entryAttachments.get(entry.id) || [];
      }
      let budgetTotal: string = DEFAULT_MONTHLY_BUDGET_MINOR;
      let budgetId: string = '';
      const budget = await db.querySql('SELECT id,CAST(total_minor AS TEXT),currency_id FROM budgets WHERE book_id=? AND period_start_date=? AND period_end_date_exclusive=? AND deleted_at_ms IS NULL',
        [this.activeBookId, period.start, period.endExclusive]);
      try {
        if (budget.goToFirstRow()) {
          if (budget.getString(2) !== this.currency.id) { throw new Error('CURRENCY_MISMATCH'); }
          budgetId = budget.getString(0); budgetTotal = budget.getString(1);
        }
      } finally { budget.close(); }
      const budgetNatureLines: BudgetNatureLine[] = [];
      const lines = await db.querySql('SELECT n.id,n.name,COALESCE(n.custom_color,n.color_token),CAST(COALESCE(l.amount_minor,0) AS TEXT),' +
        "CAST(COALESCE((SELECT SUM(t.amount_minor) FROM v_budget_expense_flows t WHERE t.spending_nature_id=n.id AND t.book_id=? AND substr(t.local_date,1,7)=?),0) AS TEXT)," +
        'n.archived_at_ms FROM spending_natures n LEFT JOIN budget_nature_lines l ON l.spending_nature_id=n.id AND l.budget_id=? ' +
        'WHERE n.deleted_at_ms IS NULL AND (n.archived_at_ms IS NULL OR l.id IS NOT NULL OR EXISTS(SELECT 1 FROM v_budget_expense_flows f WHERE f.spending_nature_id=n.id AND f.book_id=? AND substr(f.local_date,1,7)=?)) ORDER BY n.sort_order,n.created_at_ms,n.id',
        [this.activeBookId, month, budgetId, this.activeBookId, month]);
      try {
        while (lines.goToNextRow()) {
          budgetNatureLines.push({ natureId: lines.getString(0), name: lines.getString(1), colorKey: lines.getString(2),
            amountMinor: lines.getString(3), usedMinor: lines.getString(4), archived: !lines.isColumnNull(5) });
        }
      } finally { lines.close(); }
      return { bookId: this.activeBookId, bookName: bookName, categories: categories, incomeCategories: incomeCategories,
        spendingNatures: spendingNatures, tags: tags, budgetNatureLines: budgetNatureLines, accounts: accounts,
        entries: entries, incomeMinor: income.toString(), expenseMinor: expense.toString(),
        budgetTotalMinor: budgetTotal, budgetUsedMinor: budgetUsed.toString() };
    });
  }
}
