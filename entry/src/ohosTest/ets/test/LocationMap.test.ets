import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { Money } from '../../../main/ets/core/money/Money';

/** Explicit online Map Kit test; run only on the disposable, registered test device. */
export default function locationMapTest() {
  describe('LocationMapUI', () => {
    it('shows_saved_pin_keeps_it_on_edit_and_opens_native_details', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
      await delegator.addAbilityMonitor(monitor);
      try {
        await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
        await delegator.waitAbilityMonitor(monitor, 10000);
      } finally { await delegator.removeAbilityMonitor(monitor); }
      const host = (await delegator.getCurrentTopAbility()).context;
      await delegator.print('LOCATION_MAP_FILES_DIR=' + host.filesDir);
      const name = AppStorage.get<string>('ledgerDatabaseName') || '';
      expect(name.startsWith('xiaoqiao_app_test_ui_')).assertTrue();
      const workspace = await LedgerWorkspace.open(host, name);
      const date = new Date();
      const localDate = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
      const amount = Money.parse('10', workspace.currency);
      await workspace.saveExpense({ id: 'map-detail-fixture', bookId: DEFAULT_BOOK_ID, categoryId: 'expense-food-0',
        gross: amount, discount: Money.parse('0', workspace.currency), bookPaid: amount,
        includeInAssets: false, includeInBudget: false, note: '详情地图测试', merchantName: '详情地图测试位置',
        addressText: '北京市东城区景山前街4号', location: { latitudeE6: 39916345, longitudeE6: 116397155 },
        occurredAtMs: date.getTime(), localDate: localDate, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        offsetMinutes: -date.getTimezoneOffset() });
      await workspace.saveExpense({ id: 'map-text-only-fixture', bookId: DEFAULT_BOOK_ID, categoryId: 'expense-food-0',
        gross: amount, discount: Money.parse('0', workspace.currency), bookPaid: amount,
        includeInAssets: false, includeInBudget: false, note: '仅文字地址', addressText: '历史手填地址',
        occurredAtMs: date.getTime(), localDate: localDate, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        offsetMinutes: -date.getTimezoneOffset() });
      const driver = Driver.create();
      await (await driver.waitForComponent(ON.id('ledger-tab-4'), 10000)).click();
      const settings = await driver.waitForComponent(ON.id('settings-scroll'), 5000);
      await (await settings.scrollSearch(ON.id('settings-data-exchange'))).click();
      await driver.waitForComponent(ON.id('data-exchange-page'), 5000);
      await (await driver.findComponent(ON.id('data-exchange-close'))).click();
      await (await driver.waitForComponent(ON.id('ledger-tab-0'), 5000)).click();
      await (await driver.waitForComponent(ON.id('map-text-only-fixture'), 5000)).click();
      await driver.waitForComponent(ON.id('entry-detail-edit'), 5000);
      expect(await driver.findComponent(ON.id('entry-location-map'))).assertNull();
      await (await driver.findComponent(ON.id('entry-detail-close'))).click();
      await (await driver.waitForComponent(ON.id('map-detail-fixture'), 5000)).click();
      let scroll = await driver.waitForComponent(ON.id('entry-detail-scroll'), 5000);
      expect(await scroll.scrollSearch(ON.id('entry-location-map')) !== null).assertTrue();
      await scroll.scrollToBottom(1200);
      const viewport = await scroll.getBounds();
      await driver.swipe(viewport.left + 30, viewport.bottom - 80, viewport.left + 30, viewport.top + 80, 800);
      await driver.delayMs(600);
      expect(await driver.waitForComponent(ON.text('点击查看位置'), 20000) !== null).assertTrue();
      expect(await driver.screenCap(host.filesDir + '/xq-entry-location-map.png')).assertTrue();
      await delegator.print('LOCATION_INLINE_READY');
      await driver.delayMs(2000);
      const openBounds = await (await driver.findComponent(ON.id('entry-location-map-open'))).getBounds();
      const actionsBounds = await (await driver.findComponent(ON.id('entry-detail-edit'))).getBounds();
      expect(openBounds.bottom <= actionsBounds.top).assertTrue();
      await (await driver.findComponent(ON.id('entry-location-map-open'))).click();
      expect(await driver.waitForComponent(ON.text('详情地图测试位置'), 10000) !== null).assertTrue();
      expect(await driver.waitForComponent(ON.text('路线'), 15000) !== null).assertTrue();
      expect(await driver.screenCap(host.filesDir + '/xq-entry-location-native.png')).assertTrue();
      await delegator.print('LOCATION_NATIVE_READY');
      await driver.delayMs(2000);
      await driver.pressBack();
      // Native Map Kit dismissal animates over the still-present detail page.
      await driver.delayMs(1500);
      expect(await driver.findComponent(ON.text('路线'))).assertNull();
      await driver.waitForComponent(ON.id('entry-detail-edit'), 5000);
      await (await driver.findComponent(ON.id('entry-detail-edit'))).click();
      await (await driver.waitForComponent(ON.id('expense-amount'), 5000)).click();
      await (await driver.waitForComponent(ON.id('expense-key-保存'), 5000)).click();
      await driver.waitForComponent(ON.id('entry-detail-amount'), 5000);
      const detail = await workspace.entryDetail('map-detail-fixture');
      expect(detail.location?.latitudeE6).assertEqual(39916345); expect(detail.location?.longitudeE6).assertEqual(116397155);
      scroll = await driver.waitForComponent(ON.id('entry-detail-scroll'), 5000);
      expect(await scroll.scrollSearch(ON.id('entry-location-map')) !== null).assertTrue();
      await scroll.scrollToBottom(1200);
      await driver.swipe(viewport.left + 30, viewport.bottom - 80, viewport.left + 30, viewport.top + 80, 800);
      await driver.delayMs(600);
      expect(await driver.waitForComponent(ON.text('点击查看位置'), 20000) !== null).assertTrue();
    });
  });
}
