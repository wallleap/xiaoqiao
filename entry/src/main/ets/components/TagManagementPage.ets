import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { util } from '@kit.ArkTS';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { TAG_COLORS, TagProfile } from '../domain/model/TagProfile';
import { tagBackground, tagTextColor } from '../presentation/ledger/TagStyles';

@Component
export struct TagManagementPage {
  workspace: LedgerWorkspace | undefined = undefined;
  sheetMaterial: SystemUiMaterial | undefined = undefined;
  onClose: () => void = () => {};
  @State private values: TagProfile[] = [];
  @State private loading: boolean = true;
  @State private showEditor: boolean = false;
  @State private editing: TagProfile | undefined = undefined;
  @State private name: string = '';
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
    this.showEditor = true;
  }

  private beginEdit(item: TagProfile): void {
    this.editing = item;
    this.name = item.name;
    this.colorKey = item.colorKey;
    this.error = '';
    this.showEditor = true;
  }

  private async save(): Promise<void> {
    if (this.busy || this.workspace === undefined) { return; }
    this.busy = true;
    this.error = '';
    try {
      if (this.editing === undefined) {
        await this.workspace.createTag({ id: util.generateRandomUUID(), name: this.name, colorKey: this.colorKey });
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

  @Builder
  private editorSheet() {
    Column({ space: 16 }) {
      Text(this.editing === undefined ? '新增标签' : '编辑标签').fontSize('20fp').fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.xq_font_primary')).width('100%')
      TextInput({ text: this.name, placeholder: '例如：旅行、报销、家庭' }).fontSize('16fp').height(48).maxLength(20)
        .borderRadius(12).backgroundColor($r('app.color.xq_app_surface_keyboard'))
        .id('tag-name').onChange((value: string) => { this.name = value; this.error = ''; })
      Text('颜色').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(TAG_COLORS, (color: string) => {
          Button('标签', { type: ButtonType.Capsule }).height(36).fontSize('13fp')
            .fontColor(tagTextColor(color)).backgroundColor(tagBackground(color))
            .border({ width: this.colorKey === color ? 1.5 : 0,
              color: this.colorKey === color ? tagTextColor(color) : Color.Transparent })
            .margin({ right: 8, bottom: 8 }).id('tag-color-' + color)
            .onClick(() => { this.colorKey = color; })
        }, (color: string) => color)
      }.width('100%')
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
          Column({ space: 10 }) {
            Text('标签用于跨分类检索，例如旅行、报销、家庭；一条账目可以选择多个标签。')
              .fontSize('14fp').lineHeight('21fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            Button('新增标签', { type: ButtonType.Capsule }).width('100%').height(44).fontSize('14fp')
              .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.busy)
              .id('tag-create').onClick(() => { this.beginCreate(); })
          }.padding(16).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
          Row() {
            Text('我的标签').fontSize('18fp').fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.xq_font_primary'))
            Blank()
            Text(`${this.values.length} 个`).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
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
            }.width('100%').padding(32)
          } else {
            ForEach(this.values, (item: TagProfile) => {
              Row({ space: 12 }) {
                Text('#' + item.name).fontSize('16fp').fontWeight(FontWeight.Medium).fontColor(tagTextColor(item.colorKey))
                  .backgroundColor(tagBackground(item.colorKey)).borderRadius(16)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 }).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                Button('编辑', { type: ButtonType.Capsule }).height(32).fontSize('12fp')
                  .fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_keyboard'))
                  .enabled(!this.busy).id('tag-edit-' + item.id).onClick(() => { this.beginEdit(item); })
                Button('删除', { type: ButtonType.Capsule }).height(32).fontSize('12fp')
                  .fontColor($r('app.color.xq_warning')).backgroundColor($r('app.color.xq_app_surface_keyboard'))
                  .enabled(!this.busy).id('tag-delete-' + item.id).onClick(() => { this.remove(item); })
              }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
                .id('tag-row-' + item.id)
            }, (item: TagProfile) => item.id + ':' + item.revision)
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
