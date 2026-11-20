import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LedgerDatabase, DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { AccountCommand } from '../../../main/ets/domain/model/AccountProfile';
import { IncomeCommand } from '../../../main/ets/domain/model/IncomeRecord';
import { Money } from '../../../main/ets/core/money/Money';

function account(workspace: LedgerWorkspace, id: string, opening: string = '100', kind: string = 'asset'): AccountCommand {
  return { id: id, name: id, kind: kind, styleKey: 'wechat_pay', includeInNetAssets: true, opening: Money.parse(opening, workspace.currency) };
}
function income(workspace: LedgerWorkspace, id: string, accountId: string): IncomeCommand {
  const date = new Date(2027, 0, 15, 12, 30); const amount = Money.parse('10', workspace.currency);
  return { id: id, bookId: DEFAULT_BOOK_ID, categoryId: 'income-salary', amount: amount, bookAmount: amount,
    accountId: accountId, accountAmount: amount, includeInAssets: true, note: '账户验证', occurredAtMs: date.getTime(),
    localDate: '2027-01-15', timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -date.getTimezoneOffset() };
}

export default function accountsTest() {
  describe('Accounts', () => {
    it('opening_metadata_archive_history_and_net_assets_are_independent', 0, async () => {
      const host = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const name = 'xiaoqiao_app_test_accounts_' + util.generateRandomUUID() + '.db';
      try {
        let workspace = await LedgerWorkspace.open(host, name);
        await workspace.createAccount(account(workspace, 'asset'));
        await workspace.createAccount(account(workspace, 'debt', '-25', 'liability'));
        await workspace.createAccount(account(workspace, 'zero', '0'));
        let overview = await workspace.accountOverview();
        expect(overview.accounts.length).assertEqual(3); expect(overview.assetsMinor).assertEqual('10000');
        expect(overview.liabilitiesMinor).assertEqual('2500'); expect(overview.netMinor).assertEqual('7500');
        let snapshot = await workspace.snapshot('2027-01');
        expect(snapshot.entries.length).assertEqual(0); expect(snapshot.incomeMinor).assertEqual('0');
        expect(snapshot.expenseMinor).assertEqual('0'); expect(snapshot.budgetUsedMinor).assertEqual('0');
        await workspace.saveIncome(income(workspace, 'income-asset', 'asset'));
        await workspace.saveIncome(income(workspace, 'repay-debt', 'debt'));
        expect((await workspace.accountOverview()).netMinor).assertEqual('9500');
        await workspace.archiveAccount('debt', 1, true);
        overview = await workspace.accountOverview();
        expect(overview.netMinor).assertEqual('11000');
        expect(overview.liabilitiesMinor).assertEqual('0');
        expect(overview.accounts.find((item) => item.id === 'debt')?.balanceMinor).assertEqual('-1500');
        await workspace.archiveAccount('debt', 2, false);
        expect((await workspace.accountOverview()).netMinor).assertEqual('9500');
        const edited = account(workspace, 'asset', '999'); edited.name = '改名'; edited.styleKey = 'alipay'; edited.includeInNetAssets = false;
        await workspace.updateAccount(edited, 1);
        overview = await workspace.accountOverview();
        const asset = overview.accounts.find((item) => item.id === 'asset');
        if (asset === undefined) { throw new Error('ACCOUNT_MISSING'); }
        expect(asset.name).assertEqual('改名'); expect(asset.brand).assertEqual('alipay'); expect(asset.balanceMinor).assertEqual('11000');
        expect(overview.netMinor).assertEqual('-1500');
        let rejected = false;
        try { await workspace.updateAccount(edited, 1); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        await workspace.archiveAccount('asset', 2, true);
        snapshot = await workspace.snapshot('2027-01');
        expect(snapshot.accounts.some((item) => item.id === 'asset')).assertFalse();
        expect(snapshot.entries.length).assertEqual(2); expect(snapshot.incomeMinor).assertEqual('2000');
        overview = await workspace.accountOverview();
        expect(overview.accounts.find((item) => item.id === 'asset')?.balanceMinor).assertEqual('11000');
        expect(overview.netMinor).assertEqual('-1500');
        rejected = false;
        try { await workspace.saveIncome(income(workspace, 'new-into-archived', 'asset')); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        // An existing transaction may keep its archived account, but cannot switch into another archived account.
        const detail = await workspace.entryDetail('income-asset');
        const unchanged = income(workspace, 'income-asset', 'asset');
        await workspace.updateIncome(unchanged, detail.revision);
        await workspace.archiveAccount('asset', 3, false);
        expect((await workspace.snapshot('2027-01')).accounts.some((item) => item.id === 'asset')).assertTrue();
        await workspace.deleteEntry('repay-debt');
        expect((await workspace.accountOverview()).netMinor).assertEqual('-2500');
        await LedgerWorkspace.close(name);
        workspace = await LedgerWorkspace.open(host, name);
        expect((await workspace.accountOverview()).accounts.find((item) => item.id === 'asset')?.balanceMinor).assertEqual('11000');
        await LedgerWorkspace.close(name);
        const db = await LedgerDatabase.open(host, name);
        try {
          const rows = await db.querySql("SELECT COUNT(*),SUM(CASE WHEN posting_state='posted' THEN 1 ELSE 0 END) FROM balance_adjustments WHERE kind='opening'");
          try { expect(rows.goToFirstRow()).assertTrue(); expect(rows.getLong(0)).assertEqual(3); expect(rows.getLong(1)).assertEqual(3); }
          finally { rows.close(); }
          const movements = await db.querySql("SELECT COUNT(*) FROM account_movements WHERE leg='adjustment'");
          try { expect(movements.goToFirstRow()).assertTrue(); expect(movements.getLong(0)).assertEqual(3); }
          finally { movements.close(); }
        } finally { await db.close(); }
      } finally { await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name); }
    });

    it('account_and_opening_publish_rollback_as_one_unit_and_duplicate_id_rejects', 0, async () => {
      const host = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const name = 'xiaoqiao_app_test_accounts_rollback_' + util.generateRandomUUID() + '.db';
      try {
        const db = await LedgerDatabase.open(host, name);
        try {
          await db.executeSql("CREATE TRIGGER reject_opening BEFORE UPDATE OF posting_state ON balance_adjustments WHEN NEW.account_id='reject' AND NEW.posting_state='posted' BEGIN SELECT RAISE(ABORT,'reject opening'); END");
        } finally { await db.close(); }
        let workspace = await LedgerWorkspace.open(host, name);
        let rejected = false;
        try { await workspace.createAccount(account(workspace, 'reject')); } catch (_) { rejected = true; }
        expect(rejected).assertTrue(); expect((await workspace.accountOverview()).accounts.length).assertEqual(0);
        await workspace.createAccount(account(workspace, 'valid'));
        rejected = false;
        try { await workspace.createAccount(account(workspace, 'valid')); } catch (_) { rejected = true; }
        expect(rejected).assertTrue(); expect((await workspace.accountOverview()).accounts.length).assertEqual(1);
        await LedgerWorkspace.close(name);
        const reopened = await LedgerDatabase.open(host, name);
        try {
          const rows = await reopened.querySql("SELECT (SELECT COUNT(*) FROM accounts),(SELECT COUNT(*) FROM balance_adjustments),(SELECT COUNT(*) FROM account_movements),(SELECT COUNT(*) FROM balance_adjustments WHERE posting_state='draft')");
          try { expect(rows.goToFirstRow()).assertTrue(); expect(rows.getLong(0)).assertEqual(1); expect(rows.getLong(1)).assertEqual(1);
            expect(rows.getLong(2)).assertEqual(1); expect(rows.getLong(3)).assertEqual(0); } finally { rows.close(); }
        } finally { await reopened.close(); }
      } finally { await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name); }
    });
  });
}
