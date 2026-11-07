import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { Money } from '../../../main/ets/core/money/Money';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { ExpenseCommand } from '../../../main/ets/domain/model/ExpenseRecord';
import { SpendingNatureProfile } from '../../../main/ets/domain/model/SpendingNature';
import { REVIEW_SCHEMA_SHA256, REVIEW_SCHEMA_STATEMENTS } from '../../../main/ets/data/rdb/ReviewSchema';
import { RdbSession } from '../../../main/ets/data/rdb/RdbSession';
import { SpendingNatureMigration } from '../../../main/ets/data/rdb/SpendingNatureMigration';
import { TransferMigration } from '../../../main/ets/data/rdb/TransferMigration';

let cachedContext: common.UIAbilityContext | undefined = undefined;

async function testContext(): Promise<common.UIAbilityContext> {
  if (cachedContext !== undefined) { return cachedContext; }
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  try {
    cachedContext = (await delegator.getCurrentTopAbility()).context;
    return cachedContext;
  } catch (_) { /* Class-only execution can start before EntryAbility is on top. */ }
  const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
  await delegator.addAbilityMonitor(monitor);
  try {
    await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
    cachedContext = (await delegator.waitAbilityMonitor(monitor, 10000)).context;
    return cachedContext;
  } finally { await delegator.removeAbilityMonitor(monitor); }
}

function expense(workspace: LedgerWorkspace, nature: string, id: string): ExpenseCommand {
  const date = new Date(2027, 1, 12, 10, 20);
  const amount = Money.parse('25.00', workspace.currency);
  return { id: id, bookId: DEFAULT_BOOK_ID, categoryId: 'expense-food', gross: amount,
    discount: Money.parse('0.00', workspace.currency), bookPaid: amount, includeInAssets: false, includeInBudget: true,
    spendingNatureId: nature, note: '支出性质测试', occurredAtMs: date.getTime(),
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, localDate: '2027-02-12', offsetMinutes: -date.getTimezoneOffset() };
}

