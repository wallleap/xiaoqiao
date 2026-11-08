import { LedgerBackupPackage } from '../backup/LedgerBackupPackage';
import { AccountCalibrationCommand, AdjustmentCursor, AdjustmentPage } from '../../domain/model/AccountCalibration';
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
import { ExpenseCategory, LedgerAccount, LedgerSnapshot, SavedLedgerEntry, SpendingNatureChoice,
  TagChoice } from '../../domain/model/LedgerSnapshot';
import { RecordExpense } from '../../domain/services/RecordExpense';
import { UpdateExpense } from '../../domain/services/UpdateExpense';
import { EntryDetail } from '../../domain/model/EntryDetail';
import { MonthlyBudget, DEFAULT_MONTHLY_BUDGET_MINOR } from '../../domain/model/MonthlyBudget';
import { LedgerBook, ValidatedLedgerBook } from '../../domain/model/LedgerBook';
import { BudgetNatureLine, SpendingNatureCommand, SpendingNatureProfile, ValidatedSpendingNature } from '../../domain/model/SpendingNature';
import { CategoryCommand, CategoryProfile, ValidatedCategory } from '../../domain/model/CategoryProfile';
import { TagCommand, TagProfile, ValidatedTag } from '../../domain/model/TagProfile';
import { LedgerDatabase, DEFAULT_BOOK_ID } from './LedgerDatabase';
import { RdbLedgerRepository } from './RdbLedgerRepository';
import { RdbSession } from './RdbSession';
import { LocalLedgerBackup } from './LocalLedgerBackup';
import { RdbStatisticsRepository } from './RdbStatisticsRepository';
import { LedgerStatistics, StatisticsBucketUnit, StatisticsEntry, StatisticsKind } from '../../domain/model/LedgerStatistics';

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

  async saveExpense(command: ExpenseCommand): Promise<void> { await this.writer.execute(command); }

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
      const rows = await db.querySql('SELECT id,name,color_token,built_in,sort_order,revision,archived_at_ms FROM spending_natures WHERE deleted_at_ms IS NULL ORDER BY archived_at_ms IS NOT NULL,sort_order,created_at_ms,id');
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
      await db.insert('spending_natures', { id: draft.id, name: draft.name, name_key: draft.name, color_token: draft.colorKey,
        built_in: 0, sort_order: sortOrder, created_at_ms: now, updated_at_ms: now });
    });
  }

  async updateSpendingNature(command: SpendingNatureCommand, revision: number): Promise<void> {
    const draft = new ValidatedSpendingNature(command).command;
    if (!Number.isSafeInteger(revision) || revision < 1 || revision >= Number.MAX_SAFE_INTEGER) { throw new Error('INVALID_EXPECTED_REVISION'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const duplicate = await db.querySql('SELECT id FROM spending_natures WHERE id<>? AND deleted_at_ms IS NULL AND name_key=? LIMIT 1',
        [draft.id, draft.name]);
      try { if (duplicate.goToFirstRow()) { throw new Error('SPENDING_NATURE_NAME_EXISTS'); } } finally { duplicate.close(); }
      const changed = await db.update({ name: draft.name, name_key: draft.name, color_token: draft.colorKey,
        updated_at_ms: Date.now(), revision: revision + 1 }, new relationalStore.RdbPredicates('spending_natures')
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
    await this.updater.execute(command, expectedRevision);
  }

  async accountOverview(): Promise<AccountOverview> { return this.accountRepository.snapshot(); }
  async calibrateAccount(command: AccountCalibrationCommand): Promise<void> { await this.accountRepository.calibrate(command); }
  async accountAdjustments(id: string, cursor: AdjustmentCursor | undefined = undefined): Promise<AdjustmentPage> { return this.accountRepository.adjustmentHistory(id, cursor); }
  async createAccount(command: AccountCommand): Promise<void> { await this.accountRepository.create(command); }
  async updateAccount(command: AccountCommand, revision: number): Promise<void> { await this.accountRepository.update(command, revision); }
  async archiveAccount(id: string, revision: number, archived: boolean): Promise<void> { await this.accountRepository.archive(id, revision, archived); }

  async saveTransfer(command: TransferCommand): Promise<void> { await this.transfer.save(command); }
  async updateTransfer(command: TransferCommand, revision: number): Promise<void> { await this.transfer.update(command, revision); }

  async saveIncome(command: IncomeCommand): Promise<void> { await this.income.save(command); }
  async updateIncome(command: IncomeCommand, revision: number): Promise<void> { await this.income.update(command, revision); }

  async statistics(startDate: string, endDateExclusive: string, kind: StatisticsKind,
    unit: StatisticsBucketUnit): Promise<LedgerStatistics> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<LedgerStatistics> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      return this.statisticsRepository.snapshot(this.activeBookId, startDate, endDateExclusive, kind, unit);
    });
  }

  async statisticsEntries(startDate: string, endDateExclusive: string, kind: StatisticsKind,
    categoryKey: string): Promise<StatisticsEntry[]> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<StatisticsEntry[]> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      return this.statisticsRepository.entries(this.activeBookId, startDate, endDateExclusive, kind, categoryKey);
    });
  }

  async entryDetail(id: string): Promise<EntryDetail> {
    if (id.trim().length === 0) { throw new Error('INVALID_TRANSACTION_ID'); }
    return this.session.read(async (db: relationalStore.RdbStore): Promise<EntryDetail> => {
      this.activeBookId = await this.activeBookFromMeta(db);
      const rows = await db.querySql("SELECT t.id,t.book_id,b.name,t.kind,t.revision,COALESCE(t.category_id,''),COALESCE(c.name,'转账'),COALESCE(c.icon_key,'other'),COALESCE(m.account_id,d.from_account_id,''),COALESCE(a.name,''),t.currency_id,u.code,u.symbol,u.minor_unit,CAST(t.gross_minor AS TEXT),CAST(t.discount_minor AS TEXT),CAST(t.paid_minor AS TEXT),CAST(COALESCE(t.book_minor,t.paid_minor) AS TEXT),t.include_in_budget,t.include_in_assets,t.balance_mode,t.occurred_at_ms,t.occurred_local_date,t.occurred_timezone,t.occurred_offset_minutes,t.note,t.book_currency_id,COALESCE(m.currency_id,t.currency_id),(SELECT COUNT(*) FROM fx_snapshots WHERE transaction_id=t.id),COALESCE(mi.account_id,''),COALESCE(ai.name,''),COALESCE(mi.currency_id,t.currency_id),t.group_id,COALESCE(d.purpose,'transfer'),CAST(COALESCE(d.out_minor,t.paid_minor) AS TEXT),CAST(COALESCE(d.in_minor,t.paid_minor) AS TEXT),CAST(COALESCE(d.fee_minor,0) AS TEXT),CAST(COALESCE(d.coupon_minor,0) AS TEXT),COALESCE(d.fee_in_expense,1),COALESCE(d.fee_in_budget,1),COALESCE(a.kind,'asset'),COALESCE(ai.kind,'asset'),COALESCE(nt.spending_nature_id,''),COALESCE(n.name,''),COALESCE(n.color_token,'') FROM v_posted_transactions t JOIN transactions nt ON nt.id=t.id JOIN books b ON b.id=t.book_id JOIN currencies u ON u.id=t.currency_id LEFT JOIN categories c ON c.id=t.category_id LEFT JOIN spending_natures n ON n.id=nt.spending_nature_id LEFT JOIN transfer_details d ON d.transaction_id=t.id LEFT JOIN account_movements m ON m.transaction_id=t.id AND m.leg<>'transfer_in' LEFT JOIN accounts a ON a.id=COALESCE(m.account_id,d.from_account_id) LEFT JOIN account_movements mi ON mi.transaction_id=t.id AND mi.leg='transfer_in' LEFT JOIN accounts ai ON ai.id=mi.account_id WHERE t.id=? AND t.book_id=?",
        [id, this.activeBookId]);
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
          feeInExpense: rows.getLong(38) === 1, feeInBudget: rows.getLong(39) === 1, accountKind: rows.getString(40), toAccountKind: rows.getString(41),
          spendingNatureId: rows.getString(42), spendingNatureName: rows.getString(43), spendingNatureColor: rows.getString(44), canEdit: canEdit };
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
      const tags: TagChoice[] = [];
      const tagRows = await db.querySql('SELECT g.id,g.name,COALESCE(g.color_token,\'neutral\') FROM transaction_tags tt ' +
        'JOIN tags g ON g.id=tt.tag_id WHERE tt.transaction_id=? ORDER BY g.sort_order,g.created_at_ms,g.id', [detail.id]);
      try {
        while (tagRows.goToNextRow()) {
          tags.push({ id: tagRows.getString(0), name: tagRows.getString(1), colorKey: tagRows.getString(2) });
        }
      } finally { tagRows.close(); }
      detail.tags = tags;
      return detail;
    });
  }

  /** Deletes exactly one posted entry in this workspace. Movements remain as history. */
  async deleteEntry(id: string): Promise<void> {
    if (id.trim().length === 0) { throw new Error('INVALID_TRANSACTION_ID'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      this.activeBookId = await this.activeBookFromMeta(db);
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
      const natureRows = await db.querySql('SELECT id,name,color_token FROM spending_natures WHERE deleted_at_ms IS NULL AND archived_at_ms IS NULL ORDER BY sort_order,created_at_ms,id');
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
      const rows = await db.querySql("SELECT t.id,t.note,CASE WHEN t.kind='transfer' THEN CASE d.purpose WHEN 'credit_repayment' THEN '信用卡还款' WHEN 'loan_repayment' THEN '借款还款' WHEN 'topup' THEN '充值' WHEN 'withdrawal' THEN '提现' ELSE '转账' END ELSE c.name END,COALESCE(c.icon_key,'transfer'),COALESCE(a.name,'不使用账户'),t.occurred_local_date,t.occurred_at_ms,t.occurred_offset_minutes,t.kind,CAST(COALESCE(t.book_minor,t.paid_minor) AS TEXT),t.include_in_budget,CAST(t.gross_minor AS TEXT),CAST(t.discount_minor AS TEXT),COALESCE(ai.name,''),CAST(COALESCE(d.out_minor,t.paid_minor) AS TEXT),CAST(COALESCE(d.fee_minor,0) AS TEXT),CAST(COALESCE(d.coupon_minor,0) AS TEXT),COALESCE(d.purpose,'transfer'),COALESCE(d.fee_in_expense,1),COALESCE(d.fee_in_budget,1) FROM transactions t LEFT JOIN categories c ON c.id=t.category_id LEFT JOIN transfer_details d ON d.transaction_id=t.id LEFT JOIN account_movements m ON m.transaction_id=t.id AND m.leg<>'transfer_in' LEFT JOIN accounts a ON a.id=COALESCE(m.account_id,d.from_account_id) LEFT JOIN account_movements mi ON mi.transaction_id=t.id AND mi.leg='transfer_in' LEFT JOIN accounts ai ON ai.id=mi.account_id WHERE t.book_id=? AND t.posting_state='posted' AND t.deleted_at_ms IS NULL AND (t.import_batch_id IS NULL OR EXISTS(SELECT 1 FROM import_batches b WHERE b.id=t.import_batch_id AND b.status='committed')) AND (t.kind IN ('expense','income') OR (t.kind='transfer' AND t.currency_id='CNY' AND NOT EXISTS(SELECT 1 FROM account_movements x WHERE x.transaction_id=t.id AND x.currency_id<>'CNY'))) AND substr(t.occurred_local_date,1,7)=? ORDER BY t.occurred_at_ms DESC,t.created_at_ms DESC,t.id DESC", [this.activeBookId, month]);
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
      const tagNames: Map<string, string[]> = new Map();
      const tagIds: Map<string, string[]> = new Map();
      const entryTagRows = await db.querySql('SELECT tt.transaction_id,g.id,g.name FROM transaction_tags tt ' +
        'JOIN tags g ON g.id=tt.tag_id JOIN v_posted_transactions tx ON tx.id=tt.transaction_id ' +
        'WHERE tt.book_id=? AND substr(tx.occurred_local_date,1,7)=? ORDER BY g.sort_order,g.created_at_ms,g.id',
        [this.activeBookId, month]);
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
        entry.tagIds = tagIds.get(entry.id) || [];
        entry.tagNames = tagNames.get(entry.id) || [];
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
      const lines = await db.querySql('SELECT n.id,n.name,n.color_token,CAST(COALESCE(l.amount_minor,0) AS TEXT),' +
        "CAST(COALESCE((SELECT SUM(t.book_minor) FROM v_posted_transactions t JOIN transactions raw ON raw.id=t.id WHERE raw.spending_nature_id=n.id AND t.book_id=? AND t.kind='expense' AND t.include_in_budget=1 AND substr(t.occurred_local_date,1,7)=?),0) AS TEXT)," +
        'n.archived_at_ms FROM spending_natures n LEFT JOIN budget_nature_lines l ON l.spending_nature_id=n.id AND l.budget_id=? ' +
        'WHERE n.deleted_at_ms IS NULL AND (n.archived_at_ms IS NULL OR l.id IS NOT NULL) ORDER BY n.sort_order,n.created_at_ms,n.id',
        [this.activeBookId, month, budgetId]);
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
