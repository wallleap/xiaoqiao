import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { BackupFileInfo, BackupFiles } from '../../../main/ets/data/backup/BackupFiles';
import { BackupZip } from '../../../main/ets/data/backup/BackupZip';
import { LedgerXlsxExport } from '../../../main/ets/data/exchange/LedgerXlsxExport';
import { listXlsxSheets, readXlsxTable } from '../../../main/ets/data/exchange/LedgerXlsxImport';
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
      const formulaDirectory = context.cacheDir + '/xiaoqiao-formula-' + util.generateRandomUUID();
      const formulaPath = formulaDirectory + '.xlsx';
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
        const sheets = await listXlsxSheets(path, context.cacheDir);
        expect(sheets.length).assertEqual(1);
        expect(sheets[0].name).assertEqual('账目');
        const table = await readXlsxTable(path, context.cacheDir);
        expect(table.headers[0]).assertEqual('日期');
        expect(table.headers.includes('商户')).assertTrue();
        expect(table.headers.includes('转账用途')).assertTrue();
        expect(table.rows.length).assertEqual(1);
        expect(table.rows[0][0]).assertEqual('2026-11-08');
        expect(table.rows[0][12]).assertEqual('28.00');
        const formulaParts = BackupZip.decodeOffice(await BackupFiles.read(path));
        await BackupFiles.mkdir(formulaDirectory + '/_rels');
        await BackupFiles.mkdir(formulaDirectory + '/xl/_rels');
        await BackupFiles.mkdir(formulaDirectory + '/xl/worksheets');
        const formulaInfos: BackupFileInfo[] = [];
        for (const part of formulaParts) {
          let text = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(part.data));
          if (part.path === 'xl/worksheets/sheet1.xml') {
            text = text.replace(/<c r="A2"[^>]*>[\s\S]*?<\/c>/,
              '<c r="A2" t="str"><f>&quot;2026-11-08&quot;</f><v>2026-11-08</v></c>');
          }
          await BackupFiles.writeText(formulaDirectory + '/' + part.path, text);
          formulaInfos.push(await BackupFiles.info(formulaDirectory + '/' + part.path, part.path));
        }
        await BackupZip.encodeOffice(formulaDirectory, formulaPath, formulaInfos);
        const formulaTable = await readXlsxTable(formulaPath, context.cacheDir);
        expect(formulaTable.rows[0][0]).assertEqual('2026-11-08');
      } finally {
        if (await fs.access(path)) { await fs.unlink(path); }
        if (await fs.access(formulaPath)) { await fs.unlink(formulaPath); }
        await BackupFiles.remove(formulaDirectory);
      }
    });
  });
}