export default function spendingNatureTest() {
  describe('SpendingNature', () => {
    it('upgrades_v2_database_without_rewriting_existing_transaction', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_app_test_nature_migration_' + util.generateRandomUUID() + '.db';
      try {
        const db = await relationalStore.getRdbStore(host, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
        await RdbSession.forStore(db).write(async (store: relationalStore.RdbStore): Promise<void> => {
          for (const sql of REVIEW_SCHEMA_STATEMENTS) { if (!sql.startsWith('PRAGMA')) { await store.executeSql(sql); } }
          await store.insert('db_meta', { key: 'schema_checksum', value: REVIEW_SCHEMA_SHA256 });
          await store.insert('schema_migrations', { version: 1, checksum: REVIEW_SCHEMA_SHA256, applied_at_ms: 1 });
          await store.insert('currencies', { id: 'CNY', code: 'CNY', name: '人民币', symbol: '¥', minor_unit: 2,
            valid_from: '2026-01-01', source_version: 'test' });
          await store.insert('books', { id: DEFAULT_BOOK_ID, name: '旧账本', base_currency_id: 'CNY',
            timezone: 'Asia/Shanghai', created_at_ms: 1, updated_at_ms: 1 });
          await TransferMigration.apply(store, '', false);
          await store.insert('categories', { id: 'legacy-category', book_id: DEFAULT_BOOK_ID, kind: 'expense',
            name: '旧分类', name_key: '旧分类', created_at_ms: 1, updated_at_ms: 1 });
          await store.insert('transactions', { id: 'legacy-expense', book_id: DEFAULT_BOOK_ID, kind: 'expense',
            category_id: 'legacy-category', currency_id: 'CNY', gross_minor: 1000, discount_minor: 0, paid_minor: 1000,
            book_currency_id: 'CNY', book_minor: 1000, include_in_assets: 0, include_in_budget: 1,
            occurred_at_ms: 1, occurred_local_date: '1970-01-01', occurred_timezone: 'UTC', occurred_offset_minutes: 0,
            created_at_ms: 1, updated_at_ms: 1 });
          await store.executeSql("UPDATE transactions SET posting_state='posted' WHERE id='legacy-expense'");
        });
        expect(await SpendingNatureMigration.status(db)).assertEqual(2);
        await SpendingNatureMigration.upgradeCandidate(db);
        expect(await SpendingNatureMigration.status(db)).assertEqual(3);
        const rows = await db.querySql("SELECT COUNT(*),COUNT(spending_nature_id) FROM transactions WHERE id='legacy-expense'");
        try { expect(rows.goToFirstRow()).assertTrue(); expect(rows.getLong(0)).assertEqual(1); expect(rows.getLong(1)).assertEqual(0); }
        finally { rows.close(); }
        await db.close();
      } finally {
        await relationalStore.deleteRdbStore(host, name);
      }
    });

    it('rolls_back_v3_schema_and_marker_when_migration_marker_write_fails', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_app_test_nature_failure_' + util.generateRandomUUID() + '.db';
      try {
        const db = await relationalStore.getRdbStore(host, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
        await RdbSession.forStore(db).write(async (store: relationalStore.RdbStore): Promise<void> => {
          for (const sql of REVIEW_SCHEMA_STATEMENTS) { if (!sql.startsWith('PRAGMA')) { await store.executeSql(sql); } }
          await store.insert('db_meta', { key: 'schema_checksum', value: REVIEW_SCHEMA_SHA256 });
          await store.insert('schema_migrations', { version: 1, checksum: REVIEW_SCHEMA_SHA256, applied_at_ms: 1 });
          await store.insert('currencies', { id: 'CNY', code: 'CNY', name: '人民币', symbol: '¥', minor_unit: 2,
            valid_from: '2026-01-01', source_version: 'test' });
          await store.insert('books', { id: DEFAULT_BOOK_ID, name: '旧账本', base_currency_id: 'CNY',
            timezone: 'Asia/Shanghai', created_at_ms: 1, updated_at_ms: 1 });
          await TransferMigration.apply(store, '', false);
          await store.executeSql("CREATE TRIGGER reject_v3 BEFORE INSERT ON schema_migrations WHEN NEW.version=3 BEGIN SELECT RAISE(ABORT,'late v3 failure'); END");
        });
        let rejected = false;
        try { await SpendingNatureMigration.upgradeCandidate(db); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        expect(await SpendingNatureMigration.status(db)).assertEqual(2);
        const table = await db.querySql("SELECT name FROM sqlite_master WHERE type='table' AND name='spending_natures'");
        try { expect(table.rowCount).assertEqual(0); } finally { table.close(); }
        const columns = await db.querySql("PRAGMA table_info('transactions')");
        let hasColumn = false;
        try {
          while (columns.goToNextRow()) { if (columns.getString(1) === 'spending_nature_id') { hasColumn = true; } }
        } finally { columns.close(); }
        expect(hasColumn).assertFalse();
        await db.close();
      } finally {
        await relationalStore.deleteRdbStore(host, name);
      }
    });

    it('seeds_builtins_manages_custom_values_and_round_trips_transaction_nature', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_app_test_nature_' + util.generateRandomUUID() + '.db';
      try {
        const workspace = await LedgerWorkspace.open(host, name);
        let values = await workspace.spendingNatures();
        expect(values.length).assertEqual(4);
        expect(values.filter((item: SpendingNatureProfile) => item.builtIn).length).assertEqual(4);
        await workspace.createSpendingNature({ id: 'nature-health', name: '健康投入', colorKey: 'calm' });
        let custom = (await workspace.spendingNatures()).find((item: SpendingNatureProfile) => item.id === 'nature-health');
        expect(custom === undefined ? '' : custom.name).assertEqual('健康投入');
        expect(custom === undefined ? 0 : custom.revision).assertEqual(1);
        await workspace.updateSpendingNature({ id: 'nature-health', name: '健康与运动', colorKey: 'social' }, 1);
        custom = (await workspace.spendingNatures()).find((item: SpendingNatureProfile) => item.id === 'nature-health');
        expect(custom === undefined ? '' : custom.name).assertEqual('健康与运动');
        expect(custom === undefined ? 0 : custom.revision).assertEqual(2);

        await workspace.saveExpense(expense(workspace, 'nature-health', 'nature-expense'));
        let detail = await workspace.entryDetail('nature-expense');
        expect(detail.spendingNatureId).assertEqual('nature-health');
        expect(detail.spendingNatureName).assertEqual('健康与运动');
        expect(detail.spendingNatureColor).assertEqual('social');
        await workspace.updateExpense(expense(workspace, 'nature-growth', 'nature-expense'), 1);
        detail = await workspace.entryDetail('nature-expense');
        expect(detail.spendingNatureId).assertEqual('nature-growth');
        expect(detail.spendingNatureName).assertEqual('成长提升');

        await workspace.archiveSpendingNature('nature-health', 2, true);
        values = await workspace.spendingNatures();
        custom = values.find((item: SpendingNatureProfile) => item.id === 'nature-health');
        expect(custom === undefined ? false : custom.archived).assertTrue();
        expect((await workspace.snapshot('2027-02')).spendingNatures.some((item) => item.id === 'nature-health')).assertFalse();
        await workspace.archiveSpendingNature('nature-health', 3, false);
        expect((await workspace.snapshot('2027-02')).spendingNatures.some((item) => item.id === 'nature-health')).assertTrue();

        let duplicate = false;
        try { await workspace.createSpendingNature({ id: 'nature-duplicate', name: '成长提升', colorKey: 'growth' }); }
        catch (_) { duplicate = true; }
        expect(duplicate).assertTrue();
        let invalid = false;
        try { await workspace.saveExpense(expense(workspace, 'missing-nature', 'invalid-nature')); } catch (_) { invalid = true; }
        expect(invalid).assertTrue();
      } finally {
        await LedgerWorkspace.close(name);
        await relationalStore.deleteRdbStore(host, name);
      }
    });
  });
}
