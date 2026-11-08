import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { describe, expect, it } from '@ohos/hypium';
import { Money } from '../../../main/ets/core/money/Money';
import { BackupFiles } from '../../../main/ets/data/backup/BackupFiles';
import { BackupZip } from '../../../main/ets/data/backup/BackupZip';
import { exportLedgerCsv } from '../../../main/ets/data/exchange/LedgerCsvExport';
import { LedgerAttachmentZipExport } from '../../../main/ets/data/exchange/LedgerAttachmentZipExport';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { ExpenseCommand } from '../../../main/ets/domain/model/ExpenseRecord';
import { LedgerAttachmentDraft } from '../../../main/ets/domain/model/LedgerAttachment';
import { IncomeCommand } from '../../../main/ets/domain/model/IncomeRecord';
import { TransferCommand } from '../../../main/ets/domain/model/TransferRecord';

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

function expense(workspace: LedgerWorkspace, id: string, attachments: LedgerAttachmentDraft[]): ExpenseCommand {
  const date = new Date(2027, 2, 20, 12, 30);
  const amount = Money.parse('26.00', workspace.currency);
  return { id: id, bookId: DEFAULT_BOOK_ID, categoryId: 'expense-food-0',
    gross: amount, discount: Money.parse('0', workspace.currency), bookPaid: amount,
    includeInAssets: false, includeInBudget: true, note: '附件闭环',
    attachments: attachments, occurredAtMs: date.getTime(), localDate: '2027-03-20',
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, offsetMinutes: -date.getTimezoneOffset() };
}

