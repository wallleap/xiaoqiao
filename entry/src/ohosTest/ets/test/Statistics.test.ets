import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { Money } from '../../../main/ets/core/money/Money';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { ExpenseCommand } from '../../../main/ets/domain/model/ExpenseRecord';
import { IncomeCommand } from '../../../main/ets/domain/model/IncomeRecord';
import { TransferCommand } from '../../../main/ets/domain/model/TransferRecord';

async function testContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  try { return (await delegator.getCurrentTopAbility()).context; }
  catch (_) { /* Class-only execution can start before EntryAbility is on top. */ }
  const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
  await delegator.addAbilityMonitor(monitor);
  try {
    await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
    return (await delegator.waitAbilityMonitor(monitor, 10000)).context;
  } finally { await delegator.removeAbilityMonitor(monitor); }
}

function wallDate(value: string): Date {
  const parts = value.split('-');
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0, 0);
}

function expense(workspace: LedgerWorkspace, id: string, date: string, categoryId: string, amount: string,
  budget: boolean): ExpenseCommand {
  const occurred = wallDate(date);
  const money = Money.parse(amount, workspace.currency);
  return { id: id, bookId: DEFAULT_BOOK_ID, categoryId: categoryId, gross: money,
    discount: Money.parse('0', workspace.currency), bookPaid: money,
    includeInAssets: false, includeInBudget: budget,
    spendingNatureId: budget ? 'nature-survival' : undefined,
    note: id, occurredAtMs: occurred.getTime(), localDate: date,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -occurred.getTimezoneOffset() };
}

function income(workspace: LedgerWorkspace, id: string, date: string): IncomeCommand {
  const occurred = wallDate(date);
  const money = Money.parse('30', workspace.currency);
  return { id: id, bookId: DEFAULT_BOOK_ID, categoryId: 'income-salary', amount: money, bookAmount: money,
    includeInAssets: false, note: id, occurredAtMs: occurred.getTime(), localDate: date,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -occurred.getTimezoneOffset() };
}

function transfer(workspace: LedgerWorkspace, date: string): TransferCommand {
  const occurred = wallDate(date);
  return { id: 'stat-transfer', bookId: DEFAULT_BOOK_ID, fromAccountId: 'stat-a', toAccountId: 'stat-b',
    amount: Money.parse('1', workspace.currency), fee: Money.parse('0.05', workspace.currency),
    feeInBudget: true, includeInAssets: true, note: '转账不应计入本金',
    occurredAtMs: occurred.getTime(), localDate: date,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -occurred.getTimezoneOffset() };
}

export default function statisticsTest() {
  describe('Statistics', () => {
    it('aggregates_period_trends_root_categories_budget_categories_and_fee_only', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_app_test_statistics_' + util.generateRandomUUID() + '.db';
      try {
        const workspace = await LedgerWorkspace.open(host, name);
        await workspace.createAccount({ id: 'stat-a', name: '统计钱包', kind: 'asset', styleKey: 'cash',
          includeInNetAssets: true, opening: Money.parse('100', workspace.currency) });
        await workspace.createAccount({ id: 'stat-b', name: '统计储蓄', kind: 'asset', styleKey: 'cash',
          includeInNetAssets: true, opening: Money.parse('0', workspace.currency) });
        await workspace.saveExpense(expense(workspace, 'stat-food', '2027-01-05', 'expense-food-0', '10', true));
        await workspace.saveExpense(expense(workspace, 'stat-transport', '2027-01-06', 'expense-transport', '5', false));
        await workspace.saveIncome(income(workspace, 'stat-income', '2027-01-07'));
        await workspace.saveTransfer(transfer(workspace, '2027-01-08'));

        const expenseStats = await workspace.statistics('2027-01-01', '2027-02-01', 'expense', 'day');
        expect(expenseStats.totalMinor).assertEqual('1505');
        expect(expenseStats.buckets.length).assertEqual(31);
        expect(expenseStats.buckets.find((item) => item.key === '2027-01-05')?.amountMinor).assertEqual('1000');
        expect(expenseStats.buckets.find((item) => item.key === '2027-01-08')?.amountMinor).assertEqual('5');
        const food = expenseStats.categories.find((item) => item.key === 'expense-food');
        expect(food?.amountMinor).assertEqual('1000');
        expect(expenseStats.categories.find((item) => item.key === 'expense-transport')?.amountMinor).assertEqual('500');
        const fee = expenseStats.categories.find((item) => item.key === 'transfer_fee');
        expect(fee?.amountMinor).assertEqual('5');
        expect(expenseStats.categories.some((item) => item.amountMinor === '10000')).assertFalse();
        expect(expenseStats.budgetCategories.find((item) => item.key === 'nature-survival')?.amountMinor).assertEqual('1000');
        expect(expenseStats.budgetCategories.find((item) => item.key === 'unassigned')?.amountMinor).assertEqual('5');

        const incomeStats = await workspace.statistics('2027-01-01', '2027-02-01', 'income', 'day');
        expect(incomeStats.totalMinor).assertEqual('3000');
        expect(incomeStats.categories.find((item) => item.key === 'income-salary')?.amountMinor).assertEqual('3000');
        expect(incomeStats.budgetCategories.length).assertEqual(0);

        const foodEntries = await workspace.statisticsEntries('2027-01-01', '2027-02-01', 'expense', 'expense-food');
        expect(foodEntries.length).assertEqual(1);
        expect(foodEntries[0].id).assertEqual('stat-food');
        const feeEntries = await workspace.statisticsEntries('2027-01-01', '2027-02-01', 'expense', 'transfer_fee');
        expect(feeEntries.length).assertEqual(1);
        expect(feeEntries[0].amountMinor).assertEqual('5');

        let invalidRange = false;
        try { await workspace.statistics('2027-02-01', '2027-01-01', 'expense', 'day'); }
        catch (_) { invalidRange = true; }
        expect(invalidRange).assertTrue();
      } finally {
        await LedgerWorkspace.close(name);
        await relationalStore.deleteRdbStore(host, name);
      }
    });
  });
}
