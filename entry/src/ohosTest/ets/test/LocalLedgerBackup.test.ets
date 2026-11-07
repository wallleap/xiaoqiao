import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { Money } from '../../../main/ets/core/money/Money';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { RdbSession } from '../../../main/ets/data/rdb/RdbSession';

async function context(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
  await Driver.create().waitForComponent(ON.id('ledger-tab-4'), 10000);
  return (await delegator.getCurrentTopAbility()).context;
}

async function writeInvalid(path: string): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try { await fs.write(file.fd, 'this is not an SQLite database'); }
  finally { await fs.close(file); }
}

async function clean(host: common.Context, name: string, exportPath: string): Promise<void> {
  await LedgerWorkspace.close(name);
  await relationalStore.deleteRdbStore(host, name);
  for (const path of [exportPath, ...['_pending.db', '_previous.db', '_candidate.db', '_export.db', '_rollback_work.db']
    .map((suffix: string) => host.databaseDir + '/rdb/' + name.slice(0, -3) + '_local_backup' + suffix)]) {
    if (await fs.access(path)) { await fs.unlink(path); }
  }
}

export default function localLedgerBackupTest() {
  describe('LocalLedgerBackup', () => {
    it('round_trips_balances_and_keeps_pre_restore_copy', 0, async () => {
      const host = await context();
      const name = 'xiaoqiao_app_test_backup_' + util.generateRandomUUID() + '.db';
      const path = host.cacheDir + '/' + name;
      const month = '2026-10';
      try {
        let workspace = await LedgerWorkspace.open(host, name);
        await workspace.createAccount({ id: 'wallet', name: '备份测试账户', kind: 'asset', styleKey: 'cash',
          includeInNetAssets: true, opening: Money.parse('100.00', workspace.currency) });
        const amount = Money.parse('25.50', workspace.currency);
        await workspace.saveExpense({ id: 'expense', bookId: DEFAULT_BOOK_ID, categoryId: 'expense-food',
          gross: amount, discount: Money.parse('0', workspace.currency), bookPaid: amount, accountPaid: amount,
          accountId: 'wallet', includeInAssets: true, includeInBudget: true, note: '备份测试',
          occurredAtMs: new Date('2026-10-08T12:00:00+08:00').getTime(), localDate: '2026-10-08',
          offsetMinutes: 480, timezone: 'Asia/Shanghai' });
        await workspace.setMonthlyBudget(month, '3000');
        await workspace.localBackup.exportTo(path);
        await workspace.deleteEntry('expense');
        await workspace.setMonthlyBudget(month, '4000');
        const preview = await workspace.localBackup.prepare(path);
        expect(preview.books).assertEqual(1);
        expect(preview.entries).assertEqual(1);
        expect(preview.accounts).assertEqual(1);
        expect(preview.bytes > 0).assertTrue();
        await workspace.localBackup.discard();
        expect((await workspace.snapshot(month)).entries.length).assertEqual(0);
        let refused = false;
        try { await workspace.localBackup.restore(); } catch (_) { refused = true; }
        expect(refused).assertTrue();
        await workspace.localBackup.prepare(path);
        await workspace.localBackup.restore();
        await LedgerWorkspace.close(name);
        workspace = await LedgerWorkspace.open(host, name);
        expect((await workspace.snapshot(month)).entries.length).assertEqual(1);
        expect((await workspace.snapshot(month)).budgetTotalMinor).assertEqual('300000');
        expect((await workspace.accountOverview()).netMinor).assertEqual('7450');
        expect(await workspace.localBackup.hasPrevious()).assertTrue();
        await workspace.localBackup.exportTo(path, true);
        expect((await workspace.localBackup.prepare(path)).entries).assertEqual(0);
        await workspace.localBackup.restore();
        expect((await workspace.snapshot(month)).budgetTotalMinor).assertEqual('400000');
        expect((await workspace.accountOverview()).netMinor).assertEqual('10000');
        await writeInvalid(path);
        let invalid = false;
        try { await workspace.localBackup.prepare(path); } catch (_) { invalid = true; }
        expect(invalid).assertTrue();
        expect((await workspace.snapshot(month)).budgetTotalMinor).assertEqual('400000');
      } finally { await clean(host, name, path); }
    });

    it('recovers_interrupted_restore_before_opening_the_ledger', 0, async () => {
      const host = await context();
      const name = 'xiaoqiao_app_test_recovery_' + util.generateRandomUUID() + '.db';
      const path = host.cacheDir + '/' + name;
      const pending = host.databaseDir + '/rdb/' + name.slice(0, -3) + '_local_backup_pending.db';
      const month = '2026-10';
      try {
        let workspace = await LedgerWorkspace.open(host, name);
        await workspace.setMonthlyBudget(month, '3000');
        await workspace.localBackup.exportTo(path);
        await workspace.setMonthlyBudget(month, '4000');
        await LedgerWorkspace.close(name);
        const db = await relationalStore.getRdbStore(host, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
        try {
          await RdbSession.forStore(db).read(async (store: relationalStore.RdbStore): Promise<void> => {
            await store.backup(pending);
            await store.restore(path);
          });
        } finally { await db.close(); }
        workspace = await LedgerWorkspace.open(host, name);
        expect((await workspace.snapshot(month)).budgetTotalMinor).assertEqual('400000');
        expect(await fs.access(pending)).assertFalse();
        expect(await workspace.localBackup.hasPrevious()).assertTrue();
      } finally { await clean(host, name, path); }
    });

    it('opens_backup_settings_and_cancels_the_system_picker', 0, async () => {
      const host = await context();
      const name = AppStorage.get<string>('ledgerDatabaseName') || '';
      if (!name.startsWith('xiaoqiao_app_test_')) { throw new Error('ISOLATED_DATABASE_REQUIRED'); }
      const driver = Driver.create();
      if (await driver.findComponent(ON.id('local-backup-page')) === null) {
        await (await driver.findComponent(ON.id('ledger-tab-4'))).click();
      }
      const select = await driver.waitForComponent(ON.id('local-backup-select'), 5000);
      expect(select !== null).assertTrue();
      expect(await select.isEnabled()).assertTrue();
      expect(await driver.findComponent(ON.id('local-backup-save')) !== null).assertTrue();
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-local-backup-settings.png')).assertTrue();
      const page = await (await driver.findComponent(ON.id('local-backup-page'))).getBounds();
      await select.click();
      // The system picker keeps the app's nodes present underneath its private window.
      for (let attempt = 0; attempt < 20; attempt++) {
        if (!await select.isEnabled()) { break; }
        await driver.delayMs(100);
      }
      expect(await select.isEnabled()).assertFalse();
      await driver.delayMs(500);
      const middle = Math.round((page.top + page.bottom) / 2);
      await driver.swipe(page.left + 2, middle, page.left + 300, middle, 1000);
      const reopened = await driver.waitForComponent(ON.id('local-backup-select').enabled(true), 5000);
      expect(reopened !== null).assertTrue();
      expect(await driver.findComponent(ON.id('local-backup-preview'))).assertNull();
      expect(await driver.findComponent(ON.id('local-backup-feedback'))).assertNull();
      await (await driver.findComponent(ON.id('ledger-tab-0'))).click();
      expect(await driver.waitForComponent(ON.id('ledger-scroll'), 5000) !== null).assertTrue();
    });
  });
}
