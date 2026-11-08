import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { Money } from '../../../main/ets/core/money/Money';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { ExpenseCommand } from '../../../main/ets/domain/model/ExpenseRecord';
import { IncomeCommand } from '../../../main/ets/domain/model/IncomeRecord';
import { TransferCommand } from '../../../main/ets/domain/model/TransferRecord';
import { filterEntries, LedgerKind, presentEntry } from '../../../main/ets/presentation/ledger/LedgerOverview';

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

function wallDate(): Date {
  return new Date(2027, 2, 10, 12, 0, 0, 0);
}

function expense(workspace: LedgerWorkspace, id: string, tagIds: string[]): ExpenseCommand {
  const date = wallDate();
  const money = Money.parse('12', workspace.currency);
  return { id: id, bookId: DEFAULT_BOOK_ID, categoryId: 'expense-food-0', gross: money,
    discount: Money.parse('0', workspace.currency), bookPaid: money,
    includeInAssets: false, includeInBudget: false, tagIds: tagIds, note: id,
    occurredAtMs: date.getTime(), localDate: '2027-03-10',
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -date.getTimezoneOffset() };
}

export default function tagsTest() {
  describe('Tags', () => {
    it('manages_tags_links_all_record_kinds_updates_clears_deletes_and_searches', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_app_test_tags_' + util.generateRandomUUID() + '.db';
      try {
        const workspace = await LedgerWorkspace.open(host, name);
        await workspace.createTag({ id: 'tag-travel', name: '旅行', colorKey: 'brand' });
        await workspace.createTag({ id: 'tag-work', name: '工作', colorKey: 'income' });
        expect((await workspace.tags()).length).assertEqual(2);
        let duplicate = false;
        try { await workspace.createTag({ id: 'tag-duplicate', name: '旅行', colorKey: 'neutral' }); }
        catch (_) { duplicate = true; }
        expect(duplicate).assertTrue();

        await workspace.createAccount({ id: 'tag-a', name: '标签钱包', kind: 'asset', styleKey: 'cash',
          includeInNetAssets: true, opening: Money.parse('100', workspace.currency) });
        await workspace.createAccount({ id: 'tag-b', name: '标签储蓄', kind: 'asset', styleKey: 'cash',
          includeInNetAssets: true, opening: Money.parse('0', workspace.currency) });
        await workspace.saveExpense(expense(workspace, 'tag-expense', ['tag-travel', 'tag-work']));

        const incomeDate = wallDate();
        const incomeMoney = Money.parse('30', workspace.currency);
        const income: IncomeCommand = { id: 'tag-income', bookId: DEFAULT_BOOK_ID, categoryId: 'income-salary',
          amount: incomeMoney, bookAmount: incomeMoney, includeInAssets: false, tagIds: ['tag-work'],
          note: '标签收入', occurredAtMs: incomeDate.getTime(), localDate: '2027-03-10',
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -incomeDate.getTimezoneOffset() };
        await workspace.saveIncome(income);
        const transfer: TransferCommand = { id: 'tag-transfer', bookId: DEFAULT_BOOK_ID,
          fromAccountId: 'tag-a', toAccountId: 'tag-b', amount: Money.parse('5', workspace.currency),
          includeInAssets: true, tagIds: ['tag-travel'], note: '标签转账',
          occurredAtMs: incomeDate.getTime(), localDate: '2027-03-10',
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -incomeDate.getTimezoneOffset() };
        await workspace.saveTransfer(transfer);

        let snapshot = await workspace.snapshot('2027-03');
        expect(snapshot.tags.length).assertEqual(2);
        const savedExpense = snapshot.entries.find((entry) => entry.id === 'tag-expense');
        expect(savedExpense?.tagIds?.join(',')).assertEqual('tag-travel,tag-work');
        expect(savedExpense?.tagNames?.join(',')).assertEqual('旅行,工作');
        expect(snapshot.entries.find((entry) => entry.id === 'tag-income')?.tagNames?.join(',')).assertEqual('工作');
        expect(snapshot.entries.find((entry) => entry.id === 'tag-transfer')?.tagNames?.join(',')).assertEqual('旅行');
        const presented = snapshot.entries.map(presentEntry);
        expect(filterEntries(presented, LedgerKind.All, '旅行', '').length).assertEqual(2);
        expect(filterEntries(presented, LedgerKind.All, '', '', ['tag-travel']).length).assertEqual(2);
        expect(filterEntries(presented, LedgerKind.All, '', '', ['tag-travel', 'tag-work']).length).assertEqual(1);
        const tagStatistics = await workspace.statistics('2027-03-01', '2027-04-01', 'expense', 'day');
        expect(tagStatistics.tagCategories.find((tag) => tag.key === 'tag-travel')?.amountMinor).assertEqual('1200');
        expect(tagStatistics.tagCategories.find((tag) => tag.key === 'tag-work')?.amountMinor).assertEqual('1200');
        expect(tagStatistics.tagCategories.find((tag) => tag.key === 'tag-work')?.entryCount).assertEqual(1);
        const workTagEntries = await workspace.statisticsEntries('2027-03-01', '2027-04-01', 'expense', '', 'tag-work');
        expect(workTagEntries.length).assertEqual(1);
        expect(workTagEntries[0].id).assertEqual('tag-expense');

        const detail = await workspace.entryDetail('tag-expense');
        expect(detail.tags?.length).assertEqual(2);
        await workspace.updateExpense(expense(workspace, 'tag-expense', ['tag-work']), detail.revision);
        snapshot = await workspace.snapshot('2027-03');
        expect(snapshot.entries.find((entry) => entry.id === 'tag-expense')?.tagNames?.join(',')).assertEqual('工作');

        const beforeInvalid = snapshot.entries.length;
        let invalid = false;
        try { await workspace.saveExpense(expense(workspace, 'tag-invalid', ['missing-tag'])); }
        catch (_) { invalid = true; }
        expect(invalid).assertTrue();
        expect((await workspace.snapshot('2027-03')).entries.length).assertEqual(beforeInvalid);

        const travel = (await workspace.tags()).find((item) => item.id === 'tag-travel');
        await workspace.deleteTag('tag-travel', travel?.revision || 1);
        snapshot = await workspace.snapshot('2027-03');
        expect(snapshot.tags.some((item) => item.id === 'tag-travel')).assertFalse();
        expect(snapshot.entries.find((entry) => entry.id === 'tag-transfer')?.tagNames?.join(',')).assertEqual('旅行');
        await workspace.createTag({ id: 'tag-travel-new', name: '旅行', colorKey: 'alert' });
        expect((await workspace.tags()).some((item) => item.id === 'tag-travel-new')).assertTrue();
      } finally {
        await LedgerWorkspace.close(name);
        await relationalStore.deleteRdbStore(host, name);
      }
    });
  });
}
