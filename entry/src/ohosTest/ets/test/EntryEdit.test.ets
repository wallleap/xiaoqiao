import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LedgerDatabase, DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { ExpenseCommand } from '../../../main/ets/domain/model/ExpenseRecord';
import { Money } from '../../../main/ets/core/money/Money';

function command(workspace: LedgerWorkspace, id: string, account: string, gross: string, discount: string,
  budget: boolean = true, assets: boolean = true, february: boolean = false, note: string = '编辑测试'): ExpenseCommand {
  const date = february ? new Date(2027, 1, 15, 12, 30) : new Date(2026, 10, 15, 12, 30);
  const amount = Money.parse(gross, workspace.currency);
  const reduction = Money.parse(discount, workspace.currency);
  const paid = amount.subtract(reduction);
  return { id: id, bookId: DEFAULT_BOOK_ID, categoryId: 'expense-food-1', gross: amount, discount: reduction, bookPaid: paid,
    accountId: account || undefined, accountPaid: account ? paid : undefined,
    includeInAssets: assets, includeInBudget: budget, note: note, occurredAtMs: date.getTime(),
    localDate: february ? '2027-02-15' : '2026-11-15', timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    offsetMinutes: -date.getTimezoneOffset() };
}

async function balances(host: common.Context, name: string, first: string, second: string): Promise<void> {
  await LedgerWorkspace.close(name);
  const db = await LedgerDatabase.open(host, name);
  try {
    const rows = await db.querySql('SELECT account_id,CAST(balance_minor AS TEXT) FROM v_account_balances ORDER BY account_id');
    try {
      expect(rows.rowCount).assertEqual(2);
      expect(rows.goToNextRow()).assertTrue(); expect(rows.getString(1)).assertEqual(first);
      expect(rows.goToNextRow()).assertTrue(); expect(rows.getString(1)).assertEqual(second);
    } finally { rows.close(); }
  } finally { await db.close(); }
}

async function seedAccounts(db: relationalStore.RdbStore): Promise<void> {
  for (const id of ['account-a', 'account-b']) {
    await db.insert('accounts', { id: id, name: id, kind: 'asset', currency_id: 'CNY', created_at_ms: 1, updated_at_ms: 1 });
  }
}

