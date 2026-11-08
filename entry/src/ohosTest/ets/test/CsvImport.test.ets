import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { Money } from '../../../main/ets/core/money/Money';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { detectCsvMapping, parseCsv, previewCsv } from '../../../main/ets/data/exchange/LedgerCsvImport';

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

export default function csvImportTest() {
  describe('CsvImport', () => {
    it('maps_previews_and_imports_with_preserved_balance_atomically', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_app_test_csv_import_' + util.generateRandomUUID() + '.db';
      try {
        const workspace = await LedgerWorkspace.open(host, name);
        expect(util.TextDecoder.create('gb18030').decodeToString(
          new Uint8Array([0xb5, 0xbc, 0xb3, 0xf6, 0xd0, 0xc5, 0xcf, 0xa2]))).assertEqual('导出信息');
        await workspace.createAccount({ id: 'csv-account', name: '导入账户', kind: 'asset', styleKey: 'cash',
          includeInNetAssets: true, opening: Money.parse('100', workspace.currency) });
        await workspace.createCategory({ id: 'csv-expense-shared', kind: 'expense', name: '同名分类', iconKey: 'other' });
        await workspace.createCategory({ id: 'csv-income-shared', kind: 'income', name: '同名分类', iconKey: 'other' });
        const snapshot = await workspace.snapshot('2027-05');
        const table = parseCsv('\uFEFF日期,类型,金额,分类,账户,备注,商户,地址\r\n' +
          '2027.05.01 18:21:44,,-12.00,餐饮 / 午餐,导入账户,点号日期带时间,午餐商户,人民路 1 号\r\n' +
          '2027-05-02,,"5,000.00",工资,导入账户,正数为收入,公司,\r\n' +
          '2027-05-03,支出,8.00,宠物 / 猫粮,宠物钱包,新建分类账户,宠物店,\r\n' +
          '2027-05-04,收入,100.00,副业收入,兼职钱包,明确类型,客户,\r\n' +
          '2027-05-05,,-3.00,宠物/猫粮,宠物钱包,复用同批新建项,宠物店,\r\n' +
          '2027-05-06,交易支出,1.00,同名分类,导入账户,同名支出分类,,\r\n' +
          '2027-05-07,交易收入,2.00,同名分类,导入账户,同名收入分类,,\r\n' +
          '不是日期,支出,8.00,餐饮,导入账户,问题行,,\r\n');
        const mapping = detectCsvMapping(table.headers);
        const preview = previewCsv(table, mapping, snapshot);
        expect(preview.length).assertEqual(8);
        expect(preview.filter((row) => row.valid).length).assertEqual(7);
        expect(preview.filter((row) => !row.valid).length).assertEqual(1);
        expect(preview[0].type).assertEqual('expense');
        expect(preview[0].date).assertEqual('2027-05-01');
        expect(preview[0].time).assertEqual('18:21');
        expect(preview[0].timeKnown).assertTrue();
        expect(preview[1].type).assertEqual('income');
        expect(preview[2].categoryName).assertEqual('其他');
        expect(preview[2].createCategory).assertFalse();
        expect(preview[2].createAccount).assertFalse();
        expect(preview[2].accountId).assertEqual('');
        const createAccountsPreview = previewCsv(table, mapping, snapshot,
          { createMissingCategories: true, createMissingAccounts: true, existingIds: [] });
        expect(createAccountsPreview[2].createCategory).assertTrue();
        expect(createAccountsPreview[2].categoryName).assertEqual('宠物 / 猫粮');
        expect(`${createAccountsPreview[2].accountName}:${createAccountsPreview[2].accountId}:${createAccountsPreview[2].createAccount}`)
          .assertEqual('宠物钱包::true');
        expect(preview[5].categoryId).assertEqual('csv-expense-shared');
        expect(preview[6].categoryId).assertEqual('csv-income-shared');
        const progress: number[] = [];
        const count = await workspace.importCsvBatch('fixture.csv', 'fixture-sha', preview, table.delimiter,
          false,
          (completed: number, total: number) => { progress.push(completed); expect(total).assertEqual(7); });
        expect(count).assertEqual(7);
        expect(progress.length).assertEqual(8);
        expect(progress[0]).assertEqual(0);
        expect(progress[progress.length - 1]).assertEqual(7);
        const imported = await workspace.snapshot('2027-05');
        expect(imported.entries.length).assertEqual(7);
        expect(imported.expenseMinor).assertEqual('2400');
        expect(imported.incomeMinor).assertEqual('510200');
        expect(imported.budgetUsedMinor).assertEqual('0');
        expect((await workspace.accountOverview()).netMinor).assertEqual('10000');
        expect(imported.categories.some((category) => category.name === '猫粮')).assertFalse();
        expect((await workspace.accountOverview()).accounts.some((account) => account.name === '宠物钱包')).assertFalse();
        const timeEntry = imported.entries.find((entry) => entry.note === '点号日期带时间');
        expect(timeEntry !== undefined).assertTrue();
        const detail = await workspace.entryDetail(timeEntry?.id || '');
        expect(detail.balanceMode).assertEqual('preserve');
        expect(detail.merchantName).assertEqual('午餐商户');
        expect(detail.addressText).assertEqual('人民路 1 号');
        const local = new Date(detail.occurredAtMs + detail.offsetMinutes * 60000);
        expect(local.getUTCHours()).assertEqual(18);
        expect(local.getUTCMinutes()).assertEqual(21);

        const duplicateTable = parseCsv('日期,类型,金额,分类,交易单号\r\n' +
          '2027-05-10,支出,1.00,餐饮,file-duplicate\r\n' +
          '2027-05-11,支出,2.00,餐饮,file-duplicate\r\n' +
          '2027-05-12,收入,3.00,工资,existing-source\r\n');
        const duplicatePreview = previewCsv(duplicateTable, detectCsvMapping(duplicateTable.headers), imported,
          { createMissingCategories: true, createMissingAccounts: true, existingIds: ['existing-source'] });
        expect(duplicatePreview[0].duplicate).assertFalse();
        expect(duplicatePreview[1].duplicate).assertTrue();
        expect(duplicatePreview[1].duplicateReason).assertEqual('文件内重复');
        expect(duplicatePreview[1].selected).assertFalse();
        expect(duplicatePreview[2].duplicate).assertTrue();
        expect(duplicatePreview[2].duplicateReason).assertEqual('历史账目已有');
        expect(duplicatePreview[2].selected).assertFalse();
        const splitTable = parseCsv('日期,时间,类型,金额,分类\r\n2027-05-15,19:08:30,支出,1.00,餐饮\r\n');
        const splitPreview = previewCsv(splitTable, detectCsvMapping(splitTable.headers), imported);
        expect(splitPreview[0].time).assertEqual('19:08');
        expect(splitPreview[0].timeKnown).assertTrue();
        const statementTable = parseCsv('微信支付账单明细\r\n说明信息\r\n' +
          '交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注\r\n' +
          '45592.70208333333,商户消费,便利店,饮料,支出,17.20,零钱,支付成功,statement-1,merchant-1,\r\n' +
          '2026-11-08 10:00:00,转账,好友,,不计收支,100.00,零钱,已到账,statement-2,merchant-2,\r\n');
        const statementPreview = previewCsv(statementTable, detectCsvMapping(statementTable.headers), imported);
        expect(statementTable.rows.length).assertEqual(2);
        expect(statementPreview[0].time).assertEqual('16:51');
        expect(statementPreview[0].issues.join(',')).assertEqual('');
        expect(statementPreview[1].valid).assertFalse();
        expect(statementPreview[1].selected).assertFalse();
        expect(statementPreview[1].issues.includes('不计收支，已跳过')).assertTrue();
        duplicatePreview[1].selected = true;
        duplicatePreview[2].selected = true;
        expect(await workspace.importCsvBatch('duplicate.csv', 'duplicate-sha', duplicatePreview, ',')).assertEqual(3);
        expect(await workspace.importCsvBatch('apply.csv', 'apply-sha', [preview[0]], ',', true)).assertEqual(1);
        expect((await workspace.accountOverview()).netMinor).assertEqual('8800');
      } finally {
        await LedgerWorkspace.close(name);
        await relationalStore.deleteRdbStore(host, name);
      }
    });
  });
}
