import { CategoryIconBadge } from './CategoryIconBadge';
import { AccountProfile } from '../domain/model/AccountProfile';
import { LedgerSearchCursor } from '../domain/model/LedgerSearch';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType, BottomBuilderShowType } from '@kit.UIDesignKit';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { LedgerEntry, presentEntry, displayAmount } from '../presentation/ledger/LedgerOverview';
import { Money } from '../core/money/Money';
import { currencyUnit, currencyDefinition } from '../core/money/Currencies';

@Component
export struct LedgerSearchPage {
  workspace: LedgerWorkspace | undefined = undefined;
  accounts: AccountProfile[] = [];
  chipMaterial: SystemUiMaterial | undefined = undefined;
  menuMaterial: SystemUiMaterial | undefined = undefined;
  @State private accountId: string = '';
  @Prop @Watch('reload') refreshToken: number = 0;
  onClose: () => void = () => {};
  onOpenEntry: (entry: LedgerEntry) => void = () => {};
  @State private keyword: string = '';
  @State private entries: LedgerEntry[] = [];
  @State private loading: boolean = false;
  @State private hasMore: boolean = false;
  private cursor: LedgerSearchCursor | undefined = undefined;
  private searchTimer: number = -1;
  private active: boolean = false;
  @State private error: string = '';
  private request: number = 0;
  private focusTimer: number = -1;
  private readonly controller: SearchController = new SearchController();
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.active = true; this.reload(); }
  aboutToDisappear(): void {
    this.active = false; this.request++;
    if (this.searchTimer !== -1) { clearTimeout(this.searchTimer); this.searchTimer = -1; }
    if (this.focusTimer !== -1) { clearTimeout(this.focusTimer); this.focusTimer = -1; }
  }
  private focusSearch(): void {
    if (this.focusTimer !== -1) { clearTimeout(this.focusTimer); }
    this.focusTimer = setTimeout(() => {
      this.focusTimer = -1;
      this.getUIContext().getFocusController().requestFocus('ledger-search-input');
    }, 100);
  }
  private close(): void {
    this.controller.stopEditing(); this.onClose();
  }
  private queueSearch(): void {
    this.request++;
    if (this.searchTimer !== -1) { clearTimeout(this.searchTimer); }
    this.entries = []; this.cursor = undefined; this.hasMore = false; this.error = '';
    this.loading = this.keyword.trim().length > 0;
    this.searchTimer = setTimeout(() => { this.searchTimer = -1; this.reload(); }, 250);
  }
  private reload(): void {
    if (this.searchTimer !== -1) { clearTimeout(this.searchTimer); this.searchTimer = -1; }
    this.entries = []; this.cursor = undefined; this.hasMore = false;
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.fetchPage(false);
  }
  private async fetchPage(append: boolean): Promise<void> {
    if (!this.active || !this.workspace) { return; }
    if (append && (this.loading || !this.hasMore)) { return; }
    const query = this.keyword.trim();
    const request = ++this.request;
    this.error = '';
    if (!query) { this.loading = false; return; }
    this.loading = true;
    try {
      const page = await this.workspace.searchEntries(query, append ? this.cursor : undefined, 50, this.accountId);
      if (this.active && request === this.request) {
        const values = page.entries.map(presentEntry);
        this.entries = append ? this.entries.concat(values) : values;
        this.cursor = page.nextCursor; this.hasMore = page.hasMore;
      }
    } catch (_) {
      if (this.active && request === this.request) { this.error = '搜索暂时失败，请重试'; }
    } finally { if (this.active && request === this.request) { this.loading = false; } }
  }
  private amount(entry: LedgerEntry): string {
    const sign = entry.prepaidId ? (entry.prepaidKind === 'refund' ? '+' : '−') : entry.recoveryKind || entry.income ? '+' : entry.transfer ? '' : '−';
    if (entry.fx) {
      return sign + currencyDefinition(entry.fx.currencyId).symbol + Money.fromMinorText(entry.fx.paidMinor, currencyUnit(entry.fx.currencyId)).toDecimalString();
    }
    return sign + '¥' + displayAmount(entry.recoveryKind ? (-BigInt(entry.minor)).toString() : entry.minor);
  }
  @Builder
  private resultRow(entry: LedgerEntry) {
    Row({ space: 12 }) {
      CategoryIconBadge({ icon: entry.icon, badgeSize: 44, glyphSize: 28 })
      Column({ space: 5 }) {
        Text(entry.title).fontSize('15fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(entry.date.replace(/-/g, '/') + ' ' + entry.time + (entry.account && entry.account !== '不使用账户' ? ' · ' + entry.account : ''))
          .fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(this.amount(entry)).fontSize('16fp').fontFamily('XiaoQiaoDINMedium')
        .fontColor(entry.prepaidId || entry.transfer ? $r('app.color.xq_font_primary') : entry.income || entry.recoveryKind ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
        .maxLines(1).constraintSize({ maxWidth: '42%' })
    }.width('100%').padding(16).borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      .onClick(() => { this.controller.stopEditing(); this.onOpenEntry(entry); })
  }
  @Builder
  private titleSearch() {
    Row() {
      Search({ value: this.keyword, placeholder: '搜索备注、收支分类、账户或标签', controller: this.controller })
          .id('ledger-search-input').width('100%').height(44).borderRadius(22)
          .backgroundColor(this.chipMaterial !== undefined ? Color.Transparent : $r('app.color.xq_app_surface_card'))
          .systemMaterial(this.chipMaterial).textFont({ size: '14fp' }).placeholderFont({ size: '14fp' })
          .fontColor($r('app.color.xq_font_primary')).placeholderColor($r('app.color.xq_font_secondary'))
          .searchIcon({ src: $r('app.media.lucide_search1'), size: 18, color: $r('app.color.xq_icon_secondary') })
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: { src: $r('app.media.lucide_x1'), size: 18, color: $r('app.color.xq_icon_secondary') } })
          .enableKeyboardOnFocus(true)
          .onAppear(() => { this.focusSearch(); })
          .maxLength(200).onChange((value: string) => { this.keyword = value; this.queueSearch(); })
          .onSubmit(() => { this.controller.stopEditing(); this.reload(); })
    }.width('100%').height(56).alignItems(VerticalAlign.Center)
      .padding({ left: 64, right: 16 }).hitTestBehavior(HitTestMode.Transparent)
  }

  private selectAccount(id: string): void {
    if (id === this.accountId) { return; }
    this.accountId = id; this.reload();
  }
  private accountMenuOptions(): MenuOptions {
    const options: MenuOptions = { placement: Placement.BottomLeft };
    if (this.menuMaterial !== undefined) { options.systemMaterial = this.menuMaterial; }
    return options;
  }
  @Builder
  private accountMenu() {
    Menu() {
      MenuItem({ content: this.accountId ? '全部账户' : '✓ 全部账户' })
        .contentFontColor(!this.accountId ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_primary'))
        .onClick(() => { this.selectAccount(''); })
      ForEach(this.accounts, (account: AccountProfile) => {
        MenuItem({ content: (this.accountId === account.id ? '✓ ' : '') + account.name + ' · ' + account.currencyId + (account.archived ? '（已归档）' : '') })
          .contentFontColor(this.accountId === account.id ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_primary'))
          .onClick(() => { this.selectAccount(account.id); })
      }, (account: AccountProfile) => account.id)
    }
  }
  @Builder
  private accountFilter() {
    Row() {
      Button({ type: ButtonType.Capsule }) {
        Row({ space: 6 }) {
          Text(this.accountId ? this.accounts.find((account: AccountProfile) => account.id === this.accountId)?.name || '已选账户' : '全部账户')
            .fontSize('13fp').fontColor(this.accountId ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Image($r('app.media.lucide_chevron_down1')).width(12).height(12).fillColor($r('app.color.xq_icon_secondary'))
        }
      }.height(32).padding({ left: 12, right: 12 }).constraintSize({ maxWidth: '80%' })
        .backgroundColor(this.chipMaterial !== undefined ? Color.Transparent : $r('app.color.xq_app_surface_card'))
        .systemMaterial(this.chipMaterial).id('search-account-filter')
        .onClick(() => { this.controller.stopEditing(); })
        .bindMenu(this.accountMenu, this.accountMenuOptions())
      Blank()
    }.width('100%').height(48).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)
  }

  build() {
    HdsNavigation() {
      // Follow the HDS navigation example: bind the direct scrollable child so
      // the component safe area reserves both the title and bottomBuilder.
      List({ space: 12, scroller: this.scroller }) {
        if (!this.keyword.trim()) {
          ListItem() { Text('输入关键词搜索全部账单').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%').textAlign(TextAlign.Center).padding(24) }
        } else {
          ForEach(this.entries, (entry: LedgerEntry) => { ListItem() { this.resultRow(entry) } }, (entry: LedgerEntry) => entry.id)
          if (this.loading) { ListItem() { Text('正在搜索…').fontSize('14fp').padding(24) } }
          else if (this.error) {
            ListItem() { Button(this.error + ' · 重试').fontSize('14fp').onClick(() => { if (this.entries.length > 0) { this.fetchPage(true); } else { this.reload(); } }) }
          } else if (this.entries.length === 0) {
            ListItem() { Text('没有找到相关账单').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%').textAlign(TextAlign.Center).padding(24) }
          } else if (!this.hasMore) {
            ListItem() {
              Text('没有更多了').fontSize('12fp').fontColor($r('app.color.xq_font_tertiary'))
                .width('100%').textAlign(TextAlign.Center).padding({ top: 24, bottom: 16 })
            }
          }
        }
      }.width('100%').height('100%').padding({ left: 16, right: 16 })
        .contentStartOffset(12).contentEndOffset(24)
        .clip(false).cachedCount(3, true)
        .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => { if (!this.error) { this.fetchPage(true); } })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .dynamicHideTitleBar({ hideTitleArea: false, hideBottomBuilder: false, hideStatusBar: false })
      .titleBar({ enableComponentSafeArea: true, content: { title: { mainTitle: '' }, stackBuilder: this.titleSearch.bind(this),
        bottomBuilder: { builder: this.accountFilter.bind(this), height: 48, showType: BottomBuilderShowType.DIRECTLY_SHOW }, divider: { showType: DividerShowType.OFF }, backIcon: { action: () => { this.close(); } } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
  }
}
