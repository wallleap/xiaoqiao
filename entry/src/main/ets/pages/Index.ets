import { LengthMetrics, ChipGroup, ChipSize, IconGroupSuffix } from '@kit.ArkUI';
import { HdsTabs, hdsMaterial, HdsNavigation, HdsNavigationTitleMode, HdsListItemCard,
  PrefixImage, SuffixCustomBuilder, HdsSnackBar, SnackBarOperationType, ScrollEffectType, DividerShowType } from '@kit.UIDesignKit';
import { AmountText } from '../components/AmountText';
import { LedgerEntry, LedgerKind, displayAmount, filterEntries, previewEntries } from '../presentation/ledger/LedgerOverview';

@Entry
@Component
struct Index {
  @StorageProp('ledgerPreview') private preview: boolean = false;
  @StorageProp('ledgerScrollPreview') private scrollPreview: boolean = false;
  @State private kind: LedgerKind = LedgerKind.All;
  @State private keyword: string = '';
  @State private showSearch: boolean = false;
  @State private showSelection: boolean = false;
  @State private selectionKind: number = 0;
  @State private account: string = '';
  @State private pendingAccount: string = '';
  @State private viewportWidth: number = 390;
  @State private recordWidth: number = 358;
  @State private darkTitleBar: boolean = false;
  private readonly bodyScroller: Scroller = new Scroller();
  private snackBar: HdsSnackBar | undefined = undefined;
  private readonly labels: string[] = ['账目', '统计', '记一笔', '资产', '设置'];
  private readonly tabIcons: Resource[] = [$r('app.media.lucide_house1'),
    $r('app.media.lucide_chart_no_axes_combined1'), $r('app.media.lucide_plus1'),
    $r('app.media.lucide_wallet1'), $r('app.media.lucide_settings1')];

  private entries(): LedgerEntry[] {
    return filterEntries(this.preview ? previewEntries(this.scrollPreview) : [], this.kind, this.keyword, this.account);
  }

  private month(): string {
    const now = new Date();
    return this.preview ? '2026年10月' : `${now.getFullYear()}年${now.getMonth() + 1}月`;
  }

  aboutToAppear(): void {
    const fonts = this.getUIContext().getFont();
    fonts.registerFont({ familyName: 'XiaoQiaoDINRegular',
      familySrc: $rawfile('fonts/D-DIN-PRO-400-Regular.ttf') });
    fonts.registerFont({ familyName: 'XiaoQiaoDINMedium',
      familySrc: $rawfile('fonts/D-DIN-PRO-500-Medium.ttf') });
  }

  aboutToDisappear(): void {
    this.snackBar?.dismiss();
  }

  private notify(message: string): void {
    if (this.snackBar === undefined) {
      this.snackBar = new HdsSnackBar(this.getUIContext());
    }
    this.snackBar.dismiss();
    this.snackBar.show({}, { content: message }, {
      operationType: SnackBarOperationType.CLOSE_BUTTON_ONLY,
      onCloseButtonClick: () => { this.snackBar?.dismiss(); }, closeButtonAccessibilityText: '关闭提示'
    }, { duration: 3000 });
  }

