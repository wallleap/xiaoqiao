import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LedgerDatabase, DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { RdbSession } from '../../../main/ets/data/rdb/RdbSession';
import { AccountCalibrationCommand, AdjustmentCursor } from '../../../main/ets/domain/model/AccountCalibration';
import { Money } from '../../../main/ets/core/money/Money';

function calibration(workspace: LedgerWorkspace, id: string, accountId: string, before: string, after: string, revision: number = 1): AccountCalibrationCommand {
  return { id: id, accountId: accountId, expectedRevision: revision, before: Money.parse(before, workspace.currency), after: Money.parse(after, workspace.currency), reason: ' 核对实际余额 ' };
}
async function create(workspace: LedgerWorkspace, id: string, opening: string = '100', kind: string = 'asset'): Promise<void> {
  await workspace.createAccount({ id: id, name: id, kind: kind, styleKey: 'cash', includeInNetAssets: true, opening: Money.parse(opening, workspace.currency) });
}
async function income(workspace: LedgerWorkspace): Promise<void> {
  const date = new Date(2027, 0, 15, 12, 30); const amount = Money.parse('10', workspace.currency);
  await workspace.saveIncome({ id: 'income', bookId: DEFAULT_BOOK_ID, categoryId: 'income-salary', amount: amount, bookAmount: amount, accountId: 'asset', accountAmount: amount, includeInAssets: true, note: '历史收入', occurredAtMs: date.getTime(), localDate: '2027-01-15', timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -date.getTimezoneOffset() });
}

