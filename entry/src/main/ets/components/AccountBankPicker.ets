import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType, BottomBuilderShowType } from '@kit.UIDesignKit';
import { BANK_ACCOUNT_STYLES, BankAccountStyle } from '../domain/model/BankAccountStyles';
import { ACCOUNT_STYLES, AccountStyle } from '../domain/model/AccountProfile';
import { AccountAvatar } from './AccountAvatar';

/** Native alphabet index + grouped list, following ArkUI's list navigation API. */
@Component
export struct AccountBankPicker {
  onBack: () => void = () => {};
  searchMaterial: SystemUiMaterial | undefined = undefined;
  statusBarContentColor: string = '#E5000000';
  onSelectBank: (key: string) => void = () => {};
  @Prop accountKind: string = 'asset';
  scroller: Scroller = new Scroller();
  @Link @Watch('resetIndex') query: string;
  @State private selectedLetter: number = 0;

  private resetIndex(): void { this.selectedLetter = 0; }
  private commonBanks(): BankAccountStyle[] {
    const names: string[] = ['工商银行', '农业银行', '中国银行', '建设银行', '交通银行', '中国邮政储蓄银行', '招商银行'];
    const result: BankAccountStyle[] = [];
    for (const name of names) {
      const bank = BANK_ACCOUNT_STYLES.find((item: BankAccountStyle) => item.name === name && item.variant === 'monochrome' && !item.historical);
      if (bank !== undefined) { result.push(bank); }
    }
    return result;
  }
  private banks(): BankAccountStyle[] {
    const query = this.query.trim().toLowerCase();
    return BANK_ACCOUNT_STYLES.filter((item: BankAccountStyle) => item.variant === 'monochrome' && !item.historical &&
      (!query || (item.name + ' ' + (item.searchText || '')).toLowerCase().includes(query)));
  }
  private letters(): string[] {
    const letters: string[] = [];
    for (const item of this.banks()) {
      const letter = item.indexLetter || '#';
      if (!letters.includes(letter)) { letters.push(letter); }
    }
    return this.query.trim().length === 0 ? ['常用'].concat(letters.sort()) : letters.sort();
  }
  private group(letter: string): BankAccountStyle[] {
    if (letter === '常用') { return this.commonBanks(); }
    return this.banks().filter((item: BankAccountStyle) => item.indexLetter === letter);
  }
  private select(key: string): void {
    try { this.getUIContext().getFocusController().clearFocus(); } catch (_) {}
    this.onSelectBank(key);
  }
  @Builder
  private groupTitle(letter: string) {
    Text(letter).fontSize('13fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_secondary'))
      .width('100%').padding({ left: 12, top: 12, bottom: 8 })
  }
  private otherBankStyle(): AccountStyle | undefined {
    const key = this.accountKind === 'liability' ? 'credit_card' : 'bank_card';
    return ACCOUNT_STYLES.find((item: AccountStyle) => item.key === key);
  }
  @Builder
  private otherBankRow() {
    Row({ space: 12 }) {
      AccountAvatar({ iconKey: this.otherBankStyle()?.key || 'bank_card',
        brandColor: this.otherBankStyle()?.color || '#5378B8', diameter: 36 })
      Text('其他银行').fontSize('15fp').fontColor($r('app.color.xq_font_primary')).layoutWeight(1)
    }.width('100%').padding(12)
      .onClick(() => { this.select('other_bank'); })
  }
  @Builder
  private bankSearch() {
    Row() {
      Search({ value: this.query, placeholder: '搜索银行名称或简称' })
        .height(44).width('100%').borderRadius(22)
        .backgroundColor(this.searchMaterial !== undefined ? Color.Transparent : $r('app.color.xq_app_surface_card'))
        .systemMaterial(this.searchMaterial).textFont({ size: '14fp' }).placeholderFont({ size: '14fp' })
        .fontColor($r('app.color.xq_font_primary')).placeholderColor($r('app.color.xq_font_secondary'))
        .searchIcon({ src: $r('app.media.lucide_search1'), size: 18, color: $r('app.color.xq_icon_secondary') })
        .cancelButton({ style: CancelButtonStyle.INPUT, icon: { src: $r('app.media.lucide_x1'), size: 18, color: $r('app.color.xq_icon_secondary') } })
        .onChange((value: string) => { this.query = value; })
    }.width('100%').height(60).padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  private bankIndex() {
    Column() {
      if (this.letters().length > 0) {
      AlphabetIndexer({ arrayValue: this.letters(), selected: this.selectedLetter })
        .selected(this.selectedLetter).itemSize(16).font({ size: '10fp' })
        .color($r('app.color.xq_font_secondary')).selectedColor($r('app.color.xq_font_on_primary'))
        .selectedBackgroundColor($r('app.color.xq_brand'))
        .width(24)
        .onSelect((index: number) => { this.selectedLetter = index; this.scroller.scrollToIndex(index); })
      }
    }.width(28).height(this.letters().length * 16 + 16)
      .margin({ right: 4 }).translate({ y: 40 }).zIndex(2)
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .visibility(this.letters().length > 0 ? Visibility.Visible : Visibility.Hidden)
  }
  build() {
    // Render the index as a real sibling, not a custom overlay on a native
    // navigation/list node. Only this narrow column intercepts index touches.
    Stack({ alignContent: Alignment.End }) {
    HdsNavigation() {
      // Bind the direct List to HDS; intermediate full-height rows/columns
      // prevent the list from extending beneath the immersive title area.
      List({ scroller: this.scroller }) {
        if (this.banks().length === 0) {
          ListItem() {
            Column() {
              Text('没有匹配的银行').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).padding(24)
              this.otherBankRow()
            }.width('100%')
          }
        } else {
          ForEach(this.letters(), (letter: string) => {
            ListItemGroup({ header: this.groupTitle(letter) }) {
              ForEach(this.group(letter), (bank: BankAccountStyle, index: number) => {
                ListItem() {
                  Column() {
                    Row({ space: 12 }) {
                      AccountAvatar({ iconKey: bank.preferredVariant === 'color' ? bank.key + '_color' : bank.key,
                        iconVariant: bank.preferredVariant || 'monochrome', brandColor: bank.color, diameter: 36 })
                      Text(bank.name).fontSize('15fp').fontColor($r('app.color.xq_font_primary')).layoutWeight(1).maxLines(2)
                    }.width('100%').padding(12).onClick(() => { this.select(bank.key); })
                    if (letter === '常用' || index < this.group(letter).length - 1) {
                      Divider().color($r('app.color.xq_app_divider_subtle')).strokeWidth(0.5).margin({ left: 60 })
                    }
                  }.width('100%')
                }
              }, (bank: BankAccountStyle) => bank.key)
              if (letter === '常用') {
                ListItem() { this.otherBankRow() }
              }
            }
          }, (letter: string) => letter)
        }
      }.width('100%').height('100%').padding({ left: 16, right: 36 })
        .contentStartOffset(12).contentEndOffset(24).clip(false)
        .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onScrollIndex((first: number) => { this.selectedLetter = first; })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .dynamicHideTitleBar({ hideTitleArea: false, hideBottomBuilder: false, hideStatusBar: false })
      .titleBar({ enableComponentSafeArea: true, avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '选择发卡行' },
          bottomBuilder: { builder: this.bankSearch.bind(this), height: 60, showType: BottomBuilderShowType.DIRECTLY_SHOW },
          divider: { showType: DividerShowType.OFF }, backIcon: { action: () => { this.onBack(); } } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
          backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
            backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .bindToScrollable([this.scroller])
      .systemBarStyle({ statusBarContentColor: this.statusBarContentColor }, { statusBarContentColor: this.statusBarContentColor })
      .width('100%').height('100%').backgroundColor($r('app.color.xq_app_surface_page'))
      this.bankIndex()
    }.width('100%').height('100%').backgroundColor($r('app.color.xq_app_surface_page'))
      // The outer host spans the window; HDS alone reserves the system and
      // title component safe areas. Do not also ignore them on HDS itself.
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}
