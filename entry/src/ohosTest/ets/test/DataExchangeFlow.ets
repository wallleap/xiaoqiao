import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { Money } from '../../../main/ets/core/money/Money';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { ExpenseCommand } from '../../../main/ets/domain/model/ExpenseRecord';

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

function csvExpense(workspace: LedgerWorkspace): ExpenseCommand {
  const now = new Date();
  const money = Money.parse('12', workspace.currency);
  return { id: 'csv-ui-expense', bookId: DEFAULT_BOOK_ID, categoryId: 'expense-food-0',
    gross: money, discount: Money.parse('0', workspace.currency), bookPaid: money,
    includeInAssets: false, includeInBudget: false, note: 'CSV 导出账目',
    occurredAtMs: now.getTime(),
    localDate: `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -now.getTimezoneOffset() };
}

export default function dataExchangeFlowTest() {
  describe('DataExchangeUI', () => {
    it('opens_csv_export_page_with_current_month_count', 0, async () => {
      const context = await uiContext();
      const driver = Driver.create();
      const databaseName = AppStorage.get<string>('ledgerDatabaseName') || '';
      const workspace = await LedgerWorkspace.open(context, databaseName);
      await workspace.saveExpense(csvExpense(workspace));
      await driver.waitForComponent(ON.id('ledger-tab-4'), 10000);
      await (await driver.findComponent(ON.id('ledger-tab-4'))).click();
      const settingsScroll = await driver.waitForComponent(ON.id('settings-scroll'), 5000);
      await (await settingsScroll.scrollSearch(ON.id('settings-data-exchange'))).click();
      await driver.waitForComponent(ON.id('data-exchange-page'), 5000);
      await driver.waitForComponent(ON.text('共 1 笔账目'), 5000);
      await driver.waitForComponent(ON.id('data-export-csv').enabled(true), 5000);
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-csv-export.png')).assertTrue();
      await (await driver.findComponent(ON.id('data-exchange-close'))).click();
      await driver.waitForComponent(ON.id('settings-data-exchange'), 5000);
    });
  });
}
