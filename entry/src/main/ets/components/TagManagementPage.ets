import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType, HdsColorPicker } from '@kit.UIDesignKit';
import { util } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { TAG_COLORS, TagProfile, isCustomTagColor } from '../domain/model/TagProfile';
import { tagBackground, tagTextColor } from '../presentation/ledger/TagStyles';

@Component
export struct TagManagementPage {
  workspace: LedgerWorkspace | undefined = undefined;
  sheetMaterial: SystemUiMaterial | undefined = undefined;
  onClose: () => void = () => {};
  onCreated: (id: string) => void = () => {};
  @State private values: TagProfile[] = [];
  @State private loading: boolean = true;
  @State private showEditor: boolean = false;
  @State private editing: TagProfile | undefined = undefined;
  @State private name: string = '';
  @State private nameFocused: boolean = false;
  @State private colorKey: string = 'brand';
  @State private busy: boolean = false;
  @State private error: string = '';
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
    this.error = '';
    try { this.values = await this.workspace.tags(); }
    catch (_) { this.error = '标签暂时无法读取，请返回后重试'; }
    finally { this.loading = false; }
  }

  private beginCreate(): void {
    this.editing = undefined;
    this.name = '';
    this.colorKey = 'brand';
    this.error = '';
    this.nameFocused = false;
    this.showEditor = true;
  }

  private beginEdit(item: TagProfile): void {
    this.editing = item;
    this.name = item.name;
    this.colorKey = item.colorKey;
    this.error = '';
    this.nameFocused = false;
    this.showEditor = true;
  }

  private async save(): Promise<void> {
    if (this.busy || this.workspace === undefined) { return; }
    this.busy = true;
    this.error = '';
    try {
      if (this.editing === undefined) {
        const id = util.generateRandomUUID();
        await this.workspace.createTag({ id: id, name: this.name, colorKey: this.colorKey });
        this.onCreated(id);
      } else {
        await this.workspace.updateTag({ id: this.editing.id, name: this.name, colorKey: this.colorKey }, this.editing.revision);
      }
      this.values = await this.workspace.tags();
      this.showEditor = false;
    } catch (error) {
      const code = (error as Error).message;
      this.error = code === 'TAG_NAME_EXISTS' ? '已有同名标签' :
        code === 'TAG_CHANGED' ? '标签已更新，请关闭后重新打开' :
        this.name.trim().length === 0 ? '请填写标签名称' : '保存失败，请稍后重试';
    } finally { this.busy = false; }
  }

  private remove(item: TagProfile): void {
    if (this.busy || this.workspace === undefined) { return; }
    this.getUIContext().getPromptAction().showDialog({
      title: '删除这个标签？',
      message: `历史账目中的“${item.name}”标签会保留显示，但新记账时不再可选。标签删除后不能恢复。`,
      buttons: [{ text: '取消', color: $r('app.color.xq_font_secondary') },
        { text: '删除', color: $r('app.color.xq_warning') }]
    }).then(async (result) => {
      if (result.index !== 1 || this.workspace === undefined) { return; }
      this.busy = true;
      this.error = '';
      try {
        await this.workspace.deleteTag(item.id, item.revision);
        this.values = await this.workspace.tags();
      } catch (_) { this.error = '标签已变更或暂时无法删除，请刷新后重试'; }
      finally { this.busy = false; }
    }).catch(() => {});
  }

  private sheetOptions(): SheetOptions {
    const options: SheetOptions = { height: 440, showClose: true };
    if (this.sheetMaterial !== undefined) { options.systemMaterial = this.sheetMaterial; }
    else { options.backgroundColor = $r('app.color.xq_app_surface_card'); }
    return options;
  }

  private nativeColorPickerAvailable(): boolean {
    return deviceInfo.sdkApiVersion >= 26 && canIUse('SystemCapability.UIDesign.HDSPattern.Standard');
  }

  private acceptPickedColor(value: string): void {
    const normalized = /^#FF[0-9a-fA-F]{6}$/i.test(value) ? '#' + value.substring(3) : value;
    if (!isCustomTagColor(normalized)) { this.error = '请选择不透明颜色，格式为 #RRGGBB'; return; }
    this.colorKey = normalized.toUpperCase();
    this.error = '';
  }

  @Builder
  private editorSheet() {
    Column({ space: 16 }) {
      Text(this.editing === undefined ? '新增标签' : '编辑标签').fontSize('20fp').fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.xq_font_primary')).width('100%').padding({ right: 40 })
      Text('标签名称').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      TextInput({ text: this.name, placeholder: '点击输入标签名称，例如：旅行' }).width('100%').fontSize('16fp').height(52).maxLength(20)
        .fontColor($r('app.color.xq_font_primary')).placeholderFont({ size: '14fp' })
        .placeholderColor($r('app.color.xq_font_tertiary')).padding({ left: 16, right: 16 })
        .caretColor($r('app.color.xq_brand')).borderRadius(12).backgroundColor($r('app.color.xq_app_surface_page'))
        .border({ width: 1, color: this.nameFocused ? $r('app.color.xq_brand') : Color.Transparent })
        .onFocus(() => { this.nameFocused = true; }).onBlur(() => { this.nameFocused = false; })
        .id('tag-name').onChange((value: string) => { this.name = value; this.error = ''; })
      Text('颜色').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        if (this.nativeColorPickerAvailable()) {
          Stack({ alignContent: Alignment.Center }) {
            HdsColorPicker({ initialColor: isCustomTagColor(this.colorKey) ? this.colorKey : '#FF5425',
              onColorSelected: (color: string) => { this.acceptPickedColor(color); } })
              .width(24).height(24).accessibilityText('自定义标签颜色').id('tag-custom-color')
          }.width(44).height(44).margin({ right: 8, bottom: 8 })
        }
        ForEach(TAG_COLORS, (color: string) => {
          Button({ type: ButtonType.Circle }) {
            Stack() {
              Circle().width(24).height(24).fill(tagTextColor(color))
              if (this.colorKey === color) {
                Image($r('app.media.lucide_check1')).width(16).height(16).fillColor($r('app.color.xq_font_primary'))
              }
            }.width(36).height(36).borderRadius(18)
              .backgroundColor(this.colorKey === color ? tagBackground(color) : Color.Transparent)
          }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
            .margin({ right: 8, bottom: 8 }).id('tag-color-' + color)
            .accessibilityText('标签颜色' + (TAG_COLORS.indexOf(color) + 1))
            .accessibilityDescription(this.colorKey === color ? '已选中' : '未选中')
            .onClick(() => { this.colorKey = color; })
        }, (color: string) => color)
      }.width('100%')
      if (!this.nativeColorPickerAvailable()) {
        TextInput({ text: isCustomTagColor(this.colorKey) ? this.colorKey : '', placeholder: '自定义颜色：#RRGGBB' })
          .width('100%').height(44).maxLength(7).fontSize('14fp').borderRadius(12)
          .backgroundColor($r('app.color.xq_app_surface_page'))
          .onChange((value: string) => { if (isCustomTagColor(value)) { this.acceptPickedColor(value); } })
      }
      if (this.error.length > 0) {
        Text(this.error).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%')
      }
      Row({ space: 12 }) {
        Button('取消', { type: ButtonType.Capsule }).layoutWeight(1).height(44)
          .fontColor($r('app.color.xq_font_primary')).backgroundColor($r('app.color.xq_app_surface_keyboard'))
          .enabled(!this.busy).onClick(() => { this.showEditor = false; })
        Button(this.busy ? '保存中' : '保存', { type: ButtonType.Capsule }).layoutWeight(1).height(44)
          .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.busy)
          .id('tag-save').onClick(() => { this.save(); })
      }.width('100%')
    }.padding(24).width('100%').height('100%')
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Text('为账目添加补充标记，可选择多个。').fontSize('12fp')
            .fontColor($r('app.color.xq_font_secondary')).width('100%')
          Row() {
            Text('我的标签').fontSize('16fp').fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.xq_font_primary'))
            Text(`${this.values.length} 个`).fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')).margin({ left: 8 })
            Blank()
            if (this.values.length > 0) {
              Button('＋ 新增标签').height(40).padding({ left: 8, right: 0 }).fontSize('14fp')
                .fontColor($r('app.color.xq_font_emphasize')).backgroundColor(Color.Transparent).enabled(!this.busy)
                .id('tag-create').onClick(() => { this.beginCreate(); })
            }
          }.width('100%')
          if (this.loading) {
            Text('正在读取…').fontSize('14fp').padding(24)
          } else if (this.error.length > 0 && this.values.length === 0) {
            Text(this.error).fontSize('14fp').fontColor($r('app.color.xq_warning')).padding(16)
            Button('重新读取').onClick(() => { this.load(); })
          } else if (this.values.length === 0) {
            Column({ space: 8 }) {
              Image($r('app.media.lucide_tags1')).width(40).height(40).fillColor($r('app.color.xq_icon_tertiary'))
              Text('还没有标签').fontSize('16fp').fontColor($r('app.color.xq_font_primary'))
              Text('新增后可在记账时多选。').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
              Button('新增标签', { type: ButtonType.Capsule }).height(44).fontSize('14fp').margin({ top: 12 })
                .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.busy)
                .id('tag-create').onClick(() => { this.beginCreate(); })
            }.width('100%').padding(32)
          } else {
            Column() {
              ForEach(this.values, (item: TagProfile, index: number) => {
                Row({ space: 10 }) {
                  Circle().width(8).height(8).fill(tagTextColor(item.colorKey)).flexShrink(0)
                  Text('#' + item.name).fontSize('16fp').fontColor($r('app.color.xq_font_primary')).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  Button('编辑', { type: ButtonType.Capsule }).height(32).fontSize('12fp')
                    .fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_keyboard'))
                    .enabled(!this.busy).id('tag-edit-' + item.id).onClick(() => { this.beginEdit(item); })
                  Button('删除', { type: ButtonType.Capsule }).height(32).fontSize('12fp')
                    .fontColor($r('app.color.xq_warning')).backgroundColor($r('app.color.xq_app_surface_keyboard'))
                    .enabled(!this.busy).id('tag-delete-' + item.id).onClick(() => { this.remove(item); })
                }.padding({ left: 16, right: 16, top: 10, bottom: 10 }).constraintSize({ minHeight: 60 }).width('100%')
                  .alignItems(VerticalAlign.Center).id('tag-row-' + item.id)
                if (index < this.values.length - 1) {
                  Divider().color($r('app.color.xq_comp_divider')).margin({ left: 34, right: 16 })
                }
              }, (item: TagProfile) => item.id + ':' + item.revision)
            }.width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card')).clip(true)
          }
        }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }.id('tag-scroll').width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '标签' }, divider: { showType: DividerShowType.OFF },
          backIcon: { componentId: 'tag-close', action: () => { if (!this.busy) { this.onClose(); } } } },
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
      .bindSheet($$this.showEditor, this.editorSheet(), this.sheetOptions()).id('tag-page')
  }
}
