import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { Money } from '../../../main/ets/core/money/Money';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { ExpenseCommand } from '../../../main/ets/domain/model/ExpenseRecord';
import { IncomeCommand } from '../../../main/ets/domain/model/IncomeRecord';

async function uiContext(): Promise<common.UIAbilityContext> {
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

function today(): Date {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate(), 12, 0, 0, 0);
}

function expense(workspace: LedgerWorkspace, id: string, categoryId: string, amount: string,
  budget: boolean, tagIds: string[] = []): ExpenseCommand {
  const date = today();
  const money = Money.parse(amount, workspace.currency);
  return { id: id, bookId: DEFAULT_BOOK_ID, categoryId: categoryId, gross: money,
    discount: Money.parse('0', workspace.currency), bookPaid: money,
    includeInAssets: false, includeInBudget: budget,
    spendingNatureId: budget ? 'nature-survival' : undefined,
    tagIds: tagIds,
    note: id, occurredAtMs: date.getTime(),
    localDate: `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -date.getTimezoneOffset() };
}

function income(workspace: LedgerWorkspace): IncomeCommand {
  const date = today();
  const money = Money.parse('50', workspace.currency);
  return { id: 'statistics-ui-income', bookId: DEFAULT_BOOK_ID, categoryId: 'income-salary',
    amount: money, bookAmount: money, includeInAssets: false, note: '统计收入',
    occurredAtMs: date.getTime(),
    localDate: `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -date.getTimezoneOffset() };
}

export default function statisticsFlowTest() {
  describe('StatisticsUI', () => {
    it('shows_populated_trends_rankings_custom_range_and_entry_drilldown', 0, async () => {
      const context = await uiContext();
      const driver = Driver.create();
      const databaseName = AppStorage.get<string>('ledgerDatabaseName') || 'xiaoqiao_app_test_statistics_ui.db';
      const workspace = await LedgerWorkspace.open(context, databaseName);
      await workspace.createTag({ id: 'statistics-tag-travel', name: '旅行', colorKey: 'brand' });
      await workspace.saveExpense(expense(workspace, 'statistics-ui-food', 'expense-food-0', '12', true,
        ['statistics-tag-travel']));
      await workspace.saveExpense(expense(workspace, 'statistics-ui-transport', 'expense-transport', '8', false));
      await workspace.saveIncome(income(workspace));

      await driver.waitForComponent(ON.id('ledger-tab-1'), 10000);
      await (await driver.findComponent(ON.id('ledger-tab-1'))).click();
      await driver.waitForComponent(ON.id('statistics-page'), 5000);
      await driver.waitForComponent(ON.id('statistics-category-expense-food'), 5000);
      await driver.waitForComponent(ON.id('statistics-category-expense-transport'), 5000);
      await driver.waitForComponent(ON.id('statistics-budget-nature-survival'), 5000);
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-statistics-populated.png')).assertTrue();

      const pageScroll = await driver.waitForComponent(ON.id('statistics-scroll'), 5000);
      const categoryCard = await pageScroll.scrollSearch(ON.id('statistics-category-expense-food'));
      expect(categoryCard !== null).assertTrue();
      if (categoryCard === null) { throw new Error('STATISTICS_CATEGORY_NOT_FOUND'); }
      await categoryCard.click();
      await driver.waitForComponent(ON.id('statistics-entries-sheet'), 5000);
      await driver.waitForComponent(ON.id('statistics-entry-statistics-ui-food'), 5000);
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-statistics-entry-sheet.png')).assertTrue();
      await driver.pressBack();
      for (let attempt = 0; attempt < 20; attempt++) {
        if (await driver.findComponent(ON.id('statistics-entries-sheet')) === null) { break; }
        await driver.delayMs(100);
      }
      await driver.delayMs(600);
      await driver.waitForComponent(ON.id('statistics-page'), 5000);

      const pageBounds = await pageScroll.getBounds();
      const pageCenter = Math.round((pageBounds.left + pageBounds.right) / 2);
      let tagCard = await driver.findComponent(ON.id('statistics-tag-statistics-tag-travel'));
      for (let attempt = 0; attempt < 4 && tagCard === null; attempt++) {
        await driver.swipe(pageCenter, pageBounds.bottom - 650, pageCenter, pageBounds.top + 650, 1200);
        await driver.delayMs(300);
        tagCard = await driver.findComponent(ON.id('statistics-tag-statistics-tag-travel'));
      }
      expect(tagCard !== null).assertTrue();
      if (tagCard === null) { throw new Error('STATISTICS_TAG_NOT_FOUND'); }
      await tagCard.click();
      await driver.waitForComponent(ON.id('statistics-entries-sheet'), 5000);
      await driver.waitForComponent(ON.id('statistics-entry-statistics-ui-food'), 5000);
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-statistics-tag-sheet.png')).assertTrue();
      await driver.pressBack();
      await driver.delayMs(700);

      await pageScroll.scrollToTop(1200);
      await (await driver.findComponent(ON.id('statistics-range-3'))).click();
      await driver.waitForComponent(ON.id('statistics-custom-start'), 5000);
      await driver.delayMs(900);
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-statistics-custom-range.png')).assertTrue();
      await driver.pressBack();
      await driver.delayMs(600);
      context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      await driver.delayMs(500);
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-statistics-dark.png')).assertTrue();
      context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      await driver.delayMs(300);

      await (await driver.findComponent(ON.id('ledger-tab-0'))).click();
      await driver.waitForComponent(ON.text('日常账本'), 5000);
    });
  });
}
