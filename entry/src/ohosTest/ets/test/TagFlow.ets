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

function monthKey(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
}

function taggedExpense(workspace: LedgerWorkspace, id: string, note: string, tagIds: string[]): ExpenseCommand {
  const now = new Date();
  const money = Money.parse('12', workspace.currency);
  return { id: id, bookId: DEFAULT_BOOK_ID, categoryId: 'expense-food-0',
    gross: money, discount: Money.parse('0', workspace.currency), bookPaid: money,
    includeInAssets: false, includeInBudget: false, tagIds: tagIds, note: note,
    occurredAtMs: now.getTime(),
    localDate: `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -now.getTimezoneOffset() };
}

export default function tagFlowTest() {
  describe('TagUI', () => {
    it('creates_filters_and_selects_tag_in_expense_editor', 0, async () => {
      const context = await uiContext();
      const driver = Driver.create();
      await driver.waitForComponent(ON.id('ledger-tab-4'), 10000);
      await (await driver.findComponent(ON.id('ledger-tab-4'))).click();
      await (await driver.waitForComponent(ON.id('settings-tags'), 5000)).click();
      await driver.waitForComponent(ON.id('tag-page'), 5000);
      await (await driver.findComponent(ON.id('tag-create'))).click();
      const nameInput = await driver.waitForComponent(ON.id('tag-name'), 5000);
      await driver.delayMs(700);
      await nameInput.inputText('旅行');
      await driver.delayMs(600);
      await driver.pressBack();
      await driver.delayMs(600);
      await (await driver.waitForComponent(ON.id('tag-save'), 5000)).click();
      const created = await driver.waitForComponent(ON.text('#旅行'), 5000);
      expect(created !== null).assertTrue();
      if (created === null) { throw new Error('TAG_NOT_CREATED'); }
      for (let attempt = 0; attempt < 20; attempt++) {
        if (await driver.findComponent(ON.id('tag-name')) === null) { break; }
        await driver.delayMs(100);
      }
      await driver.delayMs(1500);
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-tags-management.png')).assertTrue();
      await (await driver.findComponent(ON.id('tag-close'))).click();
      await driver.waitForComponent(ON.id('settings-tags'), 5000);
      const databaseName = AppStorage.get<string>('ledgerDatabaseName') || '';
      const workspace = await LedgerWorkspace.open(context, databaseName);
      const createdTag = (await workspace.tags()).find((item) => item.name === '旅行');
      expect(createdTag !== undefined).assertTrue();
      if (createdTag === undefined) { throw new Error('TAG_NOT_PERSISTED'); }
      await workspace.saveExpense(taggedExpense(workspace, 'tag-ui-expense', 'UI旅行账目', [createdTag.id]));
      await workspace.saveExpense(taggedExpense(workspace, 'tag-ui-untagged', 'UI普通账目', []));
      await (await driver.findComponent(ON.id('settings-tags'))).click();
      await driver.waitForComponent(ON.id('tag-page'), 5000);
      await (await driver.findComponent(ON.id('tag-close'))).click();
      await driver.waitForComponent(ON.id('settings-tags'), 5000);
      await driver.delayMs(1200);
      expect((await workspace.snapshot(monthKey())).tags.some((item) => item.name === '旅行')).assertTrue();

      await (await driver.findComponent(ON.id('ledger-tab-0'))).click();
      await (await driver.waitForComponent(ON.id('ledger-filter-action'), 5000)).click();
      await (await driver.waitForComponent(ON.id('ledger-tag-filter-' + createdTag.id), 5000)).click();
      await (await driver.findComponent(ON.text('完成'))).click();
      for (let attempt = 0; attempt < 20; attempt++) {
        if (await driver.findComponent(ON.id('ledger-filter-sheet')) === null) { break; }
        await driver.delayMs(100);
      }
      await driver.delayMs(1500);
      await driver.waitForComponent(ON.id('tag-ui-expense'), 5000);
      expect(await driver.findComponent(ON.id('tag-ui-untagged'))).assertNull();
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-tag-filter.png')).assertTrue();

      await (await driver.waitForComponent(ON.id('ledger-add-expense'), 5000)).click();
      await driver.waitForComponent(ON.id('expense-tags'), 5000);
      const form = await driver.waitForComponent(ON.id('expense-form-scroll'), 5000);
      expect(form !== null).assertTrue();
      if (form === null) { throw new Error('EXPENSE_FORM_NOT_FOUND'); }
      const tag = await form.scrollSearch(ON.id('expense-tag-' + createdTag.id));
      expect(tag !== null).assertTrue();
      if (tag === null) { throw new Error('EDITOR_TAG_NOT_FOUND'); }
      await tag.click();
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-expense-tag-selected.png')).assertTrue();
      await driver.pressBack();
      await driver.waitForComponent(ON.id('ledger-add-expense'), 10000);
      await driver.delayMs(1200);

      const taggedId = 'tag-ui-expense';
      const detail = await workspace.entryDetail(taggedId);
      expect(detail.tags?.some((tagValue) => tagValue.name === '旅行')).assertTrue();
    });
  });
}
