import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { RdbMerchantFields } from '../../../main/ets/data/rdb/RdbMerchantFields';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { Money } from '../../../main/ets/core/money/Money';
import { ExpenseCommand } from '../../../main/ets/domain/model/ExpenseRecord';
import { IncomeCommand } from '../../../main/ets/domain/model/IncomeRecord';
import { TransferCommand } from '../../../main/ets/domain/model/TransferRecord';
import { exportLedgerCsv } from '../../../main/ets/data/exchange/LedgerCsvExport';

async function testContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  try { return (await delegator.getCurrentTopAbility()).context; } catch (_) {}
  const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
  await delegator.addAbilityMonitor(monitor);
  try {
    await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
    return (await delegator.waitAbilityMonitor(monitor, 10000)).context;
  } finally { await delegator.removeAbilityMonitor(monitor); }
}

export default function merchantFieldsTest() {
  describe('MerchantFields', () => {
    it('preserves_imported_links_and_clears_or_detaches_only_the_edited_entry', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_p0_merchant_' + util.generateRandomUUID() + '.db';
      const db = await relationalStore.getRdbStore(host, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
      try {
        await db.executeSql('CREATE TABLE merchants(id TEXT PRIMARY KEY,name TEXT)');
        await db.executeSql('CREATE TABLE transactions(id TEXT PRIMARY KEY,merchant_id TEXT,merchant_name_snapshot TEXT,address_text TEXT,latitude_e6 INTEGER,longitude_e6 INTEGER)');
        await db.executeSql("INSERT INTO merchants VALUES('shop','原商户')");
        await db.executeSql("INSERT INTO transactions VALUES('a','shop','原商户','旧地址',31230416,121473701)");
        await db.executeSql("INSERT INTO transactions VALUES('b','shop','原商户','另一地址',NULL,NULL)");
        await RdbMerchantFields.apply(db, 'a', undefined, undefined);
        const kept = await db.querySql("SELECT latitude_e6,longitude_e6 FROM transactions WHERE id='a'");
        try { expect(kept.goToFirstRow()).assertTrue(); expect(kept.getLong(0)).assertEqual(31230416); }
        finally { kept.close(); }
        await RdbMerchantFields.apply(db, 'a', ' 原商户 ', ' 新地址 ');
        const same = await db.querySql("SELECT merchant_id,address_text,latitude_e6,longitude_e6 FROM transactions WHERE id='a'");
        try { expect(same.goToFirstRow()).assertTrue(); expect(same.getString(0)).assertEqual('shop');
          expect(same.getString(1)).assertEqual('新地址'); expect(same.isColumnNull(2)).assertTrue(); expect(same.isColumnNull(3)).assertTrue(); } finally { same.close(); }
        await RdbMerchantFields.apply(db, 'a', '新商户', undefined);
        const changed = await db.querySql("SELECT merchant_id,merchant_name_snapshot,address_text FROM transactions WHERE id='a'");
        try { expect(changed.goToFirstRow()).assertTrue(); expect(changed.isColumnNull(0)).assertTrue();
          expect(changed.getString(1)).assertEqual('新商户'); expect(changed.getString(2)).assertEqual('新地址'); } finally { changed.close(); }
        await RdbMerchantFields.apply(db, 'b', '', '');
        const cleared = await db.querySql("SELECT merchant_id,merchant_name_snapshot,address_text FROM transactions WHERE id='b'");
        try { expect(cleared.goToFirstRow()).assertTrue();
          for (const column of [0, 1, 2]) { expect(cleared.isColumnNull(column)).assertTrue(); } } finally { cleared.close(); }
        const merchant = await db.querySql("SELECT name FROM merchants WHERE id='shop'");
        try { expect(merchant.goToFirstRow()).assertTrue(); expect(merchant.getString(0)).assertEqual('原商户'); }
        finally { merchant.close(); }
      } finally { await db.close(); await relationalStore.deleteRdbStore(host, name); }
    });
    it('saves_updates_clears_and_exports_text_for_all_manual_kinds', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_app_test_merchant_' + util.generateRandomUUID() + '.db';
      try {
        let workspace = await LedgerWorkspace.open(host, name);
        const date = new Date(2027, 2, 20, 12);
        const amount = Money.parse('10', workspace.currency);
        const expense: ExpenseCommand = { id: 'merchant-expense', bookId: DEFAULT_BOOK_ID,
          categoryId: 'expense-food-0', gross: amount, discount: Money.parse('0', workspace.currency), bookPaid: amount,
          includeInAssets: false, includeInBudget: true, note: '商户地址测试', merchantName: '  咖啡店  ', addressText: '  一号路  ', location: { latitudeE6: 31230416, longitudeE6: 121473701 },
          occurredAtMs: date.getTime(), localDate: '2027-03-20', timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
          offsetMinutes: -date.getTimezoneOffset() };
        const income: IncomeCommand = { id: 'merchant-income', bookId: DEFAULT_BOOK_ID, categoryId: 'income-salary',
          amount: amount, bookAmount: amount, includeInAssets: false, note: expense.note,
          merchantName: expense.merchantName, addressText: expense.addressText, location: expense.location, occurredAtMs: expense.occurredAtMs,
          localDate: expense.localDate, timezone: expense.timezone, offsetMinutes: expense.offsetMinutes };
        await workspace.createAccount({ id: 'merchant-from', name: '测试转出', kind: 'asset', styleKey: 'bank_card',
          includeInNetAssets: true, opening: Money.parse('100', workspace.currency) });
        await workspace.createAccount({ id: 'merchant-to', name: '测试转入', kind: 'asset', styleKey: 'bank_card',
          includeInNetAssets: true, opening: Money.parse('0', workspace.currency) });
        const transfer: TransferCommand = { id: 'merchant-transfer', bookId: DEFAULT_BOOK_ID,
          fromAccountId: 'merchant-from', toAccountId: 'merchant-to', amount: amount, includeInAssets: true,
          note: expense.note, merchantName: expense.merchantName, addressText: expense.addressText, location: expense.location,
          occurredAtMs: expense.occurredAtMs, localDate: expense.localDate, timezone: expense.timezone, offsetMinutes: expense.offsetMinutes };
        await workspace.saveExpense(expense); await workspace.saveIncome(income); await workspace.saveTransfer(transfer);
        await LedgerWorkspace.close(name);
        workspace = await LedgerWorkspace.open(host, name);
        for (const id of [expense.id, income.id, transfer.id]) {
          const detail = await workspace.entryDetail(id);
          expect(detail.merchantName).assertEqual('咖啡店'); expect(detail.addressText).assertEqual('一号路');
          expect(detail.location?.latitudeE6).assertEqual(31230416); expect(detail.location?.longitudeE6).assertEqual(121473701);
        }
        const csv = exportLedgerCsv(await workspace.snapshot('2027-03'));
        expect(csv.includes('咖啡店')).assertTrue(); expect(csv.includes('一号路')).assertTrue();
        const changedExpense: ExpenseCommand = { id: expense.id, bookId: expense.bookId, categoryId: expense.categoryId,
          gross: expense.gross, discount: expense.discount, bookPaid: expense.bookPaid,
          includeInAssets: expense.includeInAssets, includeInBudget: expense.includeInBudget, note: expense.note,
          occurredAtMs: expense.occurredAtMs, localDate: expense.localDate, timezone: expense.timezone,
          offsetMinutes: expense.offsetMinutes, merchantName: '新商户', addressText: '新地址', location: { latitudeE6: 0, longitudeE6: 0 } };
        await workspace.updateExpense(changedExpense, (await workspace.entryDetail(expense.id)).revision);
        const changedIncome: IncomeCommand = { id: income.id, bookId: income.bookId, categoryId: income.categoryId,
          amount: income.amount, bookAmount: income.bookAmount, includeInAssets: income.includeInAssets,
          note: income.note, occurredAtMs: income.occurredAtMs, localDate: income.localDate,
          timezone: income.timezone, offsetMinutes: income.offsetMinutes, merchantName: '新商户', addressText: '新地址', location: { latitudeE6: 0, longitudeE6: 0 } };
        await workspace.updateIncome(changedIncome, (await workspace.entryDetail(income.id)).revision);
        const changedTransfer: TransferCommand = { id: transfer.id, bookId: transfer.bookId, fromAccountId: transfer.fromAccountId,
          toAccountId: transfer.toAccountId, amount: transfer.amount, includeInAssets: transfer.includeInAssets,
          note: transfer.note, occurredAtMs: transfer.occurredAtMs, localDate: transfer.localDate,
          timezone: transfer.timezone, offsetMinutes: transfer.offsetMinutes, merchantName: '新商户', addressText: '新地址', location: { latitudeE6: 0, longitudeE6: 0 } };
        await workspace.updateTransfer(changedTransfer, (await workspace.entryDetail(transfer.id)).revision);
        for (const id of [expense.id, income.id, transfer.id]) {
          const detail = await workspace.entryDetail(id);
          expect(detail.merchantName).assertEqual('新商户'); expect(detail.addressText).assertEqual('新地址');
          expect(detail.location?.latitudeE6).assertEqual(0); expect(detail.location?.longitudeE6).assertEqual(0);
        }
        const clearExpense: ExpenseCommand = { id: expense.id, bookId: expense.bookId, categoryId: expense.categoryId,
          gross: expense.gross, discount: expense.discount, bookPaid: expense.bookPaid,
          includeInAssets: expense.includeInAssets, includeInBudget: expense.includeInBudget, note: expense.note,
          occurredAtMs: expense.occurredAtMs, localDate: expense.localDate, timezone: expense.timezone,
          offsetMinutes: expense.offsetMinutes, merchantName: '', addressText: '', location: null };
        const clearIncome: IncomeCommand = { id: income.id, bookId: income.bookId, categoryId: income.categoryId,
          amount: income.amount, bookAmount: income.bookAmount, includeInAssets: income.includeInAssets,
          note: income.note, occurredAtMs: income.occurredAtMs, localDate: income.localDate,
          timezone: income.timezone, offsetMinutes: income.offsetMinutes, merchantName: '', addressText: '', location: null };
        const clearTransfer: TransferCommand = { id: transfer.id, bookId: transfer.bookId, fromAccountId: transfer.fromAccountId,
          toAccountId: transfer.toAccountId, amount: transfer.amount, includeInAssets: transfer.includeInAssets,
          note: transfer.note, occurredAtMs: transfer.occurredAtMs, localDate: transfer.localDate,
          timezone: transfer.timezone, offsetMinutes: transfer.offsetMinutes, merchantName: '', addressText: '', location: null };
        await workspace.updateExpense(clearExpense, (await workspace.entryDetail(expense.id)).revision);
        await workspace.updateIncome(clearIncome, (await workspace.entryDetail(income.id)).revision);
        await workspace.updateTransfer(clearTransfer, (await workspace.entryDetail(transfer.id)).revision);
        await LedgerWorkspace.close(name);
        const reopened = await LedgerWorkspace.open(host, name);
        for (const id of [expense.id, income.id, transfer.id]) {
          const detail = await reopened.entryDetail(id);
          expect(detail.merchantName || '').assertEqual(''); expect(detail.addressText || '').assertEqual('');
          expect(detail.location === undefined).assertTrue();
        }
      } finally {
        await LedgerWorkspace.close(name);
        await relationalStore.deleteRdbStore(host, name);
      }
    });
    it('enters_text_saves_and_refills_the_editor', 0, async () => {
      await testContext();
      const driver = Driver.create();
      await (await driver.waitForComponent(ON.id('ledger-tab-0'), 10000)).click();
      await (await driver.waitForComponent(ON.id('ledger-add-expense'), 5000)).click();
      await (await driver.waitForComponent(ON.id('expense-key-1'), 5000)).click();
      const categories = await driver.waitForComponent(ON.id('expense-categories'), 5000);
      const bounds = await categories.getBounds();
      const center = Math.round((bounds.left + bounds.right) / 2);
      await driver.swipe(center, bounds.bottom - 40, center, bounds.top + 40, 600);
      await driver.waitForComponent(ON.id('expense-categories-compact'), 5000);
      const scroll = await driver.waitForComponent(ON.id('expense-form-scroll'), 5000);
      await (await scroll.scrollSearch(ON.id('expense-merchant'))).inputText('界面测试商户');
      await (await scroll.scrollSearch(ON.id('expense-address'))).inputText('界面测试地址');
      await driver.pressBack();
      await (await driver.waitForComponent(ON.id('expense-amount'), 5000)).click();
      await (await driver.waitForComponent(ON.id('expense-key-保存'), 5000)).click();
      await driver.waitForComponent(ON.id('ledger-add-expense'), 5000);
      const host = await testContext();
      const databaseName = AppStorage.get<string>('ledgerDatabaseName') || '';
      expect(databaseName.startsWith('xiaoqiao_app_test_ui_')).assertTrue();
      const workspace = await LedgerWorkspace.open(host, databaseName);
      const date = new Date();
      const month = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
      const snapshot = await workspace.snapshot(month);
      const entry = snapshot.entries.find((item) => item.merchant === '界面测试商户');
      if (entry === undefined) { throw new Error('MERCHANT_UI_ENTRY_MISSING'); }
      expect(entry.address).assertEqual('界面测试地址');
      await (await driver.waitForComponent(ON.id(entry.id), 5000)).click();
      await (await driver.waitForComponent(ON.id('entry-detail-edit'), 5000)).click();
      const editCategories = await driver.waitForComponent(ON.id('expense-categories'), 5000);
      const editBounds = await editCategories.getBounds();
      await driver.swipe(center, editBounds.bottom - 40, center, editBounds.top + 40, 600);
      const editScroll = await driver.waitForComponent(ON.id('expense-form-scroll'), 5000);
      expect(await (await editScroll.scrollSearch(ON.id('expense-merchant'))).getText()).assertEqual('界面测试商户');
      expect(await (await editScroll.scrollSearch(ON.id('expense-address'))).getText()).assertEqual('界面测试地址');
      await (await driver.findComponent(ON.id('expense-close'))).click();
    });
  });
}
