import { recoveryError } from '../domain/model/ExpenseRecovery';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { BackupFiles } from '../data/backup/BackupFiles';
import { exportLedgerCsv, filterLedgerEntries, LEDGER_EXPORT_COLUMNS,
  LedgerExportColumn } from '../data/exchange/LedgerCsvExport';
import { LedgerXlsxExport } from '../data/exchange/LedgerXlsxExport';
import { LedgerAttachmentZipExport } from '../data/exchange/LedgerAttachmentZipExport';
import { listXlsxSheets, readXlsxRows, XlsxSheetInfo } from '../data/exchange/LedgerXlsxImport';
import { CsvColumnMapping, CsvPreviewRow, detectCsvDelimiter, detectCsvMapping,
  detectHeaderRowIndex, parseCsvRows, previewCsv, readDelimitedText, tableFromRows } from '../data/exchange/LedgerCsvImport';
import { CsvImportMetadata, ImportBatchRowDetail, ImportBatchSummary, ImportPreviewCounts,
  countImportPreview, ImportProfile } from '../data/exchange/ImportProfile';
import { LedgerAccount, LedgerSnapshot, SavedLedgerEntry } from '../domain/model/LedgerSnapshot';
import { transferPurposeLabel } from '../domain/model/TransferRecord';
import { localDate, parseLocalDate } from '../presentation/statistics/StatisticsPeriod';

