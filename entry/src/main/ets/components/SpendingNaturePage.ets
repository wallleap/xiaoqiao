import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { util } from '@kit.ArkTS';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { SPENDING_NATURE_COLORS, SpendingNatureProfile } from '../domain/model/SpendingNature';
import { spendingNatureBackground, spendingNatureText } from '../presentation/ledger/SpendingNatureStyles';

@Component
export struct SpendingNaturePage {
  workspace: LedgerWorkspace | undefined = undefined;
  sheetMaterial: SystemUiMaterial | undefined = undefined;
  onClose: () => void = () => {};
  @State private values: SpendingNatureProfile[] = [];
  @State private loading: boolean = true;
  @State private showArchived: boolean = false;
  @State private showEditor: boolean = false;
  @State private editing: SpendingNatureProfile | undefined = undefined;
  @State private name: string = '';
  @State private colorKey: string = 'neutral';
  @State private busy: boolean = false;
  @State private error: string = '';
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.load(); }

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
    this.editing = undefined; this.name = ''; this.colorKey = 'neutral'; this.error = ''; this.showEditor = true;
  }

  private beginEdit(item: SpendingNatureProfile): void {
    this.editing = item; this.name = item.name; this.colorKey = item.colorKey; this.error = ''; this.showEditor = true;
  }

  private async save(): Promise<void> {
    if (this.busy || this.workspace === undefined) { return; }
    this.busy = true; this.error = '';
    try {
      if (this.editing === undefined) {
        await this.workspace.createSpendingNature({ id: util.generateRandomUUID(), name: this.name, colorKey: this.colorKey });
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
    const options: SheetOptions = { height: 440, showClose: true };
    if (this.sheetMaterial !== undefined) { options.systemMaterial = this.sheetMaterial; }
    else { options.backgroundColor = $r('app.color.xq_app_surface_card'); }
    return options;
  }

  @Builder
  private editorSheet() {
    Column({ space: 16 }) {
      Text(this.editing === undefined ? '新增预算分类' : '编辑预算分类').fontSize('20fp').fontWeight(FontWeight.Bold).width('100%')
      TextInput({ text: this.name, placeholder: '例如：健康投入' }).fontSize('16fp').height(48).maxLength(20)
        .borderRadius(12).backgroundColor($r('app.color.xq_app_surface_keyboard'))
        .id('spending-nature-name').onChange((value: string) => { this.name = value; this.error = ''; })
      Text('颜色').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(SPENDING_NATURE_COLORS, (color: string) => {
          Button('示例', { type: ButtonType.Capsule }).height(36).fontSize('13fp')
            .fontColor(spendingNatureText(color)).backgroundColor(spendingNatureBackground(color))
            .border({ width: this.colorKey === color ? 1.5 : 0,
              color: this.colorKey === color ? spendingNatureText(color) : Color.Transparent })
            .margin({ right: 8, bottom: 8 }).id('spending-nature-color-' + color)
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
          .id('spending-nature-save').onClick(() => { this.save(); })
      }.width('100%')
    }.padding(24).width('100%').height('100%')
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Column({ space: 8 }) {
            Text('用于月度分类预算和支出目的分析。细则仍由收支分类记录，标签继续负责交叉检索。')
              .fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            Button('新增自定义预算分类', { type: ButtonType.Capsule }).width('100%').height(44).fontSize('14fp')
              .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.busy)
              .id('spending-nature-create').onClick(() => { this.beginCreate(); })
          }.padding(16).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
          Row() {
            Text(this.showArchived ? '已归档' : '使用中').fontSize('18fp').fontWeight(FontWeight.Medium)
            Blank()
            Button(this.showArchived ? '使用中' : '已归档', { type: ButtonType.Capsule }).height(32)
              .fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).backgroundColor(Color.Transparent)
              .id('spending-nature-toggle-archive').onClick(() => { this.showArchived = !this.showArchived; })
          }.width('100%')
          if (this.loading) {
            Text('正在读取…').fontSize('14fp').padding(24)
          } else if (this.error.length > 0 && this.values.length === 0) {
            Text(this.error).fontSize('14fp').fontColor($r('app.color.xq_warning')).padding(16)
            Button('重新读取').onClick(() => { this.load(); })
          } else {
            ForEach(this.visible(), (item: SpendingNatureProfile) => {
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Row({ space: 8 }) {
                    Text(item.name).fontSize('16fp').fontWeight(FontWeight.Medium).maxLines(1)
                      .fontColor(spendingNatureText(item.colorKey))
                    if (item.builtIn) {
                      Text('内置').fontSize('10fp').fontColor($r('app.color.xq_font_tertiary'))
                    }
                  }
                  Text(item.archived ? '历史预算仍保留' : '可分配月度预算').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button('编辑', { type: ButtonType.Capsule }).height(32).fontSize('12fp')
                  .fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_keyboard'))
                  .enabled(!this.busy).id('spending-nature-edit-' + item.id).onClick(() => { this.beginEdit(item); })
                Button(item.archived ? '恢复' : '归档', { type: ButtonType.Capsule }).height(32).fontSize('12fp')
                  .fontColor($r('app.color.xq_font_secondary')).backgroundColor($r('app.color.xq_app_surface_keyboard'))
                  .enabled(!this.busy).id('spending-nature-archive-' + item.id).onClick(() => { this.archive(item); })
              }.padding(16).width('100%').borderRadius(16)
                .backgroundColor(item.colorKey === 'neutral' ? $r('app.color.xq_app_surface_card') : spendingNatureBackground(item.colorKey))
                .id('spending-nature-row-' + item.id)
            }, (item: SpendingNatureProfile) => item.id + ':' + item.revision)
          }
        }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }.id('spending-nature-scroll').width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '预算分类' }, divider: { showType: DividerShowType.OFF },
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
