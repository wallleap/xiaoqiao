import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { BackupFiles } from '../data/backup/BackupFiles';
import { exportLedgerCsv } from '../data/exchange/LedgerCsvExport';
import { LedgerSnapshot } from '../domain/model/LedgerSnapshot';

@Component
export struct DataExchangePage {
  workspace: LedgerWorkspace | undefined = undefined;
  monthKey: string = '';
  monthLabel: string = '';
  onClose: () => void = () => {};
  @State private snapshot: LedgerSnapshot | undefined = undefined;
  @State private loading: boolean = true;
  @State private busy: boolean = false;
  @State private message: string = '';
  @State private error: boolean = false;
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
    try { this.snapshot = await this.workspace.snapshot(this.monthKey); }
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
        }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
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
