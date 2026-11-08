import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { Money } from '../../../main/ets/core/money/Money';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { ExpenseCommand } from '../../../main/ets/domain/model/ExpenseRecord';
import { CsvPreviewRow } from '../../../main/ets/data/exchange/LedgerCsvImport';

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

function currentDate(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
}

function monthKey(): string {
  return currentDate().substring(0, 7);
}

function csvExpense(workspace: LedgerWorkspace): ExpenseCommand {
  const now = new Date();
  const money = Money.parse('12', workspace.currency);
  return { id: 'csv-ui-expense', bookId: DEFAULT_BOOK_ID, categoryId: 'expense-food-0',
    gross: money, discount: Money.parse('0', workspace.currency), bookPaid: money,
    includeInAssets: false, includeInBudget: false, note: 'CSV 导出账目',
    occurredAtMs: now.getTime(),
    localDate: currentDate(),
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
      const pageScroll = await driver.waitForComponent(ON.id('data-exchange-scroll'), 5000);
      const importButton = await pageScroll.scrollSearch(ON.id('data-import-csv'));
      expect(importButton !== null).assertTrue();
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-csv-import-section.png')).assertTrue();
      const current = await workspace.snapshot(monthKey());
      const category = current.categories.find((item) => item.name === '餐饮');
      const importedRow: CsvPreviewRow = { rowNumber: 2, raw: [], date: currentDate(), time: '18:21',
        timeKnown: true, type: 'expense', amount: '9.00', categoryId: category?.id || '',
        categoryName: '餐饮', createCategory: false, accountId: '', accountName: '',
        createAccount: false, sourceId: 'ui-source', duplicate: false, duplicateReason: '',
        selected: true, merchant: '', address: '', note: 'CSV 新导入', valid: true, issues: [] };
      await workspace.importCsvBatch('ui.csv', 'ui-sha', [importedRow], ',');
      await (await driver.findComponent(ON.id('data-exchange-close'))).click();
      await driver.waitForComponent(ON.id('settings-data-exchange'), 5000);
      await (await driver.findComponent(ON.id('ledger-tab-0'))).click();
      await driver.waitForComponent(ON.text('CSV 新导入'), 5000);
    });
  });
}
