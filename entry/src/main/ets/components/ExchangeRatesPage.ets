import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { enabledCurrencies } from '../core/money/CurrencySettings';
import { CurrencyManagerSheet } from './CurrencyManagerSheet';
import { adaptiveColumns, gridColumnsTemplate } from '../presentation/layout/AdaptiveGrid';
import { CurrencyFlagBadge } from './CurrencyFlagBadge';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { CURRENCIES, CurrencyDefinition, currencyDefinition } from '../core/money/Currencies';
import { OfficialExchangeRates } from '../data/exchange/OfficialExchangeRates';
import { ExchangeRateRow, queryExchangeRates, filterExchangeRates, exchangeRateRowKey } from '../presentation/exchange/ExchangeRateQuery';

@Component
export struct ExchangeRatesPage {
  workspace: LedgerWorkspace | undefined = undefined;
  onClose: () => void = () => {};
  actionMaterial: SystemUiMaterial | undefined = undefined;
  sheetMaterial: SystemUiMaterial | undefined = undefined;
  @State private showManager: boolean = false;
  @State private managerTarget: string = '';
  @State private managerMode: string = 'list';
  private settingsDirty: boolean = false;
  private addedCurrencyCode: string = '';
  private quietSheetMaterial: SystemUiMaterial | undefined = undefined;
  private preparingSheetMaterial: Promise<void> | undefined = undefined;
  @State private configVersion: number = 0;
  @State private showBaseSheet: boolean = false;
  @State private baseKeyword: string = '';
  @State private baseCode: string = 'CNY';
  @State private keyword: string = '';
  @State private rows: ExchangeRateRow[] = [];
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private baseGridColumns: number = 3;
  @State private baseGridFontScale: number = 1;
  private active: boolean = false;
  private request: number = 0;
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.active = true; this.openRates(); }
  aboutToDisappear(): void { this.active = false; this.request++; this.loading = false; this.showBaseSheet = false; this.showManager = false; }
  private async openRates(): Promise<void> {
    const version = ++this.request;
    this.loading = true; this.error = '';
    try {
      await this.workspace?.currencySettings.load();
      if (!this.active || version !== this.request) { return; }
      if (!enabledCurrencies().some((item: CurrencyDefinition) => item.code === this.baseCode)) { this.baseCode = 'CNY'; }
      await this.reload();
    } catch (_) {
      if (this.active && version === this.request) { this.loading = false; this.error = '币种设置读取失败，请重试'; }
    }
  }
  private today(): string {
    const now = new Date();
    return now.getFullYear().toString() + '-' + (now.getMonth() + 1).toString().padStart(2, '0') + '-' + now.getDate().toString().padStart(2, '0');
  }
  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }
  private visibleRows(): ExchangeRateRow[] { return filterExchangeRates(this.rows, this.keyword); }
  private showFeedback(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
  }
  private async reload(manual: boolean = false): Promise<void> {
    const version = ++this.request;
    const base = this.baseCode;
    this.loading = true; this.error = '';
    if (manual) { this.showFeedback('正在读取汇率…'); }
    try {
      const rows = await queryExchangeRates(base, this.today(), (from: string, to: string, date: string) => OfficialExchangeRates.quote(from, to, date));
      if (!this.active || version !== this.request || base !== this.baseCode) { return; }
      if (rows.length > 0 && rows.every((row: ExchangeRateRow) => row.rate.length === 0)) {
        this.error = '汇率暂不可用，可检查网络或点击币种设置手动汇率';
        if (this.rows.length === 0) { this.rows = rows; }
      } else { this.rows = rows; }
    } catch (_) {
      if (this.active && version === this.request) { this.error = '汇率暂时无法读取，请重试'; }
    } finally {
      if (this.active && version === this.request) {
        this.loading = false;
        if (manual) {
          if (this.error) { this.showFeedback('汇率读取失败，请检查网络或手动汇率设置'); }
          else {
            const unavailable = this.rows.filter((row: ExchangeRateRow) => !row.rate).length;
            const cached = this.rows.some((row: ExchangeRateRow) => row.cached);
            this.showFeedback((cached ? '已读取缓存报价' : '汇率读取完成') +
              (unavailable > 0 ? '，' + unavailable.toString() + ' 个币种暂不可用' : ''));
          }
        }
      }
    }
  }
  private async selectBase(selected: number | number[]): Promise<void> {
    if (!this.active) { return; }
    const index = typeof selected === 'number' ? selected : selected.length === 1 ? selected[0] : -1;
    const currency = CURRENCIES[index];
    if (currency === undefined) { return; }
    this.showBaseSheet = false;
    try { this.getUIContext().getFocusController().clearFocus(); } catch (_) {}
    if (currency.code === this.baseCode) { return; }
    this.baseCode = currency.code; this.rows = []; this.keyword = '';
    // A scroll controller reset is optional; a temporarily detached controller
    // must never prevent the newly selected quote direction from being loaded.
    try { this.scroller.scrollTo({ xOffset: 0, yOffset: 0 }); } catch (_) {}
    await this.reload();
  }
  private async chooseBase(): Promise<void> {
    if (!this.active || this.showBaseSheet) { return; }
    await this.prepareSheetMaterial();
    if (!this.active || this.showBaseSheet) { return; }
    try { this.getUIContext().getFocusController().clearFocus(); } catch (_) {}
    this.showManager = false; this.baseKeyword = ''; this.showBaseSheet = true;
  }
  private baseChoices(): CurrencyDefinition[] {
    const keyword = this.baseKeyword.trim().toLowerCase();
    return enabledCurrencies().filter((item: CurrencyDefinition) => !keyword || (item.code + ' ' + item.name).toLowerCase().includes(keyword));
  }
  private prepareSheetMaterial(): Promise<void> {
    if (this.preparingSheetMaterial !== undefined) { return this.preparingSheetMaterial; }
    this.preparingSheetMaterial = this.loadSheetMaterial();
    return this.preparingSheetMaterial;
  }
  private async loadSheetMaterial(): Promise<void> {
    if (this.sheetMaterial === undefined) { return; }
    try {
      const factory = await import('../presentation/exchange/ExchangeSheetMaterial');
      this.quietSheetMaterial = factory.createExchangeSheetMaterial();
    } catch (_) { /* Keep the themed fallback instead of reusing an interactive material. */ }
  }
  private baseSheetOptions(): SheetOptions {
    const height: SheetSize | Length = this.showManager && this.managerMode === 'rate' ? '55%' : SheetSize.LARGE;
    const options: SheetOptions = { height: height, detents: [height], dragBar: false, showClose: true, onDisappear: () => { this.sheetClosed(); },
      keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE };
    if (this.quietSheetMaterial !== undefined) { options.systemMaterial = this.quietSheetMaterial; }
    else { options.backgroundColor = $r('app.color.xq_app_surface_page'); }
    return options;
  }
  private converted(row: ExchangeRateRow): string { return row.rate || row.error; }
  private async manage(target: string = ''): Promise<void> {
    if (this.showBaseSheet || !this.active) { return; }
    await this.prepareSheetMaterial();
    if (!this.active || this.showBaseSheet) { return; }
    try { this.getUIContext().getFocusController().clearFocus(); } catch (_) {}
    this.managerTarget = target; this.managerMode = target ? 'rate' : 'list'; this.showManager = true; this.showBaseSheet = true;
  }
  private settingsChanged(createdCode: string = ''): void {
    if (!this.active) { return; }
    if (createdCode) { this.addedCurrencyCode = createdCode; }
    this.settingsDirty = true;
    // Persist now, but do not rebuild the presenting page/material while the native sheet is open.
    this.request++;
    if (!this.showBaseSheet) { this.applySettingsChanges(); }
  }
  private sheetClosed(): void {
    this.showBaseSheet = false; this.showManager = false;
    this.applySettingsChanges();
  }
  private applySettingsChanges(): void {
    if (!this.active || !this.settingsDirty) { return; }
    this.settingsDirty = false; this.configVersion++;
    if (this.addedCurrencyCode) {
      this.keyword = ''; this.addedCurrencyCode = '';
      try { this.scroller.scrollTo({ xOffset: 0, yOffset: 0 }); } catch (_) {}
    }
    // A changed/deleted override must not remain visible when its replacement fails.
    this.rows = [];
    if (!enabledCurrencies().some((item: CurrencyDefinition) => item.code === this.baseCode)) { this.baseCode = 'CNY'; }
    this.reload();
  }
  @Builder
  private currencyManager() {
    CurrencyManagerSheet({ workspace: this.workspace, baseCode: this.baseCode, initialTarget: this.managerTarget,
      onSaved: (createdCode?: string) => { this.settingsChanged(createdCode || ''); },
      onModeChanged: (mode: string) => { this.managerMode = mode; },
      onClose: () => { this.showBaseSheet = false; } })
  }
  @Builder
  private sheetContent() {
    // The dedicated material disables press deformation; no extra scroll interceptor is needed.
    if (this.showManager) { this.currencyManager() }
    else { this.baseCurrencySheet() }
  }
  @Builder
  private baseCurrencySheet() {
    Column({ space: 16 }) {
      Text('选择基准币种').fontSize('20fp').fontWeight(FontWeight.Bold).fontColor($r('app.color.xq_font_primary'))
        .width('100%').padding({ right: 48 })
      Search({ value: this.baseKeyword, placeholder: '搜索货币名称或代码' }).height(40)
        .textFont({ size: '14fp' }).placeholderFont({ size: '14fp' })
        .backgroundColor($r('app.color.xq_app_surface_card'))
        .searchIcon({ src: $r('app.media.lucide_search1'), size: 18, color: $r('app.color.xq_icon_secondary') })
        .onChange((value: string) => { this.baseKeyword = value; }).id('exchange-base-search')
      if (this.baseChoices().length === 0) {
        Text('没有匹配的币种').fontSize('13fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      }
      Grid() {
        ForEach(this.baseChoices(), (currency: CurrencyDefinition) => {
          GridItem() {
            Button({ type: ButtonType.Normal, stateEffect: false }) {
              Column({ space: 4 }) {
                CurrencyFlagBadge({ currencyCode: currency.code, flagWidth: 32, refreshToken: this.configVersion })
                Text(currency.name).fontSize('12fp').minFontSize('10fp').maxFontSize('12fp').maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center).width('100%').height(30 * this.baseGridFontScale)
                  .fontColor(this.baseCode === currency.code ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_primary'))
                Text(currency.code).fontSize('11fp').fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_secondary'))
              }.width('100%').justifyContent(FlexAlign.Center)
            }.width('100%').height(100 + 44 * (this.baseGridFontScale - 1)).padding(8)
              .backgroundColor($r('app.color.xq_exchange_currency_card_background'))
              .border({ width: 1, color: this.baseCode === currency.code ? $r('app.color.xq_brand') : Color.Transparent })
              .borderRadius(14).clip(true)
              .id('exchange-base-' + currency.code)
              .accessibilityText(currency.name + ' ' + currency.code + (this.baseCode === currency.code ? '，当前基准币种' : ''))
              .onClick(() => { this.selectBase(CURRENCIES.findIndex((item: CurrencyDefinition) => item.code === currency.code)); })
          }.height(100 + 44 * (this.baseGridFontScale - 1)).borderRadius(14).clip(true)
        }, (currency: CurrencyDefinition) => currency.code + ':' + this.configVersion.toString())
      }.columnsTemplate(gridColumnsTemplate(this.baseGridColumns)).columnsGap(8).rowsGap(8).width('100%').layoutWeight(1)
        .onAreaChange((_oldArea: Area, area: Area) => {
          const ui = this.getUIContext();
          this.baseGridFontScale = Math.max(1, ui.fp2px(12) / ui.vp2px(12));
          this.baseGridColumns = adaptiveColumns(Number(area.width), 96, 8, 6, this.baseGridFontScale);
        })
        .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
    }.width('100%').height('100%').padding(24)
  }
  @Builder
  private baseSelector() {
    Row({ space: 12 }) {
      Text('基准币种').fontSize('13fp').fontColor($r('app.color.xq_font_secondary'))
      Blank()
      Button({ type: ButtonType.Capsule, stateEffect: false }) {
        Row({ space: 6 }) {
          CurrencyFlagBadge({ currencyCode: this.baseCode, flagWidth: 24, refreshToken: this.configVersion })
          Text(this.baseCode + ' · ' + currencyDefinition(this.baseCode).name).fontSize('14fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
          Image($r('app.media.lucide_chevron_down1')).width(14).height(14).fillColor($r('app.color.xq_icon_primary'))
        }
      }.height(36).padding({ left: 12, right: 12 })
        .backgroundColor(this.actionMaterial === undefined ? $r('app.color.xq_app_surface_card') : Color.Transparent)
        .systemMaterial(this.actionMaterial).onClick(() => { this.chooseBase(); })
        .accessibilityText('选择基准币种，当前' + currencyDefinition(this.baseCode).name).id('exchange-base-selector')
    }.width('100%').height(52)
  }
  @Builder
  private rateRow(row: ExchangeRateRow) {
    Row({ space: 12 }) {
      CurrencyFlagBadge({ currencyCode: row.code, refreshToken: this.configVersion })
      Column({ space: 4 }) {
        Text(row.code).fontSize('16fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
        Text(row.name).fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Column({ space: 4 }) {
        Text(this.converted(row)).fontSize(row.rate ? '18fp' : '13fp').fontFamily('XiaoQiaoDINMedium')
          .fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('12fp').maxFontSize('18fp')
          .constraintSize({ maxWidth: 200 }).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (row.date) {
          Text(row.date + (row.manual ? ' · 手动' : row.cached ? ' · 缓存报价' : '')).fontSize('11fp').fontColor($r('app.color.xq_font_secondary'))
        }
      }.alignItems(HorizontalAlign.End)
    }.width('100%').padding(16).borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      .accessibilityText('1 ' + this.baseCode + ' 兑换 ' + this.converted(row) + ' ' + row.code + '，点击修改汇率')
      .onClick(() => { this.manage(row.code); })
  }
  build() {
    HdsNavigation() {
      // Follow the working search-page structure. HDS owns only its title safe
      // area; the base selector and search remain in one natural-height ListItem.
      List({ space: 12, scroller: this.scroller }) {
        ListItem() {
          Column({ space: 12 }) {
            this.baseSelector()
            Text('1 ' + this.baseCode + ' 可兑换').fontSize('20fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary')).width('100%')
            Text('在线报价：欧洲央行 ECB；手动汇率优先 · 点击币种修改').fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            Search({ value: this.keyword, placeholder: '搜索币种名称或代码' }).height(44)
              .backgroundColor($r('app.color.xq_app_surface_card')).textFont({ size: '14fp' }).placeholderFont({ size: '14fp' })
              .searchIcon({ src: $r('app.media.lucide_search1'), size: 18, color: $r('app.color.xq_icon_secondary') })
              .onChange((value: string) => { this.keyword = value; }).id('exchange-currency-search')
          }.width('100%').padding({ bottom: 4 })
        }
        if (this.loading) {
          ListItem() { Text(this.rows.length > 0 ? '更新中…' : '正在读取汇率…').fontSize('13fp').fontColor($r('app.color.xq_font_secondary')).padding(16) }
        }
        if (this.error) {
          ListItem() {
            Button(this.error + '，点击重试').fontSize('13fp').fontColor($r('app.color.xq_font_emphasize'))
              .backgroundColor(Color.Transparent).enabled(!this.loading).onClick(() => { this.openRates(); })
          }
        }
        ForEach(this.visibleRows(), (row: ExchangeRateRow) => { ListItem() { this.rateRow(row) } }, (row: ExchangeRateRow) => exchangeRateRowKey(this.baseCode, row) + ':' + this.configVersion.toString())
        if (!this.loading && !this.error && this.rows.length === 0) {
          ListItem() { Text('没有启用的目标币种，点击右上角 ＋ 添加或开启').fontSize('13fp').fontColor($r('app.color.xq_font_secondary')).width('100%').textAlign(TextAlign.Center).padding(24) }
        }
        if (!this.loading && !this.error && this.rows.length > 0 && this.visibleRows().length === 0) {
          ListItem() { Text('没有匹配的币种').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%').textAlign(TextAlign.Center).padding(24) }
        }
      }.width('100%').height(LayoutPolicy.matchParent).padding({ left: 16, right: 16 }).contentStartOffset(12).contentEndOffset(24)
        .clip(false).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .dynamicHideTitleBar({ hideTitleArea: false, hideBottomBuilder: false, hideStatusBar: false })
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '汇率转换' }, backIcon: { action: () => { this.onClose(); } },
          menu: { maxCount: 1, value: [{ content: { icon: $r('app.media.lucide_plus1'), label: '管理币种', isEnabled: this.workspace !== undefined, action: () => { this.manage(); } } }] },
          divider: { showType: DividerShowType.OFF } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
          backIconStyle: { iconColor: $r('app.color.xq_icon_primary') }, menuStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
            backIconStyle: { iconColor: $r('app.color.xq_icon_primary') }, menuStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .bindToScrollable([this.scroller]).systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .width('100%').height(LayoutPolicy.matchParent).backgroundColor($r('app.color.xq_app_surface_page'))
      .bindSheet($$this.showBaseSheet, this.sheetContent(), this.baseSheetOptions())
  }
}
