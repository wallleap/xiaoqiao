import { describe, expect, it } from '@ohos/hypium';
import { Driver, ON, abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';

async function uiContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  try { return (await delegator.getCurrentTopAbility()).context; }
  catch (_) { /* Class-only execution may start before EntryAbility is on top. */ }
  const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
  await delegator.addAbilityMonitor(monitor);
  try {
    await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
    return (await delegator.waitAbilityMonitor(monitor, 10000)).context;
  } finally { await delegator.removeAbilityMonitor(monitor); }
}

export default function spendingNatureFlowTest() {
  describe('SpendingNatureUI', () => {
    it('manages_custom_nature_and_selects_it_from_expense_editor', 0, async () => {
      const context = await uiContext();
      const driver = Driver.create();
      await driver.waitForComponent(ON.id('ledger-tab-4'), 10000);
      await (await driver.findComponent(ON.id('ledger-tab-4'))).click();
      const settingsScroll = await driver.waitForComponent(ON.id('settings-scroll'), 10000);
      const settings = await settingsScroll.scrollSearch(ON.id('settings-spending-natures'));
      await settings.click();
      await driver.waitForComponent(ON.id('spending-nature-page'), 5000);
      await driver.waitForComponent(ON.text('生存保障'), 5000);
      await driver.waitForComponent(ON.text('体验享受'), 5000);
      await driver.waitForComponent(ON.text('成长提升'), 5000);
      await driver.waitForComponent(ON.text('突发支出'), 5000);
      await driver.waitForComponent(ON.id('spending-nature-create'), 5000);
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-spending-natures.png')).assertTrue();
      await (await driver.findComponent(ON.id('spending-nature-close'))).click();
      await driver.waitForComponent(ON.id('settings-spending-natures'), 5000);
      await (await driver.findComponent(ON.id('ledger-tab-0'))).click();
      await (await driver.waitForComponent(ON.id('ledger-add-expense'), 5000)).click();
      const form = await driver.waitForComponent(ON.id('expense-form-scroll'), 5000);
      const growth = await form.scrollSearch(ON.id('expense-nature-nature-growth'));
      await growth.click();
      await driver.pressBack();
      await driver.delayMs(400);
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-spending-nature-editor.png')).assertTrue();
      await (await driver.findComponent(ON.id('expense-close'))).click();
      await driver.waitForComponent(ON.id('ledger-add-expense'), 5000);
    });
  });
}
