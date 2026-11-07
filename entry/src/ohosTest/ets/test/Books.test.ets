import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { Money } from '../../../main/ets/core/money/Money';
import { ExpenseCommand } from '../../../main/ets/domain/model/ExpenseRecord';
import { LedgerSnapshot } from '../../../main/ets/domain/model/LedgerSnapshot';

let cachedContext: common.UIAbilityContext | undefined = undefined;

async function testContext(): Promise<common.UIAbilityContext> {
  if (cachedContext !== undefined) { return cachedContext; }
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  try {
    cachedContext = (await delegator.getCurrentTopAbility()).context;
    return cachedContext;
  } catch (_) { /* A class-only run may start before EntryAbility is on top. */ }
  const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
  await delegator.addAbilityMonitor(monitor);
  try {
    await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
    cachedContext = (await delegator.waitAbilityMonitor(monitor, 10000)).context;
    return cachedContext;
  } finally { await delegator.removeAbilityMonitor(monitor); }
}

function expense(workspace: LedgerWorkspace, snapshot: LedgerSnapshot, id: string): ExpenseCommand {
  const category = snapshot.categories.find((item) => item.name === '午餐');
  if (category === undefined) { throw new Error('TEST_CATEGORY_MISSING'); }
  const date = new Date(2027, 0, 20, 12, 30);
  const amount = Money.parse('12.00', workspace.currency);
  return { id: id, bookId: snapshot.bookId, categoryId: category.id, gross: amount, discount: Money.parse('0.00', workspace.currency),
    bookPaid: amount, includeInAssets: false, includeInBudget: true, note: '账本隔离测试', occurredAtMs: date.getTime(),
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, localDate: '2027-01-20', offsetMinutes: -date.getTimezoneOffset() };
}

export default function booksTest() {
  describe('Books', () => {
    it('switch_create_isolate_categories_budget_and_persist_active_book', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_app_test_books_' + util.generateRandomUUID() + '.db';
      try {
        let workspace = await LedgerWorkspace.open(host, name);
        let books = await workspace.books();
        expect(books.length).assertEqual(1);
        expect(books[0].id).assertEqual(DEFAULT_BOOK_ID);
        expect(workspace.bookId()).assertEqual(DEFAULT_BOOK_ID);
        await workspace.createBook('  旅行账本  ', 'book-travel-test');
        expect(workspace.bookId()).assertEqual('book-travel-test');
        let travel = await workspace.snapshot('2027-01');
        expect(travel.bookName).assertEqual('旅行账本');
        expect(travel.categories.length).assertEqual(18);
        expect(travel.incomeCategories.length).assertEqual(6);
        expect(travel.categories.some((item) => item.id === 'expense-food')).assertFalse();
        const travelCategory = travel.categories.find((item) => item.name === '午餐');
        expect(travelCategory === undefined ? '' : travelCategory.parentId.length > 0).assertTrue();
        await workspace.saveExpense(expense(workspace, travel, 'travel-expense'));
        await workspace.setMonthlyBudget('2027-01', '5000');
        travel = await workspace.snapshot('2027-01');
        expect(travel.entries.length).assertEqual(1);
        expect(travel.budgetTotalMinor).assertEqual('500000');

        await workspace.selectBook(DEFAULT_BOOK_ID);
        const home = await workspace.snapshot('2027-01');
        expect(home.bookName).assertEqual('日常账本');
        expect(home.entries.length).assertEqual(0);
        expect(home.budgetTotalMinor).assertEqual('250000');
        let hidden = false;
        try { await workspace.entryDetail('travel-expense'); } catch (_) { hidden = true; }
        expect(hidden).assertTrue();
        await workspace.setMonthlyBudget('2027-01', '3000');

        await workspace.selectBook('book-travel-test');
        expect((await workspace.snapshot('2027-01')).budgetTotalMinor).assertEqual('500000');
        await LedgerWorkspace.close(name);
        workspace = await LedgerWorkspace.open(host, name);
        expect(workspace.bookId()).assertEqual('book-travel-test');
        const reopened = await workspace.snapshot('2027-01');
        expect(reopened.entries[0].id).assertEqual('travel-expense');
        expect((await workspace.entryDetail('travel-expense')).bookId).assertEqual('book-travel-test');
      } finally {
        await LedgerWorkspace.close(name);
        await relationalStore.deleteRdbStore(host, name);
      }
    });

    it('edit_conflict_archive_restore_and_keep_one_active_book', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_app_test_books_state_' + util.generateRandomUUID() + '.db';
      try {
        const workspace = await LedgerWorkspace.open(host, name);
        await workspace.createBook('旅行账本', 'book-travel-test');
        await workspace.updateBook('book-travel-test', '旅行 2027', 1);
        let travel = (await workspace.books()).find((book) => book.id === 'book-travel-test');
        expect(travel === undefined ? '' : travel.name).assertEqual('旅行 2027');
        expect(travel === undefined ? 0 : travel.revision).assertEqual(2);
        let conflict = false;
        try { await workspace.updateBook('book-travel-test', '旅行冲突', 1); } catch (_) { conflict = true; }
        expect(conflict).assertTrue();
        let duplicate = false;
        try { await workspace.createBook('日常账本', 'book-duplicate-test'); } catch (_) { duplicate = true; }
        expect(duplicate).assertTrue();

        await workspace.archiveBook('book-travel-test', 2, true);
        expect(workspace.bookId()).assertEqual(DEFAULT_BOOK_ID);
        let books = await workspace.books();
        travel = books.find((book) => book.id === 'book-travel-test');
        expect(travel === undefined ? false : travel.archived).assertTrue();
        let selectedArchived = false;
        try { await workspace.selectBook('book-travel-test'); } catch (_) { selectedArchived = true; }
        expect(selectedArchived).assertTrue();
        let lastActive = false;
        try {
          const current = books.find((book) => book.id === DEFAULT_BOOK_ID);
          await workspace.archiveBook(DEFAULT_BOOK_ID, current === undefined ? 1 : current.revision, true);
        } catch (_) { lastActive = true; }
        expect(lastActive).assertTrue();

        await workspace.archiveBook('book-travel-test', 3, false);
        travel = (await workspace.books()).find((book) => book.id === 'book-travel-test');
        expect(travel === undefined ? true : travel.archived).assertFalse();
        expect(travel === undefined ? 0 : travel.revision).assertEqual(4);
        await workspace.selectBook('book-travel-test');
        expect(workspace.bookId()).assertEqual('book-travel-test');
        await LedgerWorkspace.close(name);
        const reopened = await LedgerWorkspace.open(host, name);
        expect(reopened.bookId()).assertEqual('book-travel-test');
        await LedgerWorkspace.close(name);
      } finally {
        await LedgerWorkspace.close(name);
        await relationalStore.deleteRdbStore(host, name);
      }
    });
  });
}
