import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LedgerDatabase, DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { IncomeCommand } from '../../../main/ets/domain/model/IncomeRecord';
import { Money } from '../../../main/ets/core/money/Money';

function command(workspace: LedgerWorkspace, amount: string, account: string = 'a', assets: boolean = true,
  february: boolean = false, category: string = 'income-salary', note: string = '收入测试'): IncomeCommand {
  const date = new Date(2027, february ? 1 : 0, 15, 12, 30);
  const money = Money.parse(amount, workspace.currency);
  return { id: 'income-target', bookId: DEFAULT_BOOK_ID, categoryId: category, amount: money, bookAmount: money,
    accountId: account || undefined, accountAmount: account ? money : undefined, includeInAssets: assets,
    note: note, occurredAtMs: date.getTime(), localDate: february ? '2027-02-15' : '2027-01-15',
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -date.getTimezoneOffset() };
}

export default function incomeTest() {
  describe('Income', () => {
    it('income_balances_month_rules_conflict_rollback_and_delete', 0, async () => {
      const host = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const name = 'xiaoqiao_app_test_income_' + util.generateRandomUUID() + '.db';
      try {
        const db = await LedgerDatabase.open(host, name);
        try {
          for (const id of ['a', 'b']) {
            await db.insert('accounts', { id: id, name: id, kind: 'asset', currency_id: 'CNY', created_at_ms: 1, updated_at_ms: 1 });
          }
          await db.executeSql("CREATE TRIGGER reject_income BEFORE UPDATE OF posting_state ON transactions WHEN NEW.posting_state='posted' AND NEW.note='reject-income' BEGIN SELECT RAISE(ABORT,'reject income'); END");
        } finally { await db.close(); }
        let workspace = await LedgerWorkspace.open(host, name);
        expect((await workspace.snapshot('2027-01')).incomeCategories.length).assertEqual(6);
        await workspace.saveIncome(command(workspace, '100'));
        let snapshot = await workspace.snapshot('2027-01');
        expect(snapshot.incomeMinor).assertEqual('10000'); expect(snapshot.expenseMinor).assertEqual('0');
        expect(snapshot.budgetUsedMinor).assertEqual('0'); expect(snapshot.entries[0].discountMinor).assertEqual('0');
        let detail = await workspace.entryDetail('income-target');
        expect(detail.kind).assertEqual('income'); expect(detail.canEdit).assertTrue();
        expect(detail.includeInBudget).assertFalse();
        await LedgerWorkspace.close(name);
        let reopened = await LedgerDatabase.open(host, name);
        try {
          const balances = await reopened.querySql("SELECT CAST(balance_minor AS TEXT) FROM v_account_balances WHERE account_id='a'");
          try { expect(balances.goToFirstRow()).assertTrue(); expect(balances.getString(0)).assertEqual('10000'); }
          finally { balances.close(); }
        } finally { await reopened.close(); }
        workspace = await LedgerWorkspace.open(host, name);
        await workspace.updateIncome(command(workspace, '150', 'b', true, true, 'income-bonus'), 1);
        expect((await workspace.snapshot('2027-01')).entries.length).assertEqual(0);
        expect((await workspace.snapshot('2027-02')).incomeMinor).assertEqual('15000');
        await LedgerWorkspace.close(name);
        reopened = await LedgerDatabase.open(host, name);
        try {
          const balances = await reopened.querySql('SELECT account_id,CAST(balance_minor AS TEXT) FROM v_account_balances ORDER BY account_id');
          try {
            expect(balances.goToNextRow()).assertTrue(); expect(balances.getString(1)).assertEqual('0');
            expect(balances.goToNextRow()).assertTrue(); expect(balances.getString(1)).assertEqual('15000');
          } finally { balances.close(); }
        } finally { await reopened.close(); }
        workspace = await LedgerWorkspace.open(host, name);
        let rejected = false;
        try { await workspace.updateIncome(command(workspace, '300'), 1); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        rejected = false;
        try { await workspace.updateIncome(command(workspace, '300', 'a', true, false, 'income-salary', 'reject-income'), 2); }
        catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        detail = await workspace.entryDetail('income-target');
        expect(detail.revision).assertEqual(2); expect(detail.accountId).assertEqual('b'); expect(detail.paidMinor).assertEqual('15000');
        rejected = false;
        try { await workspace.updateIncome(command(workspace, '100', 'a', true, false, 'expense-food'), 2); }
        catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        await workspace.updateIncome(command(workspace, '200', 'b', false, true), 2);
        expect((await workspace.snapshot('2027-02')).incomeMinor).assertEqual('20000');
        await LedgerWorkspace.close(name);
        reopened = await LedgerDatabase.open(host, name);
        try {
          const balances = await reopened.querySql('SELECT CAST(balance_minor AS TEXT) FROM v_account_balances');
          try { while (balances.goToNextRow()) { expect(balances.getString(0)).assertEqual('0'); } }
          finally { balances.close(); }
        } finally { await reopened.close(); }
        workspace = await LedgerWorkspace.open(host, name);
        await workspace.updateIncome(command(workspace, '220', '', true, true), 3);
        expect((await workspace.entryDetail('income-target')).accountId).assertEqual('');
        await workspace.deleteEntry('income-target');
        expect((await workspace.snapshot('2027-02')).incomeMinor).assertEqual('0');
        rejected = false;
        try { await workspace.updateIncome(command(workspace, '1'), 4); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
      } finally { await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name); }
    });

    it('income_defaults_do_not_reseed_or_overwrite_existing_categories', 0, async () => {
      const host = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const name = 'xiaoqiao_app_test_income_seed_' + util.generateRandomUUID() + '.db';
      try {
        let db = await LedgerDatabase.open(host, name);
        await db.executeSql("DELETE FROM categories WHERE kind='income'");
        await db.executeSql("DELETE FROM db_meta WHERE key='income_categories_v1'");
        await db.insert('categories', { id: 'custom-income', book_id: DEFAULT_BOOK_ID, kind: 'income', name: '自定收入', name_key: '自定收入',
          icon_key: 'gift', created_at_ms: 1, updated_at_ms: 1, archived_at_ms: 2 });
        await db.close();
        db = await LedgerDatabase.open(host, name);
        try {
          const rows = await db.querySql("SELECT id,name,archived_at_ms FROM categories WHERE kind='income'");
          try { expect(rows.rowCount).assertEqual(1); expect(rows.goToFirstRow()).assertTrue();
            expect(rows.getString(0)).assertEqual('custom-income'); expect(rows.getString(1)).assertEqual('自定收入'); expect(rows.getLong(2)).assertEqual(2); }
          finally { rows.close(); }
          await db.executeSql("UPDATE categories SET deleted_at_ms=3 WHERE id='custom-income'");
        } finally { await db.close(); }
        db = await LedgerDatabase.open(host, name);
        try {
          const rows = await db.querySql("SELECT COUNT(*) FROM categories WHERE kind='income'");
          try { expect(rows.goToFirstRow()).assertTrue(); expect(rows.getLong(0)).assertEqual(1); } finally { rows.close(); }
        } finally { await db.close(); }
      } finally { await relationalStore.deleteRdbStore(host, name); }
    });
  });
}