export default function entryEditTest() {
  describe('EntryEdit', () => {
    it('edit_moves_account_month_flags_and_rolls_back_conflicts', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const host = ability.context;
      const name = 'xiaoqiao_app_test_edit_' + util.generateRandomUUID() + '.db';
      try {
        const db = await LedgerDatabase.open(host, name);
        try {
          await seedAccounts(db);
          await db.executeSql("CREATE TRIGGER reject_edit_publish BEFORE UPDATE OF posting_state ON transactions WHEN NEW.posting_state='posted' AND NEW.note='reject-edit' BEGIN SELECT RAISE(ABORT,'edit publish failure'); END");
        } finally { await db.close(); }
        let workspace = await LedgerWorkspace.open(host, name);
        await workspace.saveExpense(command(workspace, 'edit-target', 'account-a', '20', '2'));
        let detail = await workspace.entryDetail('edit-target');
        expect(detail.categoryPath).assertEqual('餐饮 / 午餐');
        expect(detail.revision).assertEqual(1); expect(detail.canEdit).assertTrue();
        await balances(host, name, '-1800', '0');
        workspace = await LedgerWorkspace.open(host, name);
        await workspace.updateExpense(command(workspace, 'edit-target', 'account-b', '35', '5', false, true, true), 1);
        expect((await workspace.snapshot('2026-11')).entries.length).assertEqual(0);
        let snapshot = await workspace.snapshot('2027-02');
        expect(snapshot.entries.length).assertEqual(1); expect(snapshot.entries[0].id).assertEqual('edit-target');
        expect(snapshot.expenseMinor).assertEqual('3000'); expect(snapshot.budgetUsedMinor).assertEqual('0');
        await balances(host, name, '0', '-3000');
        workspace = await LedgerWorkspace.open(host, name);
        await workspace.updateExpense(command(workspace, 'edit-target', 'account-b', '35', '5', true, false, true), 2);
        expect((await workspace.snapshot('2027-02')).budgetUsedMinor).assertEqual('3000');
        await balances(host, name, '0', '0');
        workspace = await LedgerWorkspace.open(host, name);
        await workspace.updateExpense(command(workspace, 'edit-target', '', '35', '5', true, true, true), 3);
        let conflict = false;
        try { await workspace.updateExpense(command(workspace, 'edit-target', 'account-a', '99', '0'), 1); }
        catch (error) { conflict = (error as Error).message === 'TRANSACTION_CHANGED'; }
        expect(conflict).assertTrue();
        let rejected = false;
        try { await workspace.updateExpense(command(workspace, 'edit-target', 'account-a', '80', '0', true, true, false, 'reject-edit'), 4); }
        catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        detail = await workspace.entryDetail('edit-target');
        expect(detail.revision).assertEqual(4); expect(detail.paidMinor).assertEqual('3000');
        expect(detail.accountId).assertEqual(''); expect(detail.localDate).assertEqual('2027-02-15');
        snapshot = await workspace.snapshot('2027-02');
        expect(snapshot.entries.length).assertEqual(1); expect(snapshot.budgetUsedMinor).assertEqual('3000');
        await balances(host, name, '0', '0');
        workspace = await LedgerWorkspace.open(host, name);
        await workspace.deleteEntry('edit-target');
        let deleted = false;
        try { await workspace.updateExpense(command(workspace, 'edit-target', '', '1', '0'), 4); } catch (_) { deleted = true; }
        expect(deleted).assertTrue();
        let missing = false;
        try { await workspace.entryDetail('edit-target'); } catch (_) { missing = true; }
        expect(missing).assertTrue();
        await LedgerWorkspace.close(name);
        const verify = await LedgerDatabase.open(host, name);
        try {
          const rows = await verify.querySql("SELECT COUNT(*),SUM(CASE WHEN posting_state='draft' THEN 1 ELSE 0 END) FROM transactions");
          try { expect(rows.goToFirstRow()).assertTrue(); expect(rows.getLong(0)).assertEqual(1); expect(rows.getLong(1)).assertEqual(0); }
          finally { rows.close(); }
        } finally { await verify.close(); }
      } finally { await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name); }
    });

    it('edit_preserves_import_identity_and_balance_policy', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const host = ability.context;
      const name = 'xiaoqiao_app_test_edit_import_' + util.generateRandomUUID() + '.db';
      try {
        const db = await LedgerDatabase.open(host, name);
        const date = new Date(2026, 10, 15, 12, 30);
        try {
          await seedAccounts(db);
          await db.insert('import_batches', { id: 'batch', book_id: DEFAULT_BOOK_ID, file_sha256: 'fixture', file_name: 'fixture.csv',
            sheet_name: '', header_row: 1, profile_snapshot_json: '{}', status: 'committing', total_count: 1,
            selected_count: 1, skipped_count: 0, confirmed_at_ms: 1, created_at_ms: 1 });
          await db.insert('import_rows', { id: 'source-row', batch_id: 'batch', row_number: 2, raw_json: '{}', validation_status: 'valid', selected: 1 });
          await db.insert('transactions', { id: 'imported', book_id: DEFAULT_BOOK_ID, kind: 'expense', category_id: 'expense-food-1',
            currency_id: 'CNY', gross_minor: 1300, discount_minor: 200, paid_minor: 1100, book_currency_id: 'CNY', book_minor: 1100,
            include_in_budget: 1, include_in_assets: 1, balance_mode: 'preserve', import_batch_id: 'batch', import_row_id: 'source-row',
            occurred_at_ms: date.getTime(), occurred_local_date: '2026-11-15', occurred_timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
            occurred_offset_minutes: -date.getTimezoneOffset(), created_at_ms: 1, updated_at_ms: 1 });
          await db.insert('account_movements', { id: 'leg', transaction_id: 'imported', account_id: 'account-a', currency_id: 'CNY',
            leg: 'expense', delta_minor: -1100, occurred_at_ms: date.getTime() });
          await db.executeSql("UPDATE transactions SET posting_state='posted' WHERE id='imported'");
          await db.executeSql("UPDATE import_batches SET status='committed',committed_at_ms=2 WHERE id='batch'");
        } finally { await db.close(); }
        const workspace = await LedgerWorkspace.open(host, name);
        const detail = await workspace.entryDetail('imported');
        expect(detail.balanceMode).assertEqual('preserve');
        await workspace.updateExpense(command(workspace, 'imported', 'account-b', '22', '2'), detail.revision);
        expect((await workspace.entryDetail('imported')).balanceMode).assertEqual('preserve');
        expect((await workspace.snapshot('2026-11')).budgetUsedMinor).assertEqual('2000');
        await balances(host, name, '0', '0');
        const verify = await LedgerDatabase.open(host, name);
        try {
          const rows = await verify.querySql("SELECT id,revision,import_row_id,import_batch_id,balance_mode FROM transactions WHERE id='imported'");
          try {
            expect(rows.goToFirstRow()).assertTrue(); expect(rows.getString(0)).assertEqual('imported');
            expect(rows.getLong(1)).assertEqual(2); expect(rows.getString(2)).assertEqual('source-row');
            expect(rows.getString(3)).assertEqual('batch'); expect(rows.getString(4)).assertEqual('preserve');
          } finally { rows.close(); }
        } finally { await verify.close(); }
      } finally { await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name); }
    });
  });
}
