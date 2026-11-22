import { adaptiveColumns } from '../presentation/layout/AdaptiveGrid';
import { summaryValue, summaryStatus } from '../presentation/profile/PersonalSummaryState';
import { Money } from '../core/money/Money';
import { authentication } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { CurrencyUnit } from '../core/money/CurrencyUnit';
import { LedgerUsageSummary } from '../domain/model/LedgerSnapshot';
import { HuaweiAccountConnection } from '../data/cloud/HuaweiCloudBackup';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';

@Component
export struct LocalBackupPage {
  @Prop @Watch('readyChanged') ready: boolean = false;
  @Prop @Watch('personalChanged') active: boolean = false;
  @Prop @Watch('personalChanged') refreshToken: number = 0;
  @Prop netMinor: string = '';
  @Prop netLoading: boolean = false;
  @Prop netError: string = '';
  onRetryAssets: () => void = () => {};
  // Visual hook only; billing/entitlement integration is intentionally not implemented yet.
  @Prop paidEdition: boolean = false;
  @Prop usage: LedgerUsageSummary | undefined = undefined;
  @Prop usageLoading: boolean = false;
  @Prop usageError: string = '';
  onRetryUsage: () => void = () => {};
  @State private connected: boolean = false;
  @State private nickName: string = '';
  @State private avatarUri: string = '';
  @State private avatarFailed: boolean = false;
  @State private loginBusy: boolean = false;
  private appeared: boolean = false;
  private personalRequest: number = 0;

  @Prop busy: boolean = false;
  onOpenBackupRestore: () => void = () => {};
  onOpenSpendingNatures: () => void = () => {};
  onOpenCategories: () => void = () => {};
  onOpenTags: () => void = () => {};
  onOpenDataExchange: () => void = () => {};
  onOpenHuaweiCloud: () => void = () => {};
  onOpenSettings: () => void = () => {};
  onOpenBooks: () => void = () => {};
  onOpenAccounts: () => void = () => {};
  onOpenBudget: () => void = () => {};
  onOpenStatistics: () => void = () => {};
  onOpenRecords: () => void = () => {};
  onOpenExchangeRates: () => void = () => {};

  @State private shortcutColumns: number = 4;
  @State private shortcutFontScale: number = 1;
  @State private headerOffset: number = 0;
  @State private memberBadgeWidth: number = 118;
  @State private memberBadgeHeight: number = 22;
  @State private memberActionWidth: number = 60;
  @State private memberActionHeight: number = 18;

