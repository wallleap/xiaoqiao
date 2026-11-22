import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { DEFAULT_TRANSACTION_COLORS, TransactionColors, TransactionColorKind, TransactionColorOption } from '../presentation/ledger/TransactionColors';

@Component
export struct TransactionColorsPage {
  workspace: LedgerWorkspace | undefined = undefined;
  onClose: () => void = () => {};
  onSaving: (saving: boolean) => void = () => {};
  @StorageProp('transactionColorSelection') private selection: string = DEFAULT_TRANSACTION_COLORS;
  @State private saving: boolean = false;
  @State private error: string = '';
  private readonly scroller: Scroller = new Scroller();

  private async save(json: string): Promise<void> {
    if (this.saving || this.workspace === undefined || json === this.selection) { return; }
    this.saving = true; this.onSaving(true); this.error = '';
    try { await this.workspace.saveTransactionColors(json); }
    catch (_) { this.error = '颜色未保存，请重新选择后再试'; }
    finally { this.saving = false; this.onSaving(false); }
  }
  private choose(kind: TransactionColorKind, id: string): void {
    if (TransactionColors.disabled(kind,id,this.selection)) { return; }
    this.save(TransactionColors.change(this.selection,kind,id));
  }
  private selected(kind: TransactionColorKind, id: string): boolean { return TransactionColors.selected(kind,this.selection) === id; }
  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8,'0');
  }
  @Builder
  private previewRow(kind: TransactionColorKind, label: string, amount: string) {
    Row({ space: 12 }) {
      Circle().width(8).height(8).fill(TransactionColors.color(kind,this.selection))
      Text(label).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).layoutWeight(1)
      Text(amount).fontSize('20fp').fontFamily('XiaoQiaoDINMedium').fontColor(TransactionColors.color(kind,this.selection))
    }.width('100%').constraintSize({ minHeight: 44 })
  }
  @Builder
  private colorOption(kind: TransactionColorKind, option: TransactionColorOption) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        Stack() {
          Circle().width(28).height(28).fill(TransactionColors.swatch(option.id))
          if (this.selected(kind,option.id)) {
            Circle().width(36).height(36).fill(Color.Transparent).stroke($r('app.color.xq_font_emphasize')).strokeWidth(2)
          }
          if (TransactionColors.disabled(kind,option.id,this.selection)) {
            Image($r('app.media.lucide_lock1')).width(14).height(14).fillColor($r('app.color.xq_app_surface_card'))
          }
        }.height(38).width(40)
        Text(option.name).fontSize('12fp').fontColor($r('app.color.xq_font_primary'))
      }.width('100%')
    }.width(64).height(76).padding(4).borderRadius(12)
      .backgroundColor(Color.Transparent).fontColor($r('app.color.xq_font_primary'))
      .enabled(!this.saving && this.workspace !== undefined && !TransactionColors.disabled(kind,option.id,this.selection))
      .opacity(TransactionColors.disabled(kind,option.id,this.selection) ? 0.35 : 1)
      .accessibilityText(option.name + (this.selected(kind,option.id) ? '，已选中' : TransactionColors.disabled(kind,option.id,this.selection) ? '，另一收支类型已使用，不可选' : ''))
      .onClick(() => { this.choose(kind,option.id); }).id('transaction-color-' + kind + '-' + option.id)
  }
  @Builder
  private section(kind: TransactionColorKind, title: string) {
    Column({ space: 12 }) {
      Text(title).fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(TransactionColors.options(kind), (option: TransactionColorOption) => { this.colorOption(kind,option) }, (option: TransactionColorOption) => option.id)
      }.width('100%')
    }.width('100%').padding(16).borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
  }
  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Column({ space: 4 }) {
            Text('效果预览').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%').margin({ bottom: 8 })
            this.previewRow('expense','支出','− ¥128.00')
            this.previewRow('income','收入','+ ¥3,600.00')
            this.previewRow('transfer','转账','¥500.00')
          }.width('100%').padding(16).borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
          this.section('expense','支出颜色')
          this.section('income','收入颜色')
          this.section('transfer','转账颜色')
          Text('红色、绿色不能同时用于支出和收入，已使用的颜色会在另一项禁用。黑色可共用，深色模式下随主题适配。')
            .fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%').padding({ left: 8, right: 8 })
          if (this.error.length > 0) { Text(this.error).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%') }
          Button('恢复默认', { type: ButtonType.Capsule }).height(40).fontSize('14fp').fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_card'))
            .enabled(!this.saving && this.workspace !== undefined).onClick(() => { this.save(DEFAULT_TRANSACTION_COLORS); }).id('transaction-colors-reset')
        }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '收支转账颜色' }, divider: { showType: DividerShowType.OFF }, backIcon: { action: () => { if (!this.saving) { this.onClose(); } } } },
        style: {
          originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]).id('transaction-colors-page')
  }
}
