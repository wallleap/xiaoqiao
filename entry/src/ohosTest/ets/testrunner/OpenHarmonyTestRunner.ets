import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import { util } from '@kit.ArkTS';

export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {}

  async onRun(): Promise<void> {
    // Set before any ability is launched: device automation never writes the user's ledger.
    AppStorage.setOrCreate('ledgerDatabaseName', 'xiaoqiao_app_test_ui_' + util.generateRandomUUID() + '.db');
    // Load UiTest after the framework has registered the ability delegator.
    const suite = await import('../test/List.test');
    Hypium.hypiumTest(abilityDelegatorRegistry.getAbilityDelegator(),
      abilityDelegatorRegistry.getArguments(), suite.default);
  }
}