export default function accountCalibrationTest() {
  describe('AccountCalibration', () => {
    it('calibration_is_append_only_signed_balance_and_not_income_expense_or_budget', 0, async () => {
      const host = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const name = 'xiaoqiao_app_test_calibration_' + util.generateRandomUUID() + '.db';
      try {
        let workspace = await LedgerWorkspace.open(host, name); await create(workspace, 'asset'); await create(workspace, 'debt', '-50', 'liability');
        await income(workspace);
        await workspace.calibrateAccount(calibration(workspace, 'asset-calibration', 'asset', '110', '80.25'));
        await workspace.calibrateAccount(calibration(workspace, 'debt-calibration', 'debt', '-50', '-20'));
        await workspace.calibrateAccount(calibration(workspace, 'debt-overpayment', 'debt', '-20', '5.25', 2));
        await workspace.calibrateAccount(calibration(workspace, 'asset-overdraft', 'asset', '80.25', '-5', 2));
        let overview = await workspace.accountOverview();
        expect(overview.accounts.find((item) => item.id === 'asset')?.balanceMinor).assertEqual('-500');
        expect(overview.accounts.find((item) => item.id === 'debt')?.balanceMinor).assertEqual('525'); expect(overview.netMinor).assertEqual('25');
        const history = (await workspace.accountAdjustments('asset')).items;
        expect(history.length).assertEqual(3); expect(history.filter((item) => item.kind === 'opening')[0].afterMinor).assertEqual('10000');
        const row = history.find((item) => item.id === 'asset-calibration');
        expect(row?.beforeMinor).assertEqual('11000'); expect(row?.afterMinor).assertEqual('8025'); expect(row?.deltaMinor).assertEqual('-2975'); expect(row?.reason).assertEqual('核对实际余额');
        let snapshot = await workspace.snapshot('2027-01');
        expect(snapshot.entries.length).assertEqual(1); expect(snapshot.incomeMinor).assertEqual('1000'); expect(snapshot.expenseMinor).assertEqual('0'); expect(snapshot.budgetUsedMinor).assertEqual('0');
        await workspace.deleteEntry('income');
        expect((await workspace.accountOverview()).accounts.find((item) => item.id === 'asset')?.balanceMinor).assertEqual('-1500');
        expect((await workspace.accountAdjustments('asset')).items.find((item) => item.id === 'asset-calibration')?.beforeMinor).assertEqual('11000');
        await LedgerWorkspace.close(name); workspace = await LedgerWorkspace.open(host, name);
        overview = await workspace.accountOverview(); expect(overview.netMinor).assertEqual('-975');
        expect((await workspace.accountAdjustments('debt')).items.length).assertEqual(3);
        snapshot = await workspace.snapshot('2027-01'); expect(snapshot.entries.length).assertEqual(0);
        await LedgerWorkspace.close(name);
        const db = await LedgerDatabase.open(host, name);
        try {
          let blocked = false; try { await db.executeSql("UPDATE balance_adjustments SET reason='rewrite' WHERE id='asset-calibration'"); } catch (_) { blocked = true; }
          expect(blocked).assertTrue(); blocked = false;
          try { await db.executeSql("DELETE FROM balance_adjustments WHERE id='asset-calibration'"); } catch (_) { blocked = true; }
          expect(blocked).assertTrue();
          const rows = await db.querySql("SELECT (SELECT COUNT(*) FROM balance_adjustments WHERE kind='opening'),(SELECT COUNT(*) FROM balance_adjustments WHERE kind='calibration'),(SELECT COUNT(*) FROM account_movements WHERE adjustment_id IS NOT NULL),(SELECT COUNT(*) FROM transactions)");
          try { rows.goToFirstRow(); expect(rows.getLong(0)).assertEqual(2); expect(rows.getLong(1)).assertEqual(4); expect(rows.getLong(2)).assertEqual(6); expect(rows.getLong(3)).assertEqual(1); } finally { rows.close(); }
        } finally { await db.close(); }
      } finally { await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name); }
    });

    it('stale_balance_revision_duplicate_publish_and_leg_failures_roll_back', 0, async () => {
      const host = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const name = 'xiaoqiao_app_test_calibration_guard_' + util.generateRandomUUID() + '.db';
      try {
        let workspace = await LedgerWorkspace.open(host, name); await create(workspace, 'asset');
        const stale = calibration(workspace, 'stale', 'asset', '100', '90'); await income(workspace);
        let rejected = false; try { await workspace.calibrateAccount(stale); } catch (error) { rejected = (error as Error).message === 'BALANCE_CHANGED'; }
        expect(rejected).assertTrue(); expect((await workspace.accountAdjustments('asset')).items.length).assertEqual(1);
        await workspace.calibrateAccount(calibration(workspace, 'valid', 'asset', '110', '90'));
        rejected = false; try { await workspace.calibrateAccount(calibration(workspace, 'valid', 'asset', '90', '80', 2)); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        await LedgerWorkspace.close(name);
        const db = await LedgerDatabase.open(host, name);
        try {
          await db.executeSql("CREATE TRIGGER reject_calibration_publish BEFORE UPDATE OF posting_state ON balance_adjustments WHEN NEW.id='reject-publish' AND NEW.posting_state='posted' BEGIN SELECT RAISE(ABORT,'reject calibration'); END");
          await db.executeSql("CREATE TRIGGER reject_calibration_leg BEFORE INSERT ON account_movements WHEN NEW.adjustment_id='reject-leg' BEGIN SELECT RAISE(ABORT,'reject movement'); END");
        } finally { await db.close(); }
        workspace = await LedgerWorkspace.open(host, name);
        for (const id of ['reject-publish', 'reject-leg']) {
          rejected = false; try { await workspace.calibrateAccount(calibration(workspace, id, 'asset', '90', '70', 2)); } catch (_) { rejected = true; }
          expect(rejected).assertTrue();
          expect((await workspace.accountOverview()).accounts[0].balanceMinor).assertEqual('9000'); expect((await workspace.accountOverview()).accounts[0].revision).assertEqual(2);
          expect((await workspace.accountAdjustments('asset')).items.length).assertEqual(2);
        }
        const races = await Promise.all([
          workspace.calibrateAccount(calibration(workspace, 'race-a', 'asset', '90', '60', 2)).then(() => true, () => false),
          workspace.calibrateAccount(calibration(workspace, 'race-b', 'asset', '90', '50', 2)).then(() => true, () => false)
        ]);
        expect(races.filter((value: boolean) => value).length).assertEqual(1);
        const current = (await workspace.accountOverview()).accounts[0]; expect(current.revision).assertEqual(3);
        await workspace.archiveAccount('asset', current.revision, true);
        rejected = false; try { await workspace.calibrateAccount(calibration(workspace, 'archived', 'asset', '60', '40', 4)); } catch (_) { rejected = true; }
        expect(rejected).assertTrue(); expect((await workspace.accountAdjustments('asset')).items.length).assertEqual(3);
        rejected = false; try { await workspace.calibrateAccount(calibration(workspace, 'missing', 'missing', '0', '1')); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        await LedgerWorkspace.close(name);
        const verify = await LedgerDatabase.open(host, name);
        try {
          const rows = await verify.querySql("SELECT (SELECT COUNT(*) FROM balance_adjustments),(SELECT COUNT(*) FROM balance_adjustments WHERE posting_state='draft'),(SELECT COUNT(*) FROM account_movements WHERE adjustment_id IS NOT NULL)");
          try { rows.goToFirstRow(); expect(rows.getLong(0)).assertEqual(3); expect(rows.getLong(1)).assertEqual(0); expect(rows.getLong(2)).assertEqual(3); } finally { rows.close(); }
        } finally { await verify.close(); }
      } finally { await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name); }
    });

    it('history_cursor_handles_equal_timestamps_without_missing_or_duplicate_records', 0, async () => {
      const host = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const name = 'xiaoqiao_app_test_calibration_pages_' + util.generateRandomUUID() + '.db';
      try {
        let workspace = await LedgerWorkspace.open(host, name); await create(workspace, 'asset', '0'); await LedgerWorkspace.close(name);
        const db = await LedgerDatabase.open(host, name);
        try {
          await RdbSession.forStore(db).write(async (store: relationalStore.RdbStore): Promise<void> => {
            for (let index = 0; index < 25; index++) {
              const id = 'cal-' + String(index).padStart(2, '0');
              await store.insert('balance_adjustments', { id: id, account_id: 'asset', kind: 'calibration', before_minor: index, after_minor: index + 1, delta_minor: 1, reason: '分页测试', occurred_at_ms: 1000, created_at_ms: 1000 });
              await store.insert('account_movements', { id: 'movement-' + id, adjustment_id: id, account_id: 'asset', currency_id: 'CNY', leg: 'adjustment', delta_minor: 1, occurred_at_ms: 1000 });
              await store.executeSql('UPDATE balance_adjustments SET posting_state=\'posted\' WHERE id=?', [id]);
            }
            await store.insert('balance_adjustments', { id: 'hidden-draft', account_id: 'asset', kind: 'calibration', before_minor: 25, after_minor: 26, delta_minor: 1, reason: '草稿不能展示', occurred_at_ms: Date.now(), created_at_ms: Date.now() });
          });
        } finally { await db.close(); }
        workspace = await LedgerWorkspace.open(host, name);
        const first = await workspace.accountAdjustments('asset'); expect(first.items.length).assertEqual(20); expect(first.next !== undefined).assertTrue();
        const second = await workspace.accountAdjustments('asset', first.next); expect(second.items.length).assertEqual(6); expect(second.next === undefined).assertTrue();
        const all = first.items.concat(second.items); const ids = new Set(all.map((item) => item.id));
        expect(ids.size).assertEqual(26); expect(ids.has('cal-00')).assertTrue(); expect(ids.has('cal-24')).assertTrue(); expect(ids.has('hidden-draft')).assertFalse();
        let invalid = false; const cursor: AdjustmentCursor = { id: '', occurredAtMs: 1000 };
        try { await workspace.accountAdjustments('asset', cursor); } catch (_) { invalid = true; } expect(invalid).assertTrue();
      } finally { await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name); }
    });
  });
}
