import { common } from '@kit.AbilityKit';
import { Driver, ON, abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { enterAmount } from './AmountKeyboardFlow';

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

export default function budgetNatureFlowTest() {
  describe('BudgetNatureUI', () => {
    it('sets_monthly_nature_budget_from_budget_page', 0, async () => {
      const context = await uiContext();
      const driver = Driver.create();
      await driver.waitForComponent(ON.id('ledger-edit-budget'), 10000);
      await (await driver.findComponent(ON.id('ledger-edit-budget'))).click();
      await driver.waitForComponent(ON.id('budget-page'), 5000);
      await (await driver.waitForComponent(ON.id('budget-nature-nature-survival'), 5000)).click();
      await enterAmount(driver, 'budget-nature-input', '800');
      await (await driver.waitForComponent(ON.id('budget-nature-input-key-保存').enabled(true), 5000)).click();
      const name = AppStorage.get<string>('ledgerDatabaseName') || '';
      const workspace = await LedgerWorkspace.open(context, name);
      const now = new Date();
      const month = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
      let allocated = false;
      for (let attempt = 0; attempt < 50; attempt++) {
        const snapshot = await workspace.snapshot(month);
        allocated = snapshot.budgetNatureLines.some((line) => line.natureId === 'nature-survival' && line.amountMinor === '80000');
        if (allocated) { break; }
        await driver.delayMs(200);
      }
      expect(allocated).assertTrue();
      expect(await driver.screenCap(context.filesDir + '/xiaoqiao-budget-nature.png')).assertTrue();
      if (await driver.findComponent(ON.id('budget-nature-input')) !== null) { await driver.pressBack(); }
      await driver.delayMs(500);
      await (await driver.findComponent(ON.id('budget-close'))).click();
      await driver.waitForComponent(ON.id('ledger-edit-budget'), 5000);
    });
  });
}
