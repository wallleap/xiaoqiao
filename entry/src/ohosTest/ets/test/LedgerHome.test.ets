import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON, On, Component, abilityDelegatorRegistry } from '@kit.TestKit';

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
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-empty.png')).assertTrue();
        // Short content accepts a drag and springs back without moving the fixed navigation.
        const emptyScroll = await driver.findComponent(ON.id('ledger-scroll'));
        const emptyViewport = await emptyScroll.getBounds();
        const emptyNav = await driver.findComponent(ON.id('ledger-book-selector'));
        const emptyTab = await driver.findComponent(ON.id('ledger-tab-0'));
        const emptyNavBefore = await emptyNav.getBounds();
        const emptyTabBefore = await emptyTab.getBounds();
        const emptyCenter = Math.round((emptyViewport.left + emptyViewport.right) / 2);
        await driver.swipe(emptyCenter, emptyViewport.top + 900, emptyCenter, emptyViewport.top + 1500, 600);
        await driver.delayMs(600); // Wait for the short-content spring to settle.
        expect((await emptyNav.getBounds()).top).assertEqual(emptyNavBefore.top);
        expect((await emptyTab.getBounds()).top).assertEqual(emptyTabBefore.top);
        const firstEntry = await driver.findComponent(ON.text('开始记第一笔账'));
        await firstEntry.click();
        await driver.waitForComponent(ON.text('记一笔页面将在下一步接入'), 5000);
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-hds-snackbar.png')).assertTrue();
        await driver.delayMs(3200); // Verify the HDS feedback's configured three-second lifetime.
        await waitForAbsence(driver, ON.text('记一笔页面将在下一步接入'));
        AppStorage.setOrCreate('ledgerPreview', true);
        const lunchCard = await driver.waitForComponent(ON.id('preview-lunch'), 5000);
        await driver.waitForComponent(ON.text('午餐'), 5000);
        await driver.waitForComponent(ON.text('地铁'), 5000);
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
        // The whole body scrolls; both HDS navigation areas keep the same screen bounds.
        const navigation = await driver.findComponent(ON.id('ledger-book-selector'));
        const tab = await driver.findComponent(ON.id('ledger-tab-0'));
        const navigationBefore = await navigation.getBounds();
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
        const navigationAfter = await navigation.getBounds();
        const tabAfter = await tab.getBounds();
        expect(navigationAfter.top).assertEqual(navigationBefore.top);
        expect(navigationAfter.bottom).assertEqual(navigationBefore.bottom);
        expect(tabAfter.top).assertEqual(tabBefore.top);
        expect(tabAfter.bottom).assertEqual(tabBefore.bottom);
        expect(tailBounds.top > navigationAfter.bottom).assertTrue();
        expect(tailBounds.bottom < tabAfter.top).assertTrue();
        expect(await driver.screenCap(ability.context.filesDir + '/xiaoqiao-home-scrolled.png')).assertTrue();
        for (let attempt = 0; attempt < 12; attempt++) {
          const summary = await driver.findComponent(ON.id('ledger-summary'));
          if (summary !== null && (await summary.getBounds()).top >= summaryBefore.top - 2) { break; }
          await driver.swipe(center, navigationBefore.bottom + 180, center, tabBefore.top - 120, 2200);
        }
        const restoredSummary = await driver.waitForComponent(ON.id('ledger-summary'), 5000);
        expect((await restoredSummary.getBounds()).top >= summaryBefore.top - 2).assertTrue();
        AppStorage.setOrCreate('ledgerScrollPreview', false);
        await driver.waitForComponent(ON.text('本月预算剩余'), 5000);
        const amount = await driver.findComponent(ON.text('514.00'));
        await amount.click();
        await driver.waitForComponent(ON.text('完整金额'), 5000);
        const dismissAmount = await driver.findComponent(ON.text('知道了'));
        await dismissAmount.click();
        await waitForAbsence(driver, ON.text('完整金额'));
        expect(await driver.findComponent(ON.text('最近账目'))).assertNull();
        const expense = await driver.findComponent(ON.text('支出'));
        await expense.click();
        await waitForAbsence(driver, ON.id('preview-salary'));
        await driver.waitForComponent(ON.id('preview-lunch'), 5000);
        const income = await driver.findComponent(ON.text('收入'));
        await income.click();
        await driver.waitForComponent(ON.id('preview-salary'), 5000);
        await waitForAbsence(driver, ON.id('preview-lunch'));
        expect(await driver.findComponent(ON.id('preview-lunch'))).assertNull();
        const all = await driver.findComponent(ON.text('全部'));
        await all.click();
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
        await driver.pressBack();
      } finally {
        AppStorage.setOrCreate('ledgerScrollPreview', false);
        AppStorage.setOrCreate('ledgerPreview', false);
      }
    });
  });
}
