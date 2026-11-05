import { common } from '@kit.AbilityKit';
import { Driver, ON } from '@kit.TestKit';
import { expect } from '@ohos/hypium';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';

export async function verifyTransfersUI(driver: Driver, host: common.UIAbilityContext, workspace: LedgerWorkspace, month: string): Promise<void> {
  await driver.delayMs(3200);
  const from = (await workspace.accountOverview()).accounts[0];
  await (await driver.findComponent(ON.id('ledger-tab-3'))).click();
  await (await driver.waitForComponent(ON.id('accounts-create'), 5000)).click();
  await (await driver.waitForComponent(ON.id('account-name'), 5000)).inputText('转入测试账户');
  await driver.delayMs(600); await driver.pressBack();
  await (await driver.waitForComponent(ON.id('account-save'), 5000)).click();
  await driver.waitForComponent(ON.id('accounts-page'), 5000); await driver.delayMs(3200);
  const to = (await workspace.accountOverview()).accounts.find((item) => item.id !== from.id);
  if (to === undefined) { throw new Error('TRANSFER_RECEIVER_MISSING'); }
  await (await driver.findComponent(ON.id('ledger-add-expense'))).click();
  await driver.waitForComponent(ON.id('expense-keyboard'), 5000);
  await (await driver.findComponent(ON.text('转账').within(ON.id('expense-kind-selector')))).click();
  expect(await driver.findComponent(ON.id('expense-categories'))).assertNull();
  expect(await driver.findComponent(ON.id('expense-discount-control'))).assertNull();
  expect(await driver.findComponent(ON.id('expense-budget-rule'))).assertNull();
  await (await driver.findComponent(ON.id('expense-hide-keyboard'))).click();
  await driver.waitForComponent(ON.id('expense-resume-amount'), 5000);
  await (await driver.findComponent(ON.id('expense-account-value'))).click();
  await (await driver.waitForComponent(ON.text(from.name), 5000)).click();
  await driver.waitForComponent(ON.id('expense-keyboard'), 5000);
  await (await driver.findComponent(ON.id('expense-hide-keyboard'))).click();
  await driver.waitForComponent(ON.id('expense-resume-amount'), 5000);
  await (await driver.findComponent(ON.id('expense-to-account-value'))).click();
  await (await driver.waitForComponent(ON.text(to.name), 5000)).click();
  await driver.waitForComponent(ON.id('expense-keyboard'), 5000);
  expect(await (await driver.findComponent(ON.id('expense-account-value'))).getText()).assertEqual(from.name);
  expect(await (await driver.findComponent(ON.id('expense-to-account-value'))).getText()).assertEqual(to.name);
  await (await driver.findComponent(ON.id('transfer-swap-accounts'))).click();
  expect(await (await driver.findComponent(ON.id('expense-account-value'))).getText()).assertEqual(to.name);
  expect(await (await driver.findComponent(ON.id('expense-to-account-value'))).getText()).assertEqual(from.name);
  await (await driver.findComponent(ON.id('transfer-swap-accounts'))).click();
  expect(await (await driver.findComponent(ON.id('expense-account-value'))).getText()).assertEqual(from.name);
  expect(await (await driver.findComponent(ON.id('expense-to-account-value'))).getText()).assertEqual(to.name);
  for (const key of ['2', '5']) { await (await driver.findComponent(ON.id('expense-key-' + key))).click(); }
  await driver.waitForComponent(ON.id('expense-amount').text('25'), 5000);
  await driver.waitForComponent(ON.id('expense-paid').text('实际转出 ¥25.00 · 转入 ¥25.00'), 5000);
  expect(await driver.screenCap(host.filesDir + '/xiaoqiao-transfer-input.png')).assertTrue();
  await (await driver.findComponent(ON.id('expense-key-保存'))).click();
  await driver.waitForComponent(ON.text('转账'), 5000);
  let snapshot = await workspace.snapshot(month);
  expect(snapshot.entries.length).assertEqual(1); expect(snapshot.entries[0].transfer).assertTrue();
  const id = snapshot.entries[0].id;
  expect(snapshot.incomeMinor).assertEqual('0'); expect(snapshot.expenseMinor).assertEqual('0'); expect(snapshot.budgetUsedMinor).assertEqual('0');
  let accounts = (await workspace.accountOverview()).accounts;
  expect(accounts.find((item) => item.id === from.id)?.balanceMinor).assertEqual('7500');
  expect(accounts.find((item) => item.id === to.id)?.balanceMinor).assertEqual('2500');
  // Both income and expense filters exclude principal, while All restores the same one-row transfer.
  for (const label of ['支出', '收入']) {
    await (await driver.findComponent(ON.text(label).within(ON.id('ledger-filters')))).click();
    await driver.waitForComponent(ON.text('没有符合条件的账目'), 5000);
    expect(await driver.findComponent(ON.id(id))).assertNull();
  }
  await (await driver.findComponent(ON.text('全部').within(ON.id('ledger-filters')))).click();
  await (await driver.waitForComponent(ON.id(id), 5000)).click();
  await driver.waitForComponent(ON.id('entry-detail-amount').text('25.00'), 5000);
  expect(await (await driver.findComponent(ON.id('entry-detail-from-account'))).getText()).assertEqual(from.name);
  expect(await (await driver.findComponent(ON.id('entry-detail-to-account'))).getText()).assertEqual(to.name);
  expect(await driver.screenCap(host.filesDir + '/xiaoqiao-transfer-receipt.png')).assertTrue();
  await (await driver.findComponent(ON.id('entry-detail-edit'))).click();
  await driver.waitForComponent(ON.text('编辑转账'), 5000);
  expect(await (await driver.findComponent(ON.id('expense-amount'))).getText()).assertEqual('25.00');
  await (await driver.findComponent(ON.id('expense-key-清空'))).click();
  for (const key of ['4', '0']) { await (await driver.findComponent(ON.id('expense-key-' + key))).click(); }
  await (await driver.findComponent(ON.id('expense-key-保存'))).click();
  await driver.waitForComponent(ON.id('entry-detail-amount').text('40.00'), 5000); await driver.delayMs(3200);
  const detail = await workspace.entryDetail(id);
  expect(detail.revision).assertEqual(2); expect(detail.accountId).assertEqual(from.id); expect(detail.toAccountId).assertEqual(to.id);
  accounts = (await workspace.accountOverview()).accounts;
  expect(accounts.find((item) => item.id === from.id)?.balanceMinor).assertEqual('6000');
  expect(accounts.find((item) => item.id === to.id)?.balanceMinor).assertEqual('4000');
  await (await driver.findComponent(ON.id('entry-detail-edit'))).click();
  await driver.waitForComponent(ON.text('编辑转账'), 5000);
  await (await driver.findComponent(ON.id('expense-close'))).click();
  await driver.waitForComponent(ON.id('entry-detail-amount').text('40.00'), 5000);
  expect((await workspace.entryDetail(id)).revision).assertEqual(2);
  await (await driver.findComponent(ON.id('entry-detail-delete'))).click();
  await driver.waitForComponent(ON.text('确定删除这笔账目吗？'), 5000);
  const deletes = await driver.findComponents(ON.text('删除')); await deletes[deletes.length - 1].click();
  await driver.waitForComponent(ON.text('开始记第一笔账'), 5000);
  snapshot = await workspace.snapshot(month); expect(snapshot.entries.length).assertEqual(0);
  accounts = (await workspace.accountOverview()).accounts;
  expect(accounts.find((item) => item.id === from.id)?.balanceMinor).assertEqual('10000');
  expect(accounts.find((item) => item.id === to.id)?.balanceMinor).assertEqual('0');
  // Add a liability account, then verify fee/coupon editing through the actual custom keyboard.
  await (await driver.findComponent(ON.id('ledger-tab-3'))).click();
  await (await driver.waitForComponent(ON.id('accounts-create'), 5000)).click();
  await (await driver.waitForComponent(ON.id('account-name'), 5000)).inputText('还款测试信用卡');
  await driver.delayMs(600); await driver.pressBack();
  await (await driver.findComponent(ON.text('负债账户').within(ON.id('account-kind')))).click();
  await (await driver.findComponent(ON.id('account-save'))).click();
  await driver.waitForComponent(ON.id('accounts-page'), 5000); await driver.delayMs(3200);
  const debt = (await workspace.accountOverview()).accounts.find((item) => item.kind === 'liability');
  if (debt === undefined) { throw new Error('UI_REPAYMENT_ACCOUNT_MISSING'); }
  await (await driver.findComponent(ON.id('ledger-add-expense'))).click();
  await driver.waitForComponent(ON.id('expense-keyboard'), 5000);
  await (await driver.findComponent(ON.text('转账').within(ON.id('expense-kind-selector')))).click();
  await (await driver.findComponent(ON.id('expense-hide-keyboard'))).click();
  await driver.waitForComponent(ON.id('expense-resume-amount'), 5000);
  await (await driver.findComponent(ON.id('transfer-purpose'))).click();
  await (await driver.waitForComponent(ON.text('信用卡还款'), 5000)).click();
  await driver.waitForComponent(ON.id('expense-keyboard'), 5000);
  await (await driver.findComponent(ON.id('expense-account-value'))).click();
  await (await driver.waitForComponent(ON.text(from.name), 5000)).click();
  await driver.waitForComponent(ON.id('expense-keyboard'), 5000);
  await (await driver.findComponent(ON.id('expense-to-account-value'))).click();
  await (await driver.waitForComponent(ON.text(debt.name), 5000)).click();
  await driver.waitForComponent(ON.id('expense-keyboard'), 5000);
  for (const key of ['1','0','0']) { await (await driver.findComponent(ON.id('expense-key-' + key))).click(); }
  await (await driver.findComponent(ON.id('transfer-fee-control'))).click();
  for (const key of ['1','+','1']) { await (await driver.findComponent(ON.id('expense-key-' + key))).click(); }
  await (await driver.findComponent(ON.id('transfer-coupon-control'))).click();
  for (const key of ['7','−','2']) { await (await driver.findComponent(ON.id('expense-key-' + key))).click(); }
  await driver.waitForComponent(ON.id('expense-paid').text('实际转出 ¥97.00 · 转入 ¥100.00'), 5000);
  await driver.waitForComponent(ON.id('transfer-fee-expression').text('1+1'), 5000);
  await driver.waitForComponent(ON.id('transfer-coupon-expression').text('7−2'), 5000);
  await driver.delayMs(500);
  expect(await driver.screenCap(host.filesDir + '/xiaoqiao-repayment-input.png')).assertTrue();
  await (await driver.findComponent(ON.id('expense-key-保存'))).click();
  await driver.waitForComponent(ON.text('信用卡还款'), 5000); await driver.delayMs(3200);
  snapshot = await workspace.snapshot(month);
  expect(snapshot.entries.length).assertEqual(1); expect(snapshot.expenseMinor).assertEqual('200'); expect(snapshot.budgetUsedMinor).assertEqual('200');
  const repaymentId = snapshot.entries[0].id;
  accounts = (await workspace.accountOverview()).accounts;
  expect(accounts.find((item) => item.id === from.id)?.balanceMinor).assertEqual('300');
  expect(accounts.find((item) => item.id === debt.id)?.balanceMinor).assertEqual('10000');
  await (await driver.findComponent(ON.text('支出').within(ON.id('ledger-filters')))).click();
  await driver.waitForComponent(ON.text('2.00').within(ON.id(repaymentId)), 5000);
  await driver.delayMs(500); expect(await driver.screenCap(host.filesDir + '/xiaoqiao-repayment-expense.png')).assertTrue();
  await (await driver.waitForComponent(ON.id(repaymentId), 5000)).click();
  await driver.waitForComponent(ON.id('entry-detail-amount').text('97.00'), 5000);
  await driver.delayMs(500); expect(await driver.screenCap(host.filesDir + '/xiaoqiao-repayment-receipt.png')).assertTrue();
  await (await driver.findComponent(ON.id('entry-detail-edit'))).click();
  await driver.waitForComponent(ON.text('编辑转账'), 5000);
  await driver.waitForComponent(ON.id('expense-paid').text('实际转出 ¥97.00 · 转入 ¥100.00'), 5000);
  await (await driver.findComponent(ON.id('expense-close'))).click();
  await driver.waitForComponent(ON.id('entry-detail-delete'), 5000);
  await (await driver.findComponent(ON.id('entry-detail-delete'))).click();
  await driver.waitForComponent(ON.text('确定删除这笔账目吗？'), 5000);
  const repaymentDeletes = await driver.findComponents(ON.text('删除')); await repaymentDeletes[repaymentDeletes.length - 1].click();
  await driver.waitForComponent(ON.text('没有符合条件的账目'), 5000);
  expect((await workspace.snapshot(month)).expenseMinor).assertEqual('0');
  expect((await workspace.accountOverview()).accounts.find((item) => item.id === from.id)?.balanceMinor).assertEqual('10000');

}
