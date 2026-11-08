import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { BackupFiles } from '../../../main/ets/data/backup/BackupFiles';
import { BackupZip } from '../../../main/ets/data/backup/BackupZip';
import { LedgerXlsxExport } from '../../../main/ets/data/exchange/LedgerXlsxExport';
import { readXlsxTable } from '../../../main/ets/data/exchange/LedgerXlsxImport';
import { LedgerSnapshot } from '../../../main/ets/domain/model/LedgerSnapshot';

async function testContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  try { return (await delegator.getCurrentTopAbility()).context; }
  catch (_) { /* Class-only execution can start before EntryAbility is on top. */ }
  const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
  await delegator.addAbilityMonitor(monitor);
  try {
    await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
    return (await delegator.waitAbilityMonitor(monitor, 10000)).context;
  } finally { await delegator.removeAbilityMonitor(monitor); }
}

export default function xlsxExportTest() {
  describe('XlsxExport', () => {
    it('writes_openxml_workbook_with_headers_rows_numbers_and_tags', 0, async () => {
      const context = await testContext();
      const path = context.cacheDir + '/xiaoqiao-test-' + util.generateRandomUUID() + '.xlsx';
      try {
        const snapshot: LedgerSnapshot = {
          bookId: 'book', bookName: '账本', categories: [], incomeCategories: [], spendingNatures: [], tags: [],
          budgetNatureLines: [], accounts: [], incomeMinor: '0', expenseMinor: '2800',
          budgetTotalMinor: '250000', budgetUsedMinor: '0',
          entries: [{ id: 'xlsx-row', note: '午餐 & 咖啡', category: '餐饮', iconKey: 'food', account: '微信',
            date: '2026-11-08', occurredAtMs: new Date(2026, 10, 8, 12, 30).getTime(),
            offsetMinutes: -new Date(2026, 10, 8, 12, 30).getTimezoneOffset(), income: false,
            minor: '2800', grossMinor: '3000', discountMinor: '200', tagNames: ['旅行'] }]
        };
        await LedgerXlsxExport.exportTo(path, snapshot, context);
        const entries = BackupZip.decodeOffice(await BackupFiles.read(path));
        expect(entries.length).assertEqual(6);
        const sheet = entries.find((entry) => entry.path === 'xl/worksheets/sheet1.xml');
        expect(sheet !== undefined).assertTrue();
        const xml = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(sheet?.data || new ArrayBuffer(0)));
        expect(xml.includes('日期')).assertTrue();
        expect(xml.includes('午餐 &amp; 咖啡')).assertTrue();
        expect(xml.includes('<v>28.00</v>')).assertTrue();
        expect(xml.includes('旅行')).assertTrue();
        const table = await readXlsxTable(path);
        expect(table.headers[0]).assertEqual('日期');
        expect(table.rows.length).assertEqual(1);
        expect(table.rows[0][0]).assertEqual('2026-11-08');
        expect(table.rows[0][10]).assertEqual('28.00');
      } finally {
        if (await fs.access(path)) { await fs.unlink(path); }
      }
    });
  });
}
