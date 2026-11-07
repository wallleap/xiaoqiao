import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { Money } from '../../../main/ets/core/money/Money';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { ExpenseCommand } from '../../../main/ets/domain/model/ExpenseRecord';
import { BudgetNatureLine } from '../../../main/ets/domain/model/SpendingNature';
import { REVIEW_SCHEMA_SHA256, REVIEW_SCHEMA_STATEMENTS } from '../../../main/ets/data/rdb/ReviewSchema';
import { RdbSession } from '../../../main/ets/data/rdb/RdbSession';
import { TransferMigration } from '../../../main/ets/data/rdb/TransferMigration';
import { SpendingNatureMigration } from '../../../main/ets/data/rdb/SpendingNatureMigration';
import { BudgetNatureMigration } from '../../../main/ets/data/rdb/BudgetNatureMigration';

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

function expense(workspace: LedgerWorkspace, id: string, amountText: string, nature?: string): ExpenseCommand {
  const date = new Date(2027, 2, 8, 12, 0);
  const amount = Money.parse(amountText, workspace.currency);
  return { id: id, bookId: DEFAULT_BOOK_ID, categoryId: 'expense-food', gross: amount,
    discount: Money.parse('0.00', workspace.currency), bookPaid: amount, includeInAssets: false, includeInBudget: true,
    spendingNatureId: nature, note: '分类预算测试', occurredAtMs: date.getTime(),
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, localDate: '2027-03-08', offsetMinutes: -date.getTimezoneOffset() };
}

export default function budgetNatureTest() {
  describe('BudgetNature', () => {
    it('rolls_back_v4_schema_when_marker_insert_fails', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_app_test_budget_closed_loop_' + util.generateRandomUUID() + '.db';
      try {
        const db = await relationalStore.getRdbStore(host, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
        await RdbSession.forStore(db).write(async (store: relationalStore.RdbStore): Promise<void> => {
          for (const sql of REVIEW_SCHEMA_STATEMENTS) { if (!sql.startsWith('PRAGMA')) { await store.executeSql(sql); } }
          await store.insert('db_meta', { key: 'schema_checksum', value: REVIEW_SCHEMA_SHA256 });
          await store.insert('schema_migrations', { version: 1, checksum: REVIEW_SCHEMA_SHA256, applied_at_ms: 1 });
          await store.insert('currencies', { id: 'CNY', code: 'CNY', name: '人民币', symbol: '¥', minor_unit: 2,
            valid_from: '2026-01-01', source_version: 'test' });
          await store.insert('books', { id: DEFAULT_BOOK_ID, name: '测试账本', base_currency_id: 'CNY',
            timezone: 'Asia/Shanghai', created_at_ms: 1, updated_at_ms: 1 });
          await TransferMigration.apply(store, '', false);
          await SpendingNatureMigration.apply(store, '', false);
          await store.executeSql("CREATE TRIGGER reject_v4 BEFORE INSERT ON schema_migrations WHEN NEW.version=4 BEGIN SELECT RAISE(ABORT,'late v4 failure'); END");
        });
        let rejected = false;
        try { await BudgetNatureMigration.upgradeCandidate(db); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        expect(await BudgetNatureMigration.status(db)).assertEqual(3);
        const table = await db.querySql("SELECT name FROM sqlite_master WHERE type='table' AND name='budget_nature_lines'");
        try { expect(table.rowCount).assertEqual(0); } finally { table.close(); }
        await db.close();
      } finally {
        await relationalStore.deleteRdbStore(host, name);
      }
    });

    it('allocates_monthly_budget_by_nature_and_tracks_usage', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_app_test_budget_nature_' + util.generateRandomUUID() + '.db';
      try {
        const workspace = await LedgerWorkspace.open(host, name);
        await workspace.setMonthlyBudget('2027-03', '3000');
        await workspace.setBudgetNatureAmount('2027-03', 'nature-survival', '1000');
        await workspace.setBudgetNatureAmount('2027-03', 'nature-growth', '1200');
        await workspace.saveExpense(expense(workspace, 'survival-expense', '300', 'nature-survival'));
        await workspace.saveExpense(expense(workspace, 'growth-expense', '200', 'nature-growth'));
        await workspace.saveExpense(expense(workspace, 'unassigned-expense', '100'));
        let snapshot = await workspace.snapshot('2027-03');
        expect(snapshot.budgetTotalMinor).assertEqual('300000');
        expect(snapshot.budgetUsedMinor).assertEqual('60000');
        let survival = snapshot.budgetNatureLines.find((line: BudgetNatureLine) => line.natureId === 'nature-survival');
        let growth = snapshot.budgetNatureLines.find((line: BudgetNatureLine) => line.natureId === 'nature-growth');
        expect(survival === undefined ? '' : survival.amountMinor).assertEqual('100000');
        expect(survival === undefined ? '' : survival.usedMinor).assertEqual('30000');
        expect(growth === undefined ? '' : growth.amountMinor).assertEqual('120000');
        expect(growth === undefined ? '' : growth.usedMinor).assertEqual('20000');
        let exceeded = false;
        try { await workspace.setBudgetNatureAmount('2027-03', 'nature-experience', '1000'); } catch (_) { exceeded = true; }
        expect(exceeded).assertTrue();
        let totalTooLow = false;
        try { await workspace.setMonthlyBudget('2027-03', '2000'); } catch (_) { totalTooLow = true; }
        expect(totalTooLow).assertTrue();
        await workspace.setBudgetNatureAmount('2027-03', 'nature-survival', '700');
        await workspace.setMonthlyBudget('2027-03', '2000');
        await workspace.setBudgetNatureAmount('2027-03', 'nature-growth', '0');
        snapshot = await workspace.snapshot('2027-03');
        survival = snapshot.budgetNatureLines.find((line: BudgetNatureLine) => line.natureId === 'nature-survival');
        growth = snapshot.budgetNatureLines.find((line: BudgetNatureLine) => line.natureId === 'nature-growth');
        expect(snapshot.budgetTotalMinor).assertEqual('200000');
        expect(survival === undefined ? '' : survival.amountMinor).assertEqual('70000');
        expect(growth === undefined ? '' : growth.amountMinor).assertEqual('0');
      } finally {
        await LedgerWorkspace.close(name);
        await relationalStore.deleteRdbStore(host, name);
      }
    });
  });
}
