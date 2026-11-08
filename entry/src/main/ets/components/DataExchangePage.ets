import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { BackupFiles } from '../data/backup/BackupFiles';
import { exportLedgerCsv } from '../data/exchange/LedgerCsvExport';
import { LedgerXlsxExport } from '../data/exchange/LedgerXlsxExport';
import { listXlsxSheets, readXlsxTable, XlsxSheetInfo } from '../data/exchange/LedgerXlsxImport';
import { CsvColumnMapping, CsvPreviewRow, CsvTable, detectCsvMapping, parseCsv,
  previewCsv } from '../data/exchange/LedgerCsvImport';
import { LedgerSnapshot } from '../domain/model/LedgerSnapshot';

@Component
export struct DataExchangePage {
  workspace: LedgerWorkspace | undefined = undefined;
  monthKey: string = '';
  monthLabel: string = '';
  onClose: () => void = () => {};
  onImported: () => Promise<void> = async () => {};
  @State private snapshot: LedgerSnapshot | undefined = undefined;
  @State private loading: boolean = true;
  @State private busy: boolean = false;
  @State private message: string = '';
  @State private error: boolean = false;
  @State private importBusy: boolean = false;
  @State private importMessage: string = '';
  @State private importError: boolean = false;
  @State private importHeaders: string[] = [];
  @State private importRows: string[][] = [];
  @State private importPreview: CsvPreviewRow[] = [];
  @State private importMapping: CsvColumnMapping = { date: -1, time: -1, type: -1, amount: -1, category: -1,
    account: -1, note: -1, sourceId: -1, merchant: -1, address: -1 };
  @State private importFileName: string = '';
  @State private importSha256: string = '';
  @State private importDelimiter: string = ',';
  @State private createMissingCategories: boolean = true;
  @State private createMissingAccounts: boolean = true;
  @State private importCompleted: number = 0;
  @State private importTotal: number = 0;
  @State private xlsxUri: string = '';
  @State private xlsxSheets: XlsxSheetInfo[] = [];
  @State private xlsxSheetPath: string = '';
  @State private existingImportIds: string[] = [];
  @State private importApplyBalance: boolean = false;
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.load(); }

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
    }
    catch (_) { this.message = '账本暂时无法读取，请返回后重试'; this.error = true; }
    finally { this.loading = false; }
  }

  private async exportCsv(): Promise<void> {
    if (this.busy || this.snapshot === undefined || this.workspace === undefined) { return; }
    this.busy = true;
    this.message = '';
    this.error = false;
    try {
      const options = new picker.DocumentSaveOptions();
      const safeBook = (this.snapshot.bookName || '账本').replace(/[\\/:*?"<>|]/g, '_');
      options.newFileNames = [`${safeBook}-${this.monthKey}.csv`];
      const pickerInstance = new picker.DocumentViewPicker(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const destinations = await pickerInstance.save(options);
      if (destinations.length === 0) { return; }
      await BackupFiles.writeText(destinations[0], exportLedgerCsv(this.snapshot));
      this.message = `已导出 ${this.snapshot.entries.length} 笔账目`;
    } catch (_) {
      this.message = 'CSV 未能保存，请检查存储空间后重试';
      this.error = true;
    } finally { this.busy = false; }
  }

  private async exportXlsx(): Promise<void> {
    if (this.busy || this.snapshot === undefined || this.workspace === undefined) { return; }
    this.busy = true;
    this.message = '';
    this.error = false;
    try {
      const options = new picker.DocumentSaveOptions();
      const safeBook = (this.snapshot.bookName || '账本').replace(/[\\/:*?"<>|]/g, '_');
      options.newFileNames = [`${safeBook}-${this.monthKey}.xlsx`];
      const pickerInstance = new picker.DocumentViewPicker(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const destinations = await pickerInstance.save(options);
      if (destinations.length === 0) { return; }
      await LedgerXlsxExport.exportTo(destinations[0], this.snapshot,
        this.getUIContext().getHostContext() as common.Context);
      this.message = `已导出 ${this.snapshot.entries.length} 笔账目`;
    } catch (_) {
      this.message = 'Excel 文件未能保存，请检查存储空间后重试';
      this.error = true;
    } finally { this.busy = false; }
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
      const text = await BackupFiles.text(sources[0]);
      const table: CsvTable = parseCsv(text);
      const info = await BackupFiles.info(sources[0], 'import.csv');
      this.importFileName = sources[0].split('/').pop() || 'import.csv';
      this.importSha256 = info.sha256;
      this.importApplyBalance = false;
      this.importHeaders = table.headers;
      this.importRows = table.rows;
      this.importDelimiter = table.delimiter;
      this.importMapping = detectCsvMapping(table.headers);
      this.refreshImportPreview();
      this.importMessage = `已读取 ${table.rows.length} 行，请检查字段映射`;
    } catch (_) {
      this.importMessage = 'CSV 无法读取，请检查文件编码、引号和表头';
      this.importError = true;
    } finally { this.importBusy = false; }
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
      const sheets = await listXlsxSheets(sources[0]);
      const path = sheets.length > 0 ? sheets[0].path : '';
      const table = await readXlsxTable(sources[0], path);
      const info = await BackupFiles.info(sources[0], 'import.xlsx');
      this.xlsxUri = sources[0];
      this.xlsxSheets = sheets;
      this.xlsxSheetPath = path;
      this.importFileName = sources[0].split('/').pop() || 'import.xlsx';
      this.importSha256 = info.sha256;
      this.importApplyBalance = false;
      this.importHeaders = table.headers;
      this.importRows = table.rows;
      this.importDelimiter = ',';
      this.importMapping = detectCsvMapping(table.headers);
      this.refreshImportPreview();
      this.importMessage = `已读取 ${table.rows.length} 行，请检查字段映射`;
    } catch (_) {
      this.importMessage = 'Excel 文件无法读取，请检查工作簿和工作表';
      this.importError = true;
    } finally { this.importBusy = false; }
  }

  private refreshImportPreview(): void {
    if (this.snapshot === undefined || this.importHeaders.length === 0) { return; }
    this.importPreview = previewCsv({ headers: this.importHeaders, rows: this.importRows,
      delimiter: this.importDelimiter }, this.importMapping, this.snapshot,
      { createMissingCategories: this.createMissingCategories,
        createMissingAccounts: this.createMissingAccounts, existingIds: this.existingImportIds });
  }

  private mappingLabel(index: number): string {
    return index >= 0 && index < this.importHeaders.length ? this.importHeaders[index] : '不映射';
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
      category: field === 'category' ? index : this.importMapping.category,
      account: field === 'account' ? index : this.importMapping.account,
      note: field === 'note' ? index : this.importMapping.note,
      sourceId: field === 'sourceId' ? index : this.importMapping.sourceId,
      merchant: field === 'merchant' ? index : this.importMapping.merchant,
      address: field === 'address' ? index : this.importMapping.address
    };
    this.refreshImportPreview();
    this.importMessage = '';
  }

  private clearImport(): void {
    this.importHeaders = [];
    this.importRows = [];
    this.importPreview = [];
    this.importFileName = '';
    this.importSha256 = '';
    this.importMessage = '';
    this.importError = false;
    this.xlsxUri = '';
    this.xlsxSheets = [];
    this.xlsxSheetPath = '';
    this.importApplyBalance = false;
  }

  private async selectXlsxSheet(index: number): Promise<void> {
    const sheet = this.xlsxSheets[index];
    if (sheet === undefined || this.xlsxUri.length === 0 || this.importBusy) { return; }
    this.importBusy = true;
    try {
      const table = await readXlsxTable(this.xlsxUri, sheet.path);
      this.xlsxSheetPath = sheet.path;
      this.importHeaders = table.headers;
      this.importRows = table.rows;
      this.importMapping = detectCsvMapping(table.headers);
      this.refreshImportPreview();
      this.importMessage = `已读取工作表“${sheet.name}”，共 ${table.rows.length} 行`;
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

  private async confirmImportCsv(): Promise<void> {
    if (this.importBusy || this.workspace === undefined || this.snapshot === undefined ||
      this.importPreview.filter((row: CsvPreviewRow) => row.valid && row.selected).length === 0) { return; }
    this.importBusy = true;
    this.importCompleted = 0;
    this.importTotal = this.importPreview.filter((row: CsvPreviewRow) => row.valid && row.selected).length;
    const skippedCount = this.importPreview.length - this.importTotal;
    const duplicateCount = this.importPreview.filter((row: CsvPreviewRow) => row.duplicate).length;
    this.importMessage = '';
    this.importError = false;
    try {
      const count = await this.workspace.importCsvBatch(this.importFileName, this.importSha256,
        this.importPreview, this.importDelimiter, this.importApplyBalance, (completed: number, total: number) => {
          this.importCompleted = completed;
          this.importTotal = total;
        });
      this.clearImport();
      this.importMessage = `已导入 ${count} 笔，跳过 ${skippedCount} 笔` +
        (duplicateCount > 0 ? `（重复 ${duplicateCount} 笔）` : '') + '；' +
        (this.importApplyBalance ? '账户余额已按记录更新' : '当前账户余额未改变');
      await this.onImported();
      await this.load();
    } catch (error) {
      const code = (error as Error).message;
      this.importMessage = code.startsWith('CSV_CATEGORY_INVALID') ? '导入未完成：分类与收支类型不匹配' :
        code === 'CSV_ACCOUNT_INVALID' ? '导入未完成：账户不可用' :
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
        createAccount: row.createAccount, sourceId: row.sourceId, duplicate: row.duplicate,
        duplicateReason: row.duplicateReason, selected: !row.selected, merchant: row.merchant,
        address: row.address, note: row.note,
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
        Text('导入 CSV').fontSize('20fp').fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.xq_font_primary')).width('100%')
        Text('默认只补历史账目，不改变当前账户余额。日期、类型、金额和分类必须匹配；账户可选。')
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
          this.mappingRow('日期', 'date', this.importMapping.date)
          this.mappingRow('时间', 'time', this.importMapping.time)
          this.mappingRow('类型', 'type', this.importMapping.type)
          this.mappingRow('金额', 'amount', this.importMapping.amount)
          this.mappingRow('分类', 'category', this.importMapping.category)
          this.mappingRow('账户', 'account', this.importMapping.account)
          this.mappingRow('备注', 'note', this.importMapping.note)
          this.mappingRow('来源编号', 'sourceId', this.importMapping.sourceId)
          this.mappingRow('商户', 'merchant', this.importMapping.merchant)
          this.mappingRow('地址', 'address', this.importMapping.address)
          Row() {
            Text('自动创建缺失分类').fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.createMissingCategories })
              .selectedColor($r('app.color.xq_brand')).id('csv-create-categories')
              .onChange((value: boolean) => { this.createMissingCategories = value; this.refreshImportPreview(); })
          }.width('100%')
          Row() {
            Text('自动创建缺失账户').fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.createMissingAccounts })
              .selectedColor($r('app.color.xq_brand')).id('csv-create-accounts')
              .onChange((value: boolean) => { this.createMissingAccounts = value; this.refreshImportPreview(); })
          }.width('100%')
          Text('新账户默认创建为资产账户；名称包含“信用卡、花呗、借呗、贷款、待还”时按负债账户创建。')
            .fontSize('12fp').lineHeight('18fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
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
        }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
        Row() {
          Text(`已选择 ${this.importPreview.filter((row: CsvPreviewRow) => row.valid && row.selected).length} 笔`).fontSize('14fp')
            .fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_confirm'))
          Blank()
          Text(`问题 ${this.importPreview.filter((row: CsvPreviewRow) => !row.valid).length} 笔 · 重复 ${this.importPreview.filter((row: CsvPreviewRow) => row.duplicate).length} 笔`).fontSize('14fp')
            .fontColor($r('app.color.xq_warning'))
        }.width('100%')
        ForEach(this.importPreview.slice(0, 20), (row: CsvPreviewRow) => {
          Column({ space: 5 }) {
            Row() {
              Text(`第 ${row.rowNumber} 行`).fontSize('13fp').fontWeight(FontWeight.Medium)
                .fontColor(row.valid ? $r('app.color.xq_font_primary') : $r('app.color.xq_warning'))
              Blank()
              Text(!row.valid ? row.issues.join('、') : row.duplicate ? row.duplicateReason : '可导入').fontSize('12fp')
                .fontColor(row.valid && !row.duplicate ? $r('app.color.xq_confirm') : $r('app.color.xq_warning'))
                .maxLines(2)
            }.width('100%')
            if (row.valid) {
              Text(`${row.date}${row.timeKnown ? ' ' + row.time : ''} · ${row.type === 'income' ? '收入' : '支出'} · ${row.createCategory ?
                row.categoryName : this.categoryName(row.categoryId)} · ${row.createAccount ?
                row.accountName : this.accountName(row.accountId)} · ¥${row.amount}`)
                .fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
              if (row.createCategory || row.createAccount) {
                Text([
                  row.createCategory ? `将新建分类“${row.categoryName}”` : '',
                  row.createAccount ? `将新建账户“${row.accountName}”` : ''
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
            }
          }.padding(12).width('100%').borderRadius(12).backgroundColor($r('app.color.xq_app_surface_card'))
        }, (row: CsvPreviewRow) => `${row.rowNumber}:${row.valid}:${row.date}:${row.amount}`)
        if (this.importPreview.length > 20) {
          Text(`预览前 20 行，另有 ${this.importPreview.length - 20} 行将在确认时一并处理`).fontSize('12fp')
            .fontColor($r('app.color.xq_font_tertiary')).width('100%')
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

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Column({ space: 12 }) {
            Text('导出本月账目').fontSize('20fp').fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.xq_font_primary')).width('100%')
            Text(`${this.monthLabel} · ${this.snapshot?.bookName || '当前账本'}`).fontSize('14fp')
              .fontColor($r('app.color.xq_font_secondary')).width('100%')
            Text(this.loading ? '正在统计可导出账目…' : `共 ${this.snapshot?.entries.length || 0} 笔账目`)
              .fontSize('14fp').fontColor($r('app.color.xq_font_primary')).width('100%')
            Button(this.busy ? '正在导出' : '导出 CSV', { type: ButtonType.Capsule }).width('100%').height(48)
              .fontSize('16fp').fontColor(Color.White).backgroundColor($r('app.color.xq_brand'))
              .enabled(!this.loading && !this.busy && (this.snapshot?.entries.length || 0) > 0)
              .id('data-export-csv').onClick(() => { this.exportCsv(); })
            Button(this.busy ? '正在导出' : '导出 Excel', { type: ButtonType.Capsule }).width('100%').height(46)
              .fontSize('15fp').fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_page'))
              .enabled(!this.loading && !this.busy && (this.snapshot?.entries.length || 0) > 0)
              .id('data-export-xlsx').onClick(() => { this.exportXlsx(); })
          }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
          Column({ space: 8 }) {
            Text('导出字段').fontSize('16fp').fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.xq_font_primary')).width('100%')
            Text('日期、时间、类型、分类、账户、转入账户、备注、币种、原金额、优惠、实付金额、手续费、转账优惠、标签和账目 ID。')
              .fontSize('13fp').lineHeight('20fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            Text('CSV 使用 UTF-8 BOM 和标准引号转义，可直接用常见表格软件打开。完整备份与图片资源仍使用“本地备份与恢复”。')
              .fontSize('12fp').lineHeight('18fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
          }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
          if (this.message.length > 0) {
            Text(this.message).fontSize('13fp').width('100%')
              .fontColor(this.error ? $r('app.color.xq_warning') : $r('app.color.xq_confirm'))
              .id('data-exchange-message')
          }
          this.importSection()
        }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }.id('data-exchange-scroll').width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '导入与导出' }, divider: { showType: DividerShowType.OFF },
          backIcon: { componentId: 'data-exchange-close', action: () => { if (!this.busy) { this.onClose(); } } } },
        style: {
          originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
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
