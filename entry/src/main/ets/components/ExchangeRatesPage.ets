import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { CURRENCIES, CurrencyDefinition, currencyDefinition } from '../core/money/Currencies';
import { OfficialExchangeRates } from '../data/exchange/OfficialExchangeRates';
import { ExchangeRateRow, queryExchangeRates, filterExchangeRates, exchangeRateRowKey } from '../presentation/exchange/ExchangeRateQuery';

@Component
export struct ExchangeRatesPage {
  onClose: () => void = () => {};
  actionMaterial: SystemUiMaterial | undefined = undefined;
  @State private baseCode: string = 'CNY';
  @State private keyword: string = '';
  @State private rows: ExchangeRateRow[] = [];
  @State private loading: boolean = false;
  @State private error: string = '';
  private active: boolean = false;
  private request: number = 0;
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.active = true; this.reload(); }
  aboutToDisappear(): void { this.active = false; this.request++; this.loading = false; }
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
    if (this.loading) { return; }
    const version = ++this.request;
    const base = this.baseCode;
    this.loading = true; this.error = '';
    if (manual) { this.showFeedback('正在读取汇率…'); }
    try {
      const rows = await queryExchangeRates(base, this.today(), (from: string, to: string, date: string) => OfficialExchangeRates.quote(from, to, date));
      if (!this.active || version !== this.request || base !== this.baseCode) { return; }
      if (rows.every((row: ExchangeRateRow) => row.rate.length === 0)) {
        this.error = '汇率暂时无法获取，请检查网络后重试';
      } else { this.rows = rows; }
    } catch (_) {
      if (this.active && version === this.request) { this.error = '汇率暂时无法读取，请重试'; }
    } finally {
      if (this.active && version === this.request) {
        this.loading = false;
        if (manual) {
          if (this.error) { this.showFeedback('汇率读取失败，请检查网络后重试'); }
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
    if (!this.active || this.loading) { return; }
    const index = typeof selected === 'number' ? selected : selected.length === 1 ? selected[0] : -1;
    const currency = CURRENCIES[index];
    if (currency === undefined || currency.code === this.baseCode) { return; }
    this.baseCode = currency.code; this.rows = []; this.keyword = '';
    // A scroll controller reset is optional; a temporarily detached controller
    // must never prevent the newly selected quote direction from being loaded.
    try { this.scroller.scrollTo({ xOffset: 0, yOffset: 0 }); } catch (_) {}
    await this.reload();
  }
  private chooseBase(): void {
    if (this.loading) { return; }
    this.getUIContext().getFocusController().clearFocus();
    this.getUIContext().showTextPickerDialog({
      range: CURRENCIES.map((item: CurrencyDefinition) => item.code + ' · ' + item.name),
      selected: CURRENCIES.findIndex((item: CurrencyDefinition) => item.code === this.baseCode),
      canLoop: false, selectedTextStyle: { color: $r('app.color.xq_font_emphasize') },
      acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      cancelButtonStyle: { fontColor: $r('app.color.xq_font_secondary') },
      onAccept: (result: TextPickerResult) => {
        this.selectBase(result.index);
      }
    });
  }
  @Builder
  private baseSelector() {
    Row({ space: 12 }) {
      Text('基准币种').fontSize('13fp').fontColor($r('app.color.xq_font_secondary'))
      Blank()
      Button({ type: ButtonType.Capsule }) {
        Row({ space: 6 }) {
          Text(this.baseCode + ' · ' + currencyDefinition(this.baseCode).name).fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
          Image($r('app.media.lucide_chevron_down1')).width(14).height(14).fillColor($r('app.color.xq_icon_primary'))
        }
      }.height(36).padding({ left: 12, right: 12 })
        .backgroundColor(this.actionMaterial === undefined ? $r('app.color.xq_app_surface_card') : Color.Transparent)
        .systemMaterial(this.actionMaterial).enabled(!this.loading).onClick(() => { this.chooseBase(); })
        .accessibilityText('选择基准币种，当前' + currencyDefinition(this.baseCode).name).id('exchange-base-selector')
    }.width('100%').height(52)
  }
  @Builder
  private rateRow(row: ExchangeRateRow) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(row.code).fontSize('16fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
        Text(row.name).fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Column({ space: 4 }) {
        Text(row.rate || row.error).fontSize(row.rate ? '18fp' : '13fp').fontFamily('XiaoQiaoDINMedium')
          .fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('12fp').maxFontSize('18fp')
          .constraintSize({ maxWidth: 200 }).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (row.date) {
          Text(row.date + (row.cached ? ' · 缓存报价' : '')).fontSize('11fp').fontColor($r('app.color.xq_font_secondary'))
        }
      }.alignItems(HorizontalAlign.End)
    }.width('100%').padding(16).borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      .accessibilityText('1 ' + this.baseCode + ' 兑换 ' + (row.rate ? row.rate + ' ' + row.code : row.name + ' 暂不可用'))
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
            Text('来源：欧洲央行 ECB · 显示实际报价日期').fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
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
              .backgroundColor(Color.Transparent).enabled(!this.loading).onClick(() => { this.reload(true); })
          }
        }
        ForEach(this.visibleRows(), (row: ExchangeRateRow) => { ListItem() { this.rateRow(row) } }, (row: ExchangeRateRow) => exchangeRateRowKey(this.baseCode, row))
        if (!this.loading && !this.error && this.rows.length > 0 && this.visibleRows().length === 0) {
          ListItem() { Text('没有匹配的币种').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%').textAlign(TextAlign.Center).padding(24) }
        }
      }.width('100%').height(LayoutPolicy.matchParent).padding({ left: 16, right: 16 }).contentStartOffset(12).contentEndOffset(24)
        .clip(false).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .dynamicHideTitleBar({ hideTitleArea: false, hideBottomBuilder: false, hideStatusBar: false })
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '汇率查询' }, backIcon: { action: () => { this.onClose(); } },
          menu: { maxCount: 1, value: [{ content: { icon: $r('app.media.lucide_refresh_cw1'), label: '重新读取', isEnabled: !this.loading, action: () => { this.reload(true); } } }] },
          divider: { showType: DividerShowType.OFF } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
          backIconStyle: { iconColor: $r('app.color.xq_icon_primary') }, menuStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
            backIconStyle: { iconColor: $r('app.color.xq_icon_primary') }, menuStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .bindToScrollable([this.scroller]).systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .width('100%').height(LayoutPolicy.matchParent).backgroundColor($r('app.color.xq_app_surface_page'))
  }
}
