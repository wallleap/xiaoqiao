import { common } from '@kit.AbilityKit';
import { Driver, ON } from '@kit.TestKit';
import { expect } from '@ohos/hypium';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { Money } from '../../../main/ets/core/money/Money';

async function waitText(driver: Driver, id: string, value: string): Promise<void> {
  const component = await driver.waitForComponent(ON.id(id).text(value), 5000);
  if (component === null) {
    const actual = await driver.findComponent(ON.id(id));
    throw new Error('CALIBRATION_UI_TEXT: ' + id + ' expected=' + value + ' actual=' + (actual === null ? '<missing>' : await actual.getText()));
  }
  expect(await component.getText()).assertEqual(value);
}
async function waitAccountBalance(driver: Driver, id: string, value: string): Promise<void> {
  const component = await driver.waitForComponent(ON.text(value).within(ON.id('account-row-' + id)), 5000);
  expect(component !== null).assertTrue(); expect(await component.getText()).assertEqual(value);
  // HDS save feedback has a three-second lifetime; wait before opening another fixed footer.
  await driver.delayMs(3200);
}

/** Runs at the end of ExpenseFlow, only in its UUID fixture which is removed in finally. */
export async function verifyAccountCalibrationUI(driver: Driver, host: common.UIAbilityContext, workspace: LedgerWorkspace, month: string): Promise<void> {
  try {
  await driver.delayMs(3200);
  const overview = await workspace.accountOverview();
  const asset = overview.accounts.find((item) => item.name === '改名账户');
  const debt = overview.accounts.find((item) => item.kind === 'liability');
  if (asset === undefined || debt === undefined) { throw new Error('CALIBRATION_FIXTURE_MISSING'); }
  await (await driver.findComponent(ON.id('ledger-tab-3'))).click();
  await (await driver.waitForComponent(ON.id('account-row-' + asset.id), 5000)).click();
  await (await driver.waitForComponent(ON.id('account-calibrate'), 5000)).click();
  await waitText(driver, 'calibration-before', '100.00');
  await (await driver.findComponent(ON.id('calibration-amount'))).inputText('80.00');
  await driver.delayMs(600); await driver.pressBack();
  await driver.waitForComponent(ON.id('account-calibration-page'), 5000);
  await (await driver.findComponent(ON.id('calibration-reason'))).inputText('与银行对账');
  await driver.delayMs(600); await driver.pressBack();
  await waitText(driver, 'calibration-after', '80.00');
  await waitText(driver, 'calibration-delta', '-20.00');
  await driver.delayMs(500); expect(await driver.screenCap(host.filesDir + '/xiaoqiao-calibration-preview.png')).assertTrue();
  await (await driver.findComponent(ON.id('calibration-confirm'))).click();
  await driver.waitForComponent(ON.text('确认校准余额？'), 5000);
  await (await driver.findComponent(ON.text('取消'))).click();
  await driver.waitForComponent(ON.id('account-calibration-page'), 5000);
  expect((await workspace.accountOverview()).accounts.find((item) => item.id === asset.id)?.balanceMinor).assertEqual('10000');
  expect((await workspace.accountAdjustments(asset.id)).items.length).assertEqual(1);
  await driver.delayMs(600);
  await (await driver.findComponent(ON.id('calibration-confirm'))).click();
  await (await driver.waitForComponent(ON.text('确认校准'), 5000)).click();
  await waitAccountBalance(driver, asset.id, '80.00');
  const first = (await workspace.accountAdjustments(asset.id)).items.find((item) => item.kind === 'calibration');
  if (first === undefined) { throw new Error('CALIBRATION_HISTORY_MISSING'); }
  expect(first.reason).assertEqual('与银行对账');
  await (await driver.findComponent(ON.id('account-row-' + asset.id))).click();
  await (await driver.waitForComponent(ON.id('account-adjustments'), 5000)).click();
  await waitText(driver, 'adjustment-after-' + first.id, '80.00');
  await driver.waitForComponent(ON.text('期初余额'), 5000);
  await driver.delayMs(500); expect(await driver.screenCap(host.filesDir + '/xiaoqiao-calibration-history.png')).assertTrue();
  await (await driver.findComponent(ON.id('adjustment-history-close'))).click();
  await (await driver.waitForComponent(ON.id('account-calibrate'), 5000)).click();
  await waitText(driver, 'calibration-before', '80.00');
  await (await driver.waitForComponent(ON.id('calibration-amount'), 5000)).inputText('70.00');
  await driver.delayMs(600); await driver.pressBack();
  // Simulate an intervening real income while the preview still carries the old balance.
  const date = new Date(); const ten = Money.parse('10', workspace.currency);
  await workspace.saveIncome({ id: 'calibration-intervening-income', bookId: DEFAULT_BOOK_ID, categoryId: 'income-salary', amount: ten, bookAmount: ten,
    accountId: asset.id, accountAmount: ten, includeInAssets: true, note: '校准并发验证', occurredAtMs: date.getTime(), localDate: `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -date.getTimezoneOffset() });
  await (await driver.findComponent(ON.id('calibration-confirm'))).click();
  await (await driver.waitForComponent(ON.text('确认校准'), 5000)).click();
  await driver.waitForComponent(ON.id('calibration-refresh'), 5000);
  expect((await workspace.accountOverview()).accounts.find((item) => item.id === asset.id)?.balanceMinor).assertEqual('9000');
  expect((await workspace.accountAdjustments(asset.id)).items.length).assertEqual(2);
  const refresh = await driver.findComponent(ON.id('calibration-refresh'));
  const refreshBounds = await refresh.getBounds();
  const pageBounds = await (await driver.findComponent(ON.id('account-calibration-page'))).getBounds();
  expect(refreshBounds.bottom <= pageBounds.bottom).assertTrue();
  await driver.delayMs(500); expect(await driver.screenCap(host.filesDir + '/xiaoqiao-calibration-conflict.png')).assertTrue();
  await refresh.click();
  await waitText(driver, 'calibration-before', '90.00');
  await waitText(driver, 'calibration-after', '70.00');
  await waitText(driver, 'calibration-delta', '-20.00');
  await (await driver.findComponent(ON.id('calibration-confirm'))).click();
  await (await driver.waitForComponent(ON.text('确认校准'), 5000)).click();
  await waitAccountBalance(driver, asset.id, '70.00');
  expect((await workspace.accountAdjustments(asset.id)).items.length).assertEqual(3);
  expect((await workspace.snapshot(month)).incomeMinor).assertEqual('1000');
  await workspace.deleteEntry('calibration-intervening-income');
  await (await driver.findComponent(ON.id('account-row-' + debt.id))).click();
  await (await driver.waitForComponent(ON.id('account-calibrate'), 5000)).click();
  await waitText(driver, 'calibration-before', '0.00');
  await (await driver.waitForComponent(ON.id('calibration-amount'), 5000)).inputText('40.00');
  await driver.delayMs(600); await driver.pressBack();
  await waitText(driver, 'calibration-after', '-40.00');
  await waitText(driver, 'calibration-delta', '-40.00');
  await driver.delayMs(500); expect(await driver.screenCap(host.filesDir + '/xiaoqiao-calibration-debt.png')).assertTrue();
  await (await driver.findComponent(ON.id('calibration-confirm'))).click();
  await (await driver.waitForComponent(ON.text('确认校准'), 5000)).click();
  await waitAccountBalance(driver, debt.id, '-40.00');
  expect((await workspace.accountOverview()).netMinor).assertEqual('-4000');
  await (await driver.findComponent(ON.id('account-row-' + debt.id))).click();
  await (await driver.waitForComponent(ON.id('account-calibrate'), 5000)).click();
  await waitText(driver, 'calibration-before', '-40.00');
  await (await driver.waitForComponent(ON.text('溢缴余额').within(ON.id('calibration-direction')), 5000)).click();
  await (await driver.findComponent(ON.id('calibration-amount'))).inputText('5.25');
  await driver.delayMs(600); await driver.pressBack();
  await waitText(driver, 'calibration-after', '5.25');
  await waitText(driver, 'calibration-delta', '+45.25');
  await (await driver.findComponent(ON.id('calibration-confirm'))).click();
  await (await driver.waitForComponent(ON.text('确认校准'), 5000)).click();
  await waitAccountBalance(driver, debt.id, '5.25');
  const final = await workspace.snapshot(month);
  expect(final.entries.length).assertEqual(0); expect(final.incomeMinor).assertEqual('0'); expect(final.expenseMinor).assertEqual('0'); expect(final.budgetUsedMinor).assertEqual('0');
  expect((await workspace.accountOverview()).netMinor).assertEqual('525');
  } catch (error) {
    await driver.screenCap(host.filesDir + '/xiaoqiao-calibration-ui-failure.png');
    throw error as Error;
  }
}
