import { common } from '@kit.AbilityKit';
import { Driver, ON, abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';

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

export default function categoryFlowTest() {
  describe('CategoryUI', () => {
    it('shows_multi_level_category_management_and_editor', 0, async () => {
      const context = await uiContext();
      const driver = Driver.create();
      await driver.waitForComponent(ON.id('ledger-tab-4'), 10000);
      await (await driver.findComponent(ON.id('ledger-tab-4'))).click();
      const settingsScroll = await driver.waitForComponent(ON.id('settings-scroll'), 10000);
      await (await settingsScroll.scrollSearch(ON.id('settings-categories'))).click();
      await driver.waitForComponent(ON.id('category-management-page'), 5000);
      await driver.waitForComponent(ON.text('餐饮'), 5000);
      await driver.waitForComponent(ON.text('交通'), 5000);
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-categories.png')).assertTrue();
      await (await driver.findComponent(ON.id('category-create'))).click();
      await driver.waitForComponent(ON.id('category-name'), 5000);
      await driver.waitForComponent(ON.id('category-parent'), 5000);
      await driver.waitForComponent(ON.id('category-icon-food'), 5000);
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-category-editor.png')).assertTrue();
      await driver.pressBack();
      await driver.delayMs(500);
      await (await driver.findComponent(ON.id('category-close'))).click();
      await driver.waitForComponent(ON.id('settings-categories'), 5000);
    });
  });
}
