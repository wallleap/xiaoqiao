import { ItemRestriction, SegmentButton, SegmentButtonOptions, SegmentButtonTextItem } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType, HdsColorPicker } from '@kit.UIDesignKit';
import { util } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { SPENDING_NATURE_COLORS, SpendingNatureProfile, isCustomNatureColor } from '../domain/model/SpendingNature';
import { spendingNatureBackground, spendingNatureText } from '../presentation/ledger/SpendingNatureStyles';

@Component
export struct SpendingNaturePage {
  workspace: LedgerWorkspace | undefined = undefined;
  sheetMaterial: SystemUiMaterial | undefined = undefined;
  @Prop @Watch('applyArchiveMaterial') segmentMaterial: SystemUiMaterial | undefined = undefined;
  onClose: () => void = () => {};
  onCreated: (id: string) => void = () => {};
  @State private values: SpendingNatureProfile[] = [];
  @State private loading: boolean = true;
  @State private showArchived: boolean = false;
  @State @Watch('archiveSelectionChanged') private archiveSelection: number[] = [0];
  @State private archiveOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '使用中' }, { text: '已归档' }] as ItemRestriction<SegmentButtonTextItem>,
    fontSize: '13fp', selectedFontSize: '13fp',
    fontColor: $r('sys.color.font_primary'), selectedFontColor: $r('app.color.xq_font_on_primary'),
    backgroundColor: Color.Transparent, selectedBackgroundColor: $r('app.color.xq_brand')
  });

  private archiveSelectionChanged(): void {
    this.showArchived = this.archiveSelection[0] === 1;
  }

  @State private showEditor: boolean = false;
  @State private editing: SpendingNatureProfile | undefined = undefined;
  @State private name: string = '';
  @State private nameFocused: boolean = false;
  @State private colorKey: string = 'neutral';
  @State private showColorPicker: boolean = false;
  @State private customColor: string = '#FF5425';
  @State private colorError: string = '';
  @State private busy: boolean = false;
  @State private error: string = '';
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.applyArchiveMaterial(); this.load(); }

  private applyArchiveMaterial(): void {
    const options = SegmentButtonOptions.tab({
      buttons: [{ text: '使用中' }, { text: '已归档' }] as ItemRestriction<SegmentButtonTextItem>,
      fontSize: '13fp', selectedFontSize: '13fp',
      fontColor: $r('sys.color.font_primary'), selectedFontColor: $r('app.color.xq_font_on_primary'),
      backgroundColor: Color.Transparent, selectedBackgroundColor: $r('app.color.xq_brand')
    });
    if (this.segmentMaterial !== undefined) { options.backgroundSystemMaterial = this.segmentMaterial; }
    this.archiveOptions = options;
  }

  @Builder
  private archiveAction() {
    Row() {
      SegmentButton({ options: this.archiveOptions, selectedIndexes: $archiveSelection })
        .width(168).constraintSize({ maxWidth: '100%' }).id('spending-nature-toggle-archive')
    }.width('100%').justifyContent(FlexAlign.End).padding({ left: 160, right: 16 })
      .hitTestBehavior(HitTestMode.Transparent)
  }

  private visible(): SpendingNatureProfile[] {
    return this.values.filter((item: SpendingNatureProfile) => item.archived === this.showArchived);
  }

  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }

  private async load(): Promise<void> {
    if (this.workspace === undefined) { this.loading = false; return; }
    this.loading = true; this.error = '';
    try { this.values = await this.workspace.spendingNatures(); }
    catch (_) { this.error = '预算分类暂时无法读取，请返回后重试'; }
    finally { this.loading = false; }
  }

  private beginCreate(): void {
    this.nameFocused = false;
    this.showColorPicker = false;
    this.editing = undefined; this.name = ''; this.colorKey = 'neutral'; this.error = ''; this.showEditor = true;
  }

  private beginEdit(item: SpendingNatureProfile): void {
    this.nameFocused = false;
    this.showColorPicker = false;
    this.editing = item; this.name = item.name; this.colorKey = item.colorKey; this.error = ''; this.showEditor = true;
  }

  private async save(): Promise<void> {
    if (this.busy || this.workspace === undefined) { return; }
    this.busy = true; this.error = '';
    try {
      if (this.editing === undefined) {
        const id = util.generateRandomUUID();
        await this.workspace.createSpendingNature({ id: id, name: this.name, colorKey: this.colorKey });
        this.onCreated(id);
      } else {
        await this.workspace.updateSpendingNature({ id: this.editing.id, name: this.name, colorKey: this.colorKey }, this.editing.revision);
      }
      this.values = await this.workspace.spendingNatures();
      this.showEditor = false;
    } catch (error) {
      const code = (error as Error).message;
      this.error = code === 'SPENDING_NATURE_NAME_EXISTS' ? '已有同名预算分类' :
        code === 'SPENDING_NATURE_CHANGED' ? '预算分类已更新，请关闭后重新打开' :
        this.name.trim().length === 0 ? '请填写名称' : '保存失败，请稍后重试';
    } finally { this.busy = false; }
  }

  private archive(item: SpendingNatureProfile): void {
    if (this.busy || this.workspace === undefined) { return; }
    const archived = !item.archived;
    this.getUIContext().getPromptAction().showDialog({
      title: archived ? '归档这个预算分类？' : '恢复这个预算分类？',
      message: archived ? '历史账目和预算继续保留该分类，新记账时不再显示。' : '恢复后可重新用于新支出和分类预算。',
      buttons: [{ text: '取消', color: $r('app.color.xq_font_primary') },
        { text: archived ? '归档' : '恢复', color: $r('app.color.xq_font_emphasize') }]
    }).then(async (result) => {
      if (result.index !== 1 || this.workspace === undefined) { return; }
      this.busy = true; this.error = '';
      try {
        await this.workspace.archiveSpendingNature(item.id, item.revision, archived);
        this.values = await this.workspace.spendingNatures();
      } catch (error) {
        this.error = (error as Error).message === 'LAST_ACTIVE_SPENDING_NATURE' ? '至少保留一个使用中的预算分类' : '无法更新状态，请重试';
      } finally { this.busy = false; }
    }).catch(() => {});
  }

  private sheetOptions(): SheetOptions {
    const options: SheetOptions = { height: 540, showClose: true };
    if (this.sheetMaterial !== undefined) { options.systemMaterial = this.sheetMaterial; }
    else { options.backgroundColor = $r('app.color.xq_app_surface_card'); }
    return options;
  }

  private moreMenuOptions(): MenuOptions {
    const options: MenuOptions = { placement: Placement.BottomRight };
    if (this.sheetMaterial !== undefined) { options.systemMaterial = this.sheetMaterial; }
    return options;
  }

  @Builder
  private natureRow(item: SpendingNatureProfile) {
    Row({ space: 12 }) {
      Column() {
        Row({ space: 12 }) {
          Text(item.name).fontSize('14fp').fontWeight(FontWeight.Regular).height(38)
            .fontColor(spendingNatureText(item.colorKey)).backgroundColor(spendingNatureBackground(item.colorKey))
            .padding({ left: 16, right: 16 }).borderRadius(19)
            .border({ width: 1.5, color: spendingNatureBackground(item.colorKey) })
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '100%' })
        }.width('100%')
      }.height(40).layoutWeight(1).justifyContent(FlexAlign.Center)
      if (item.builtIn) {
        Text('内置').fontSize('10fp').fontColor($r('app.color.xq_font_tertiary'))
          .backgroundColor($r('app.color.xq_app_surface_page')).borderRadius(4)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 }).flexShrink(0)
      }
      Row() {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.lucide_ellipsis1')).width(20).height(20).fillColor($r('app.color.xq_icon_secondary'))
        }.width(40).height(40).padding(0).backgroundColor(Color.Transparent)
          .enabled(!this.busy).id('spending-nature-more-' + item.id).accessibilityText(item.name + '的更多操作')
          .bindMenu([
            { value: '编辑', action: () => { if (!this.busy) { this.beginEdit(item); } } },
            { value: item.archived ? '恢复' : '归档', action: () => { this.archive(item); } }
          ], this.moreMenuOptions())
      }.width(40).height(40).flexShrink(0)
    }.alignItems(VerticalAlign.Center).padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      .id('spending-nature-row-' + item.id)
  }

  private nativeColorPickerAvailable(): boolean {
    return deviceInfo.sdkApiVersion >= 26 && canIUse('SystemCapability.UIDesign.HDSPattern.Standard');
  }

  private openCustomColor(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.colorError = '';
    this.customColor = isCustomNatureColor(this.colorKey) ? this.colorKey : '#FF5425';
    this.showColorPicker = true;
  }

  private normalizedPickerColor(value: string): string {
    return /^#FF[0-9a-fA-F]{6}$/i.test(value) ? '#' + value.substring(3) : value;
  }

  private acceptPickedColor(value: string): void {
    const normalized = this.normalizedPickerColor(value);
    if (!isCustomNatureColor(normalized)) { this.colorError = '请输入不透明颜色，格式为 #RRGGBB'; return; }
    this.colorKey = normalized.toUpperCase(); this.customColor = this.colorKey;
    this.showColorPicker = false;
  }

  @Builder
  private customColorPicker() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Row().width(32).height(32).borderRadius(8)
          .backgroundColor(isCustomNatureColor(this.customColor) ? this.customColor : '#FF5425')
          .border({ width: 1, color: $r('app.color.xq_comp_divider') })
        TextInput({ text: this.customColor, placeholder: '#RRGGBB' }).layoutWeight(1).height(44).maxLength(7)
          .fontSize('16fp').backgroundColor($r('app.color.xq_app_surface_page')).borderRadius(8)
          .onChange((value: string) => { this.customColor = value; this.colorError = ''; })
      }.width('100%')
      if (this.colorError.length > 0) { Text(this.colorError).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%') }
      Button('使用此颜色', { type: ButtonType.Capsule }).width('100%').height(44)
        .fontColor(Color.White).backgroundColor($r('app.color.xq_brand'))
        .onClick(() => { this.acceptPickedColor(this.customColor); })
    }.width('100%')
  }

  @Builder
  private editorSheet() {
    Column({ space: 12 }) {
      Text(this.editing === undefined ? '新增预算分类' : '编辑预算分类').fontSize('20fp').fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.xq_font_primary')).width('100%').padding({ right: 40 })
      Scroll() {
        Column({ space: 16 }) {
          Text('分类名称').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
          TextInput({ text: this.name, placeholder: '点击输入分类名称，例如：健康投入' }).width('100%').fontSize('16fp').height(52).maxLength(20)
            .fontColor($r('app.color.xq_font_primary')).placeholderFont({ size: '14fp' })
            .placeholderColor($r('app.color.xq_font_tertiary')).padding({ left: 16, right: 16 })
            .caretColor($r('app.color.xq_brand')).borderRadius(12)
            .backgroundColor($r('app.color.xq_app_surface_page'))
            .border({ width: 1, color: this.nameFocused ? $r('app.color.xq_brand') : Color.Transparent })
            .onFocus(() => { this.nameFocused = true; }).onBlur(() => { this.nameFocused = false; })
            .id('spending-nature-name').onChange((value: string) => { this.name = value; this.error = ''; })
          Text('颜色').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            if (this.nativeColorPickerAvailable()) {
              Stack({ alignContent: Alignment.Center }) {
                HdsColorPicker({ initialColor: isCustomNatureColor(this.colorKey) ? this.colorKey : this.customColor,
                  onColorSelected: (color: string) => { this.acceptPickedColor(color); } })
                  .width(24).height(24)
                  .accessibilityText('自定义颜色').id('spending-nature-custom-color')
              }.width(44).height(44).margin({ right: 8, bottom: 8 })
            } else {
              Button('+', { type: ButtonType.Circle }).width(44).height(44).padding(0)
                .fontSize('20fp').fontColor($r('app.color.xq_font_primary'))
                .margin({ right: 8, bottom: 8 }).backgroundColor($r('app.color.xq_app_surface_page'))
                .border({ width: 1, color: $r('app.color.xq_comp_divider') })
                .accessibilityText('自定义颜色').id('spending-nature-custom-color')
                .onClick(() => { if (this.showColorPicker) { this.showColorPicker = false; } else { this.openCustomColor(); } })
            }
            ForEach(SPENDING_NATURE_COLORS, (color: string) => {
              Button({ type: ButtonType.Circle }) {
                Stack() {
                  Circle().width(30).height(30).fill(spendingNatureText(color))
                  if (this.colorKey === color) {
                    Image($r('app.media.lucide_check1')).width(18).height(18).fillColor($r('app.color.xq_font_primary'))
                  }
                }.width(40).height(40).borderRadius(20)
                  .backgroundColor(this.colorKey === color ? spendingNatureBackground(color) : Color.Transparent)
              }.width(44).height(44).padding(0).margin({ right: 8, bottom: 8 }).backgroundColor(Color.Transparent)
                .accessibilityText('分类颜色' + (SPENDING_NATURE_COLORS.indexOf(color) + 1))
                .accessibilityDescription(this.colorKey === color ? '已选中' : '未选中')
                .id('spending-nature-color-' + color).onClick(() => { this.colorKey = color; })
            }, (color: string) => color)
          }.width('100%')
          if (this.showColorPicker) { this.customColorPicker() }
          if (!this.showColorPicker && this.colorError.length > 0) {
            Text(this.colorError).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%')
          }
          if (this.error.length > 0) {
            Text(this.error).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%')
          }
        }.width('100%')
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      Row({ space: 12 }) {
        Button('取消', { type: ButtonType.Capsule }).layoutWeight(1).height(44).fontSize('14fp')
          .fontColor($r('app.color.xq_font_primary')).backgroundColor($r('app.color.xq_app_surface_keyboard'))
          .enabled(!this.busy).onClick(() => { this.showEditor = false; })
        Button(this.busy ? '保存中' : '保存', { type: ButtonType.Capsule }).layoutWeight(1).height(44).fontSize('14fp')
          .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.busy)
          .id('spending-nature-save').onClick(() => { this.save(); })
      }.width('100%')
    }.padding(24).width('100%').height('100%')
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Text(this.showArchived ? '历史账目和预算会保留。' : '按支出目的分类，用于分配月度预算。')
            .fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
          if (this.loading) {
            Text('正在读取…').fontSize('14fp').padding(24)
          } else if (this.error.length > 0 && this.values.length === 0) {
            Text(this.error).fontSize('14fp').fontColor($r('app.color.xq_warning')).padding(16)
            Button('重新读取').onClick(() => { this.load(); })
          } else {
            if (this.visible().length === 0) {
              Text(this.showArchived ? '暂无归档的预算分类' : '暂无使用中的预算分类').fontSize('14fp')
                .fontColor($r('app.color.xq_font_secondary')).width('100%').padding({ top: 24, bottom: 24 })
            } else {
              Column({ space: 12 }) {
                ForEach(this.visible(), (item: SpendingNatureProfile) => {
                  this.natureRow(item)
                }, (item: SpendingNatureProfile) => item.id + ':' + item.revision)
              }.width('100%')
            }
          }
          Button('新增自定义预算分类', { type: ButtonType.Capsule }).width('100%').height(48)
            .fontSize('14fp').fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.xq_font_on_primary')).backgroundColor($r('app.color.xq_brand'))
            .enabled(!this.busy && !this.loading).id('spending-nature-create').onClick(() => { this.beginCreate(); })
        }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }.id('spending-nature-scroll').width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '预算分类' }, stackBuilder: this.archiveAction.bind(this), divider: { showType: DividerShowType.OFF },
          backIcon: { componentId: 'spending-nature-close', action: () => { if (!this.busy) { this.onClose(); } } } },
        style: {
          originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
            backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
            backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showEditor, this.editorSheet(), this.sheetOptions()).id('spending-nature-page')
  }
}
