import { verifyAccountCalibrationUI } from './AccountCalibrationFlow';
import { verifyTransfersUI } from './TransfersFlow';
import { verifyAccountsUI } from './AccountsFlow';
import { enterAmount } from './AmountKeyboardFlow';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { LedgerDatabase, DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { Money } from '../../../main/ets/core/money/Money';
import { ExpenseCommand } from '../../../main/ets/domain/model/ExpenseRecord';

function sample(workspace: LedgerWorkspace, id: string, categoryId: string = 'expense-food-1', withAccount: boolean = false): ExpenseCommand {
  const now = new Date();
  return { id: id, bookId: DEFAULT_BOOK_ID, categoryId: categoryId,
    gross: Money.parse('13.00', workspace.currency), discount: Money.parse('2.00', workspace.currency),
    bookPaid: Money.parse('11.00', workspace.currency), includeInAssets: withAccount, includeInBudget: withAccount,
    accountId: withAccount ? 'delete-account' : undefined,
    accountPaid: withAccount ? Money.parse('11.00', workspace.currency) : undefined,
    note: '隔离测试', occurredAtMs: now.getTime(), timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    localDate: `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`,
    offsetMinutes: -now.getTimezoneOffset() };
}

async function context(): Promise<common.UIAbilityContext> {
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

export default function expenseFlowTest() {
  describe('ExpenseFlow', () => {
    it('bootstrap_save_rollback_reopen_and_no_reseed', 0, async () => {
      const host = await context();
      const name = 'xiaoqiao_app_test_storage_' + util.generateRandomUUID() + '.db';
      try {
        let workspace = await LedgerWorkspace.open(host, name);
        const command = sample(workspace, 'persisted-expense');
        const month = command.localDate.substring(0, 7);
        let snapshot = await workspace.snapshot(month);
        expect(snapshot.categories.length).assertEqual(18);
        expect(snapshot.accounts.length).assertEqual(0);
        expect(snapshot.entries.length).assertEqual(0);
        expect(snapshot.budgetTotalMinor).assertEqual('250000');
        await workspace.setMonthlyBudget(month, '3000');
        await workspace.setMonthlyBudget(month, '3100');
        await workspace.saveExpense(command);
        // Exact-id retries must reject rather than creating another posted transaction.
        let duplicateRejected = false;
        try { await workspace.saveExpense(command); } catch (_) { duplicateRejected = true; }
        expect(duplicateRejected).assertTrue();
        const invalid = sample(workspace, 'invalid-expense', 'missing-category');
        let invalidRejected = false;
        try { await workspace.saveExpense(invalid); } catch (_) { invalidRejected = true; }
        expect(invalidRejected).assertTrue();
        await LedgerWorkspace.close(name);
        workspace = await LedgerWorkspace.open(host, name);
        snapshot = await workspace.snapshot(month);
        expect(snapshot.entries.length).assertEqual(1);
        expect(snapshot.expenseMinor).assertEqual('1100');
        expect(snapshot.entries[0].grossMinor).assertEqual('1300');
        expect(snapshot.entries[0].discountMinor).assertEqual('200');
        expect(snapshot.budgetUsedMinor).assertEqual('0'); // This fixture explicitly excludes the expense from budget.
        expect(snapshot.budgetTotalMinor).assertEqual('310000');
        expect((await workspace.snapshot('2099-12')).budgetTotalMinor).assertEqual('250000');
        expect(snapshot.incomeMinor).assertEqual('0');
        expect(snapshot.entries[0].category).assertEqual('午餐');
        expect(snapshot.categories.length).assertEqual(18);
        expect(snapshot.entries[0].note).assertEqual('隔离测试');
        await LedgerWorkspace.close(name);
        const db = await LedgerDatabase.open(host, name);
        try {
          const rows = await db.querySql("SELECT CAST(gross_minor AS TEXT),CAST(discount_minor AS TEXT),include_in_budget,include_in_assets FROM transactions");
          try {
            expect(rows.goToFirstRow()).assertTrue();
            expect(rows.getString(0)).assertEqual('1300'); expect(rows.getString(1)).assertEqual('200');
            expect(rows.getLong(2)).assertEqual(0); expect(rows.getLong(3)).assertEqual(0);
          } finally { rows.close(); }
        } finally { await db.close(); }
      } finally {
        await LedgerWorkspace.close(name);
        await relationalStore.deleteRdbStore(host, name);
      }
    });

    it('soft_delete_recalculates_balance_budget_and_rolls_back_on_failure', 0, async () => {
      const host = await context();
      const name = 'xiaoqiao_app_test_delete_' + util.generateRandomUUID() + '.db';
      try {
        const db = await LedgerDatabase.open(host, name);
        try {
          await db.insert('accounts', { id: 'delete-account', name: '隔离钱包', kind: 'asset', currency_id: 'CNY',
            created_at_ms: Date.now(), updated_at_ms: Date.now() });
          await db.executeSql("CREATE TRIGGER reject_test_delete BEFORE UPDATE OF deleted_at_ms ON transactions WHEN OLD.id='rollback-delete' BEGIN SELECT RAISE(ABORT,'test delete failure'); END");
        } finally { await db.close(); }
        let workspace = await LedgerWorkspace.open(host, name);
        const command = sample(workspace, 'delete-target', 'expense-food-1', true);
        const month = command.localDate.substring(0, 7);
        await workspace.saveExpense(command);
        await workspace.saveExpense(sample(workspace, 'keep-entry'));
        await workspace.saveExpense(sample(workspace, 'rollback-delete'));
        expect((await workspace.snapshot(month)).budgetUsedMinor).assertEqual('1100');
        await workspace.deleteEntry('delete-target');
        let snapshot = await workspace.snapshot(month);
        expect(snapshot.entries.length).assertEqual(2);
        expect(snapshot.expenseMinor).assertEqual('2200');
        expect(snapshot.budgetUsedMinor).assertEqual('0');
        let failed = false;
        try { await workspace.deleteEntry('rollback-delete'); } catch (_) { failed = true; }
        expect(failed).assertTrue();
        let repeated = false;
        try { await workspace.deleteEntry('delete-target'); } catch (_) { repeated = true; }
        expect(repeated).assertTrue();
        let missing = false;
        try { await workspace.deleteEntry('missing-entry'); } catch (_) { missing = true; }
        expect(missing).assertTrue();
        await LedgerWorkspace.close(name);
        workspace = await LedgerWorkspace.open(host, name);
        snapshot = await workspace.snapshot(month);
        expect(snapshot.entries.length).assertEqual(2);
        expect(snapshot.expenseMinor).assertEqual('2200');
        expect(snapshot.entries.some((entry) => entry.id === 'keep-entry')).assertTrue();
        expect(snapshot.entries.some((entry) => entry.id === 'rollback-delete')).assertTrue();
        await LedgerWorkspace.close(name);
        const verify = await LedgerDatabase.open(host, name);
        try {
          const rows = await verify.querySql("SELECT deleted_at_ms,revision FROM transactions WHERE id='delete-target'");
          try { expect(rows.goToFirstRow()).assertTrue(); expect(rows.getLong(0) > 0).assertTrue(); expect(rows.getLong(1)).assertEqual(2); }
          finally { rows.close(); }
          const balances = await verify.querySql("SELECT CAST(balance_minor AS TEXT) FROM v_account_balances WHERE account_id='delete-account'");
          try { expect(balances.goToFirstRow()).assertTrue(); expect(balances.getString(0)).assertEqual('0'); }
          finally { balances.close(); }
          const movements = await verify.querySql("SELECT id FROM account_movements WHERE transaction_id='delete-target'");
          try { expect(movements.rowCount).assertEqual(1); } finally { movements.close(); }
          const rollback = await verify.querySql("SELECT deleted_at_ms,revision FROM transactions WHERE id='rollback-delete'");
          try { expect(rollback.goToFirstRow()).assertTrue(); expect(rollback.isColumnNull(0)).assertTrue(); expect(rollback.getLong(1)).assertEqual(1); }
          finally { rollback.close(); }
        } finally { await verify.close(); }
      } finally {
        await LedgerWorkspace.close(name);
        await relationalStore.deleteRdbStore(host, name);
      }
    });

    it('unknown_database_is_not_recreated_or_seeded', 0, async () => {
      const host = await context();
      const name = 'xiaoqiao_app_test_unknown_' + util.generateRandomUUID() + '.db';
      let db = await relationalStore.getRdbStore(host, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
      await db.executeSql('CREATE TABLE sentinel(value TEXT NOT NULL)');
      await db.executeSql("INSERT INTO sentinel VALUES('keep')");
      await db.close();
      try {
        let rejected = false;
        try { const opened = await LedgerDatabase.open(host, name); await opened.close(); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        db = await relationalStore.getRdbStore(host, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
        const rows = await db.querySql('SELECT value FROM sentinel');
        try { expect(rows.goToFirstRow()).assertTrue(); expect(rows.getString(0)).assertEqual('keep'); }
        finally { rows.close(); }
        const objects = await db.querySql("SELECT name FROM sqlite_master WHERE type='table' AND name='books'");
        try { expect(objects.rowCount).assertEqual(0); } finally { objects.close(); }
      } finally {
        await db.close(); await relationalStore.deleteRdbStore(host, name);
      }
    });

    it('date_and_time_picker_refresh_form_without_saving', 0, async () => {
      const driver = Driver.create();
      await driver.waitForComponent(ON.text('开始记第一笔账'), 5000);
      await (await driver.findComponent(ON.text('开始记第一笔账'))).click();
      await driver.waitForComponent(ON.id('expense-native-keyboard'), 5000);
      await driver.pressBack();
      await driver.delayMs(500);
      await (await driver.findComponent(ON.text('时间'))).click();
      const datePicker = await driver.waitForComponent(ON.type('DatePicker'), 5000);
      const beforeDate = await datePicker.getText();
      const dateBounds = await datePicker.getBounds();
      const dayX = Math.round(dateBounds.right - (dateBounds.right - dateBounds.left) * 0.14);
      const middleY = Math.round((dateBounds.top + dateBounds.bottom) / 2);
      await driver.swipe(dayX, middleY + 130, dayX, middleY - 130, 600);
      await driver.delayMs(600);
      const selectedDate = await datePicker.getText();
      expect(selectedDate !== beforeDate).assertTrue();
      const parts = selectedDate.match(/(\d+)年(\d+)月(\d+)日/);
      if (parts === null) { throw new Error('UNEXPECTED_DATE_PICKER_VALUE'); }
      const expectedDate = parts[1] + '-' + parts[2].padStart(2, '0') + '-' + parts[3].padStart(2, '0');
      await (await driver.findComponent(ON.text('确定'))).click();
      const timePicker = await driver.waitForComponent(ON.type('TimePicker'), 5000);
      await driver.delayMs(500);
      const beforeTime = await timePicker.getText();
      const timeBounds = await timePicker.getBounds();
      const minuteX = Math.round(timeBounds.right - (timeBounds.right - timeBounds.left) * 0.25);
      const timeY = Math.round((timeBounds.top + timeBounds.bottom) / 2);
      await driver.swipe(minuteX, timeY + 130, minuteX, timeY - 130, 600);
      await driver.delayMs(600);
      const selectedTime = await timePicker.getText();
      expect(selectedTime !== beforeTime).assertTrue();
      await (await driver.findComponent(ON.text('确定'))).click();
      await driver.waitForComponent(ON.id('expense-native-keyboard'), 5000);
      // The keyboard can cover the lower form rows; inspect the returned value after hiding it.
      await driver.pressBack();
      await driver.waitForComponent(ON.id('expense-resume-amount'), 5000);
      const shown = await (await driver.findComponent(ON.id('expense-date-value'))).getText();
      expect(shown).assertEqual(expectedDate + ' ' + selectedTime);
      await driver.delayMs(500);
      await (await driver.findComponent(ON.id('expense-close'))).click();
      await driver.waitForComponent(ON.text('开始记第一笔账'), 5000);
    });

    it('keyboard_expense_save_returns_to_real_home', 0, async () => {
      const host = await context();
      const name = AppStorage.get<string>('ledgerDatabaseName') || '';
      if (!name.startsWith('xiaoqiao_app_test_')) { throw new Error('ISOLATED_DATABASE_REQUIRED'); }
      try {
      const driver = Driver.create();
      AppStorage.setOrCreate('ledgerPreview', false);
      await driver.waitForComponent(ON.text('开始记第一笔账'), 5000);
      await (await driver.findComponent(ON.text('开始记第一笔账'))).click();
      await driver.waitForComponent(ON.id('expense-keyboard'), 5000);
      const nativeKeyboard = await driver.waitForComponent(ON.id('expense-native-keyboard'), 5000);
      expect(nativeKeyboard !== null).assertTrue();
      expect(await driver.findComponent(ON.id('expense-navigation')) !== null).assertTrue();
      const keyboardBounds = await nativeKeyboard.getBounds();
      const navigationBounds = await (await driver.findComponent(ON.id('expense-navigation'))).getBounds();
      expect(Math.abs(keyboardBounds.left - navigationBounds.left) <= 2).assertTrue();
      expect(Math.abs(keyboardBounds.right - navigationBounds.right) <= 2).assertTrue();
      expect((await (await driver.findComponent(ON.id('expense-amount'))).getBounds()).bottom < keyboardBounds.top).assertTrue();
      expect(await driver.findComponent(ON.id('expense-error'))).assertNull();
      const firstKeyBounds = await (await driver.findComponent(ON.id('expense-key-1'))).getBounds();
      const initialDiscountBounds = await (await driver.findComponent(ON.id('expense-discount-control'))).getBounds();
      const keyHeight = firstKeyBounds.bottom - firstKeyBounds.top;
      const lastKeyBounds = await (await driver.findComponent(ON.id('expense-key-保存'))).getBounds();
      const panelBounds = await (await driver.findComponent(ON.id('expense-keyboard-panel'))).getBounds();
      expect(firstKeyBounds.top - initialDiscountBounds.bottom < keyHeight * 0.25).assertTrue();
      const pixelsPerVp = keyHeight / 48;
      const sideInset = firstKeyBounds.left - panelBounds.left;
      expect(Math.abs(sideInset - 16 * pixelsPerVp) <= 2).assertTrue();
      // The 32vp chip is centered in the 36vp toolbar below the 20vp top inset.
      expect(Math.abs(initialDiscountBounds.top - panelBounds.top - 22 * pixelsPerVp) <= 2).assertTrue();
      expect(Math.abs(panelBounds.bottom - lastKeyBounds.bottom - 32 * pixelsPerVp) <= 2).assertTrue();
      await driver.waitForComponent(ON.id('expense-kind-selector'), 5000);
      const amountBeforeCollapse = await (await driver.findComponent(ON.id('expense-amount'))).getBounds();
      const titleBeforeCollapse = await (await driver.findComponent(ON.id('expense-kind-selector'))).getBounds();
      const amountCard = await (await driver.findComponent(ON.id('expense-amount-card'))).getBounds();
      expect(amountCard.top >= titleBeforeCollapse.bottom).assertTrue();
      const firstCategoryBefore = await (await driver.findComponent(ON.id('expense-category-expense-food'))).getBounds();
      const expandedCard = await (await driver.findComponent(ON.id('expense-categories'))).getBounds();
      const formViewport = await (await driver.findComponent(ON.id('expense-form-scroll'))).getBounds();
      const formCenterX = Math.round((formViewport.left + formViewport.right) / 2);
      await driver.swipe(formCenterX, formViewport.bottom - 20, formCenterX, formViewport.top + 20, 600);
      await driver.waitForComponent(ON.id('expense-categories-compact'), 5000);
      await driver.delayMs(600);
      const collapsedCard = await (await driver.findComponent(ON.id('expense-categories'))).getBounds();
      expect(collapsedCard.bottom - collapsedCard.top < (expandedCard.bottom - expandedCard.top) * 0.75).assertTrue();
      expect(Math.abs((await (await driver.findComponent(ON.id('expense-amount'))).getBounds()).top - amountBeforeCollapse.top) <= 2).assertTrue();
      expect(Math.abs((await (await driver.findComponent(ON.id('expense-kind-selector'))).getBounds()).top - titleBeforeCollapse.top) <= 2).assertTrue();
      const firstCategoryCollapsed = await (await driver.findComponent(ON.id('expense-category-expense-food'))).getBounds();
      expect(Math.abs(firstCategoryCollapsed.top - firstCategoryBefore.top) <= 2).assertTrue();
      const indicator = await driver.waitForComponent(ON.type('SwiperIndicator').within(ON.id('expense-categories-compact')), 5000);
      const indicatorBounds = await indicator.getBounds();
      expect((indicatorBounds.top + indicatorBounds.bottom) / 2 >= firstCategoryCollapsed.bottom - 2).assertTrue();
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-expense-categories-collapsed.png')).assertTrue();
      const categoryY = Math.round((firstCategoryCollapsed.top + firstCategoryCollapsed.bottom) / 2);
      await driver.swipe(collapsedCard.right - 60, categoryY, collapsedCard.left + 60, categoryY, 600);
      await driver.waitForComponent(ON.id('expense-category-expense-fun'), 5000);
      await driver.swipe(collapsedCard.left + 60, categoryY, collapsedCard.right - 60, categoryY, 600);
      await driver.waitForComponent(ON.id('expense-category-expense-food'), 5000);
      const collapsedForm = await (await driver.findComponent(ON.id('expense-form-scroll'))).getBounds();
      await driver.swipe(formCenterX, collapsedForm.top + 20, formCenterX, collapsedForm.bottom - 20, 600);
      await driver.waitForComponent(ON.id('expense-categories-expanded'), 5000);
      await driver.delayMs(600);
      const restoredCategory = await (await driver.findComponent(ON.id('expense-category-expense-food'))).getBounds();
      expect(Math.abs(restoredCategory.top - firstCategoryBefore.top) <= 2).assertTrue();
      expect(Math.abs((await (await driver.findComponent(ON.id('expense-categories'))).getBounds()).bottom - expandedCard.bottom) <= 2).assertTrue();
      await (await driver.findComponent(ON.text('收入').within(ON.id('expense-kind-selector')))).click();
      await driver.waitForComponent(ON.id('expense-category-income-salary'), 5000);
      expect(await driver.findComponent(ON.id('expense-discount-control'))).assertNull();
      expect(await (await driver.findComponent(ON.id('expense-account-label'))).getText()).assertEqual('收款账户');
      await (await driver.findComponent(ON.text('转账').within(ON.id('expense-kind-selector')))).click();
      await driver.waitForComponent(ON.id('expense-to-account-value'), 5000);
      expect(await driver.findComponent(ON.id('expense-categories'))).assertNull();
      expect(await driver.findComponent(ON.id('expense-discount-control'))).assertNull();
      expect(await driver.findComponent(ON.text('转账').selected(true).within(ON.id('expense-kind-selector'))) !== null).assertTrue();
      await (await driver.findComponent(ON.text('支出').within(ON.id('expense-kind-selector')))).click();
      await driver.waitForComponent(ON.id('expense-category-expense-food'), 5000);
      expect(await driver.findComponent(ON.id('expense-discount-control')) !== null).assertTrue();
      await (await driver.findComponent(ON.id('expense-amount'))).click();
      await driver.waitForComponent(ON.id('expense-native-keyboard'), 5000);
      await (await driver.findComponent(ON.id('expense-hide-keyboard'))).click();
      await driver.delayMs(600);
      expect(await driver.findComponent(ON.id('expense-native-keyboard'))).assertNull();
      expect(await driver.findComponent(ON.id('expense-amount')) !== null).assertTrue();
      const resumeBounds = await (await driver.findComponent(ON.id('expense-resume-amount'))).getBounds();
      expect(resumeBounds.bottom < keyboardBounds.bottom).assertTrue();
      await (await driver.findComponent(ON.id('expense-amount'))).click();
      await driver.waitForComponent(ON.id('expense-native-keyboard'), 5000);
      await driver.pressBack();
      await driver.delayMs(600);
      expect(await driver.findComponent(ON.id('expense-keyboard'))).assertNull();
      expect(await driver.findComponent(ON.id('expense-amount')) !== null).assertTrue();
      await (await driver.findComponent(ON.id('expense-amount'))).click();
      await driver.waitForComponent(ON.id('expense-native-keyboard'), 5000);
      const saveKey = await driver.waitForComponent(ON.id('expense-key-保存'), 5000);
      if (saveKey === null) { throw new Error('EXPENSE_KEYBOARD_NOT_VISIBLE'); }
      // Invalid or pending amounts cannot save, but normal typing and recovery remain available.
      expect(await driver.waitForComponent(ON.id('expense-key-保存').enabled(false), 3000) !== null).assertTrue();
      await (await driver.findComponent(ON.id('expense-key-9'))).click();
      await (await driver.findComponent(ON.id('expense-key-+'))).click();
      expect(await driver.waitForComponent(ON.id('expense-key-保存').enabled(false), 3000) !== null).assertTrue();
      await (await driver.findComponent(ON.id('expense-key-1'))).click();
      expect(await driver.waitForComponent(ON.id('expense-key-保存').enabled(true), 3000) !== null).assertTrue();
      await (await driver.findComponent(ON.id('expense-key-清空'))).click();
      for (const key of '900719925474099') {
        await (await driver.findComponent(ON.id('expense-key-' + key))).click();
      }
      expect(await (await driver.findComponent(ON.id('expense-amount'))).getText()).assertEqual('90071992547409');
      const inputError = await driver.findComponent(ON.id('expense-error'));
      expect(await inputError.getText()).assertEqual('金额无法计算或超出范围，请修改输入');
      const errorBounds = await inputError.getBounds();
      const paidForError = await (await driver.findComponent(ON.id('expense-paid'))).getBounds();
      const amountCardForError = await (await driver.findComponent(ON.id('expense-amount-card'))).getBounds();
      expect(errorBounds.top >= paidForError.bottom && errorBounds.bottom <= amountCardForError.bottom).assertTrue();
      const keyboardWithError = await (await driver.findComponent(ON.id('expense-native-keyboard'))).getBounds();
      expect(keyboardWithError.bottom - keyboardWithError.top).assertEqual(keyboardBounds.bottom - keyboardBounds.top);
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-keyboard-error.png')).assertTrue();
      await (await driver.findComponent(ON.id('expense-key-清空'))).click();
      await (await driver.findComponent(ON.id('expense-key-9'))).click();
      await (await driver.findComponent(ON.id('expense-key-⌫'))).click();
      expect(await (await driver.findComponent(ON.id('expense-amount'))).getText()).assertEqual('0');
      await (await driver.findComponent(ON.id('expense-key-9'))).click();
      await (await driver.findComponent(ON.id('expense-key-清空'))).click();
      expect(await (await driver.findComponent(ON.id('expense-amount'))).getText()).assertEqual('0');
      expect(await (await driver.findComponent(ON.id('expense-discount'))).getText()).assertEqual('0');
      for (const key of ['1', '2', '+', '3', '−', '2']) {
        await (await driver.findComponent(ON.id('expense-key-' + key))).click();
      }
      await driver.waitForComponent(ON.text('实付 ¥13.00'), 3000);
      const discountControl = await driver.findComponent(ON.id('expense-discount-control'));
      const discountBefore = await discountControl.getBounds();
      await discountControl.click();
      for (const key of ['−', '1']) { await (await driver.findComponent(ON.id('expense-key-' + key))).click(); }
      const discountError = await driver.waitForComponent(ON.id('expense-error').text('优惠金额无法计算或超出范围，请修改输入'), 5000);
      expect(discountError !== null).assertTrue();
      const discountErrorBounds = await discountError.getBounds();
      const discountInError = await (await driver.findComponent(ON.id('expense-discount-control'))).getBounds();
      const firstKeyInError = await (await driver.findComponent(ON.id('expense-key-1'))).getBounds();
      expect(discountErrorBounds.top >= discountInError.bottom && discountErrorBounds.bottom <= firstKeyInError.top).assertTrue();
      // Wait for native keyboard avoidance to settle after the error line changes the panel height.
      await driver.delayMs(350);
      await (await driver.findComponent(ON.id('expense-key-清空'))).click();
      for (let attempt = 0; attempt < 20; attempt++) {
        if (await driver.findComponent(ON.id('expense-error')) === null) { break; }
        await driver.delayMs(50);
      }
      expect(await driver.findComponent(ON.id('expense-error'))).assertNull();
      for (const key of ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']) {
        await (await driver.findComponent(ON.id('expense-key-' + key))).click();
      }
      expect(await (await driver.findComponent(ON.id('expense-discount'))).getText()).assertEqual('123456789');
      const discountLong = await discountControl.getBounds();
      expect(discountLong.right - discountLong.left > discountBefore.right - discountBefore.left).assertTrue();
      const settlementHideBounds = await (await driver.findComponent(ON.id('expense-hide-keyboard'))).getBounds();
      expect(discountLong.right < settlementHideBounds.left).assertTrue();
      const paidInCard = await (await driver.findComponent(ON.id('expense-paid'))).getBounds();
      const originalAmount = await (await driver.findComponent(ON.id('expense-amount'))).getBounds();
      expect(paidInCard.top >= originalAmount.bottom).assertTrue();
      expect(paidInCard.bottom < (await (await driver.findComponent(ON.id('expense-native-keyboard'))).getBounds()).top).assertTrue();
      await (await driver.findComponent(ON.id('expense-key-清空'))).click();
      expect(await (await driver.findComponent(ON.id('expense-discount'))).getText()).assertEqual('0');
      expect(await (await driver.findComponent(ON.id('expense-amount'))).getText()).assertEqual('12+3−2');
      for (const key of ['5', '+', '2', '−', '5']) {
        await (await driver.findComponent(ON.id('expense-key-' + key))).click();
      }
      expect(await (await driver.findComponent(ON.id('expense-discount'))).getText()).assertEqual('5+2−5');
      expect(await (await driver.findComponent(ON.id('expense-amount'))).getText()).assertEqual('12+3−2');
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-discount-expression.png')).assertTrue();
      await (await driver.findComponent(ON.id('expense-amount'))).click();
      await driver.waitForComponent(ON.text('实付 ¥11.00'), 3000);
      await driver.waitForComponent(ON.id('expense-keyboard'), 5000);
      await driver.delayMs(600);
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-expense-input.png')).assertTrue();
      // Collapse the pinned categories through the user's vertical gesture before accessing lower form fields.
      const categoriesBeforeNote = await (await driver.findComponent(ON.id('expense-categories'))).getBounds();
      const categoriesCenterX = Math.round((categoriesBeforeNote.left + categoriesBeforeNote.right) / 2);
      await driver.swipe(categoriesCenterX, categoriesBeforeNote.bottom - 40,
        categoriesCenterX, categoriesBeforeNote.top + 40, 600);
      await driver.waitForComponent(ON.id('expense-categories-compact'), 5000);
      await driver.delayMs(600);
      const formScroll = await driver.findComponent(ON.id('expense-form-scroll'));
      const noteInput = await formScroll.scrollSearch(ON.id('expense-note'));
      await noteInput.inputText('键盘切换测试');
      await driver.delayMs(600);
      expect(await driver.findComponent(ON.id('expense-native-keyboard'))).assertNull();
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-expense-note-keyboard.png')).assertTrue();
      await (await driver.findComponent(ON.id('expense-note'))).inputText('');
      await driver.pressBack();
      const nature = await formScroll.scrollSearch(ON.id('expense-nature-nature-growth'));
      await nature.click();
      await (await driver.findComponent(ON.id('expense-amount'))).click();
      await driver.waitForComponent(ON.id('expense-native-keyboard'), 5000);
      expect(await (await driver.findComponent(ON.id('expense-amount'))).getText()).assertEqual('12+3−2');
      expect(await (await driver.findComponent(ON.id('expense-paid'))).getText()).assertEqual('实付 ¥11.00');
      await (await driver.findComponent(ON.id('expense-form-scroll'))).scrollToTop(1200);
      await driver.delayMs(600);
      await (await driver.findComponent(ON.id('expense-category-expense-food'))).click();
      await driver.waitForComponent(ON.text('已选中父分类；关闭可保留，或继续选择子分类'), 5000);
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-expense-category-sheet.png')).assertTrue();
      const meal = await driver.waitForComponent(ON.id('expense-category-expense-food-1'), 5000);
      if (meal === null) { throw new Error('MEAL_SHEET_NOT_VISIBLE'); }
      await meal.click();
      await driver.delayMs(600);
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-expense-editor.png')).assertTrue();
      await (await driver.findComponent(ON.id('expense-key-保存'))).click();
      const saved = await driver.waitForComponent(ON.text('午餐'), 10000);
      expect(await saved.getText()).assertEqual('午餐');
      const workspace = await LedgerWorkspace.open(host, name);
      const command = sample(workspace, 'unused');
      const snapshot = await workspace.snapshot(command.localDate.substring(0, 7));
      expect(snapshot.entries.length).assertEqual(1);
      expect(snapshot.entries[0].minor).assertEqual('1100');
      expect(snapshot.entries[0].grossMinor).assertEqual('1300');
      expect(snapshot.entries[0].discountMinor).assertEqual('200');
      expect((await workspace.entryDetail(snapshot.entries[0].id)).spendingNatureId).assertEqual('nature-growth');
      const original = await driver.waitForComponent(ON.id('ledger-original-' + snapshot.entries[0].id), 5000);
      expect(await original.getText()).assertEqual('¥13.00');
      expect(await (await driver.findComponent(ON.id('ledger-discount-value-' + snapshot.entries[0].id))).getText())
        .assertEqual('优惠 2.00');
      const paidBounds = await (await driver.findComponent(ON.text('11.00').within(ON.id(snapshot.entries[0].id)))).getBounds();
      expect((await original.getBounds()).top >= paidBounds.bottom).assertTrue();
      expect(snapshot.expenseMinor).assertEqual('1100');
      expect(snapshot.budgetTotalMinor).assertEqual('250000');
      expect(snapshot.budgetUsedMinor).assertEqual('1100');
      const today = await driver.waitForComponent(ON.text('今天'), 5000);
      const dateLabel = snapshot.entries[0].date.substring(5).replace('-', '月') + '日';
      const dateText = await driver.findComponent(ON.text(dateLabel).within(ON.id('ledger-day-' + snapshot.entries[0].date)));
      expect((await dateText.getBounds()).top >= (await today.getBounds()).bottom).assertTrue();
      expect(await (await driver.findComponent(ON.id('ledger-day-expense-' + snapshot.entries[0].date))).getText()).assertEqual('支 11.00');
      for (const text of await driver.findComponents(ON.type('Text'))) {
        expect((await text.getText()).includes('不使用账户')).assertFalse();
      }
      const expenseTotal = await driver.waitForComponent(ON.id('ledger-expense-total'), 5000);
      expect(await expenseTotal.getText()).assertEqual('11.00');
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-expense-saved.png')).assertTrue();
      // Read the saved receipt and edit the same record, then restore its amount for the existing delete checks.
      const savedId = snapshot.entries[0].id;
      await (await driver.findComponent(ON.id(savedId))).click();
      await driver.waitForComponent(ON.id('entry-detail-amount'), 5000);
      expect(await (await driver.findComponent(ON.id('entry-detail-amount'))).getText()).assertEqual('11.00');
      expect(await (await driver.findComponent(ON.id('entry-detail-discount'))).getText()).assertEqual('优惠 2.00');
      await driver.waitForComponent(ON.text('成长提升'), 5000);
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-entry-receipt.png')).assertTrue();
      await (await driver.findComponent(ON.id('entry-detail-edit'))).click();
      await driver.waitForComponent(ON.id('expense-edit-title'), 5000);
      expect(await (await driver.findComponent(ON.id('expense-amount'))).getText()).assertEqual('13.00');
      expect(await (await driver.findComponent(ON.id('expense-discount'))).getText()).assertEqual('2.00');
      await (await driver.findComponent(ON.id('expense-key-清空'))).click();
      await (await driver.findComponent(ON.id('expense-key-1'))).click();
      await (await driver.findComponent(ON.id('expense-key-4'))).click();
      await (await driver.findComponent(ON.id('expense-key-保存'))).click();
      await driver.waitForComponent(ON.id('entry-detail-amount'), 5000);
      expect(await (await driver.findComponent(ON.id('entry-detail-amount'))).getText()).assertEqual('12.00');
      const editedSnapshot = await workspace.snapshot(command.localDate.substring(0, 7));
      expect(editedSnapshot.entries.length).assertEqual(1);
      expect(editedSnapshot.entries[0].id).assertEqual(savedId);
      expect(editedSnapshot.expenseMinor).assertEqual('1200'); expect(editedSnapshot.budgetUsedMinor).assertEqual('1200');
      await driver.delayMs(3200); // HDS saved feedback dismisses before the next bottom action.
      await (await driver.findComponent(ON.id('entry-detail-edit'))).click();
      await driver.waitForComponent(ON.id('expense-edit-title'), 5000);
      await (await driver.findComponent(ON.id('expense-key-清空'))).click();
      await (await driver.findComponent(ON.id('expense-key-1'))).click();
      await (await driver.findComponent(ON.id('expense-key-3'))).click();
      await (await driver.findComponent(ON.id('expense-key-保存'))).click();
      await driver.waitForComponent(ON.id('entry-detail-amount'), 5000);
      expect(await (await driver.findComponent(ON.id('entry-detail-amount'))).getText()).assertEqual('11.00');
      await driver.delayMs(3200);
      await (await driver.findComponent(ON.id('entry-detail-close'))).click();
      await driver.waitForComponent(ON.id(savedId), 5000);
      await (await driver.findComponent(ON.id('ledger-edit-budget'))).click();
      await driver.waitForComponent(ON.text('修改月预算'), 5000);
      await enterAmount(driver, 'ledger-budget-input', '3000+');
      expect(await driver.waitForComponent(ON.id('ledger-budget-input-key-保存').enabled(false), 3000) !== null).assertTrue();
      await (await driver.findComponent(ON.id('ledger-budget-input-key-⌫'))).click();
      await driver.delayMs(600);
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-budget-editing.png')).assertTrue();
      const budgetSave = await driver.waitForComponent(ON.id('ledger-budget-input-key-保存').enabled(true), 3000);
      if (budgetSave === null) { throw new Error('BUDGET_SAVE_NOT_VISIBLE'); }
      await budgetSave.click();
      const remaining = await driver.waitForComponent(ON.text('2,989.00'), 5000);
      expect(remaining !== null).assertTrue();
      expect((await workspace.snapshot(command.localDate.substring(0, 7))).budgetTotalMinor).assertEqual('300000');
      await driver.delayMs(600); // Wait for the sheet's exit animation before the visual capture.
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-budget-updated.png')).assertTrue();
      const rowId = snapshot.entries[0].id;
      const cardBounds = await (await driver.findComponent(ON.id(rowId))).getBounds();
      const centerY = Math.round((cardBounds.top + cardBounds.bottom) / 2);
      await driver.swipe(cardBounds.right - 20, centerY, cardBounds.left + 20, centerY, 600);
      await driver.delayMs(600);
      expect(await (await driver.findComponent(ON.id('ledger-edit-' + rowId))).isEnabled()).assertTrue();
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-ledger-swipe.png')).assertTrue();
      await (await driver.findComponent(ON.id('ledger-edit-' + rowId))).click();
      await driver.waitForComponent(ON.id('expense-edit-title'), 5000);
      await (await driver.findComponent(ON.id('expense-close'))).click();
      await driver.waitForComponent(ON.id('entry-detail-amount'), 5000);
      expect((await workspace.entryDetail(rowId)).revision).assertEqual(3);
      await (await driver.findComponent(ON.id('entry-detail-close'))).click();
      const swipeAgain = await (await driver.waitForComponent(ON.id(rowId), 5000)).getBounds();
      const swipeY = Math.round((swipeAgain.top + swipeAgain.bottom) / 2);
      await driver.swipe(swipeAgain.right - 20, swipeY, swipeAgain.left + 20, swipeY, 600);
      await driver.delayMs(600);
      const deleteAction = await driver.waitForComponent(ON.id('ledger-delete-' + rowId), 5000);
      await deleteAction.click();
      await driver.waitForComponent(ON.text('确定删除这笔账目吗？'), 5000);
      const deleteMessage = '午餐・¥11.00\n账目删除之后不能恢复，请谨慎删除';
      expect(await (await driver.waitForComponent(ON.text(deleteMessage), 5000)).getText()).assertEqual(deleteMessage);
      await (await driver.findComponent(ON.text('取消'))).click();
      await driver.delayMs(600);
      expect((await workspace.snapshot(command.localDate.substring(0, 7))).entries.length).assertEqual(1);
      // Right-swipe closes the actions; long press opens a native preview context menu instead.
      await driver.swipe(cardBounds.left + 20, centerY, cardBounds.right - 20, centerY, 600);
      await driver.delayMs(600);
      expect(await driver.findComponent(ON.id('ledger-delete-' + rowId))).assertNull();
      await (await driver.findComponent(ON.id(rowId))).longClick();
      await driver.delayMs(600);
      await driver.waitForComponent(ON.id('ledger-menu-delete-' + rowId), 5000);
      expect(await (await driver.findComponent(ON.id('ledger-menu-edit-' + rowId))).isEnabled()).assertTrue();
      expect(await driver.findComponent(ON.id('ledger-delete-' + rowId))).assertNull();
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-ledger-long-press.png')).assertTrue();
      // The long-press edit entry also loads the same record; cancel must not write.
      await (await driver.findComponent(ON.id('ledger-menu-edit-' + rowId))).click();
      await driver.waitForComponent(ON.id('expense-edit-title'), 5000);
      await (await driver.findComponent(ON.id('expense-close'))).click();
      await driver.waitForComponent(ON.id('entry-detail-amount'), 5000);
      expect((await workspace.entryDetail(rowId)).revision).assertEqual(3);
      await (await driver.findComponent(ON.id('entry-detail-close'))).click();
      await driver.delayMs(600);
      expect((await workspace.snapshot(command.localDate.substring(0, 7))).entries.length).assertEqual(1);
      expect(await driver.findComponent(ON.id('ledger-menu-delete-' + rowId))).assertNull();
      await (await driver.findComponent(ON.id(rowId))).longClick();
      await driver.delayMs(600);
      await (await driver.waitForComponent(ON.id('ledger-menu-delete-' + rowId), 5000)).click();
      await driver.waitForComponent(ON.text('确定删除这笔账目吗？'), 5000);
      await driver.delayMs(400);
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-ledger-delete-confirm.png')).assertTrue();
      const confirms = await driver.findComponents(ON.text('删除'));
      await confirms[confirms.length - 1].click();
      await driver.waitForComponent(ON.text('开始记第一笔账'), 5000);
      const deleted = await workspace.snapshot(command.localDate.substring(0, 7));
      expect(deleted.entries.length).assertEqual(0);
      expect(deleted.expenseMinor).assertEqual('0');
      expect(deleted.budgetUsedMinor).assertEqual('0');
      await driver.waitForComponent(ON.text('3,000.00'), 5000);
      expect(await driver.findComponent(ON.id('ledger-day-' + snapshot.entries[0].date))).assertNull();
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-ledger-deleted.png')).assertTrue();
      // Income uses the same editor, but no discount/budget controls and no expense-budget effect.
      await driver.delayMs(3200);
      await (await driver.findComponent(ON.text('开始记第一笔账'))).click();
      await driver.waitForComponent(ON.id('expense-keyboard'), 5000);
      await (await driver.findComponent(ON.text('收入').within(ON.id('expense-kind-selector')))).click();
      await driver.waitForComponent(ON.id('expense-category-income-salary'), 5000);
      expect(await driver.findComponent(ON.id('expense-discount-control'))).assertNull();
      expect(await driver.findComponent(ON.id('expense-budget-rule'))).assertNull();
      expect(await (await driver.findComponent(ON.id('expense-account-label'))).getText()).assertEqual('收款账户');
      for (const key of ['1', '2', '5', '+', '7', '5']) { await (await driver.findComponent(ON.id('expense-key-' + key))).click(); }
      expect(await (await driver.findComponent(ON.id('expense-paid'))).getText()).assertEqual('到账 ¥200.00');
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-income-input.png')).assertTrue();
      await (await driver.findComponent(ON.id('expense-key-保存'))).click();
      await driver.waitForComponent(ON.text('工资'), 5000);
      let incomeSnapshot = await workspace.snapshot(command.localDate.substring(0, 7));
      expect(incomeSnapshot.entries.length).assertEqual(1);
      expect(incomeSnapshot.incomeMinor).assertEqual('20000'); expect(incomeSnapshot.budgetUsedMinor).assertEqual('0');
      const incomeId = incomeSnapshot.entries[0].id;
      expect(incomeSnapshot.entries[0].income).assertTrue();
      await (await driver.findComponent(ON.id(incomeId))).click();
      await driver.waitForComponent(ON.id('entry-detail-amount'), 5000);
      expect(await (await driver.findComponent(ON.id('entry-detail-amount'))).getText()).assertEqual('200.00');
      expect(await driver.findComponent(ON.id('entry-detail-discount'))).assertNull();
      await (await driver.findComponent(ON.id('entry-detail-edit'))).click();
      await driver.waitForComponent(ON.text('编辑收入'), 5000);
      expect(await (await driver.findComponent(ON.id('expense-amount'))).getText()).assertEqual('200.00');
      expect(await driver.findComponent(ON.id('expense-discount-control'))).assertNull();
      await (await driver.findComponent(ON.id('expense-key-清空'))).click();
      for (const key of ['2', '5', '0']) { await (await driver.findComponent(ON.id('expense-key-' + key))).click(); }
      await (await driver.findComponent(ON.id('expense-key-保存'))).click();
      await driver.waitForComponent(ON.id('entry-detail-amount').text('250.00'), 5000);
      await driver.delayMs(3200);
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-income-receipt.png')).assertTrue();
      incomeSnapshot = await workspace.snapshot(command.localDate.substring(0, 7));
      expect(incomeSnapshot.entries.length).assertEqual(1); expect(incomeSnapshot.entries[0].id).assertEqual(incomeId);
      expect(incomeSnapshot.incomeMinor).assertEqual('25000'); expect(incomeSnapshot.budgetUsedMinor).assertEqual('0');
      await (await driver.findComponent(ON.id('entry-detail-edit'))).click();
      await driver.waitForComponent(ON.text('编辑收入'), 5000);
      await (await driver.findComponent(ON.id('expense-close'))).click();
      await driver.waitForComponent(ON.id('entry-detail-amount'), 5000);
      expect((await workspace.entryDetail(incomeId)).revision).assertEqual(2);
      await (await driver.findComponent(ON.id('entry-detail-delete'))).click();
      await driver.waitForComponent(ON.text('确定删除这笔账目吗？'), 5000);
      const incomeConfirms = await driver.findComponents(ON.text('删除'));
      await incomeConfirms[incomeConfirms.length - 1].click();
      await driver.waitForComponent(ON.text('开始记第一笔账'), 5000);
      expect((await workspace.snapshot(command.localDate.substring(0, 7))).incomeMinor).assertEqual('0');
      await verifyAccountsUI(driver, host, workspace, command.localDate.substring(0, 7));
      await verifyTransfersUI(driver, host, workspace, command.localDate.substring(0, 7));
      await verifyAccountCalibrationUI(driver, host, workspace, command.localDate.substring(0, 7));
      } finally {
        // Only this run's UUID fixture is removed, even when the added account UI checks fail.
        await LedgerWorkspace.close(name);
        await relationalStore.deleteRdbStore(host, name);
      }
    });
  });
}
