import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';

/** Explicit smoke suite for an app with Map Kit NOT configured; excluded from full regression. */
export default function mapPickerUnavailableTest() {
  describe('MapPickerUnavailable', () => {
    it('opens_native_picker_or_explains_unavailable_service_without_losing_text', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
      await delegator.addAbilityMonitor(monitor);
      try {
        await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
        await delegator.waitAbilityMonitor(monitor, 10000);
      } finally { await delegator.removeAbilityMonitor(monitor); }
      const name = AppStorage.get<string>('ledgerDatabaseName') || '';
      expect(name.startsWith('xiaoqiao_app_test_ui_')).assertTrue();
      const driver = Driver.create();
      await (await driver.waitForComponent(ON.id('ledger-tab-0'), 10000)).click();
      await (await driver.waitForComponent(ON.id('ledger-add-expense'), 5000)).click();
      const categories = await driver.waitForComponent(ON.id('expense-categories'), 5000);
      const bounds = await categories.getBounds();
      const center = Math.round((bounds.left + bounds.right) / 2);
      await driver.swipe(center, bounds.bottom - 40, center, bounds.top + 40, 600);
      await driver.waitForComponent(ON.id('expense-categories-compact'), 5000);
      const scroll = await driver.waitForComponent(ON.id('expense-form-scroll'), 5000);
      await (await scroll.scrollSearch(ON.id('expense-merchant'))).inputText('保留商户');
      await (await scroll.scrollSearch(ON.id('expense-address'))).inputText('保留地址');
      await driver.pressBack();
      await (await scroll.scrollSearch(ON.id('expense-map-location'))).click();
      const acknowledge = await driver.waitForComponent(ON.text('知道了'), 15000);
      if (acknowledge === null) { throw new Error('MAP_PICKER_DID_NOT_RETURN_UNAVAILABLE_DIALOG'); }
      const messages = await driver.findComponents(ON.type('Text'));
      let explained = false;
      for (const message of messages) {
        const text = await message.getText();
        if (text.includes('地图')) { console.info('MapPickerSmoke: ' + text); }
        if (text.includes('当前设备不支持地图选点') || text.includes('已保留原内容')) { explained = true; }
      }
      expect(explained).assertTrue();
      await acknowledge.click();
      expect(await (await scroll.scrollSearch(ON.id('expense-merchant'))).getText()).assertEqual('保留商户');
      expect(await (await scroll.scrollSearch(ON.id('expense-address'))).getText()).assertEqual('保留地址');
      expect(await driver.waitForComponent(ON.id('expense-map-location').enabled(true), 5000) !== null).assertTrue();
      await (await driver.findComponent(ON.id('expense-close'))).click();
    });
  });
}

/** Explicit success-path integration suite for a registered app on a disposable device. */
export function mapPickerConfiguredTest() {
  describe('MapPickerConfigured', () => {
    it('opens_registered_native_location_picker', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
      await delegator.addAbilityMonitor(monitor);
      try {
        await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
        await delegator.waitAbilityMonitor(monitor, 10000);
      } finally { await delegator.removeAbilityMonitor(monitor); }
      const name = AppStorage.get<string>('ledgerDatabaseName') || '';
      expect(name.startsWith('xiaoqiao_app_test_ui_')).assertTrue();
      const driver = Driver.create();
      const keyboardPrompt = await driver.findComponent(ON.id('Paf.Permission.button_cancel'));
      if (keyboardPrompt !== null) { await keyboardPrompt.click(); }
      await (await driver.waitForComponent(ON.id('ledger-tab-0'), 10000)).click();
      await (await driver.waitForComponent(ON.id('ledger-add-expense'), 5000)).click();
      const categories = await driver.waitForComponent(ON.id('expense-categories'), 5000);
      const bounds = await categories.getBounds();
      const center = Math.round((bounds.left + bounds.right) / 2);
      await driver.swipe(center, bounds.bottom - 40, center, bounds.top + 40, 600);
      await driver.waitForComponent(ON.id('expense-categories-compact'), 5000);
      const scroll = await driver.waitForComponent(ON.id('expense-form-scroll'), 5000);
      await (await scroll.scrollSearch(ON.id('expense-map-location'))).click();
      const picker = await driver.waitForComponent(ON.text('选择位置'), 15000);
      const host = (await delegator.getCurrentTopAbility()).context;
      await driver.screenCap(host.filesDir + '/xiaoqiao-map-picker.png');
      expect(picker !== null).assertTrue();
    });
  });
}
