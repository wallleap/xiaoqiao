import { describe, expect, it } from '@ohos/hypium';
import { exportLedgerCsv, LEDGER_CSV_HEADERS } from '../../../main/ets/data/exchange/LedgerCsvExport';
import { LedgerSnapshot } from '../../../main/ets/domain/model/LedgerSnapshot';

export default function csvExportTest() {
  describe('CsvExport', () => {
    it('writes_utf8_exact_money_quotes_transfers_tags_and_special_characters', 0, () => {
      const snapshot: LedgerSnapshot = {
        bookId: 'book-csv', bookName: '旅行账本', categories: [], incomeCategories: [],
        spendingNatures: [], tags: [], budgetNatureLines: [], accounts: [], incomeMinor: '860000',
        expenseMinor: '2800', budgetTotalMinor: '250000', budgetUsedMinor: '2800',
        entries: [
          { id: 'expense-csv', note: '午餐,咖啡 "同事"', category: '餐饮', iconKey: 'food',
            account: '微信零钱', date: '2026-11-08', occurredAtMs: new Date(2026, 10, 8, 12, 30).getTime(),
            offsetMinutes: -new Date(2026, 10, 8, 12, 30).getTimezoneOffset(), income: false,
            minor: '2800', grossMinor: '3000', discountMinor: '200',
            tagIds: ['tag-travel'], tagNames: ['旅行', '报销'] },
          { id: 'income-csv', note: '工资', category: '工资', iconKey: 'salary',
            account: '日常储蓄卡', date: '2026-11-05', occurredAtMs: new Date(2026, 10, 5, 9, 0).getTime(),
            offsetMinutes: -new Date(2026, 10, 5, 9, 0).getTimezoneOffset(), income: true,
            minor: '860000', grossMinor: '860000', discountMinor: '0' },
          { id: 'transfer-csv', note: '还款', category: '信用卡还款', iconKey: 'transfer',
            account: '日常储蓄卡', toAccount: '信用卡', date: '2026-11-04',
            occurredAtMs: new Date(2026, 10, 4, 10, 0).getTime(),
            offsetMinutes: -new Date(2026, 10, 4, 10, 0).getTimezoneOffset(), income: false,
            transfer: true, minor: '9700', expenseMinor: '200', transferFeeMinor: '200',
            transferCouponMinor: '500', grossMinor: '10000', discountMinor: '0' }
        ]
      };
      const csv = exportLedgerCsv(snapshot);
      expect(csv.startsWith('\uFEFF"日期","时间"')).assertTrue();
      expect(csv.includes('\r\n')).assertTrue();
      expect(csv.includes('"午餐,咖啡 ""同事"""')).assertTrue();
      expect(csv.includes('"28.00"')).assertTrue();
      expect(csv.includes('"8600.00"')).assertTrue();
      expect(csv.includes('"2.00"')).assertTrue();
      expect(csv.includes('"5.00"')).assertTrue();
      expect(csv.includes('"旅行|报销"')).assertTrue();
      expect(csv.split('\r\n').length).assertEqual(LEDGER_CSV_HEADERS.length === 0 ? 0 : 5);
      const selectedCsv = exportLedgerCsv(snapshot, ['date', 'paid', 'tags']);
      expect(selectedCsv.startsWith('\uFEFF"日期","实付金额","标签"')).assertTrue();
      expect(selectedCsv.includes('"微信零钱"')).assertFalse();
    });
  });
}