@Component
export struct DataExchangePage {
  workspace: LedgerWorkspace | undefined = undefined;
  monthKey: string = '';
  onClose: () => void = () => {};
  onImported: () => Promise<void> = async () => {};
  @State private snapshot: LedgerSnapshot | undefined = undefined;
  @State private exportSnapshot: LedgerSnapshot | undefined = undefined;
  @State private exportRangeEntries: SavedLedgerEntry[] = [];
  @State private exportBookName: string = '';
  @State private exportKind: string = 'all';
  @State private exportAccountName: string = '';
  @State private exportStartDate: string = '';
  @State private exportEndDate: string = '';
  @State private loading: boolean = true;
  @State private busy: boolean = false;
  @State private message: string = '';
  @State private error: boolean = false;
  @State private selectedExportKeys: string[] = LEDGER_EXPORT_COLUMNS.map((column) => column.key);
  @State private importBusy: boolean = false;
  @State private importMessage: string = '';
  @State private importError: boolean = false;
  @State private importHeaders: string[] = [];
  @State private importRows: string[][] = [];
  @State private importRawRows: string[][] = [];
  @State private importText: string = '';
  @State private importHeaderIndex: number = 0;
  @State private importPreview: CsvPreviewRow[] = [];
  @State private importMapping: CsvColumnMapping = { date: -1, time: -1, type: -1, amount: -1, category: -1,
    transferAmount: -1, account: -1, toAccount: -1, purpose: -1, fee: -1, coupon: -1, feeBudget: -1, note: -1,
    sourceId: -1, merchant: -1, address: -1, latitude: -1, longitude: -1, includeInBudget: -1, spendingNature: -1, spendingNatureColor: -1, originalEntryId: -1, reimbursementPending: -1, status: -1 };
  @State private importFileName: string = '';
  @State private importSha256: string = '';
  @State private importDelimiter: string = ',';
  @State private importCompleted: number = 0;
  @State private importTotal: number = 0;
  @State private importPreviewMode: number = 0;
  @State private importPreviewLimit: number = 20;
  @State private xlsxUri: string = '';
  @State private xlsxSheets: XlsxSheetInfo[] = [];
  @State private xlsxSheetPath: string = '';
  @State private existingImportIds: string[] = [];
  @State private importApplyBalance: boolean = false;
  @State private createMissingAccounts: boolean = false;
  @State private createMissingCategories: boolean = false;
  @State private importFeeInBudget: boolean = false;
  @State private importProfiles: ImportProfile[] = [];
  @State private selectedImportProfileId: string = '';
  @State private importProfileName: string = '';
  @State private importBatches: ImportBatchSummary[] = [];
  @State private selectedImportBatchId: string = '';
  @State private selectedBatchRows: ImportBatchRowDetail[] = [];
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.load(); }

  private dateText(value: string): string {
    return value.replace(/-/g, '.');
  }

  private monthEnd(year: number, month: number): string {
    const date = new Date(year, month, 0);
    return `${year}-${String(month).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' :
      '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }

  private async load(): Promise<void> {
    if (this.workspace === undefined) { this.loading = false; return; }
    this.loading = true;
    this.message = '';
    this.error = false;
    try {
      this.snapshot = await this.workspace.snapshot(this.monthKey);
      this.existingImportIds = await this.workspace.existingImportIds();
      this.importProfiles = await this.workspace.importProfiles();
      this.importBatches = await this.workspace.recentImportBatches(10);
      if (this.exportStartDate.length === 0) {
        const monthParts = this.monthKey.split('-');
        this.exportStartDate = this.monthKey + '-01';
        this.exportEndDate = this.monthEnd(Number(monthParts[0]), Number(monthParts[1]));
      }
      await this.loadExportRange();
    }
    catch (_) { this.message = '账本暂时无法读取，请返回后重试'; this.error = true; }
    finally { this.loading = false; }
  }

  private async loadExportRange(): Promise<void> {
    const workspace = this.workspace;
    if (workspace === undefined || this.exportStartDate.length === 0 || this.exportEndDate.length === 0) { return; }
    this.exportSnapshot = undefined;
    this.exportRangeEntries = [];
    if (this.exportStartDate > this.exportEndDate) {
      this.message = '导出结束日期不能早于开始日期';
      this.error = true;
      return;
    }
    try {
      const startMonth = this.exportStartDate.substring(0, 7);
      const endMonth = this.exportEndDate.substring(0, 7);
      const entries: SavedLedgerEntry[] = [];
      let cursor = startMonth;
      let bookName = this.snapshot?.bookName || '';
      while (cursor <= endMonth) {
        const snapshot = await workspace.snapshot(cursor);
        bookName = snapshot.bookName;
        for (const entry of snapshot.entries) {
          if (entry.date >= this.exportStartDate && entry.date <= this.exportEndDate) { entries.push(entry); }
        }
        const parts = cursor.split('-');
        const next = new Date(Number(parts[0]), Number(parts[1]), 1);
        cursor = `${next.getFullYear()}-${String(next.getMonth() + 1).padStart(2, '0')}`;
      }
      entries.sort((left: SavedLedgerEntry, right: SavedLedgerEntry) =>
        right.occurredAtMs - left.occurredAtMs || right.id.localeCompare(left.id));
      this.exportRangeEntries = entries;
      this.exportBookName = bookName;
      this.applyExportFilters();
      this.message = '';
      this.error = false;
    } catch (_) {
      this.exportSnapshot = undefined;
      this.message = '导出范围读取失败，请重试';
      this.error = true;
    }
  }

  private applyExportFilters(): void {
    const entries = filterLedgerEntries(this.exportRangeEntries, this.exportKind, this.exportAccountName);
    this.exportSnapshot = { bookId: this.snapshot?.bookId || '', bookName: this.exportBookName,
      categories: this.snapshot?.categories || [], incomeCategories: this.snapshot?.incomeCategories || [],
      spendingNatures: this.snapshot?.spendingNatures || [], tags: this.snapshot?.tags || [],
      budgetNatureLines: [], accounts: this.snapshot?.accounts || [], entries: entries,
      incomeMinor: '0', expenseMinor: '0', budgetTotalMinor: '0', budgetUsedMinor: '0' };
  }

  private exportAccountOptions(): SelectOption[] {
    const values: SelectOption[] = [{ value: '全部账户' }];
    for (const account of this.snapshot?.accounts || []) { values.push({ value: account.name }); }
    return values;
  }

  private selectedExportAccountIndex(): number {
    if (this.exportAccountName.length === 0) { return 0; }
    return Math.max(0,
      (this.snapshot?.accounts || []).findIndex((account: LedgerAccount) =>
        account.name === this.exportAccountName) + 1);
  }

  private selectExportKind(kind: string): void {
    if (this.exportKind === kind) { return; }
    this.exportKind = kind;
    this.applyExportFilters();
  }

  private selectExportAccount(index: number): void {
    this.exportAccountName = index === 0 ? '' : (this.snapshot?.accounts[index - 1]?.name || '');
    this.applyExportFilters();
  }

  private pickExportDate(start: boolean): void {
    const value = parseLocalDate(start ? this.exportStartDate : this.exportEndDate);
    this.getUIContext().showDatePickerDialog({ selected: value,
      selectedTextStyle: { color: $r('app.color.xq_font_emphasize') },
      acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      cancelButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      onDateAccept: (date: Date) => {
        const valueText = localDate(date);
        if (start) { this.exportStartDate = valueText; } else { this.exportEndDate = valueText; }
        this.message = '';
        this.error = false;
        this.loadExportRange();
      }
    });
  }

  private async exportCsv(): Promise<void> {
    const exportSnapshot = this.exportSnapshot;
    if (this.busy || exportSnapshot === undefined) { return; }
    this.busy = true;
    this.message = '';
    this.error = false;
    try {
      const options = new picker.DocumentSaveOptions();
      const safeBook = (exportSnapshot.bookName || '账本').replace(/[\\/:*?"<>|]/g, '_');
      options.newFileNames = [`${safeBook}-${this.exportStartDate}-${this.exportEndDate}.csv`];
      const pickerInstance = new picker.DocumentViewPicker(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const destinations = await pickerInstance.save(options);
      if (destinations.length === 0) { return; }
      await BackupFiles.writeText(destinations[0], exportLedgerCsv(exportSnapshot, this.selectedExportKeys));
      this.message = `已导出 ${exportSnapshot.entries.length} 笔账目`;
    } catch (_) {
      this.message = 'CSV 未能保存，请检查存储空间后重试';
      this.error = true;
    } finally { this.busy = false; }
  }

  private async exportXlsx(): Promise<void> {
    const exportSnapshot = this.exportSnapshot;
    if (this.busy || exportSnapshot === undefined) { return; }
    this.busy = true;
    this.message = '';
    this.error = false;
    try {
      const options = new picker.DocumentSaveOptions();
      const safeBook = (exportSnapshot.bookName || '账本').replace(/[\\/:*?"<>|]/g, '_');
      options.newFileNames = [`${safeBook}-${this.exportStartDate}-${this.exportEndDate}.xlsx`];
      const pickerInstance = new picker.DocumentViewPicker(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const destinations = await pickerInstance.save(options);
      if (destinations.length === 0) { return; }
      await LedgerXlsxExport.exportTo(destinations[0], exportSnapshot,
        this.getUIContext().getHostContext() as common.Context, this.selectedExportKeys);
      this.message = `已导出 ${exportSnapshot.entries.length} 笔账目`;
    } catch (_) {
      this.message = 'Excel 文件未能保存，请检查存储空间后重试';
      this.error = true;
    } finally { this.busy = false; }
  }

  private async exportAttachmentZip(): Promise<void> {
    const exportSnapshot = this.exportSnapshot;
    const workspace = this.workspace;
    if (this.busy || exportSnapshot === undefined || workspace === undefined) { return; }
    this.busy = true;
    this.message = '';
    this.error = false;
    try {
      const options = new picker.DocumentSaveOptions();
      const safeBook = (exportSnapshot.bookName || '账本').replace(/[\\/:*?"<>|]/g, '_');
      options.newFileNames = [`${safeBook}-${this.exportStartDate}-${this.exportEndDate}-含图片.zip`];
      const pickerInstance = new picker.DocumentViewPicker(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const destinations = await pickerInstance.save(options);
      if (destinations.length === 0) { return; }
      await LedgerAttachmentZipExport.exportTo(destinations[0], exportSnapshot,
        exportLedgerCsv(exportSnapshot, this.selectedExportKeys), workspace.backup.resources.root,
        this.getUIContext().getHostContext() as common.Context);
      this.message = `已导出 ${exportSnapshot.entries.length} 笔账目及 ${this.exportAttachmentCount()} 张图片`;
    } catch (_) {
      this.message = '附件 ZIP 未能保存，请检查图片资源后重试';
      this.error = true;
    } finally { this.busy = false; }
  }

  private exportAttachmentCount(): number {
    return (this.exportSnapshot?.entries || []).reduce((count: number, entry: SavedLedgerEntry) =>
      count + (entry.attachments || []).length, 0);
  }

  private applyImportRows(rawRows: string[][], headerIndex: number, delimiter: string,
    resetMapping: boolean = true): void {
    const safeIndex = Math.max(0, Math.min(rawRows.length - 1, headerIndex));
    const table = tableFromRows(rawRows, delimiter, safeIndex);
    this.importRawRows = rawRows;
    this.importHeaderIndex = safeIndex;
    this.importHeaders = table.headers;
    this.importRows = table.rows;
    this.importDelimiter = delimiter;
    if (resetMapping) { this.importMapping = detectCsvMapping(table.headers); }
    this.refreshImportPreview();
    this.importMessage = `已读取 ${table.rows.length} 行，请检查表头和字段映射`;
    this.importError = false;
  }

  private resetProfileSelection(): void {
    this.selectedImportProfileId = '';
    this.importProfileName = '';
  }

  private async chooseImportCsv(): Promise<void> {
    if (this.busy || this.importBusy || this.snapshot === undefined) { return; }
    this.importBusy = true;
    this.importMessage = '';
    this.importError = false;
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['CSV 表格|.csv'];
      const pickerInstance = new picker.DocumentViewPicker(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const sources = await pickerInstance.select(options);
      if (sources.length === 0) { return; }
      const text = await readDelimitedText(sources[0]);
      const rawRows = parseCsvRows(text);
      const delimiter = detectCsvDelimiter(text);
      const headerIndex = detectHeaderRowIndex(rawRows);
      const info = await BackupFiles.info(sources[0], 'import.csv');
      this.importFileName = sources[0].split('/').pop() || 'import.csv';
      this.importSha256 = info.sha256;
      this.importText = text;
      this.importApplyBalance = false;
      this.createMissingAccounts = false;
      this.createMissingCategories = false;
      this.importFeeInBudget = false;
      this.resetProfileSelection();
      this.applyImportRows(rawRows, headerIndex, delimiter);
    } catch (_) {
      this.importMessage = 'CSV 无法读取，请检查文件编码、引号和表头';
      this.importError = true;
    } finally { this.importBusy = false; }
  }

  private toggleExportKey(key: string): void {
    this.selectedExportKeys = this.selectedExportKeys.includes(key) ?
      this.selectedExportKeys.filter((value: string) => value !== key) : [...this.selectedExportKeys, key];
  }

  private async chooseImportXlsx(): Promise<void> {
    if (this.busy || this.importBusy || this.snapshot === undefined) { return; }
    this.importBusy = true;
    this.importMessage = '';
    this.importError = false;
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['Excel 工作簿|.xlsx'];
      const pickerInstance = new picker.DocumentViewPicker(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const sources = await pickerInstance.select(options);
      if (sources.length === 0) { return; }
      const host = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const sheets = await listXlsxSheets(sources[0], host.cacheDir);
      const path = sheets.length > 0 ? sheets[0].path : '';
      const rawRows = await readXlsxRows(sources[0], host.cacheDir, path);
      const headerIndex = detectHeaderRowIndex(rawRows);
      const info = await BackupFiles.info(sources[0], 'import.xlsx');
      this.xlsxUri = sources[0];
      this.xlsxSheets = sheets;
      this.xlsxSheetPath = path;
      this.importFileName = sources[0].split('/').pop() || 'import.xlsx';
      this.importSha256 = info.sha256;
      this.importApplyBalance = false;
      this.createMissingAccounts = false;
      this.createMissingCategories = false;
      this.importFeeInBudget = false;
      this.importText = '';
      this.resetProfileSelection();
      this.applyImportRows(rawRows, headerIndex, ',');
    } catch (_) {
      this.importMessage = 'Excel 文件无法读取，请检查工作簿和工作表';
      this.importError = true;
    } finally { this.importBusy = false; }
  }

  private refreshImportPreview(): void {
    if (this.snapshot === undefined || this.importHeaders.length === 0) { return; }
    const table = tableFromRows(this.importRawRows, this.importDelimiter, this.importHeaderIndex);
    this.importPreview = previewCsv(table, this.importMapping, this.snapshot,
      { createMissingCategories: this.createMissingCategories,
        createMissingAccounts: this.createMissingAccounts, feeInBudget: this.importFeeInBudget,
        existingIds: this.existingImportIds });
    this.importPreviewMode = 0;
    this.importPreviewLimit = 20;
  }

  private filteredImportPreview(): CsvPreviewRow[] {
    if (this.importPreviewMode === 1) {
      return this.importPreview.filter((row: CsvPreviewRow) => row.duplicate);
    }
    if (this.importPreviewMode === 2) {
      return this.importPreview.filter((row: CsvPreviewRow) => !row.valid);
    }
    return this.importPreview;
  }

  private mappingLabel(index: number): string {
    return index >= 0 && index < this.importHeaders.length ? this.importHeaders[index] : '不映射';
  }

  private importSourceLabel(): string {
    if (/微信|wechat|weixin/i.test(this.importFileName)) { return '微信账单'; }
    if (/支付宝|alipay/i.test(this.importFileName)) { return '支付宝账单'; }
    return /\.xlsx$/i.test(this.importFileName) ? 'Excel 工作簿' : 'CSV 文件';
  }

  private mappingOptions(): SelectOption[] {
    const values: SelectOption[] = [{ value: '不映射' }];
    for (const header of this.importHeaders) { values.push({ value: header }); }
    return values;
  }

  private updateMapping(field: string, selected: number): void {
    const index = selected - 1;
    this.importMapping = {
      date: field === 'date' ? index : this.importMapping.date,
      time: field === 'time' ? index : this.importMapping.time,
      type: field === 'type' ? index : this.importMapping.type,
      amount: field === 'amount' ? index : this.importMapping.amount,
      transferAmount: field === 'transferAmount' ? index : this.importMapping.transferAmount,
      category: field === 'category' ? index : this.importMapping.category,
      account: field === 'account' ? index : this.importMapping.account,
      toAccount: field === 'toAccount' ? index : this.importMapping.toAccount,
      purpose: field === 'purpose' ? index : this.importMapping.purpose,
      fee: field === 'fee' ? index : this.importMapping.fee,
      coupon: field === 'coupon' ? index : this.importMapping.coupon,
      feeBudget: field === 'feeBudget' ? index : this.importMapping.feeBudget,
      note: field === 'note' ? index : this.importMapping.note,
      sourceId: field === 'sourceId' ? index : this.importMapping.sourceId,
      merchant: field === 'merchant' ? index : this.importMapping.merchant,
      address: field === 'address' ? index : this.importMapping.address,
      latitude: field === 'latitude' ? index : this.importMapping.latitude,
      longitude: field === 'longitude' ? index : this.importMapping.longitude,
      includeInBudget: field === 'includeInBudget' ? index : this.importMapping.includeInBudget,
      spendingNature: field === 'spendingNature' ? index : this.importMapping.spendingNature,
      spendingNatureColor: field === 'spendingNatureColor' ? index : this.importMapping.spendingNatureColor,
      originalEntryId: field === 'originalEntryId' ? index : this.importMapping.originalEntryId,
      reimbursementPending: field === 'reimbursementPending' ? index : this.importMapping.reimbursementPending,
      status: field === 'status' ? index : this.importMapping.status
    };
    this.refreshImportPreview();
    this.importMessage = '';
  }

  private headerRowLabel(index: number): string {
    const values = (this.importRawRows[index] || []).filter((value: string) => value.trim().length > 0).slice(0, 3);
    return `第 ${index + 1} 行` + (values.length > 0 ? ` · ${values.join(' / ')}` : ' · 空行');
  }

  private headerRowOptions(): SelectOption[] {
    const values: SelectOption[] = [];
    const count = Math.min(50, this.importRawRows.length);
    for (let index = 0; index < count; index++) { values.push({ value: this.headerRowLabel(index) }); }
    return values;
  }

  private selectHeaderRow(index: number): void {
    if (index < 0 || index >= this.importRawRows.length) { return; }
    this.applyImportRows(this.importRawRows, index, this.importDelimiter);
    this.importMessage = `表头已切换为第 ${index + 1} 行`;
  }

  private delimiterLabel(value: string): string {
    return value === '\t' ? '制表符' : value === ';' ? '分号' : '逗号';
  }

  private delimiterOptions(): SelectOption[] {
    return [{ value: '逗号' }, { value: '制表符' }, { value: '分号' }];
  }

  private selectedDelimiterIndex(): number {
    return this.importDelimiter === '\t' ? 1 : this.importDelimiter === ';' ? 2 : 0;
  }

  private selectDelimiter(index: number): void {
    const delimiter = index === 1 ? '\t' : index === 2 ? ';' : ',';
    const rows = parseCsvRows(this.importText, delimiter);
    const headerIndex = Math.min(this.importHeaderIndex, Math.max(0, rows.length - 1));
    this.applyImportRows(rows, headerIndex, delimiter);
    this.importMessage = `已切换为${this.delimiterLabel(delimiter)}分隔`;
  }

  private importProfileOptions(): SelectOption[] {
    const values: SelectOption[] = [{ value: '选择已保存模板' }];
    for (const profile of this.importProfiles) { values.push({ value: profile.name }); }
    return values;
  }

  private selectedImportProfileIndex(): number {
    const index = this.importProfiles.findIndex((profile: ImportProfile) =>
      profile.id === this.selectedImportProfileId);
    return index < 0 ? 0 : index + 1;
  }

  private applyImportProfile(index: number): void {
    if (index <= 0 || index > this.importProfiles.length) {
      this.selectedImportProfileId = '';
      return;
    }
    const profile = this.importProfiles[index - 1];
    this.selectedImportProfileId = profile.id;
    this.importProfileName = profile.name;
    this.importMapping = profile.mapping;
    this.createMissingCategories = profile.options.createMissingCategories;
    this.createMissingAccounts = profile.options.createMissingAccounts;
    this.importFeeInBudget = profile.options.feeInBudget;
    if (profile.options.delimiter.length > 0 && this.importText.length > 0) {
      const rows = parseCsvRows(this.importText, profile.options.delimiter);
      this.applyImportRows(rows, profile.options.headerRow - 1, profile.options.delimiter, false);
    } else if (this.importRawRows.length > 0) {
      this.applyImportRows(this.importRawRows, profile.options.headerRow - 1,
        profile.options.delimiter || this.importDelimiter, false);
    } else {
      this.refreshImportPreview();
    }
    this.importMessage = `已应用模板“${profile.name}”`;
    this.importError = false;
  }

  private async saveImportProfile(): Promise<void> {
    if (this.workspace === undefined || this.importHeaders.length === 0) { return; }
    try {
      const id = await this.workspace.saveImportProfile(this.selectedImportProfileId,
        this.importProfileName, this.importSourceLabel(), this.importMapping,
        { headerRow: this.importHeaderIndex + 1, delimiter: this.importDelimiter,
          createMissingCategories: this.createMissingCategories,
          createMissingAccounts: this.createMissingAccounts, feeInBudget: this.importFeeInBudget });
      this.selectedImportProfileId = id;
      this.importProfiles = await this.workspace.importProfiles();
      this.importMessage = '字段映射模板已保存';
      this.importError = false;
    } catch (_) {
      this.importMessage = '请填写模板名称后再保存';
      this.importError = true;
    }
  }

  private async deleteImportProfile(): Promise<void> {
    if (this.workspace === undefined || this.selectedImportProfileId.length === 0) { return; }
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '删除这个字段映射模板？',
      message: '模板删除后不能恢复，之后可以重新保存。',
      buttons: [{ text: '取消', color: $r('app.color.xq_font_secondary') },
        { text: '删除', color: $r('app.color.xq_warning') }]
    }).catch(() => undefined);
    if (result?.index !== 1 || this.workspace === undefined) { return; }
    await this.workspace.deleteImportProfile(this.selectedImportProfileId);
    this.selectedImportProfileId = '';
    this.importProfileName = '';
    this.importProfiles = await this.workspace.importProfiles();
    this.importMessage = '字段映射模板已删除';
    this.importError = false;
  }

  private async refreshImportHistory(): Promise<void> {
    if (this.workspace === undefined) { return; }
    this.importBatches = await this.workspace.recentImportBatches(10);
    if (this.selectedImportBatchId.length > 0) {
      this.selectedBatchRows = await this.workspace.importBatchRows(this.selectedImportBatchId);
    }
  }

  private async openImportBatch(id: string): Promise<void> {
    if (this.workspace === undefined) { return; }
    if (this.selectedImportBatchId === id) {
      this.selectedImportBatchId = '';
      this.selectedBatchRows = [];
      return;
    }
    this.selectedImportBatchId = id;
    this.selectedBatchRows = await this.workspace.importBatchRows(id);
  }

  private importCounts(): ImportPreviewCounts {
    return countImportPreview(this.importPreview);
  }

  private issueCategory(issue: string): string {
    if (issue.startsWith('交易状态') || issue === '不计收支，已跳过') { return '交易状态跳过'; }
    if (issue.includes('账户')) { return '账户未匹配'; }
    if (issue.includes('日期')) { return '日期无效'; }
    if (issue.includes('金额') || issue.includes('优惠')) { return '金额异常'; }
    if (issue.includes('分类')) { return '分类未匹配'; }
    if (issue.includes('类型')) { return '类型未识别'; }
    return issue;
  }

  private issueSummary(): string {
    const counts: Map<string, number> = new Map();
    for (const row of this.importPreview) {
      for (const issue of row.issues) {
        const key = this.issueCategory(issue);
        counts.set(key, (counts.get(key) || 0) + 1);
      }
    }
    const values: string[] = [];
    counts.forEach((count: number, key: string) => { values.push(`${key} ${count}`); });
    return values.join(' · ');
  }

  private importFileDisplayName(name: string): string {
    try { return decodeURIComponent(name); } catch (_) { return name; }
  }

  private batchStatusText(status: string): string {
    return status === 'committed' ? '已完成' : status === 'committing' ? '导入中' :
      status === 'failed' ? '失败' : status === 'validated' ? '已校验' : '待确认';
  }

  private clearImport(): void {
    this.importHeaders = [];
    this.importRows = [];
    this.importRawRows = [];
    this.importText = '';
    this.importHeaderIndex = 0;
    this.importPreview = [];
    this.importFileName = '';
    this.importSha256 = '';
    this.importMessage = '';
    this.importError = false;
    this.xlsxUri = '';
    this.xlsxSheets = [];
    this.xlsxSheetPath = '';
    this.importApplyBalance = false;
    this.createMissingAccounts = false;
    this.createMissingCategories = false;
    this.importFeeInBudget = false;
    this.resetProfileSelection();
  }

  private async selectXlsxSheet(index: number): Promise<void> {
    const sheet = this.xlsxSheets[index];
    if (sheet === undefined || this.xlsxUri.length === 0 || this.importBusy) { return; }
    this.importBusy = true;
    try {
      const host = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const rawRows = await readXlsxRows(this.xlsxUri, host.cacheDir, sheet.path);
      const headerIndex = detectHeaderRowIndex(rawRows);
      this.xlsxSheetPath = sheet.path;
      this.importText = '';
      this.resetProfileSelection();
      this.applyImportRows(rawRows, headerIndex, ',');
      this.importMessage = `已读取工作表“${sheet.name}”，请检查表头和字段映射`;
    } catch (_) {
      this.importMessage = `工作表“${sheet.name}”无法读取`;
      this.importError = true;
    } finally { this.importBusy = false; }
  }

  private sheetOptions(): SelectOption[] {
    const values: SelectOption[] = [];
    for (const sheet of this.xlsxSheets) { values.push({ value: sheet.name }); }
    return values;
  }

  private selectedSheetIndex(): number {
    return Math.max(0, this.xlsxSheets.findIndex((sheet: XlsxSheetInfo) => sheet.path === this.xlsxSheetPath));
  }

  private rawCell(row: CsvPreviewRow, column: number): string {
    return column >= 0 ? (row.raw[column] || '').trim() || '空' : '未映射';
  }

  private rawPreview(row: CsvPreviewRow): string {
    return `日期 ${this.rawCell(row, this.importMapping.date)}；类型 ${this.rawCell(row, this.importMapping.type)}；` +
      `金额 ${this.rawCell(row, this.importMapping.amount)}；转账金额 ${this.rawCell(row, this.importMapping.transferAmount)}；` +
      `分类 ${this.rawCell(row, this.importMapping.category)}；` +
      `转出 ${this.rawCell(row, this.importMapping.account)}；转入 ${this.rawCell(row, this.importMapping.toAccount)}；` +
      `用途 ${this.rawCell(row, this.importMapping.purpose)}；状态 ${this.rawCell(row, this.importMapping.status)}`;
  }

  private mappedPreview(row: CsvPreviewRow): string {
    const kind = row.type === 'income' ? '收入' : row.type === 'expense' ? '支出' :
      row.type === 'transfer' ? '转账' : row.type === 'refund' ? '退款' : row.type === 'reimbursement' ? '报销到账' : '类型未识别';
    const date = row.date.length > 0 ? row.date + (row.timeKnown ? ' ' + row.time : '') : '日期无效';
    if (row.type === 'refund' || row.type === 'reimbursement') {
      return `映射 ${date}；${kind}；${row.amount}；关联支出 ${row.originalEntryId || '未填写'}；到账 ${row.accountName || '不使用账户'}`;
    }
    if (row.type === 'transfer') {
      const from = row.createAccount ? `新建 ${row.accountName}` : this.accountName(row.accountId);
      const to = row.createToAccount === true ? `新建 ${row.toAccountName || ''}` :
        this.accountName(row.toAccountId || '');
      return `映射 ${date}；${transferPurposeLabel(row.transferPurpose || 'transfer')}；` +
        `${row.amount || '金额无效'}；${from} → ${to}；` +
        `手续费 ${row.transferFee || '0.00'}；优惠 ${row.transferCoupon || '0.00'}`;
    }
    const category = row.createCategory ? `新建 ${row.categoryName}` :
      row.categoryName || this.categoryName(row.categoryId);
    const account = row.createAccount ? `新建 ${row.accountName}` : row.accountId.length > 0 ?
      this.accountName(row.accountId) : '不使用账户';
    return `映射 ${date}；${kind}；${row.amount || '金额无效'}；${category}；${account}；` +
      `状态 ${row.sourceStatus || '未映射'}`;
  }

  private async confirmImportCsv(): Promise<void> {
    if (this.importBusy || this.workspace === undefined || this.snapshot === undefined ||
      this.importPreview.filter((row: CsvPreviewRow) => row.valid && row.selected).length === 0) { return; }
    this.importBusy = true;
    this.importCompleted = 0;
    this.importTotal = this.importPreview.filter((row: CsvPreviewRow) => row.valid && row.selected).length;
    const skippedCount = this.importPreview.length - this.importTotal;
    const duplicateCount = this.importPreview.filter((row: CsvPreviewRow) => row.duplicate).length;
    const applyBalance = this.importApplyBalance;
    this.importMessage = '';
    this.importError = false;
    try {
      const sheetName = this.xlsxSheets[this.selectedSheetIndex()]?.name || '';
      const metadata: CsvImportMetadata = {
        headerRow: this.importHeaderIndex + 1,
        sheetName: sheetName,
        sourceKind: this.importSourceLabel(),
        encoding: this.importText.length > 0 ? 'auto' : 'xlsx',
        profileSnapshot: JSON.stringify({ source: this.importSourceLabel(), version: 1,
          headerRow: this.importHeaderIndex + 1, delimiter: this.importDelimiter,
          mapping: this.importMapping, createMissingCategories: this.createMissingCategories,
          createMissingAccounts: this.createMissingAccounts, feeInBudget: this.importFeeInBudget }),
        feeInBudget: this.importFeeInBudget
      };
      const count = await this.workspace.importCsvBatch(this.importFileName, this.importSha256,
        this.importPreview, this.importDelimiter, this.importApplyBalance, (completed: number, total: number) => {
          this.importCompleted = completed;
          this.importTotal = total;
        }, metadata);
      this.clearImport();
      this.importMessage = `已导入 ${count} 笔，跳过 ${skippedCount} 笔` +
        (duplicateCount > 0 ? `（重复 ${duplicateCount} 笔）` : '') + '；' +
        (applyBalance ? '账户余额已按记录更新' : '当前账户余额未改变');
      await this.onImported();
      await this.load();
      await this.refreshImportHistory();
    } catch (error) {
      const code = (error as Error).message;
      this.importMessage = code.includes('RECOVERY_') || code.includes('ACCOUNT_UNAVAILABLE') ? recoveryError(error as Error) : code.startsWith('CSV_CATEGORY_INVALID') ? '导入未完成：分类与收支类型不匹配' :
        code === 'CSV_ACCOUNT_INVALID' ? '导入未完成：账户不可用' :
        code === 'CSV_TRANSFER_ACCOUNT_INVALID' ? '导入未完成：转账的转出、转入账户无效' :
        code === 'CSV_TRANSFER_REPAYMENT_ACCOUNT_INVALID' ? '导入未完成：还款的转入账户必须是负债账户' :
        code === 'IMPORT_BOOK_CURRENCY_MISMATCH' ? '文件中的账本币种与当前账本不同，请切换到相同币种的账本后导入' :
        code === 'CSV_NO_VALID_ROWS' ? '没有可导入的有效行' :
        `导入未完成，账目未写入（${code || '未知错误'}）`;
      this.importError = true;
    } finally { this.importBusy = false; }
  }

  private categoryName(id: string): string {
    if (id.length === 0) { return '—'; }
    return this.snapshot?.categories.find((item) => item.id === id)?.name ||
      this.snapshot?.incomeCategories.find((item) => item.id === id)?.name || '未匹配';
  }

  private togglePreviewSelection(rowNumber: number): void {
    this.importPreview = this.importPreview.map((row: CsvPreviewRow) => {
      if (row.rowNumber !== rowNumber || !row.valid) { return row; }
      return { rowNumber: row.rowNumber, raw: row.raw, date: row.date, time: row.time, timeKnown: row.timeKnown,
        type: row.type, amount: row.amount, categoryId: row.categoryId, categoryName: row.categoryName,
        createCategory: row.createCategory, accountId: row.accountId, accountName: row.accountName,
        createAccount: row.createAccount, toAccountId: row.toAccountId, toAccountName: row.toAccountName,
        createToAccount: row.createToAccount, transferPurpose: row.transferPurpose,
        transferFee: row.transferFee, transferCoupon: row.transferCoupon, feeInBudget: row.feeInBudget,
        sourceId: row.sourceId, duplicate: row.duplicate,
        duplicateReason: row.duplicateReason, selected: !row.selected, merchant: row.merchant,
        address: row.address, location: row.location, includeInBudget: row.includeInBudget, spendingNatureId: row.spendingNatureId, originalEntryId: row.originalEntryId, reimbursementPending: row.reimbursementPending, sourceStatus: row.sourceStatus, note: row.note,
        valid: row.valid, issues: row.issues };
    });
  }

  private accountName(id: string): string {
    if (id.length === 0) { return '不使用账户'; }
    return this.snapshot?.accounts.find((item) => item.id === id)?.name || '未匹配';
  }

  @Builder
  private mappingRow(label: string, field: string, selected: number) {
    Row({ space: 12 }) {
      Text(label).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).width(72)
      Select(this.mappingOptions()).selected(selected + 1).value(this.mappingLabel(selected))
        .font({ size: '13fp' }).fontColor($r('app.color.xq_font_primary'))
        .optionFontColor($r('app.color.xq_font_primary'))
        .selectedOptionFontColor($r('app.color.xq_font_emphasize'))
        .selectedOptionBgColor($r('app.color.xq_comp_emphasize_tertiary'))
        .backgroundColor($r('app.color.xq_app_surface_page')).height(40).layoutWeight(1)
        .id('csv-map-' + field).onSelect((index: number) => { this.updateMapping(field, index); })
    }.width('100%')
  }

  @Builder
  private importSection() {
    Column({ space: 16 }) {
      Column({ space: 10 }) {
        Text('导入账目').fontSize('20fp').fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.xq_font_primary')).width('100%')
        Text('默认只补历史账目，不改变当前账户余额。未匹配分类归入“其它”；未匹配账户按不使用账户导入。')
          .fontSize('12fp').lineHeight('18fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
        Row({ space: 10 }) {
          Button(this.importBusy ? '正在读取' : '选择 CSV', { type: ButtonType.Capsule }).layoutWeight(1).height(46)
            .fontSize('14fp').fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_page'))
            .enabled(!this.loading && !this.busy && !this.importBusy)
            .id('data-import-csv').onClick(() => { this.chooseImportCsv(); })
          Button(this.importBusy ? '正在读取' : '选择 Excel', { type: ButtonType.Capsule }).layoutWeight(1).height(46)
            .fontSize('14fp').fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_page'))
            .enabled(!this.loading && !this.busy && !this.importBusy)
            .id('data-import-xlsx').onClick(() => { this.chooseImportXlsx(); })
        }.width('100%')
      }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      if (this.importHeaders.length > 0) {
        Column({ space: 10 }) {
          Row() {
            Text('字段映射').fontSize('16fp').fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.xq_font_primary'))
            Blank()
            Text(this.importSourceLabel()).fontSize('12fp').fontColor($r('app.color.xq_font_emphasize'))
              .margin({ right: 8 })
            Text(this.importFileName).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '52%' })
          }.width('100%')
          if (this.xlsxSheets.length > 1) {
            Row({ space: 12 }) {
              Text('工作表').fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
              Blank()
              Select(this.sheetOptions()).selected(this.selectedSheetIndex())
                .value(this.xlsxSheets[this.selectedSheetIndex()]?.name || '工作表')
                .font({ size: '13fp' }).fontColor($r('app.color.xq_font_primary'))
                .optionFontColor($r('app.color.xq_font_primary'))
                .backgroundColor($r('app.color.xq_app_surface_page')).height(40)
                .id('data-import-sheet')
                .onSelect((index: number) => { this.selectXlsxSheet(index); })
            }.width('100%')
          }
          Row({ space: 12 }) {
            Text('表头行').fontSize('14fp').fontColor($r('app.color.xq_font_primary')).width(64)
            Select(this.headerRowOptions()).selected(this.importHeaderIndex).value(this.headerRowLabel(this.importHeaderIndex))
              .font({ size: '13fp' }).fontColor($r('app.color.xq_font_primary'))
              .optionFontColor($r('app.color.xq_font_primary'))
              .selectedOptionFontColor($r('app.color.xq_font_emphasize'))
              .backgroundColor($r('app.color.xq_app_surface_page')).height(40).layoutWeight(1)
              .id('data-import-header-row').onSelect((index: number) => { this.selectHeaderRow(index); })
          }.width('100%')
          if (this.importText.length > 0) {
            Row({ space: 12 }) {
              Text('分隔符').fontSize('14fp').fontColor($r('app.color.xq_font_primary')).width(64)
              Select(this.delimiterOptions()).selected(this.selectedDelimiterIndex())
                .value(this.delimiterLabel(this.importDelimiter))
                .font({ size: '13fp' }).fontColor($r('app.color.xq_font_primary'))
                .optionFontColor($r('app.color.xq_font_primary'))
                .selectedOptionFontColor($r('app.color.xq_font_emphasize'))
                .backgroundColor($r('app.color.xq_app_surface_page')).height(40).layoutWeight(1)
                .id('data-import-delimiter').onSelect((index: number) => { this.selectDelimiter(index); })
            }.width('100%')
          }
          Column({ space: 8 }) {
            Row({ space: 10 }) {
              Select(this.importProfileOptions()).selected(this.selectedImportProfileIndex())
                .value(this.selectedImportProfileId.length > 0 ? this.importProfileName : '选择已保存模板')
                .font({ size: '13fp' }).fontColor($r('app.color.xq_font_primary'))
                .optionFontColor($r('app.color.xq_font_primary'))
                .selectedOptionFontColor($r('app.color.xq_font_emphasize'))
                .backgroundColor($r('app.color.xq_app_surface_page')).height(40).layoutWeight(1)
                .id('data-import-profile').onSelect((index: number) => { this.applyImportProfile(index); })
              TextInput({ text: this.importProfileName, placeholder: '模板名称' })
                .fontSize('13fp').fontColor($r('app.color.xq_font_primary'))
                .backgroundColor($r('app.color.xq_app_surface_page')).height(40).layoutWeight(1)
                .id('data-import-profile-name')
                .onChange((value: string) => { this.importProfileName = value; })
            }.width('100%')
            Row({ space: 10 }) {
              Button(this.selectedImportProfileId.length > 0 ? '更新模板' : '保存模板',
                { type: ButtonType.Capsule }).layoutWeight(1).height(36).fontSize('12fp')
                .fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_page'))
                .enabled(this.importProfileName.trim().length > 0 &&
                  this.importMapping.date >= 0 && this.importMapping.amount >= 0)
                .id('data-import-profile-save').onClick(() => { this.saveImportProfile(); })
              if (this.selectedImportProfileId.length > 0) {
                Button('删除模板', { type: ButtonType.Capsule }).layoutWeight(1).height(36).fontSize('12fp')
                  .fontColor($r('app.color.xq_warning')).backgroundColor($r('app.color.xq_app_surface_page'))
                  .id('data-import-profile-delete').onClick(() => { this.deleteImportProfile(); })
              }
            }.width('100%')
          }.padding(10).width('100%').borderRadius(12).backgroundColor($r('app.color.xq_app_surface_page'))
          this.mappingRow('日期', 'date', this.importMapping.date)
          this.mappingRow('时间', 'time', this.importMapping.time)
          this.mappingRow('类型', 'type', this.importMapping.type)
          this.mappingRow('金额', 'amount', this.importMapping.amount)
          this.mappingRow('转账金额', 'transferAmount', this.importMapping.transferAmount)
          this.mappingRow('分类', 'category', this.importMapping.category)
          this.mappingRow('账户', 'account', this.importMapping.account)
          this.mappingRow('转入账户', 'toAccount', this.importMapping.toAccount)
          this.mappingRow('转账用途', 'purpose', this.importMapping.purpose)
          this.mappingRow('手续费', 'fee', this.importMapping.fee)
          this.mappingRow('转账优惠', 'coupon', this.importMapping.coupon)
          this.mappingRow('费入预算', 'feeBudget', this.importMapping.feeBudget)
          this.mappingRow('备注', 'note', this.importMapping.note)
          this.mappingRow('来源编号', 'sourceId', this.importMapping.sourceId)
          this.mappingRow('商户', 'merchant', this.importMapping.merchant)
          this.mappingRow('地址', 'address', this.importMapping.address)
          this.mappingRow('纬度', 'latitude', this.importMapping.latitude ?? -1)
          this.mappingRow('经度', 'longitude', this.importMapping.longitude ?? -1)
          Text('经纬度使用十进制度数，须同时填写或同时留空；没有坐标也可导入地址文字。')
            .fontSize('12fp').lineHeight('18fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
          this.mappingRow('计入预算', 'includeInBudget', this.importMapping.includeInBudget ?? -1)
          this.mappingRow('预算分类', 'spendingNature', this.importMapping.spendingNature ?? -1)
          this.mappingRow('预算分类颜色', 'spendingNatureColor', this.importMapping.spendingNatureColor ?? -1)
          this.mappingRow('关联支出ID', 'originalEntryId', this.importMapping.originalEntryId ?? -1)
          this.mappingRow('待报销', 'reimbursementPending', this.importMapping.reimbursementPending ?? -1)
          Text('报销、退款按正数金额导入，必须关联原支出；按到账日期冲减支出。找不到关联记录时整批不写入。').fontSize('12fp').width('100%')
          this.mappingRow('交易状态', 'status', this.importMapping.status)
          Text('分类和账户默认使用兜底或不使用账户；需要保留原始名称时可开启自动创建。')
            .fontSize('12fp').lineHeight('18fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
          Row() {
            Column({ space: 3 }) {
              Text('自动创建缺失分类').fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
              Text(this.createMissingCategories ? '未匹配分类会按文件原名称创建' : '未匹配分类归入“其它/其他”')
                .fontSize('11fp').fontColor($r('app.color.xq_font_secondary'))
            }.alignItems(HorizontalAlign.Start)
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.createMissingCategories })
              .selectedColor($r('app.color.xq_brand')).id('csv-create-categories')
              .onChange((value: boolean) => { this.createMissingCategories = value; this.refreshImportPreview(); })
          }.width('100%')
          Row() {
            Column({ space: 3 }) {
              Text('自动创建缺失账户').fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
              Text(this.createMissingAccounts ? '未匹配账户会按名称创建' : '未匹配账户按不使用账户导入')
                .fontSize('11fp').fontColor($r('app.color.xq_font_secondary'))
            }.alignItems(HorizontalAlign.Start)
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.createMissingAccounts })
              .selectedColor($r('app.color.xq_brand')).id('csv-create-accounts')
              .onChange((value: boolean) => { this.createMissingAccounts = value; this.refreshImportPreview(); })
          }.width('100%')
          Row() {
            Column({ space: 3 }) {
              Text('按记录更新余额').fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
              Text(this.importApplyBalance ? '提交后将改变所选账户余额' : '默认只补账目，不改变当前余额')
                .fontSize('11fp').fontColor(this.importApplyBalance ?
                  $r('app.color.xq_warning') : $r('app.color.xq_font_secondary'))
            }.alignItems(HorizontalAlign.Start)
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.importApplyBalance })
              .selectedColor($r('app.color.xq_warning')).id('csv-apply-balance')
              .onChange((value: boolean) => { this.importApplyBalance = value; })
          }.width('100%')
          Row() {
            Column({ space: 3 }) {
              Text('转账手续费计入预算').fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
              Text(this.importFeeInBudget ? '手续费会进入预算统计' : '手续费仍计入支出，但不占用预算')
                .fontSize('11fp').fontColor($r('app.color.xq_font_secondary'))
            }.alignItems(HorizontalAlign.Start)
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.importFeeInBudget })
              .selectedColor($r('app.color.xq_brand')).id('csv-fee-in-budget')
              .onChange((value: boolean) => { this.importFeeInBudget = value; this.refreshImportPreview(); })
          }.width('100%')
        }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
        Row() {
          Text(`已选择 ${this.importCounts().validSelected} 笔`).fontSize('14fp')
            .fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_confirm'))
          Blank()
          Text(`问题 ${this.importCounts().issues} 笔 · 重复 ${this.importCounts().duplicates} 笔`).fontSize('14fp')
            .fontColor($r('app.color.xq_warning'))
        }.width('100%')
        if (this.importCounts().newCategories > 0 || this.importCounts().newAccounts > 0) {
          Text(`将新建分类 ${this.importCounts().newCategories} 个 · 账户 ${this.importCounts().newAccounts} 个`)
            .fontSize('12fp').fontColor($r('app.color.xq_font_emphasize')).width('100%')
            .id('data-import-create-summary')
        }
        if (this.issueSummary().length > 0) {
          Text(`跳过原因：${this.issueSummary()}`).fontSize('12fp').lineHeight('18fp')
            .fontColor($r('app.color.xq_font_secondary')).width('100%')
            .id('data-import-issue-summary')
        }
        Row({ space: 8 }) {
          Button('全部', { type: ButtonType.Capsule }).height(32).fontSize('12fp')
            .fontColor(this.importPreviewMode === 0 ? Color.White : $r('app.color.xq_font_primary'))
            .backgroundColor(this.importPreviewMode === 0 ? $r('app.color.xq_brand') : $r('app.color.xq_app_surface_page'))
            .onClick(() => { this.importPreviewMode = 0; this.importPreviewLimit = 20; })
          Button(`重复 ${this.importPreview.filter((row: CsvPreviewRow) => row.duplicate).length}`,
            { type: ButtonType.Capsule }).height(32).fontSize('12fp')
            .fontColor(this.importPreviewMode === 1 ? Color.White : $r('app.color.xq_font_primary'))
            .backgroundColor(this.importPreviewMode === 1 ? $r('app.color.xq_warning') : $r('app.color.xq_app_surface_page'))
            .id('data-import-preview-duplicates')
            .onClick(() => { this.importPreviewMode = 1; this.importPreviewLimit = 20; })
          Button(`问题 ${this.importPreview.filter((row: CsvPreviewRow) => !row.valid).length}`,
            { type: ButtonType.Capsule }).height(32).fontSize('12fp')
            .fontColor(this.importPreviewMode === 2 ? Color.White : $r('app.color.xq_font_primary'))
            .backgroundColor(this.importPreviewMode === 2 ? $r('app.color.xq_warning') : $r('app.color.xq_app_surface_page'))
            .id('data-import-preview-issues')
            .onClick(() => { this.importPreviewMode = 2; this.importPreviewLimit = 20; })
        }.width('100%')
        ForEach(this.filteredImportPreview().slice(0, this.importPreviewLimit), (row: CsvPreviewRow) => {
          Column({ space: 5 }) {
            Row() {
              Text(`第 ${row.rowNumber} 行`).fontSize('13fp').fontWeight(FontWeight.Medium)
                .fontColor(row.valid ? $r('app.color.xq_font_primary') : $r('app.color.xq_warning'))
              Blank()
              Text(!row.valid ? row.issues.join('、') : row.duplicate ? row.duplicateReason : '可导入').fontSize('12fp')
                .fontColor(row.valid && !row.duplicate ? $r('app.color.xq_confirm') : $r('app.color.xq_warning'))
                .maxLines(2)
            }.width('100%')
            Text('原始：' + this.rawPreview(row)).fontSize('11fp').lineHeight('17fp')
              .fontColor($r('app.color.xq_font_tertiary')).width('100%').maxLines(4)
            Text(this.mappedPreview(row)).fontSize('11fp').lineHeight('17fp')
              .fontColor($r('app.color.xq_font_primary')).width('100%').maxLines(4)
            if (row.location !== undefined) {
              Text(`位置：纬度 ${(row.location.latitudeE6 / 1000000).toFixed(6)}，经度 ${(row.location.longitudeE6 / 1000000).toFixed(6)}`)
                .fontSize('11fp').lineHeight('17fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            }
            if (row.valid && (row.createCategory || row.createAccount || row.createToAccount === true)) {
              Text([
                row.createCategory ? `将新建分类“${row.categoryName}”` : '',
                row.createAccount ? `将新建账户“${row.accountName}”` : '',
                row.createToAccount === true ? `将新建转入账户“${row.toAccountName || ''}”` : ''
              ].filter((value: string) => value.length > 0).join('；'))
                .fontSize('11fp').fontColor($r('app.color.xq_font_emphasize')).width('100%')
            }
            if (row.duplicate) {
              Button(row.selected ? '取消导入此重复项' : '仍然导入此重复项', { type: ButtonType.Capsule })
                .height(32).fontSize('12fp').fontColor($r('app.color.xq_font_emphasize'))
                .backgroundColor($r('app.color.xq_comp_emphasize_tertiary'))
                .id('csv-duplicate-toggle-' + row.rowNumber)
                .onClick(() => { this.togglePreviewSelection(row.rowNumber); })
            }
          }.padding(12).width('100%').borderRadius(12).backgroundColor($r('app.color.xq_app_surface_card'))
        }, (row: CsvPreviewRow) => `${row.rowNumber}:${row.valid}:${row.date}:${row.amount}`)
        if (this.filteredImportPreview().length > this.importPreviewLimit) {
          Button(`再显示 50 行（剩余 ${this.filteredImportPreview().length - this.importPreviewLimit}）`,
            { type: ButtonType.Capsule }).width('100%').height(38).fontSize('13fp')
            .fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_page'))
            .id('data-import-more-preview')
            .onClick(() => { this.importPreviewLimit += 50; })
        }
        Row({ space: 12 }) {
          Button('取消导入', { type: ButtonType.Capsule }).layoutWeight(1).height(44)
            .fontColor($r('app.color.xq_font_primary')).backgroundColor($r('app.color.xq_app_surface_card'))
            .enabled(!this.importBusy).onClick(() => { this.clearImport(); })
          Button(this.importBusy ? '导入中' : '确认导入', { type: ButtonType.Capsule }).layoutWeight(1).height(44)
            .fontColor(Color.White).backgroundColor($r('app.color.xq_brand'))
            .enabled(!this.importBusy && this.importPreview.some((row: CsvPreviewRow) => row.valid && row.selected))
            .id('data-import-confirm').onClick(() => { this.confirmImportCsv(); })
        }.width('100%')
      }
      if (this.importMessage.length > 0) {
        Text(this.importMessage).fontSize('13fp').width('100%')
          .fontColor(this.importError ? $r('app.color.xq_warning') : $r('app.color.xq_confirm'))
          .id('data-import-message')
      }
      if (this.importBusy && this.importTotal > 0) {
        Column({ space: 8 }) {
          Row() {
            Text('正在写入账目').fontSize('13fp').fontColor($r('app.color.xq_font_secondary'))
            Blank()
            Text(`${this.importCompleted} / ${this.importTotal}`).fontSize('13fp')
              .fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_primary'))
              .id('data-import-progress-text')
          }.width('100%')
          Progress({ value: this.importCompleted, total: this.importTotal, type: ProgressType.Linear })
            .width('100%').height(5).color($r('app.color.xq_brand'))
            .backgroundColor($r('app.color.xq_comp_background_tertiary'))
            .id('data-import-progress')
        }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.xq_app_surface_card'))
      }
    }.width('100%')
  }

  @Builder
  private importHistorySection() {
    Column({ space: 12 }) {
      Text('导入记录').fontSize('16fp').fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.xq_font_primary')).width('100%')
      if (this.importBatches.length === 0) {
        Text('完成导入后会在这里保留批次和问题行记录。').fontSize('12fp')
          .fontColor($r('app.color.xq_font_secondary')).width('100%')
      }
      ForEach(this.importBatches, (batch: ImportBatchSummary) => {
        Column({ space: 4 }) {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 5 }) {
              Row({ space: 8 }) {
                Text(this.importFileDisplayName(batch.fileName)).fontSize('14fp').fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.xq_font_primary')).maxLines(1).layoutWeight(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.batchStatusText(batch.status)).fontSize('12fp').maxLines(1).flexShrink(0)
                  .fontColor(batch.status === 'committed' ? $r('app.color.xq_confirm') : $r('app.color.xq_warning'))
              }.width('100%')
              Text(`导入 ${batch.selectedCount} · 跳过 ${batch.skippedCount} · 问题 ${batch.issueCount}`)
                .fontSize('11fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
              if (batch.sheetName.length > 0) {
                Text(`工作表：${batch.sheetName}`).fontSize('11fp').maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontColor($r('app.color.xq_font_tertiary')).width('100%')
              }
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.width('100%').height(72).backgroundColor($r('app.color.xq_app_surface_page'))
            .id('data-import-batch-' + batch.id).onClick(() => { this.openImportBatch(batch.id); })
          if (this.selectedImportBatchId === batch.id) {
            ForEach(this.selectedBatchRows.slice(0, 50), (row: ImportBatchRowDetail) => {
              Column({ space: 3 }) {
                Row() {
                  Text(`第 ${row.rowNumber} 行`).fontSize('12fp').fontColor($r('app.color.xq_font_primary'))
                  Blank()
                  Text(row.validationStatus === 'valid' ? '可导入' : row.validationStatus === 'duplicate' ?
                    '重复' : row.validationStatus === 'invalid' ? '问题' : '待校验').fontSize('11fp')
                    .fontColor(row.validationStatus === 'valid' ? $r('app.color.xq_confirm') : $r('app.color.xq_warning'))
                }.width('100%')
                Text(row.rawPreview || '无原始内容').fontSize('11fp').lineHeight('17fp')
                  .fontColor($r('app.color.xq_font_secondary')).width('100%').maxLines(2)
                if (row.issues.length > 0) {
                  Text(row.issues.join('、')).fontSize('11fp').fontColor($r('app.color.xq_warning')).width('100%')
                }
              }.padding({ left: 10, right: 10, top: 8, bottom: 8 }).width('100%')
                .borderRadius(10).backgroundColor($r('app.color.xq_app_surface_page'))
            }, (row: ImportBatchRowDetail) => `${batch.id}:${row.rowNumber}:${row.validationStatus}`)
            if (this.selectedBatchRows.length > 50) {
              Text(`仅显示前 50 行，共 ${this.selectedBatchRows.length} 行`).fontSize('11fp')
                .fontColor($r('app.color.xq_font_tertiary')).width('100%')
            }
          }
        }.width('100%')
      }, (batch: ImportBatchSummary) => `${batch.id}:${batch.status}:${batch.issueCount}`)
    }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      .id('data-import-history')
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Column({ space: 12 }) {
            Text('导出账目').fontSize('20fp').fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.xq_font_primary')).width('100%')
            Text(`${this.dateText(this.exportStartDate)} 至 ${this.dateText(this.exportEndDate)} · ` +
              `${this.exportSnapshot?.bookName || this.snapshot?.bookName || '当前账本'}`).fontSize('14fp')
              .fontColor($r('app.color.xq_font_secondary')).width('100%')
            Row({ space: 12 }) {
              Column({ space: 6 }) {
                Text('开始日期').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
                Button(this.dateText(this.exportStartDate), { type: ButtonType.Normal }).width('100%').height(44)
                  .fontSize('16fp').fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_primary'))
                  .backgroundColor($r('app.color.xq_app_surface_page')).id('data-export-start')
                  .onClick(() => { this.pickExportDate(true); })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Column({ space: 6 }) {
                Text('结束日期').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
                Button(this.dateText(this.exportEndDate), { type: ButtonType.Normal }).width('100%').height(44)
                  .fontSize('16fp').fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_primary'))
                  .backgroundColor($r('app.color.xq_app_surface_page')).id('data-export-end')
                  .onClick(() => { this.pickExportDate(false); })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%')
            Text('起止日期均包含，可跨月选择。').fontSize('12fp')
              .fontColor($r('app.color.xq_font_tertiary')).width('100%')
            Row({ space: 8 }) {
              Button('全部', { type: ButtonType.Capsule }).height(34).fontSize('12fp')
                .fontColor(this.exportKind === 'all' ? Color.White : $r('app.color.xq_font_primary'))
                .backgroundColor(this.exportKind === 'all' ? $r('app.color.xq_brand') : $r('app.color.xq_app_surface_page'))
                .id('data-export-kind-all').onClick(() => { this.selectExportKind('all'); })
              Button('收入', { type: ButtonType.Capsule }).height(34).fontSize('12fp')
                .fontColor(this.exportKind === 'income' ? Color.White : $r('app.color.xq_font_primary'))
                .backgroundColor(this.exportKind === 'income' ? $r('app.color.xq_brand') : $r('app.color.xq_app_surface_page'))
                .id('data-export-kind-income').onClick(() => { this.selectExportKind('income'); })
              Button('支出', { type: ButtonType.Capsule }).height(34).fontSize('12fp')
                .fontColor(this.exportKind === 'expense' ? Color.White : $r('app.color.xq_font_primary'))
                .backgroundColor(this.exportKind === 'expense' ? $r('app.color.xq_brand') : $r('app.color.xq_app_surface_page'))
                .id('data-export-kind-expense').onClick(() => { this.selectExportKind('expense'); })
            }.width('100%')
            Row({ space: 12 }) {
              Text('账户').fontSize('14fp').fontColor($r('app.color.xq_font_primary')).width(48)
              Select(this.exportAccountOptions()).selected(this.selectedExportAccountIndex())
                .value(this.exportAccountName || '全部账户')
                .font({ size: '13fp' }).fontColor($r('app.color.xq_font_primary'))
                .optionFontColor($r('app.color.xq_font_primary'))
                .selectedOptionFontColor($r('app.color.xq_font_emphasize'))
                .backgroundColor($r('app.color.xq_app_surface_page')).height(40).layoutWeight(1)
                .id('data-export-account').onSelect((index: number) => { this.selectExportAccount(index); })
            }.width('100%')
            Text(this.loading ? '正在统计可导出账目…' : `共 ${this.exportSnapshot?.entries.length || 0} 笔账目`)
              .fontSize('14fp').fontColor($r('app.color.xq_font_primary')).width('100%')
            Button(this.busy ? '正在导出' : '导出 CSV', { type: ButtonType.Capsule }).width('100%').height(48)
              .fontSize('16fp').fontColor(Color.White).backgroundColor($r('app.color.xq_brand'))
              .enabled(!this.loading && !this.busy && (this.exportSnapshot?.entries.length || 0) > 0 &&
                this.selectedExportKeys.length > 0)
              .id('data-export-csv').onClick(() => { this.exportCsv(); })
            Button(this.busy ? '正在导出' : '导出 Excel', { type: ButtonType.Capsule }).width('100%').height(46)
              .fontSize('15fp').fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_page'))
              .enabled(!this.loading && !this.busy && (this.exportSnapshot?.entries.length || 0) > 0 &&
                this.selectedExportKeys.length > 0)
              .id('data-export-xlsx').onClick(() => { this.exportXlsx(); })
            Button(this.busy ? '正在导出' : `导出含图片 ZIP（${this.exportAttachmentCount()}）`,
              { type: ButtonType.Capsule }).width('100%').height(46)
              .fontSize('15fp').fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_page'))
              .enabled(!this.loading && !this.busy && this.exportAttachmentCount() > 0 &&
                this.selectedExportKeys.length > 0)
              .id('data-export-attachment-zip').onClick(() => { this.exportAttachmentZip(); })
          }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
          Column({ space: 8 }) {
            Text('导出字段').fontSize('16fp').fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.xq_font_primary')).width('100%')
            Text('可选择日期、金额、商户、地址、坐标、待报销状态及关联支出 ID 等字段。报销和退款单独导出为回款行，回导时需保留账目 ID、类型和关联支出 ID，并包含原支出或目标账本已有原支出。')
              .fontSize('13fp').lineHeight('20fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            Text('CSV 使用 UTF-8 BOM 和标准引号转义。“导出含图片 ZIP”会附带当前筛选范围的图片；完整恢复仍使用本地或 WebDAV 备份。')
              .fontSize('12fp').lineHeight('18fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(LEDGER_EXPORT_COLUMNS, (column: LedgerExportColumn) => {
                Button(column.label, { type: ButtonType.Capsule }).height(32).fontSize('12fp')
                  .fontColor(this.selectedExportKeys.includes(column.key) ?
                    Color.White : $r('app.color.xq_font_primary'))
                  .backgroundColor(this.selectedExportKeys.includes(column.key) ?
                    $r('app.color.xq_brand') : $r('app.color.xq_app_surface_page'))
                  .margin({ right: 6, bottom: 6 }).id('data-export-field-' + column.key)
                  .onClick(() => { this.toggleExportKey(column.key); })
              }, (column: LedgerExportColumn) => column.key)
            }.width('100%')
          }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
          if (this.message.length > 0) {
            Text(this.message).fontSize('13fp').width('100%')
              .fontColor(this.error ? $r('app.color.xq_warning') : $r('app.color.xq_confirm'))
              .id('data-exchange-message')
          }
          this.importSection()
          this.importHistorySection()
        }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }.id('data-exchange-scroll').width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '导入与导出' }, divider: { showType: DividerShowType.OFF },
          backIcon: { componentId: 'data-exchange-close', action: () => { if (!this.busy) { this.onClose(); } } } },
        style: {
          originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
            backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
            backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() },
        { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .id('data-exchange-page')
  }
}
