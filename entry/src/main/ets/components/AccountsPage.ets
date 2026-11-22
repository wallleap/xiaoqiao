import { currencyUnit } from '../core/money/Currencies';
import { ComponentContent, SegmentButton, SegmentButtonOptions } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { AccountOverview, AccountProfile } from '../domain/model/AccountProfile';
import { AccountAvatar } from './AccountAvatar';
import { Money } from '../core/money/Money';
import { CurrencyUnit } from '../core/money/CurrencyUnit';

interface AccountMoreMenuParams { onSort: () => void; }

@Builder
function accountMoreMenu(params: AccountMoreMenuParams) {
  Menu() {
    MenuItem() {
      Row({ space: 12 }) {
        Image($r('app.media.lucide_arrow_down_up1')).width(20).height(20)
          .fillColor($r('app.color.xq_icon_primary')).flexShrink(0)
        Text('排序').fontSize('14fp').fontWeight(FontWeight.Regular).fontColor($r('app.color.xq_font_primary')).layoutWeight(1)
      }.width('100%').alignItems(VerticalAlign.Center)
    }.onClick(params.onSort).accessibilityText('排序').id('accounts-sort-menu')
  }.width(200)
}

@Component
export struct AccountsPage {
  @Prop overview: AccountOverview | undefined = undefined;
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @State private showArchived: boolean = false;
  @State @Watch('archiveSelectionChanged') private archiveSelection: number[] = [0];
  @State private archiveOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [{ text: '使用中' }, { text: '已归档' }], multiply: false,
    fontSize: '13fp', selectedFontSize: '13fp',
    fontColor: $r('app.color.xq_font_secondary'), selectedFontColor: $r('app.color.xq_font_on_primary'),
    backgroundColor: $r('app.color.xq_app_surface_page'), selectedBackgroundColor: $r('app.color.xq_brand')
  });

  private archiveSelectionChanged(): void {
    this.showArchived = this.archiveSelection[0] === 1;
  }

  onCreate: () => void = () => {};
  onSort: () => void = () => {};
  menuMaterial: SystemUiMaterial | undefined = undefined;
  @State private menuError: string = '';
  private menuContent: ComponentContent<AccountMoreMenuParams> | undefined = undefined;
  private active: boolean = false;

  aboutToAppear(): void { this.active = true; }
  aboutToDisappear(): void { this.active = false; this.closeMore(); }
  private closeMore(): void {
    const content = this.menuContent;
    if (content === undefined) { return; }
    this.menuContent = undefined;
    this.getUIContext().getPromptAction().closeMenu(content).catch(() => {}).finally(() => { content.dispose(); });
  }
  private async openMore(): Promise<void> {
    if (this.menuContent !== undefined || this.loading || this.overview === undefined || this.error.length > 0) { return; }
    this.menuError = '';
    const content = new ComponentContent(this.getUIContext(), wrapBuilder(accountMoreMenu), {
      onSort: () => { this.closeMore(); this.onSort(); }
    } as AccountMoreMenuParams);
    this.menuContent = content;
    const options: MenuOptions = { placement: Placement.BottomRight, borderRadius: 20,
      onDidDisappear: () => { if (this.menuContent === content) { this.menuContent = undefined; content.dispose(); } } };
    if (this.menuMaterial !== undefined) { options.systemMaterial = this.menuMaterial; }
    try { await this.getUIContext().getPromptAction().openMenu(content, { id: 'accounts-more' }, options); }
    catch (_) {
      if (this.menuContent === content) { this.menuContent = undefined; content.dispose(); }
      if (this.active) { this.menuError = '菜单暂时无法打开，请重试'; }
    }
  }

  onEdit: (account: AccountProfile) => void = () => {};
  onRetry: () => void = () => {};
  private readonly scroller: Scroller = new Scroller();

  private amount(minor: string, code: string = 'CNY'): string {
    if (!minor) { return '—'; }
    const parts = Money.fromMinorText(minor, currencyUnit(code)).toDecimalString().split('.');
    return parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',') + (parts.length > 1 ? '.' + parts[1] : '');
  }
  private visible(): AccountProfile[] { return this.overview?.accounts.filter((account: AccountProfile) => account.archived === this.showArchived) || []; }

  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }

  @Builder
  private total(asset: boolean) {
    Column({ space: 6 }) {
      Text(asset ? '总资产' : '总负债').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
      Text(this.amount((asset ? this.overview?.assetsMinor : this.overview?.liabilitiesMinor) ?? '0'))
        .fontSize('20fp').fontFamily('XiaoQiaoDINMedium').id(asset ? 'accounts-total-assets' : 'accounts-total-liabilities')
        .fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('14fp').maxFontSize('20fp')
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          if (this.menuError.length > 0) { Text(this.menuError).fontSize('13fp').fontColor($r('app.color.xq_warning')).width('100%').padding({ left: 8, right: 8 }) }
          if (this.loading && this.overview === undefined) {
            Text('正在读取账户…').fontSize('14fp').padding(24)
          } else if (this.error.length > 0) {
            Text(this.error).fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).padding(16)
            Button('重新读取').onClick(() => { this.onRetry(); }).id('accounts-retry')
          } else {
            Stack({ alignContent: Alignment.TopEnd }) {
              Column({ space: 16 }) {
                Text('净资产 · CNY' + (this.overview?.accounts.some((item: AccountProfile) => !item.archived && item.includeInNetAssets && item.currencyId !== 'CNY' && item.balanceMinor !== '0') ? ' · 参考汇率估值' : '')).fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%').padding({ right: 80 })
                Text(this.amount(this.overview?.netMinor ?? '0')).fontSize('36fp').fontFamily('XiaoQiaoDINBold')
                  .fontWeight(FontWeight.Bold).fontColor($r('app.color.xq_font_primary')).width('100%')
                  .maxLines(1).minFontSize('20fp').maxFontSize('36fp').padding({ right: 80 }).id('accounts-net')
                Row({ space: 24 }) {
                  this.total(true)
                  this.total(false)
                }.width('100%')
                if ((this.overview?.valuationMissing?.length || 0) > 0) {
                  Text('外币汇率暂不可用，净资产待估值：' + this.overview?.valuationMissing?.join('、')).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
                }
              }.padding(20).width('100%')
              Image($r('app.media.cards')).width(72).height(72).objectFit(ImageFit.Contain)
                .fillColor($r('app.color.xq_account_summary_cards')).rotate({ angle: -12 })
                .margin({ top: 18, right: 20 }).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
            }.width('100%').borderRadius(20).clip(true).backgroundColor($r('app.color.xq_app_surface_card'))
              .radialGradient({ center: ['100%', '0%'], radius: 200,
                colors: [[$r('app.color.xq_account_summary_glow_start'), 0],
                  [$r('app.color.xq_account_summary_glow_middle'), 0.5], [$r('app.color.xq_app_surface_card'), 1]] })
            Row() {
              Text(this.showArchived ? '已归档账户' : '我的账户').fontSize('18fp').fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.xq_font_primary')).margin({ left: 8 })
              Blank()
              SegmentButton({ options: this.archiveOptions, selectedIndexes: $archiveSelection })
                .width(168).id('accounts-toggle-archive')
            }.width('100%')
            if (this.visible().length === 0) {
              Column({ space: 12 }) {
                Image($r('app.media.lucide_wallet1')).width(40).height(40).fillColor($r('app.color.xq_icon_tertiary'))
                Text(this.showArchived ? '暂无归档账户' : '添加你的第一个账户').fontSize('16fp').fontColor($r('app.color.xq_font_primary'))
                Text(this.showArchived ? '归档后的账户会显示在这里' : '把现金、银行卡和待还金额记清楚').fontSize('12fp')
                  .fontColor($r('app.color.xq_font_secondary'))
              }.padding({ top: 28, bottom: 32 }).width('100%')
            }
            Column({ space: 12 }) {
            ForEach(this.visible(), (account: AccountProfile) => {
              Row({ space: 12 }) {
                AccountAvatar({ iconKey: account.iconKey, brandColor: account.brandColor, iconVariant: account.iconVariant })
                Column({ space: 4 }) {
                  Text(account.name).fontSize('16fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary')).maxLines(1)
                  Text((account.kind === 'liability' ? '负债账户' : '资产账户') + (account.includeInNetAssets ? ' · ' + account.currencyId : ' · 不计总资产'))
                    .fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Column({ space: 4 }) {
                  Text(this.amount(account.balanceMinor, account.currencyId)).fontSize('20fp').fontFamily('XiaoQiaoDINMedium')
                    .fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('14fp').maxFontSize('20fp')
                  if (account.kind === 'liability' && BigInt(account.balanceMinor) > BigInt(0)) {
                    Text('溢缴余额').fontSize('10fp').fontColor($r('app.color.xq_font_secondary'))
                  }
                }.alignItems(HorizontalAlign.End).constraintSize({ maxWidth: '46%' })
                Image($r('app.media.lucide_chevron_right1')).width(14).height(14).fillColor($r('app.color.xq_icon_tertiary'))
              }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
                .id('account-row-' + account.id).onClick(() => { this.onEdit(account); })
            }, (account: AccountProfile) => account.id + ':' + account.revision + ':' + account.balanceMinor)
            }.width('100%')
          }
        }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 128 })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI).hideBackButton(true)
      .titleBar({ enableComponentSafeArea: true, avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '资产' }, divider: { showType: DividerShowType.OFF },
          menu: { maxCount: 2, value: [{ content: { icon: $r('app.media.lucide_plus1'), label: '添加账户',
            componentId: 'accounts-create', isEnabled: !this.loading && this.error.length === 0,
            action: () => { if (!this.loading && this.error.length === 0) { this.onCreate(); } } } },
            { content: { icon: $r('app.media.lucide_ellipsis1'), label: '更多', componentId: 'accounts-more',
              isEnabled: !this.loading && this.overview !== undefined && this.error.length === 0, action: () => { this.openMore(); } } }] } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
          menuStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
            menuStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]).id('accounts-page')
  }
}