export default function attachmentsTest() {
  describe('Attachments', () => {
    it('stores_links_previews_exports_and_updates_transaction_images', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_app_test_attachments_' + util.generateRandomUUID() + '.db';
      const source = host.cacheDir + '/attachment-source-' + util.generateRandomUUID() + '.png';
      const archive = host.cacheDir + '/attachment-export-' + util.generateRandomUUID() + '.zip';
      let resourceRoot = '';
      let resourceFile = '';
      try {
        const png = new util.Base64Helper().decodeSync(
          'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAGUlEQVR42mP4Eqv0nxLMMGrAqAGjBgwXAwDriXIf1SGMUgAAAABJRU5ErkJggg==');
        await BackupFiles.write(source, png.buffer as ArrayBuffer);
        const workspace = await LedgerWorkspace.open(host, name);
        resourceRoot = workspace.backup.resources.root;
        const draft = await workspace.saveImageAttachment(source);
        resourceFile = resourceRoot + '/' + draft.relativePath;
        expect((await BackupFiles.read(resourceFile, 1024 * 1024)).byteLength > 0).assertTrue();
        await workspace.saveExpense(expense(workspace, 'attachment-entry', [draft]));
        await workspace.createAccount({ id: 'attachment-source-account', name: '附件储蓄卡', kind: 'asset',
          styleKey: 'bank_card', includeInNetAssets: true, opening: Money.parse('100', workspace.currency) });
        await workspace.createAccount({ id: 'attachment-target-account', name: '附件微信', kind: 'asset',
          styleKey: 'wechat_pay', includeInNetAssets: true, opening: Money.parse('0', workspace.currency) });
        const incomeAmount = Money.parse('20', workspace.currency);
        const income: IncomeCommand = { id: 'attachment-income', bookId: DEFAULT_BOOK_ID,
          categoryId: 'income-salary', amount: incomeAmount, bookAmount: incomeAmount,
          accountId: undefined, accountAmount: undefined, includeInAssets: false,
          tagIds: [], attachments: [draft], note: '附件收入', occurredAtMs: new Date(2027, 2, 20, 13).getTime(),
          localDate: '2027-03-20', timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
          offsetMinutes: -new Date(2027, 2, 20, 13).getTimezoneOffset() };
        await workspace.saveIncome(income);
        const transferAmount = Money.parse('10', workspace.currency);
        const transfer: TransferCommand = { id: 'attachment-transfer', bookId: DEFAULT_BOOK_ID,
          fromAccountId: 'attachment-source-account', toAccountId: 'attachment-target-account',
          amount: transferAmount, includeInAssets: true, tagIds: [], attachments: [draft],
          note: '附件转账', occurredAtMs: new Date(2027, 2, 20, 14).getTime(),
          localDate: '2027-03-20', timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
          offsetMinutes: -new Date(2027, 2, 20, 14).getTimezoneOffset() };
        await workspace.saveTransfer(transfer);
        const snapshot = await workspace.snapshot('2027-03');
        expect(snapshot.entries.length).assertEqual(3);
        for (const entry of snapshot.entries) {
          expect((entry.attachments || []).length).assertEqual(1);
          expect(entry.attachments?.[0].sha256).assertEqual(draft.sha256);
        }
        const detail = await workspace.entryDetail('attachment-entry');
        expect((detail.attachments || []).length).assertEqual(1);
        expect(detail.attachments?.[0].filePath).assertEqual(resourceFile);
        await LedgerAttachmentZipExport.exportTo(archive, snapshot, exportLedgerCsv(snapshot), resourceRoot, host);
        const parts = BackupZip.decodeOffice(await BackupFiles.read(archive));
        expect(parts.some((part) => part.path === 'docProps/xiaoqiao-entries.csv')).assertTrue();
        expect(parts.some((part) => part.path === 'docProps/attachments.json')).assertTrue();
        expect(parts.some((part) => part.path === 'xl/media/' + draft.sha256 + '.png')).assertTrue();
        const changed = expense(workspace, 'attachment-entry', []);
        await workspace.updateExpense(changed, detail.revision);
        expect(((await workspace.entryDetail('attachment-entry')).attachments || []).length).assertEqual(0);
        expect(((await workspace.entryDetail('attachment-income')).attachments || []).length).assertEqual(1);
        expect(((await workspace.entryDetail('attachment-transfer')).attachments || []).length).assertEqual(1);
      } finally {
        await LedgerWorkspace.close(name);
        await relationalStore.deleteRdbStore(host, name);
        if (resourceFile.length > 0) { await BackupFiles.remove(resourceFile); }
        if (resourceRoot.length > 0) {
          await BackupFiles.remove(resourceRoot + '/images');
          await BackupFiles.remove(resourceRoot);
        }
        if (await fs.access(source)) { await BackupFiles.remove(source); }
        if (await fs.access(archive)) { await BackupFiles.remove(archive); }
      }
    });

    it('opens_attachment_section_in_expense_editor', 0, async () => {
      const host = await testContext();
      const driver = Driver.create();
      await driver.waitForComponent(ON.id('ledger-tab-0'), 10000);
      await (await driver.findComponent(ON.id('ledger-tab-0'))).click();
      await (await driver.waitForComponent(ON.id('ledger-add-expense'), 5000)).click();
      const categories = await driver.waitForComponent(ON.id('expense-categories'), 5000);
      const bounds = await categories.getBounds();
      const centerX = Math.round((bounds.left + bounds.right) / 2);
      await driver.swipe(centerX, bounds.bottom - 40, centerX, bounds.top + 40, 600);
      await driver.waitForComponent(ON.id('expense-categories-compact'), 5000);
      const formScroll = await driver.waitForComponent(ON.id('expense-form-scroll'), 5000);
      const card = await formScroll.scrollSearch(ON.id('expense-attachment-card'));
      expect(card !== null).assertTrue();
      expect(await driver.waitForComponent(ON.id('expense-attachment-add').enabled(true), 5000) !== null).assertTrue();
      expect(await driver.findComponent(ON.id('expense-attachment-list'))).assertNull();
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-expense-attachments.png')).assertTrue();
      await (await driver.findComponent(ON.id('expense-close'))).click();
      const source = host.cacheDir + '/attachment-ui-' + util.generateRandomUUID() + '.png';
      const databaseName = AppStorage.get<string>('ledgerDatabaseName') || '';
      const workspace = await LedgerWorkspace.open(host, databaseName);
      const png = new util.Base64Helper().decodeSync(
        'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAGUlEQVR42mP4Eqv0nxLMMGrAqAGjBgwXAwDriXIf1SGMUgAAAABJRU5ErkJggg==');
      try {
        await BackupFiles.write(source, png.buffer as ArrayBuffer);
        const draft = await workspace.saveImageAttachment(source);
        const now = new Date();
        const localDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-` +
          String(now.getDate()).padStart(2, '0');
        const amount = Money.parse('18.00', workspace.currency);
        await workspace.saveExpense({ id: 'attachment-ui-entry', bookId: DEFAULT_BOOK_ID,
          categoryId: 'expense-food-0', gross: amount, discount: Money.parse('0', workspace.currency),
          bookPaid: amount, includeInAssets: false, includeInBudget: false, note: '附件详情截图',
          attachments: [draft], occurredAtMs: now.getTime(), localDate: localDate,
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
          offsetMinutes: -now.getTimezoneOffset() });
        await (await driver.waitForComponent(ON.id('ledger-tab-4'), 5000)).click();
        const settings = await driver.waitForComponent(ON.id('settings-scroll'), 5000);
        await (await settings.scrollSearch(ON.id('settings-data-exchange'))).click();
        await driver.waitForComponent(ON.id('data-exchange-page'), 5000);
        await (await driver.findComponent(ON.id('data-exchange-close'))).click();
        await (await driver.waitForComponent(ON.id('ledger-tab-0'), 5000)).click();
        await (await driver.waitForComponent(ON.id('attachment-ui-entry'), 5000)).click();
        await driver.waitForComponent(ON.id('entry-detail-attachments'), 5000);
        expect(await driver.screenCap(host.filesDir + '/xiaoqiao-entry-attachments.png')).assertTrue();
        const detail = await workspace.entryDetail('attachment-ui-entry');
        const attachmentId = detail.attachments?.[0].id || '';
        await (await driver.findComponent(ON.id('entry-attachment-' + attachmentId))).click();
        await driver.waitForComponent(ON.id('entry-attachment-preview-image'), 5000);
        await driver.delayMs(1500);
        expect(await driver.screenCap(host.filesDir + '/xiaoqiao-entry-attachment-preview.png')).assertTrue();
      } finally {
        if (await fs.access(source)) { await BackupFiles.remove(source); }
      }
    });
  });
}
