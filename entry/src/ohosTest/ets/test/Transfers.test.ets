import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LedgerDatabase, DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { RdbSession } from '../../../main/ets/data/rdb/RdbSession';
import { TransferCommand } from '../../../main/ets/domain/model/TransferRecord';
import { Money } from '../../../main/ets/core/money/Money';

function command(workspace: LedgerWorkspace, id: string = 'transfer', amount: string = '100', from: string = 'a', to: string = 'b',
  assets: boolean = true, february: boolean = false, note: string = '转账测试'): TransferCommand {
  const date = new Date(2027, february ? 1 : 0, 15, 12, 30);
  return { id: id, bookId: DEFAULT_BOOK_ID, fromAccountId: from, toAccountId: to, amount: Money.parse(amount, workspace.currency),
    includeInAssets: assets, note: note, occurredAtMs: date.getTime(), localDate: february ? '2027-02-15' : '2027-01-15',
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -date.getTimezoneOffset() };
}
async function seed(workspace: LedgerWorkspace): Promise<void> {
  for (const id of ['a', 'b', 'c']) {
    await workspace.createAccount({ id: id, name: id, kind: 'asset', styleKey: 'cash', includeInNetAssets: true,
      opening: Money.parse(id === 'a' ? '1000' : '0', workspace.currency) });
  }
}
async function balances(workspace: LedgerWorkspace, a: string, b: string, c: string): Promise<void> {
  const overview = await workspace.accountOverview();
  expect(overview.accounts.find((item) => item.id === 'a')?.balanceMinor).assertEqual(a);
  expect(overview.accounts.find((item) => item.id === 'b')?.balanceMinor).assertEqual(b);
  expect(overview.accounts.find((item) => item.id === 'c')?.balanceMinor).assertEqual(c);
  expect(overview.netMinor).assertEqual('100000');
}