  @Builder
  private bookTitle() {
    Row() {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          Text('日常账本').fontSize('24fp').fontWeight(FontWeight.Bold)
            .fontColor(this.darkTitleBar ? $r('app.color.xq_font_on_primary') : $r('app.color.xq_font_primary'))
          Image($r('app.media.lucide_chevron_down1')).width(18).height(18)
            .fillColor(this.darkTitleBar ? $r('app.color.xq_icon_on_primary') : $r('app.color.xq_icon_primary'))
        }
      }.id('ledger-book-selector').backgroundColor(Color.Transparent).padding(0).height(48)
      .accessibilityText('选择账本，当前日常账本').onClick(() => { this.selectionKind = 0; this.showSelection = true; })
    }.width('100%').padding({ left: this.viewportWidth >= 600 ? 32 : 16, right: 56 })
  }

  @Builder
  private header() {
    Row({ space: 8 }) {
      Text(this.month()).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
      Text('·').fontSize('12fp').fontColor($r('app.color.xq_font_tertiary'))
      Text('CNY').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
    }.id('ledger-period').width('100%').margin({ top: 2, bottom: 16 })
    if (this.showSearch) {
      Search({ value: this.keyword, placeholder: '搜索备注、分类或账户' })
        .id('ledger-search').onChange((value: string) => { this.keyword = value; })
        .height(48).margin({ bottom: 16 })
    }
  }

  @Builder
  private summary() {
    Column({ space: 16 }) {
      Row() {
        Text(this.preview ? '本月预算剩余' : '本月预算').fontSize('14fp')
          .fontColor($r('app.color.xq_font_on_secondary'))
        Blank()
        Button({ type: ButtonType.Normal }) {
          Row({ space: 6 }) {
            Text() {
              Span(this.preview ? '预算 ' : '设置预算')
              if (this.preview) {
                Span('¥')
                Span('3,000.00').fontFamily('XiaoQiaoDINRegular')
              }
            }.fontSize('12fp')
              .fontColor($r('app.color.xq_font_on_secondary'))
            Image($r('app.media.lucide_pencil1')).width(14).height(14)
              .fillColor($r('app.color.xq_icon_on_secondary'))
          }
        }.height(32).padding(0).backgroundColor(Color.Transparent)
        .accessibilityText('修改本月预算')
        .onClick(() => { this.notify('预算编辑将在预算页面接入'); })
      }.width('100%')
      Row({ space: 12 }) {
        if (this.preview) {
          AmountText({ amount: '514.00', amountSize: 38, color: $r('app.color.xq_font_on_primary') }).layoutWeight(1)
          Stack() {
            Progress({ value: 82.9, total: 100, type: ProgressType.Ring })
              .width(64).height(64).color($r('app.color.xq_app_summary_accent')).style({ strokeWidth: 6 })
            Text('82.9%').fontFamily('XiaoQiaoDINMedium').fontSize('12fp').fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.xq_app_summary_accent'))
          }.accessibilityText('预算已使用百分之82.9')
        } else {
          Column({ space: 6 }) {
            Text('给开支一个小目标').fontSize('24fp').fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.xq_font_on_primary'))
            Text('设置预算，掌握每月花费').fontSize('12fp').fontColor($r('app.color.xq_font_on_secondary'))
          }.width('100%').alignItems(HorizontalAlign.Start)
        }
      }.width('100%').constraintSize({ minHeight: 64 })
      Row({ space: 16 }) {
        Row({ space: 6 }) {
          Image($r('app.media.lucide_arrow_down1')).width(16).height(16).fillColor('#55C9A5')
          AmountText({ amount: this.preview ? '8,600.00' : '0.00', amountSize: 14,
            color: $r('app.color.xq_font_on_secondary') })
        }.layoutWeight(1).accessibilityText('本月收入')
        Row({ space: 6 }) {
          Image($r('app.media.lucide_arrow_up1')).width(16).height(16).fillColor($r('app.color.xq_app_summary_accent'))
          AmountText({ amount: this.preview ? '2,486.00' : '0.00', amountSize: 14,
            color: $r('app.color.xq_font_on_secondary') })
        }.layoutWeight(1).justifyContent(FlexAlign.End).accessibilityText('本月支出')
      }.width('100%')
    }.id('ledger-summary').padding(16).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_summary'))
  }

  @Builder
  private entryAmount(entry: LedgerEntry) {
    AmountText({ amount: displayAmount(entry.minor), amountSize: 16, sign: entry.income ? '+' : '−',
      color: entry.income ? $r('app.color.xq_app_income') : $r('app.color.xq_font_primary') })
      .padding({ right: 16 }).constraintSize({ maxWidth: 160 })
  }

  @Builder
  private ledgerRow(entry: LedgerEntry) {
    HdsListItemCard({
      cardId: entry.id,
      cardWidth: this.recordWidth, cardHeight: 76, cardBorderRadius: 16,
      cardPrefixMargin: 16, cardSuffixMargin: 16,
      cardBackgroundColor: $r('app.color.xq_app_surface_card'),
      prefixItem: new PrefixImage({ image: entry.icon }),
      textItem: {
        primaryText: { text: entry.title },
        secondaryText: { text: `${entry.time} · ${entry.category} · ${entry.account}` }
      },
      suffixItem: new SuffixCustomBuilder(() => { this.entryAmount(entry); })
    }).id(entry.id).width('100%')
  }

  @Builder
  private emptyState() {
    Column({ space: 12 }) {
      Image($r('app.media.lucide_notebook_pen1')).width(52).height(52)
        .fillColor($r('app.color.xq_icon_tertiary')).margin({ bottom: 8 })
      Text(this.preview ? '没有符合条件的账目' : '从第一笔开始')
        .fontSize('20fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
      Text(this.preview ? '试试其他关键词或筛选条件' : '把日常收支，慢慢记清楚')
        .fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
      if (!this.preview) {
        Button('开始记第一笔账').height(44).fontSize('16fp').fontColor(Color.White)
          .linearGradient({ angle: 110, colors: [[$r('app.color.xq_app_gradient_start'), 0],
            [$r('app.color.xq_app_gradient_end'), 1]] }).borderRadius(22).margin({ top: 12 })
          .onClick(() => { this.notify('记一笔页面将在下一步接入'); })
      }
    }.width('100%').padding({ top: 52, bottom: 48, left: 16, right: 16 })
  }

  @Builder
  private filterSuffix() {
    IconGroupSuffix({ items: [{
      icon: { src: $r('app.media.lucide_list_filter1'), size: { width: 24, height: 24 } },
      accessibilityText: this.account.length > 0 ? '筛选账目，已生效' : '筛选账目',
      action: () => {
        this.pendingAccount = this.account;
        this.selectionKind = 1;
        this.showSelection = true;
      }
    }] }).id('ledger-filter-action')
  }

  @Builder
  private records() {
    Column({ space: 12 }) {
      ChipGroup({
        items: [
          { label: { text: '全部' }, allowClose: false },
          { label: { text: '支出' }, allowClose: false },
          { label: { text: '收入' }, allowClose: false }
        ],
        multiple: false,
        selectedIndexes: [this.kind],
        itemStyle: {
          size: ChipSize.NORMAL,
          backgroundColor: $r('app.color.xq_app_surface_card'),
          fontColor: $r('app.color.xq_font_secondary'),
          selectedBackgroundColor: $r('app.color.xq_brand'),
          selectedFontColor: $r('app.color.xq_font_on_primary')
        },
        chipGroupSpace: { startSpace: 0, endSpace: 0, itemSpace: 8 },
        chipGroupPadding: { top: 4, bottom: 4 },
        onChange: (selected: number[]) => {
          if (selected.length === 1) {
            this.kind = selected[0] === 1 ? LedgerKind.Expense :
              selected[0] === 2 ? LedgerKind.Income : LedgerKind.All;
          }
        },
        suffix: this.filterSuffix.bind(this)
      }).id('ledger-filters').width('100%')
      if (this.account.length > 0) {
        Text(`账户：${this.account}`).fontSize('12fp').fontColor($r('app.color.xq_font_emphasize')).width('100%')
      }
      if (this.entries().length === 0) {
        this.emptyState()
      } else {
        ForEach(this.entries(), (entry: LedgerEntry, index: number) => {
          if (index === 0 || entry.date !== this.entries()[index - 1].date) {
            Text(entry.date.substring(5).replace('-', '月') + '日')
              .fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
          }
          this.ledgerRow(entry)
        }, (entry: LedgerEntry) => entry.id)
      }
    }.width('100%').onAreaChange((_previous: Area, current: Area) => {
      const available = Number(current.width);
      if (available > 0) { this.recordWidth = available; }
    })
  }

  @Builder
  private overview() {
    Scroll(this.bodyScroller) {
      Column({ space: 0 }) {
        this.header()
        if (this.viewportWidth >= 720) {
          Row({ space: 24 }) {
            Column() { this.summary() }.width(320).alignSelf(ItemAlign.Start)
            Column() { this.records() }.layoutWeight(1)
          }.width('100%').alignItems(VerticalAlign.Top)
        } else {
          this.summary()
          Column() { this.records() }.margin({ top: 12 }).width('100%')
        }
      }.width('100%').constraintSize({ maxWidth: 1040 })
        .padding({ left: this.viewportWidth >= 600 ? 32 : 16, right: this.viewportWidth >= 600 ? 32 : 16,
          top: 68, bottom: 112 })
    }.id('ledger-scroll').width('100%').height('100%')
      .scrollable(ScrollDirection.Vertical).enableScrollInteraction(true)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onDidScroll(() => {
        // Match the midpoint of the native 0–56vp title-bar transition.
        const dark = this.bodyScroller.currentOffset().yOffset >= 28;
        if (this.darkTitleBar !== dark) { this.darkTitleBar = dark; }
      })
      .scrollBar(BarState.Off).align(Alignment.Top)
  }

  @Builder
  private tabItem(index: number) {
    if (index === 2) {
      Button({ type: ButtonType.Circle }) {
        Image(this.tabIcons[index]).width(28).height(28).fillColor(Color.White)
      }.width(52).height(52).accessibilityText('记一笔')
        .linearGradient({ angle: 110, colors: [[$r('app.color.xq_app_gradient_start'), 0],
          [$r('app.color.xq_app_gradient_end'), 1]] })
        .onClick(() => { this.notify('记一笔页面将在下一步接入'); })
    } else {
      Column({ space: 4 }) {
        Image(this.tabIcons[index]).width(22).height(22)
          .fillColor(index === 0 ? $r('app.color.xq_icon_emphasize') : $r('app.color.xq_icon_secondary'))
        Text(this.labels[index]).fontSize('10fp')
          .fontColor(index === 0 ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_secondary'))
      }.id(`ledger-tab-${index}`).height(56).width('100%').justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  private bookSheet() {
    Column({ space: 16 }) {
      Text('选择账本').fontSize('20fp').fontWeight(FontWeight.Bold).width('100%')
      Row() {
        Text('日常账本').fontSize('16fp').layoutWeight(1)
        Text('当前账本').fontSize('12fp').fontColor($r('app.color.xq_font_emphasize'))
      }.height(56).width('100%').onClick(() => { this.showSelection = false; })
      Text('账本管理将在后续接入').fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
    }.padding(24).width('100%')
  }

  @Builder
  private filterSheet() {
    Column({ space: 20 }) {
      Text('筛选账目').fontSize('20fp').fontWeight(FontWeight.Bold).width('100%')
      Text('资金账户').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      ForEach(this.preview ? ['', '微信零钱', '日常储蓄卡'] : [''], (name: string) => {
        Row() {
          Text(name.length > 0 ? name : '全部账户').fontSize('16fp').layoutWeight(1)
          Radio({ value: name, group: 'account' })
            .radioStyle({ checkedBackgroundColor: $r('app.color.xq_brand'), indicatorColor: Color.White })
            .checked(this.pendingAccount === name)
            .onChange((checked: boolean) => { if (checked) { this.pendingAccount = name; } })
        }.width('100%').height(44).onClick(() => { this.pendingAccount = name; })
      }, (name: string) => name)
      Row({ space: 12 }) {
        Button('重置').layoutWeight(1).height(48)
          .backgroundColor($r('app.color.xq_app_surface_page')).fontColor($r('app.color.xq_font_primary')).onClick(() => { this.pendingAccount = ''; })
        Button('完成').layoutWeight(1).height(48).backgroundColor($r('app.color.xq_brand')).fontColor(Color.White)
          .onClick(() => { this.account = this.pendingAccount; this.showSelection = false; })
      }.width('100%')
    }.width('100%').padding(24)
  }

  @Builder
  private selectionSheet() {
    if (this.selectionKind === 0) {
      this.bookSheet()
    } else {
      this.filterSheet()
    }
  }

  build() {
    HdsNavigation() {
      HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
        TabContent() { this.overview() }.tabBar(this.tabItem(0))
        TabContent() {}.tabBar(this.tabItem(1))
        TabContent() {}.tabBar(this.tabItem(2))
        TabContent() {}.tabBar(this.tabItem(3))
        TabContent() {}.tabBar(this.tabItem(4))
      }.width('100%').height('100%').scrollable(false).barHeight(64).barOverlap(true)
      .barFloatingStyle({ barSideMargin: 16, barBottomMargin: 12,
        systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE } })
      .onContentWillChange((_current: number, next: number): boolean => {
        if (next !== 0) {
          this.notify(next === 2 ? '记一笔页面将在下一步接入' : `${this.labels[next]}页面尚未接入`);
          return false;
        }
        return true;
      })
      .backgroundColor($r('app.color.xq_app_surface_page'))
      .onAreaChange((_oldArea: Area, newArea: Area) => { this.viewportWidth = Number(newArea.width); })
    }
    .mode(NavigationMode.Stack).hideBackButton(true).titleMode(HdsNavigationTitleMode.MINI)
    .dynamicHideTitleBar({ hideTitleArea: false, hideBottomBuilder: false, hideStatusBar: false })
    .bindToScrollable([this.bodyScroller])
    .systemBarStyle({ statusBarContentColor: '#E5000000' }, { statusBarContentColor: '#FFFFFFFF' })
    .titleBar({
      content: {
        title: { mainTitle: '' },
        divider: { showType: DividerShowType.OFF },
        stackBuilder: this.bookTitle.bind(this),
        menu: { value: [{ content: {
          icon: $r('app.media.lucide_search1'), componentId: '搜索账目', label: '搜索账目',
          action: () => {
            if (this.showSearch) { this.keyword = ''; }
            this.showSearch = !this.showSearch;
            this.bodyScroller.scrollTo({ xOffset: 0, yOffset: 0 });
          }
        } }] }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(56)
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent, maskExtraHeight: 32, blurRadius: 0 },
          contentStyle: {
            titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
            menuStyle: { iconColor: $r('app.color.xq_icon_primary') }
          }
        },
        scrollEffectStyle: {
          // ArkUI uses #AARRGGBB: a translucent gray softens the dark scroll mask.
          backgroundStyle: { backgroundColor: '#BF454D52', maskExtraHeight: 32, blurRadius: 24 },
          contentStyle: {
            titleStyle: { mainTitleColor: $r('app.color.xq_font_on_primary') },
            menuStyle: { iconColor: $r('app.color.xq_icon_on_primary') }
          }
        }
      }
    })
    .backgroundColor($r('app.color.xq_app_surface_page'))
    .bindSheet($$this.showSelection, this.selectionSheet(),
      { height: this.selectionKind === 0 ? 280 : 440, showClose: true,
        backgroundColor: $r('app.color.xq_app_surface_card') })
  }
}
