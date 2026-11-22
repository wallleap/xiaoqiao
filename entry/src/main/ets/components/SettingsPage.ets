import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { AppearanceMode, AppearanceSettings } from '../data/settings/AppearanceSettings';

// Settings subpage opened from the profile title bar. Only the appearance module is
// implemented; other settings stay out until they have a decided behaviour.
@Component
export struct SettingsPage {
  onClose: () => void = () => {};
  menuMaterial: SystemUiMaterial | undefined = undefined;
  @State private appearance: AppearanceMode = AppearanceMode.SYSTEM;
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined) { AppearanceSettings.initialize(host); }
    this.appearance = AppearanceSettings.mode();
  }

  private selectAppearance(mode: AppearanceMode): void {
    const host = this.getUIContext().getHostContext();
    if (host === undefined) { return; }
    AppearanceSettings.apply(host, mode);
    this.appearance = mode;
  }

  private appearanceLabel(): string {
    return this.appearance === AppearanceMode.LIGHT ? '浅色'
      : this.appearance === AppearanceMode.DARK ? '深色' : '跟随系统';
  }

  private appearanceMenuOptions(): MenuOptions {
    const options: MenuOptions = { placement: Placement.BottomRight, borderRadius: 20 };
    if (this.menuMaterial !== undefined) { options.systemMaterial = this.menuMaterial; }
    return options;
  }

  @Builder
  private appearanceMenu() {
    Menu() {
      MenuItem({ content: '跟随系统' })
        .contentFontColor(this.appearance === AppearanceMode.SYSTEM ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_primary'))
        .onClick(() => { this.selectAppearance(AppearanceMode.SYSTEM); })
      MenuItem({ content: '浅色' })
        .contentFontColor(this.appearance === AppearanceMode.LIGHT ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_primary'))
        .onClick(() => { this.selectAppearance(AppearanceMode.LIGHT); })
      MenuItem({ content: '深色' })
        .contentFontColor(this.appearance === AppearanceMode.DARK ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_primary'))
        .onClick(() => { this.selectAppearance(AppearanceMode.DARK); })
    }.width(224)
  }

  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }

  @Builder
  private appearanceSection() {
    Column({ space: 8 }) {
      Text('外观').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
        .width('100%').padding({ left: 8, right: 8 })
      Button({ type: ButtonType.Normal }) {
        Row() {
          Text('深色模式').fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 4 }) {
            Text(this.appearanceLabel()).fontSize('13fp').fontColor($r('app.color.xq_font_emphasize'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Image($r('app.media.lucide_chevron_down1')).width(12).height(12)
              .fillColor($r('app.color.xq_icon_secondary')).flexShrink(0)
          }.flexShrink(0)
        }.width('100%').height('100%')
      }.width('100%').height(52).padding({ left: 16, right: 16 }).borderRadius(20)
        .backgroundColor($r('app.color.xq_app_surface_card'))
        .id('settings-appearance-mode')
        .accessibilityText('深色模式：' + this.appearanceLabel())
        .bindMenu(this.appearanceMenu, this.appearanceMenuOptions())
    }.width('100%')
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          this.appearanceSection()
        }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }.id('settings-page-scroll').width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '设置' }, divider: { showType: DividerShowType.OFF },
          backIcon: { action: () => { this.onClose(); } } },
        style: {
          originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
            backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
            backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]).id('settings-page')
  }
}