export default function transfersTest() {
  describe('Transfers', () => {
    it('transfer_pair_edit_swap_month_flag_archive_and_delete', 0, async () => {
      const host = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const name = 'xiaoqiao_app_test_transfers_' + util.generateRandomUUID() + '.db';
      try {
        let workspace = await LedgerWorkspace.open(host, name); await seed(workspace);
        await workspace.saveTransfer(command(workspace)); await balances(workspace, '90000', '10000', '0');
        let snapshot = await workspace.snapshot('2027-01');
        expect(snapshot.entries.length).assertEqual(1); expect(snapshot.entries[0].transfer).assertTrue();
        expect(snapshot.entries[0].account).assertEqual('a'); expect(snapshot.entries[0].toAccount).assertEqual('b');
        expect(snapshot.incomeMinor).assertEqual('0'); expect(snapshot.expenseMinor).assertEqual('0'); expect(snapshot.budgetUsedMinor).assertEqual('0');
        let detail = await workspace.entryDetail('transfer');
        expect(detail.kind).assertEqual('transfer'); expect(detail.categoryId).assertEqual(''); expect(detail.canEdit).assertTrue();
        expect(detail.accountId).assertEqual('a'); expect(detail.toAccountId).assertEqual('b');
        await workspace.updateTransfer(command(workspace, 'transfer', '300', 'a', 'c', true, true), 1);
        await balances(workspace, '70000', '0', '30000');
        expect((await workspace.snapshot('2027-01')).entries.length).assertEqual(0);
        expect((await workspace.snapshot('2027-02')).entries.length).assertEqual(1);
        await workspace.updateTransfer(command(workspace, 'transfer', '400', 'c', 'a', true, true), 2);
        await balances(workspace, '140000', '0', '-40000');
        await workspace.updateTransfer(command(workspace, 'transfer', '400', 'c', 'a', false, true), 3);
        await balances(workspace, '100000', '0', '0');
        await workspace.updateTransfer(command(workspace, 'transfer', '250', 'a', 'b', true, true), 4);
        await workspace.archiveAccount('a', 1, true); await workspace.archiveAccount('b', 1, true);
        let rejected = false;
        try { await workspace.saveTransfer(command(workspace, 'archived')); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        await workspace.updateTransfer(command(workspace, 'transfer', '260', 'a', 'b', true, true), 5);
        await balances(workspace, '74000', '26000', '0');
        rejected = false;
        try { await workspace.updateTransfer(command(workspace, 'transfer', '1', 'b', 'a'), 6); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        await LedgerWorkspace.close(name); workspace = await LedgerWorkspace.open(host, name);
        detail = await workspace.entryDetail('transfer'); expect(detail.revision).assertEqual(6); expect(detail.paidMinor).assertEqual('26000');
        await workspace.deleteEntry('transfer'); await balances(workspace, '100000', '0', '0');
        snapshot = await workspace.snapshot('2027-02'); expect(snapshot.entries.length).assertEqual(0);
        rejected = false;
        try { await workspace.updateTransfer(command(workspace), 6); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
      } finally { await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name); }
    });

    it('same_record_repayment_fee_coupon_budget_zero_outgoing_and_delete', 0, async () => {
      const host = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const name = 'xiaoqiao_app_test_repayment_' + util.generateRandomUUID() + '.db';
      try {
        let workspace = await LedgerWorkspace.open(host, name); await seed(workspace);
        await workspace.createAccount({ id: 'debt', name: '信用卡', kind: 'liability', styleKey: 'cash', includeInNetAssets: true, opening: Money.parse('-500', workspace.currency) });
        const repayment = command(workspace, 'repayment', '100', 'a', 'debt');
        repayment.purpose = 'credit_repayment'; repayment.fee = Money.parse('2', workspace.currency); repayment.coupon = Money.parse('5', workspace.currency);
        await workspace.saveTransfer(repayment);
        let snapshot = await workspace.snapshot('2027-01');
        expect(snapshot.entries.length).assertEqual(1); expect(snapshot.entries[0].minor).assertEqual('9700');
        expect(snapshot.expenseMinor).assertEqual('200'); expect(snapshot.budgetUsedMinor).assertEqual('200'); expect(snapshot.incomeMinor).assertEqual('0');
        let overview = await workspace.accountOverview();
        expect(overview.accounts.find((item) => item.id === 'a')?.balanceMinor).assertEqual('90300');
        expect(overview.accounts.find((item) => item.id === 'debt')?.balanceMinor).assertEqual('-40000');
        let detail = await workspace.entryDetail('repayment');
        expect(detail.transferPurpose).assertEqual('credit_repayment'); expect(detail.transferOutMinor).assertEqual('9700');
        expect(detail.transferFeeMinor).assertEqual('200'); expect(detail.transferCouponMinor).assertEqual('500');
        await workspace.setMonthlyBudget('2027-01', '2500');
        await LedgerWorkspace.close(name);
        const stats = await LedgerDatabase.open(host, name);
        try {
          const rows = await stats.querySql('SELECT (SELECT expense_minor FROM v_book_totals),(SELECT used_minor FROM v_budget_usage),(SELECT COUNT(*) FROM transactions),(SELECT COUNT(*) FROM transfer_details)');
          try { rows.goToFirstRow(); expect(rows.getLong(0)).assertEqual(200); expect(rows.getLong(1)).assertEqual(200); expect(rows.getLong(2)).assertEqual(1); expect(rows.getLong(3)).assertEqual(1); } finally { rows.close(); }
        } finally { await stats.close(); }
        workspace = await LedgerWorkspace.open(host, name);
        repayment.feeInBudget = false; await workspace.updateTransfer(repayment, 1);
        expect((await workspace.snapshot('2027-01')).budgetUsedMinor).assertEqual('0');
        expect((await workspace.snapshot('2027-01')).expenseMinor).assertEqual('200');
        let rejected = false;
        repayment.toAccountId = 'b';
        try { await workspace.updateTransfer(repayment, 2); } catch (_) { rejected = true; }
        expect(rejected).assertTrue(); expect((await workspace.entryDetail('repayment')).revision).assertEqual(2);
        repayment.toAccountId = 'debt'; repayment.fee = Money.parse('0', workspace.currency); repayment.coupon = Money.parse('100', workspace.currency);
        await workspace.updateTransfer(repayment, 2);
        await LedgerWorkspace.close(name); workspace = await LedgerWorkspace.open(host, name);
        detail = await workspace.entryDetail('repayment'); expect(detail.transferOutMinor).assertEqual('0'); expect(detail.accountId).assertEqual('a'); expect(detail.canEdit).assertTrue();
        overview = await workspace.accountOverview(); expect(overview.accounts.find((item) => item.id === 'a')?.balanceMinor).assertEqual('100000');
        expect(overview.accounts.find((item) => item.id === 'debt')?.balanceMinor).assertEqual('-40000');
        await LedgerWorkspace.close(name);
        const db = await LedgerDatabase.open(host, name);
        try {
          const rows = await db.querySql("SELECT (SELECT COUNT(*) FROM transactions),(SELECT COUNT(*) FROM transfer_details),(SELECT COUNT(*) FROM account_movements WHERE transaction_id='repayment')");
          try { rows.goToFirstRow(); expect(rows.getLong(0)).assertEqual(1); expect(rows.getLong(1)).assertEqual(1); expect(rows.getLong(2)).assertEqual(1); } finally { rows.close(); }
          let blocked = false; try { await db.executeSql("UPDATE transfer_details SET fee_minor=100 WHERE transaction_id='repayment'"); } catch (_) { blocked = true; }
          expect(blocked).assertTrue();
        } finally { await db.close(); }
        workspace = await LedgerWorkspace.open(host, name); await workspace.deleteEntry('repayment');
        expect((await workspace.snapshot('2027-01')).expenseMinor).assertEqual('0');
        expect((await workspace.accountOverview()).accounts.find((item) => item.id === 'debt')?.balanceMinor).assertEqual('-50000');
      } finally { await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name); }
    });

    it('transfer_rolls_back_partial_legs_publish_and_conflicts_and_protects_groups', 0, async () => {
      const host = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const name = 'xiaoqiao_app_test_transfer_rollback_' + util.generateRandomUUID() + '.db';
      try {
        const db = await LedgerDatabase.open(host, name);
        try {
          await db.executeSql("CREATE TRIGGER reject_transfer_leg BEFORE INSERT ON account_movements WHEN NEW.transaction_id='reject-leg' AND NEW.leg='transfer_in' BEGIN SELECT RAISE(ABORT,'reject second leg'); END");
          await db.executeSql("CREATE TRIGGER reject_transfer_publish BEFORE UPDATE OF posting_state ON transactions WHEN NEW.posting_state='posted' AND NEW.note='reject-publish' BEGIN SELECT RAISE(ABORT,'reject publish'); END");
        } finally { await db.close(); }
        let workspace = await LedgerWorkspace.open(host, name); await seed(workspace);
        let rejected = false;
        try { await workspace.saveTransfer(command(workspace, 'reject-leg')); } catch (_) { rejected = true; }
        expect(rejected).assertTrue(); expect((await workspace.snapshot('2027-01')).entries.length).assertEqual(0);
        await balances(workspace, '100000', '0', '0');
        await workspace.saveTransfer(command(workspace));
        rejected = false;
        try { await workspace.saveTransfer(command(workspace)); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        rejected = false;
        try { await workspace.updateTransfer(command(workspace, 'transfer', '300', 'a', 'c', true, true, 'reject-publish'), 1); }
        catch (_) { rejected = true; }
        expect(rejected).assertTrue(); await balances(workspace, '90000', '10000', '0');
        expect((await workspace.entryDetail('transfer')).revision).assertEqual(1);
        rejected = false;
        try { await workspace.updateTransfer(command(workspace), 2); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        rejected = false;
        try { await workspace.saveTransfer(command(workspace, 'missing', '1', 'a', 'missing')); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        await LedgerWorkspace.close(name);
        const verify = await LedgerDatabase.open(host, name);
        try {
          const rows = await verify.querySql("SELECT (SELECT COUNT(*) FROM transactions),(SELECT COUNT(*) FROM account_movements WHERE transaction_id IS NOT NULL),(SELECT COUNT(*) FROM transactions WHERE posting_state='draft')");
          try { expect(rows.goToFirstRow()).assertTrue(); expect(rows.getLong(0)).assertEqual(1); expect(rows.getLong(1)).assertEqual(2); expect(rows.getLong(2)).assertEqual(0); } finally { rows.close(); }
          await RdbSession.forStore(verify).write(async (store: relationalStore.RdbStore): Promise<void> => {
            await store.executeSql("UPDATE transactions SET posting_state='draft',revision=revision+1 WHERE id='transfer'");
            await store.executeSql("UPDATE transactions SET group_id='fee-group' WHERE id='transfer'");
            await store.executeSql("UPDATE transactions SET posting_state='posted' WHERE id='transfer'");
          });
        } finally { await verify.close(); }
        workspace = await LedgerWorkspace.open(host, name);
        expect((await workspace.entryDetail('transfer')).canEdit).assertFalse();
        rejected = false; try { await workspace.updateTransfer(command(workspace), 2); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        rejected = false; try { await workspace.deleteEntry('transfer'); } catch (_) { rejected = true; }
        expect(rejected).assertTrue(); await balances(workspace, '90000', '10000', '0');
      } finally { await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name); }
    });
  });
}