  private readonly headerHeight: number = 340;
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.appeared = true; this.personalChanged(); }
  aboutToDisappear(): void { this.appeared = false; this.personalRequest++; }
  private readyChanged(): void { if (this.ready) { this.personalChanged(); } }
  private personalChanged(): void { if (this.active) { this.refreshPersonal(); } }

  private async refreshPersonal(): Promise<void> {
    const version = ++this.personalRequest;
    try {
      const host = this.getUIContext().getHostContext();
      if (host === undefined) { return; }
      HuaweiAccountConnection.initialize(host);
      await HuaweiAccountConnection.current();
      const profile = HuaweiAccountConnection.profile();
      if (version === this.personalRequest) {
        this.connected = true; this.nickName = profile.nickName; this.avatarUri = profile.avatarUri; this.avatarFailed = false;
      }
    } catch (_) {
      if (version === this.personalRequest) { this.connected = false; this.nickName = ''; this.avatarUri = ''; this.avatarFailed = false; }
    }
  }

  private async login(): Promise<void> {
    if (this.busy || this.loginBusy) { return; }
    const host = this.getUIContext().getHostContext();
    if (host === undefined) { return; }
    this.loginBusy = true;
    try {
      HuaweiAccountConnection.initialize(host);
      const request = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
      request.forceLogin = true;
      request.state = util.generateRandomUUID();
      const response = await new authentication.AuthenticationController(host).executeRequest(request) as authentication.LoginWithHuaweiIDResponse;
      if (response.data === undefined || response.state !== request.state) { throw new Error('HUAWEI_LOGIN_INVALID'); }
      HuaweiAccountConnection.connect(response.data.openID);
      try { await HuaweiAccountConnection.loadProfile(host, true); }
      catch (_) { /* Optional profile consent must not undo a successful sign-in. */ }
      if (this.appeared) { await this.refreshPersonal(); }
    } catch (error) {
      if (this.appeared) {
        const code = (error as BusinessError).code;
        let message = '登录未完成，请稍后重试';
        if (code === 1001502012 || code === 1005300001) { message = '已取消登录'; }
        else if (code === 1001500001 || code === 1001502003) { message = '应用身份校验未通过，暂时无法登录华为账号'; }
        else if (code === 1001502005) { message = '网络不可用，请连接网络后重试'; }
        this.getUIContext().getPromptAction().showToast({ message: message });
      }
    } finally { this.loginBusy = false; }
  }

  private recordedDays(): string {
    if (this.usage === undefined) { return '1'; }
    const first = this.usage.firstEntryDate;
    if (first.length === 0) { return '1'; }
    const parts = first.split('-').map((value: string) => Number(value));
    const today = new Date();
    const days = Math.floor((Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()) -
      Date.UTC(parts[0], parts[1] - 1, parts[2])) / 86400000) + 1;
    return Math.max(1, days).toString();
  }

  private netAssets(): string {
    if (this.netMinor.length === 0) { return '—'; }
    const parts = Money.fromMinorText(this.netMinor, new CurrencyUnit('CNY', 'CNY', 2)).toDecimalString().split('.');
    return parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',') + '.' + parts[1];
  }

  private paidProfileCard(): boolean { return this.connected && this.paidEdition; }

  // Only the column kind is a builder argument. Read reactive props inside each UI expression,
  // so conditional status nodes do not retain primitive loading/error snapshots.
  @Builder
  private personalStat(kind: number) {
    Column({ space: 6 }) {
      Text(summaryValue(kind === 0 ? this.recordedDays() : kind === 1 ? this.usage?.entryCount || '0' : this.netAssets(),
        kind === 2 ? this.netMinor.length > 0 : this.usage !== undefined,
        kind === 2 ? this.netLoading : this.usageLoading, kind === 2 ? this.netError : this.usageError))
        .fontSize('20fp').fontFamily('XiaoQiaoDINMedium').fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('14fp').maxFontSize('20fp')
        .width('100%').height(30).textAlign(TextAlign.Center).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(kind === 0 ? '记账天数' : kind === 1 ? '记账笔数' : '净资产').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
      if (summaryStatus(kind === 2 ? this.netMinor.length > 0 : this.usage !== undefined,
        kind === 2 ? this.netLoading : this.usageLoading, kind === 2 ? this.netError : this.usageError).length > 0) {
        Text(summaryStatus(kind === 2 ? this.netMinor.length > 0 : this.usage !== undefined,
          kind === 2 ? this.netLoading : this.usageLoading, kind === 2 ? this.netError : this.usageError)).fontSize('10fp')
          .fontColor((kind === 2 ? this.netLoading : this.usageLoading) ? $r('app.color.xq_font_secondary') : $r('app.color.xq_font_emphasize'))
      }
    }.layoutWeight(1).alignItems(HorizontalAlign.Center)
  }

  private memberBadgeContour(widthVp: number, heightVp: number): string {
    const width = this.getUIContext().vp2px(widthVp);
    const height = this.getUIContext().vp2px(heightVp);
    // A slanted lower-left edge and shaped right cap follow the supplied reference, in px.
    return 'M ' + height * 0.40 + ',0 H ' + (width - height * 0.40) +
      ' Q ' + width + ',0 ' + (width - height * 0.10) + ',' + height * 0.40 +
      ' L ' + (width - height * 0.25) + ',' + height * 0.78 +
      ' Q ' + (width - height * 0.35) + ',' + height + ' ' + (width - height * 0.60) + ',' + height +
      ' H 0 L ' + height * 0.16 + ',' + height * 0.25 +
      ' Q ' + height * 0.20 + ',0 ' + height * 0.40 + ',0 Z';
  }

  @Builder
  private memberActionLabel() {
    Stack({ alignContent: Alignment.Start }) {
      Path().commands(this.memberBadgeContour(this.memberActionWidth,this.memberActionHeight))
        .width(this.memberActionWidth).height(this.memberActionHeight).fill(this.paidEdition ? '#FFD18F' : '#D6D9DF').strokeWidth(0)
        .hitTestBehavior(HitTestMode.None)
      Text(this.paidEdition ? '会员中心' : '开通会员').fontSize('11fp').fontFamily('YouSheBiaoTiHei')
        .lineHeight('18fp').fontWeight(FontWeight.Regular).fontColor(this.paidEdition ? '#372211' : '#292D34')
        .padding({ left: 8, right: 8 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .onAreaChange((_old: Area, area: Area) => {
          const width = Number(area.width); const height = Number(area.height);
          if (width > 0 && Math.abs(width - this.memberActionWidth) > 0.25) { this.memberActionWidth = width; }
          if (height > 0 && Math.abs(height - this.memberActionHeight) > 0.25) { this.memberActionHeight = height; }
        })
    }.constraintSize({ maxWidth: '100%' })
  }

  @Builder
  private memberBadge() {
    Stack({ alignContent: Alignment.TopStart }) {
      Path().commands(this.memberBadgeContour(this.memberBadgeWidth,this.memberBadgeHeight))
        .width(this.memberBadgeWidth).height(this.memberBadgeHeight).fill(this.paidEdition ? '#402716' : '#34383F').strokeWidth(0)
        .hitTestBehavior(HitTestMode.None)
      Row({ space: 3 }) {
        Image($r('app.media.vip_wordmark')).width(30).height(13.4).objectFit(ImageFit.Contain).flexShrink(0)
          .fillColor(this.paidEdition ? '#FFD18F' : '#D6D9DF')
        this.memberActionLabel()
      }.constraintSize({ minHeight: 22, maxWidth: '100%' }).padding({ left: 20, right: 5, top: 2, bottom: 2 })
        .alignItems(VerticalAlign.Center)
        .onAreaChange((_old: Area, area: Area) => {
          const width = Number(area.width); const height = Number(area.height);
          if (width > 0 && Math.abs(width - this.memberBadgeWidth) > 0.25) { this.memberBadgeWidth = width; }
          if (height > 0 && Math.abs(height - this.memberBadgeHeight) > 0.25) { this.memberBadgeHeight = height; }
        })
      // Overlay is deliberately larger than the bar and extends beyond its upper-left edge.
      Image(this.paidEdition ? $r('app.media.vip_emblem') : $r('app.media.vip_emblem_silver'))
        .width(24).height(24).objectFit(ImageFit.Contain).position({ x: -5, y: -5 })
        .hitTestBehavior(HitTestMode.None)
    }.constraintSize({ maxWidth: '100%' }).clip(false)
      .accessibilityText(this.paidEdition ? 'VIP，会员中心' : 'VIP，开通会员')
  }

  @Builder
  private personalHeader() {
    Column({ space: 24 }) {
      Row({ space: 16 }) {
        Stack() {
          if (this.connected && this.avatarUri.length > 0 && !this.avatarFailed) {
            Image(this.avatarUri).width(56).height(56).objectFit(ImageFit.Cover)
              .onError(() => { this.avatarFailed = true; })
          } else {
            Image($r('app.media.startIcon')).width(56).height(56).objectFit(ImageFit.Contain)
          }
        }.width(56).height(56)
          .borderRadius(this.connected && this.avatarUri.length > 0 && !this.avatarFailed ? 28 : 0)
          .clip(this.connected && this.avatarUri.length > 0 && !this.avatarFailed)
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text(this.connected ? this.nickName || '华为账号用户' : '未登录').fontSize('20fp').fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.xq_font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1)
          }.width('100%').alignItems(VerticalAlign.Center)
          if (this.connected) {
            this.memberBadge()
          } else {
            Text(this.loginBusy ? '正在登录…' : '点击使用华为账号登录').fontSize('12fp')
              .fontColor($r('app.color.xq_font_secondary')).maxLines(2)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Image($r('app.media.lucide_chevron_right1')).width(20).height(20).flexShrink(0)
          .fillColor($r('app.color.xq_icon_tertiary'))
      }.width('100%').alignItems(VerticalAlign.Center).enabled(!this.busy && !this.loginBusy)
        .onClick(() => { if (this.connected) { this.onOpenHuaweiCloud(); } else { this.login(); } }).id('my-account-header')
        .accessibilityText(this.connected ? '查看华为账号与云备份' : '登录华为账号')
      Row() {
        this.personalStat(0)
        Divider().vertical(true).height(28).color($r('app.color.xq_app_divider_subtle'))
        this.personalStat(1)
        Divider().vertical(true).height(28).color($r('app.color.xq_app_divider_subtle'))
        this.personalStat(2)
      }.width('100%').alignItems(VerticalAlign.Center)
      if (this.usageError.length > 0 && !this.usageLoading) {
        Button(this.usageError + '，点击重试').fontSize('12fp').fontColor($r('app.color.xq_font_emphasize'))
          .backgroundColor(Color.Transparent).enabled(!this.usageLoading).onClick(() => { this.onRetryUsage(); })
      }
      if (this.netError.length > 0 && !this.netLoading) {
        Button('净资产：' + this.netError + '，点击重试').fontSize('12fp').fontColor($r('app.color.xq_font_emphasize'))
          .backgroundColor(Color.Transparent).onClick(() => { this.onRetryAssets(); })
      }
    }.width('100%').padding({ left: 4, right: 4, top: 8, bottom: 24 })
  }


  @Builder
  private shortcut(icon: Resource, label: string, componentId: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        Image(icon).width(36).height(36).objectFit(ImageFit.Contain)
        Text(label).fontSize('12fp').fontColor($r('app.color.xq_font_primary')).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').textAlign(TextAlign.Center)
      }.width('100%').justifyContent(FlexAlign.Center)
    }.width((100 / this.shortcutColumns).toString() + '%').height(76 + 20 * (this.shortcutFontScale - 1)).padding({ left: 2, right: 2 }).borderRadius(12).backgroundColor(Color.Transparent)
      .enabled(this.ready && !this.busy).accessibilityText(label).id(componentId).onClick(action)
  }

  @Builder
  private shortcuts() {
    Flex({ wrap: FlexWrap.Wrap }) {
      this.shortcut($r('app.media.mine_icon_ledgers'), '账本管理', 'my-books', this.onOpenBooks)
      this.shortcut($r('app.media.mine_icon_categories'), '分类设置', 'settings-categories', this.onOpenCategories)
      this.shortcut($r('app.media.mine_icon_budget_categories'), '预算分类', 'settings-spending-natures', this.onOpenSpendingNatures)
      this.shortcut($r('app.media.mine_icon_budgets'), '修改预算', 'my-budget', this.onOpenBudget)
      this.shortcut($r('app.media.mine_icon_records'), '账单明细', 'my-records', this.onOpenRecords)
      this.shortcut($r('app.media.mine_icon_tags'), '自定义标签', 'settings-tags', this.onOpenTags)
      this.shortcut($r('app.media.mine_icon_exchange_rates'), '汇率转换', 'my-exchange-rates', this.onOpenExchangeRates)
    }.width('100%').padding(12).borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
      .onAreaChange((_oldArea: Area, area: Area) => {
        const ui = this.getUIContext();
        this.shortcutFontScale = Math.max(1, ui.fp2px(12) / ui.vp2px(12));
        // Flex's measured width includes its 12 vp padding on both sides.
        this.shortcutColumns = adaptiveColumns(Number(area.width) - 24, 72, 0, 7, this.shortcutFontScale);
      })
  }

  @Builder
  private navigationCell(icon: Resource, label: string, componentId: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Image(icon).width(20).height(20).fillColor($r('app.color.xq_icon_secondary')).flexShrink(0)
        Text(label).fontSize('14fp').fontWeight(FontWeight.Regular).fontColor($r('app.color.xq_font_primary'))
          .layoutWeight(1).textAlign(TextAlign.Start).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Image($r('app.media.lucide_chevron_right1')).width(16).height(16)
          .fillColor($r('app.color.xq_icon_tertiary')).flexShrink(0)
      }.width('100%').height('100%').alignItems(VerticalAlign.Center)
    }.width('100%').height(52).padding({ left: 16, right: 16 }).borderRadius(0)
      .backgroundColor(Color.Transparent).enabled(this.ready && !this.busy)
      .accessibilityText(label).id(componentId).onClick(() => { if (this.ready && !this.busy) { action(); } })
  }

  @Builder
  private navigationCells() {
    Column() {
      this.navigationCell($r('app.media.lucide_arrow_down_up1'), '导入与导出', 'settings-data-exchange', this.onOpenDataExchange)
      Divider().color($r('app.color.xq_app_divider_subtle')).margin({ left: 48, right: 16 })
      this.navigationCell($r('app.media.lucide_database_backup1'), '备份与恢复', 'my-backup-restore', this.onOpenBackupRestore)
    }.width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card')).clip(true)
  }

  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }

  @Builder
  private headerBackdrop() {
    Stack() {
      Column().width('100%').height(this.headerHeight)
        .linearGradient({
          angle: 180,
          colors: [
            [$r('app.color.xq_profile_header_gradient_top'), 0],
            [$r('app.color.xq_profile_header_gradient_mid'), 0.5],
            [$r('app.color.xq_profile_header_gradient_bottom'), 0.86]
          ]
        })
      Column().width('100%').height(this.headerHeight)
        .radialGradient({
          center: ['100%', '0%'], radius: 260,
          colors: [[$r('app.color.xq_profile_header_glow_warm'), 0], [Color.Transparent, 1]]
        })
      Column().width('100%').height(this.headerHeight)
        .radialGradient({
          center: ['0%', '8%'], radius: 220,
          colors: [[$r('app.color.xq_profile_header_glow_cool'), 0], [Color.Transparent, 1]]
        })
    }.width('100%').height(this.headerHeight).translate({ y: -this.headerOffset })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      this.headerBackdrop()
      HdsNavigation() {
        Scroll(this.scroller) {
          Column({ space: 16 }) {
            this.personalHeader()
            this.shortcuts()
            this.navigationCells()
          }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 128 })
        }.id('settings-scroll').width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .onDidScroll(() => {
            const offset = this.scroller.currentOffset().yOffset;
            const next = Math.min(Math.max(offset, 0), this.headerHeight);
            if (next !== this.headerOffset) { this.headerOffset = next; }
          })
      }.width('100%').height('100%').mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI).hideBackButton(true)
        .titleBar({ enableComponentSafeArea: true, avoidLayoutSafeArea: true,
          content: { title: { mainTitle: '' }, divider: { showType: DividerShowType.OFF },
            menu: { maxCount: 1, value: [{ content: { icon: $r('app.media.lucide_settings1'), label: '设置',
              action: () => { this.onOpenSettings(); } } }] } },
          style: {
            originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
              menuStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
            scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
              menuStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
            systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
            scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
        .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
        .bindToScrollable([this.scroller]).backgroundColor(Color.Transparent)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]).id('local-backup-page')
    }.width('100%').height('100%').backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
