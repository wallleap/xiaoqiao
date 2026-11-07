import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON, On, Component, abilityDelegatorRegistry } from '@kit.TestKit';
import { ConfigurationConstant } from '@kit.AbilityKit';

async function waitForAbsence(driver: Driver, selector: On): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt++) {
    if (await driver.findComponent(selector) === null) {
      return;
    }
    await driver.delayMs(50);
  }
  throw new Error('EXPECTED_UI_ELEMENT_TO_DISAPPEAR');
}

export default function ledgerHomeTest() {
  describe('LedgerHomeUI', () => {
    it('empty_preview_search_and_filter', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
      const driver = Driver.create();
      await driver.waitForComponent(ON.text('日常账本'), 10000);
      const ability = await delegator.getCurrentTopAbility();
      AppStorage.setOrCreate('ledgerPreview', false);
      try {
        await driver.waitForComponent(ON.text('开始记第一笔账'), 5000);
        const illustration = await driver.waitForComponent(ON.id('ledger-empty-illustration'), 5000);
        const illustrationBounds = await illustration.getBounds();
        expect(illustrationBounds.right - illustrationBounds.left > 300).assertTrue();
        expect(Math.abs((illustrationBounds.right - illustrationBounds.left) -
          (illustrationBounds.bottom - illustrationBounds.top)) <= 2).assertTrue();
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-empty.png')).assertTrue();
        // Short content accepts a drag and springs back without moving the fixed navigation.
        const emptyScroll = await driver.findComponent(ON.id('ledger-scroll'));
        const emptyViewport = await emptyScroll.getBounds();
        const emptyNav = await driver.findComponent(ON.id('ledger-book-selector'));
        const emptyTab = await driver.findComponent(ON.id('ledger-tab-0'));
        const emptyNavBefore = await emptyNav.getBounds();
        const emptyTabBefore = await emptyTab.getBounds();
        // Native HDS title safe area must keep the period out of the title frame.
        const titleFrame = await (await driver.findComponent(ON.id('ledger-navigation-title'))).getBounds();
        const initialSummary = await (await driver.findComponent(ON.id('ledger-summary'))).getBounds();
        const initialFilters = await (await driver.findComponent(ON.id('ledger-filter-placeholder'))).getBounds();
        expect(Math.abs(initialFilters.top - initialSummary.bottom - 24 * (titleFrame.bottom - titleFrame.top) / 56) <= 2).assertTrue();
        const period = await (await driver.findComponent(ON.id('ledger-period'))).getBounds();
        expect(period.top >= titleFrame.bottom).assertTrue();
        const firstEntryAction = await driver.findComponent(ON.text('开始记第一笔账'));
        expect((await firstEntryAction.getBounds()).bottom < emptyTabBefore.top).assertTrue();
        const emptyCenter = Math.round((emptyViewport.left + emptyViewport.right) / 2);
        await driver.swipe(emptyCenter, emptyViewport.top + 900, emptyCenter, emptyViewport.top + 1500, 600);
        await driver.delayMs(600); // Wait for the short-content spring to settle.
        expect((await emptyNav.getBounds()).top).assertEqual(emptyNavBefore.top);
        expect((await emptyTab.getBounds()).top).assertEqual(emptyTabBefore.top);
        const statistics = await driver.findComponent(ON.id('ledger-tab-1'));
        await statistics.click();
        await driver.waitForComponent(ON.text('统计页面尚未接入'), 5000);
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-hds-snackbar.png')).assertTrue();
        await driver.delayMs(3200); // Verify the HDS feedback's configured three-second lifetime.
        await waitForAbsence(driver, ON.text('统计页面尚未接入'));
        AppStorage.setOrCreate('ledgerPreview', true);
        const lunchCard = await driver.waitForComponent(ON.id('preview-lunch'), 5000);
        await driver.waitForComponent(ON.text('午餐'), 5000);
        await driver.waitForComponent(ON.text('地铁'), 5000);
        await driver.waitForComponent(ON.text('12:30 · 微信零钱'), 5000);
        expect(await (await driver.waitForComponent(ON.id('ledger-original-preview-lunch'), 5000)).getText()).assertEqual('¥30.00');
        expect(await (await driver.findComponent(ON.id('ledger-discount-value-preview-lunch'))).getText()).assertEqual('优惠 2.00');
        expect(await driver.findComponent(ON.id('ledger-discount-preview-metro'))).assertNull();
        expect(await driver.findComponent(ON.text('今天'))).assertNull();
        expect(await (await driver.findComponent(ON.id('ledger-day-expense-2026-10-28'))).getText()).assertEqual('支 32.00');
        expect(await (await driver.findComponent(ON.id('ledger-day-income-2026-10-25'))).getText()).assertEqual('收 8,600.00');
        expect(await driver.findComponent(ON.text('12:30 · 餐饮 · 微信零钱'))).assertNull();
        const categoryDisc = await (await driver.findComponent(ON.id('ledger-category-disc-preview-lunch'))).getBounds();
        const categoryGlyph = await (await driver.findComponent(ON.id('ledger-category-glyph-preview-lunch'))).getBounds();
        expect(categoryGlyph.right - categoryGlyph.left < (categoryDisc.right - categoryDisc.left) * 0.7).assertTrue();
        expect(Math.abs((categoryGlyph.left + categoryGlyph.right) - (categoryDisc.left + categoryDisc.right)) <= 2).assertTrue();
        expect(Math.abs((categoryGlyph.top + categoryGlyph.bottom) - (categoryDisc.top + categoryDisc.bottom)) <= 2).assertTrue();
        const cardBounds = await lunchCard.getBounds();
        expect(cardBounds.right - cardBounds.left > 400).assertTrue();
        const lunchTitle = await driver.findComponent(ON.text('午餐'));
        const titleBounds = await lunchTitle.getBounds();
        const images = await driver.findComponents(ON.type('Image'));
        let categoryImageFound = false;
        for (const image of images) {
          const iconBounds = await image.getBounds();
          if (iconBounds.left >= cardBounds.left && iconBounds.right <= cardBounds.right &&
            iconBounds.top >= cardBounds.top && iconBounds.bottom <= cardBounds.bottom) {
            expect(titleBounds.left - iconBounds.right > (iconBounds.right - iconBounds.left) * 0.2).assertTrue();
            categoryImageFound = true;
            break;
          }
        }
        expect(categoryImageFound).assertTrue();
        const lunchAmount = await driver.findComponent(ON.text('28.00'));
        const amountBounds = await lunchAmount.getBounds();
        expect(cardBounds.right - amountBounds.right > (cardBounds.right - cardBounds.left) * 0.02).assertTrue();
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-preview.png')).assertTrue();
        const filterButtonBefore = await (await driver.findComponent(ON.id('ledger-filter-action'))).getBounds();
        const filterPlaceholder = await (await driver.findComponent(ON.id('ledger-filter-placeholder'))).getBounds();
        expect(Math.abs(filterButtonBefore.right - filterPlaceholder.right) <= 2).assertTrue();
        // The title changes content, while the HDS title frame and bottom tabs stay fixed.
        const tab = await driver.findComponent(ON.id('ledger-tab-0'));
        const navigationBefore = await (await driver.findComponent(ON.id('ledger-navigation-title'))).getBounds();
        const tabBefore = await tab.getBounds();
        const summaryBefore = await (await driver.findComponent(ON.id('ledger-summary'))).getBounds();
        AppStorage.setOrCreate('ledgerScrollPreview', true);
        const scroll = await driver.findComponent(ON.id('ledger-scroll'));
        const viewport = await scroll.getBounds();
        const center = Math.round((viewport.left + viewport.right) / 2);
        await driver.swipe(center, viewport.bottom - 400, center, viewport.top + 400, 1200);
        const movedSummary = await driver.findComponent(ON.id('ledger-summary'));
        if (movedSummary !== null) {
          expect((await movedSummary.getBounds()).top < summaryBefore.top - 100).assertTrue();
        }
        await driver.delayMs(300); // Capture the native gradient blur after the first scroll settles.
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-gradient-header.png')).assertTrue();
        const pinned = await (await driver.findComponent(ON.id('ledger-navigation-filters'))).getBounds();
        expect(Math.abs(pinned.top - navigationBefore.top) <= 2).assertTrue();
        expect(Math.abs(pinned.bottom - navigationBefore.bottom) <= 2).assertTrue();
        expect(await driver.findComponent(ON.id('ledger-book-selector'))).assertNull();
        expect(await driver.findComponent(ON.id('搜索账目'))).assertNull();
        expect((await driver.findComponents(ON.id('ledger-filters'))).length).assertEqual(1);
        expect(Math.abs((await (await driver.findComponent(ON.id('ledger-filter-action'))).getBounds()).right -
          filterButtonBefore.right) <= 2).assertTrue();
        ability.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
        await driver.delayMs(400);
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-filter-dark.png')).assertTrue();
        ability.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
        await driver.delayMs(400);
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-filter-light.png')).assertTrue();
        let tail: Component | null = null;
        for (let attempt = 0; attempt < 12; attempt++) {
          tail = await driver.findComponent(ON.id('preview-scroll-tail'));
          if (tail !== null) {
            const bounds = await tail.getBounds();
            if (bounds.bottom < tabBefore.top && bounds.top > navigationBefore.bottom) { break; }
          }
          await driver.swipe(center, tabBefore.top - 120, center, navigationBefore.bottom + 180, 2200);
        }
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-scroll-diagnostic.png')).assertTrue();
        if (tail === null) { throw new Error('SCROLL_TAIL_NOT_VISIBLE'); }
        const tailBounds = await tail.getBounds();
        const navigationAfter = await (await driver.findComponent(ON.id('ledger-navigation-title'))).getBounds();
        const tabAfter = await (await driver.findComponent(ON.id('ledger-tab-0'))).getBounds();
        expect(navigationAfter.top).assertEqual(navigationBefore.top);
        expect(navigationAfter.bottom).assertEqual(navigationBefore.bottom);
        expect(tabAfter.top).assertEqual(tabBefore.top);
        expect(tabAfter.bottom).assertEqual(tabBefore.bottom);
        expect(tailBounds.top > navigationAfter.bottom).assertTrue();
        expect(tailBounds.bottom < tabAfter.top).assertTrue();
        expect(Math.abs((await (await driver.findComponent(ON.id('ledger-navigation-filters'))).getBounds()).top - pinned.top) <= 2).assertTrue();
        // The fallback keeps the same native sticky geometry on systems without API 26 materials.
        AppStorage.setOrCreate('ledgerForceLegacyMaterials', true);
        await driver.waitForComponent(ON.id('ledger-filter-surface-legacy'), 5000);
        expect(Math.abs((await (await driver.findComponent(ON.id('ledger-navigation-filters'))).getBounds()).top - pinned.top) <= 2).assertTrue();
        const pinnedFilter = await driver.findComponent(ON.id('ledger-filter-action'));
        await pinnedFilter.click();
        await driver.waitForComponent(ON.text('筛选账目'), 5000);
        await driver.pressBack();
        await waitForAbsence(driver, ON.text('筛选账目'));
        AppStorage.setOrCreate('ledgerForceLegacyMaterials', false);
        await driver.delayMs(600); // The previous HDS sheet's visual exit outlasts accessibility detachment.
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-scrolled.png')).assertTrue();
        // Reproduce switching to an empty kind while already docked: the wallet has expenses but no income.
        await (await driver.findComponent(ON.id('ledger-filter-action'))).click();
        await driver.waitForComponent(ON.text('资金账户'), 5000);
        await (await driver.waitForComponent(ON.text('微信零钱'), 5000)).click();
        await (await driver.findComponent(ON.text('完成'))).click();
        await waitForAbsence(driver, ON.text('资金账户'));
        await driver.delayMs(600);
        await (await driver.findComponent(ON.text('收入').within(ON.id('ledger-filters')))).click();
        await driver.waitForComponent(ON.text('没有符合条件的账目'), 5000);
        await driver.delayMs(400); // Wait for the list's content-size clamp and HDS title update.
        const emptyPinned = await (await driver.waitForComponent(ON.id('ledger-navigation-filters'), 5000)).getBounds();
        expect(emptyPinned.top).assertEqual(pinned.top);
        expect(emptyPinned.bottom).assertEqual(pinned.bottom);
        expect(await driver.findComponent(ON.id('ledger-book-selector'))).assertNull();
        expect((await driver.findComponents(ON.id('ledger-filters'))).length).assertEqual(1);
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-pinned-empty.png')).assertTrue();
        await driver.swipe(center, emptyPinned.bottom + 100, center, tabBefore.top - 120, 1200);
        await driver.delayMs(600);
        await waitForAbsence(driver, ON.id('ledger-navigation-filters'));
        await driver.waitForComponent(ON.id('ledger-book-selector'), 5000);
        await driver.swipe(center, tabBefore.top - 120, center, navigationBefore.bottom + 180, 1200);
        await driver.waitForComponent(ON.id('ledger-navigation-filters'), 5000);
        await (await driver.findComponent(ON.text('全部').within(ON.id('ledger-filters')))).click();
        await driver.waitForComponent(ON.id('preview-lunch'), 5000);
        expect(await driver.findComponent(ON.id('ledger-navigation-filters')) !== null).assertTrue();
        await (await driver.findComponent(ON.id('ledger-filter-action'))).click();
        await driver.waitForComponent(ON.text('重置'), 5000);
        await (await driver.findComponent(ON.text('重置'))).click();
        await (await driver.findComponent(ON.text('完成'))).click();
        await waitForAbsence(driver, ON.text('资金账户'));
        for (let attempt = 0; attempt < 12; attempt++) {
          const summary = await driver.findComponent(ON.id('ledger-summary'));
          if (summary !== null && (await summary.getBounds()).top >= summaryBefore.top - 2) { break; }
          // Start the gesture below the fixed title row.
          await driver.swipe(center, Math.max(navigationBefore.bottom + 180, pinned.bottom + 100),
            center, tabBefore.top - 120, 2200);
        }
        const restoredSummary = await driver.waitForComponent(ON.id('ledger-summary'), 5000);
        expect((await restoredSummary.getBounds()).top >= summaryBefore.top - 2).assertTrue();
        await waitForAbsence(driver, ON.id('ledger-navigation-filters'));
        await driver.waitForComponent(ON.id('ledger-book-selector'), 5000);
        await driver.waitForComponent(ON.id('搜索账目'), 5000);
        expect((await driver.findComponents(ON.id('ledger-filters'))).length).assertEqual(1);
        AppStorage.setOrCreate('ledgerScrollPreview', false);
        await driver.waitForComponent(ON.text('本月预算剩余'), 5000);
        const amount = await driver.findComponent(ON.text('514.00'));
        await amount.click();
        await driver.waitForComponent(ON.text('完整金额'), 5000);
        const dismissAmount = await driver.findComponent(ON.text('知道了'));
        await dismissAmount.click();
        await waitForAbsence(driver, ON.text('完整金额'));
        expect(await driver.findComponent(ON.text('最近账目'))).assertNull();
        const expense = await driver.findComponent(ON.text('支出').within(ON.id('ledger-filters')));
        await expense.click();
        await waitForAbsence(driver, ON.id('preview-salary'));
        await driver.waitForComponent(ON.id('preview-lunch'), 5000);
        const income = await driver.findComponent(ON.text('收入').within(ON.id('ledger-filters')));
        await income.click();
        await driver.waitForComponent(ON.id('preview-salary'), 5000);
        await waitForAbsence(driver, ON.id('preview-lunch'));
        expect(await driver.findComponent(ON.id('preview-lunch'))).assertNull();
        // Repeated changes must resolve to the last selected kind, without stale exiting pages.
        for (const label of ['支出', '收入', '支出', '全部']) {
          await (await driver.findComponent(ON.text(label).within(ON.id('ledger-filters')))).click();
        }
        await driver.delayMs(650);
        await driver.waitForComponent(ON.id('ledger-record-page-0'), 5000);
        expect(await driver.findComponent(ON.id('ledger-record-page-1'))).assertNull();
        expect(await driver.findComponent(ON.id('ledger-record-page-2'))).assertNull();
        await driver.waitForComponent(ON.id('preview-lunch'), 5000);
        await driver.waitForComponent(ON.id('preview-salary'), 5000);
        const search = await driver.findComponent(ON.id('搜索账目'));
        await search.click();
        const input = await driver.waitForComponent(ON.id('ledger-search'), 5000);
        await input.inputText('地铁');
        await driver.waitForComponent(ON.id('preview-metro'), 5000);
        await waitForAbsence(driver, ON.id('preview-salary'));
        expect(await driver.findComponent(ON.id('preview-salary'))).assertNull();
        await input.inputText('不存在的账目');
        await driver.waitForComponent(ON.text('没有符合条件的账目'), 5000);
        const closeSearch = await driver.findComponent(ON.id('搜索账目'));
        await closeSearch.click();
        await driver.waitForComponent(ON.id('preview-lunch'), 5000);
        const filter = await driver.findComponent(ON.id('ledger-filter-action'));
        await filter.click();
        await driver.waitForComponent(ON.text('资金账户'), 5000);
        const account = await driver.findComponent(ON.text('日常储蓄卡'));
        await account.click();
        const done = await driver.findComponent(ON.text('完成'));
        await driver.delayMs(600); // Let the radio selection and sheet spring settle before the visual capture.
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-filter-sheet.png')).assertTrue();
        await done.click();
        await waitForAbsence(driver, ON.text('资金账户'));
        await driver.waitForComponent(ON.text('账户：日常储蓄卡'), 5000);
        await waitForAbsence(driver, ON.id('preview-lunch'));
        expect(await driver.findComponent(ON.id('preview-lunch'))).assertNull();
        await driver.waitForComponent(ON.id('preview-salary'), 5000);
        await driver.delayMs(600); // Accessibility detaches the sheet before its visual exit animation completes.
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-filter.png')).assertTrue();
        const books = await driver.findComponent(ON.id('ledger-book-selector'));
        await books.click();
        await driver.waitForComponent(ON.text('选择账本'), 5000);
        await driver.waitForComponent(ON.id('ledger-book-new'), 5000);
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-books-preview.png')).assertTrue();
        await driver.pressBack();
        // Restore committed filters before the next test uses the real isolated ledger.
        await driver.delayMs(600);
        await (await driver.findComponent(ON.id('ledger-filter-action'))).click();
        await driver.waitForComponent(ON.text('重置'), 5000);
        await (await driver.findComponent(ON.text('重置'))).click();
        await (await driver.findComponent(ON.text('完成'))).click();
        await waitForAbsence(driver, ON.text('资金账户'));
      } finally {
        ability.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
        AppStorage.setOrCreate('ledgerForceLegacyMaterials', false);
        AppStorage.setOrCreate('ledgerScrollPreview', false);
        AppStorage.setOrCreate('ledgerPreview', false);
      }
    });
  });
}
