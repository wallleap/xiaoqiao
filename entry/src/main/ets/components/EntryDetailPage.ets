import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { transferPurposeLabel } from '../domain/model/TransferRecord';
import { EntryDetail } from '../domain/model/EntryDetail';
import { TagChoice } from '../domain/model/LedgerSnapshot';
import { Money } from '../core/money/Money';
import { CurrencyUnit } from '../core/money/CurrencyUnit';
import { categoryIcon } from '../presentation/ledger/CategoryIcons';

@Component
export struct EntryDetailPage {
  @Prop entry: EntryDetail | undefined = undefined;
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop busy: boolean = false;
  onClose: () => void = () => {};
  onEdit: () => void = () => {};
  onDelete: () => void = () => {};
  onRetry: () => void = () => {};
  private readonly scroller: Scroller = new Scroller();

  private amount(minor: string): string {
    const entry = this.entry;
    if (entry === undefined) { return '—'; }
    const decimal = Money.fromMinorText(minor, new CurrencyUnit(entry.currencyId, entry.currencyCode, entry.currencyScale)).toDecimalString();
    const parts = decimal.split('.');
    return parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',') + (parts.length > 1 ? '.' + parts[1] : '');
  }

  private dateText(): string {
    if (this.entry === undefined) { return ''; }
    const local = new Date(this.entry.occurredAtMs + this.entry.offsetMinutes * 60000);
    return this.entry.localDate + ' ' + String(local.getUTCHours()).padStart(2, '0') + ':' + String(local.getUTCMinutes()).padStart(2, '0');
  }

  @Builder
  private field(label: string, value: string) {
    Row({ space: 16 }) {
      Text(label).fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
      Blank()
      Text(value).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).textAlign(TextAlign.End)
        .constraintSize({ maxWidth: '68%' }).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%').padding({ top: 9, bottom: 9 })
  }

  @Builder
  private transferAccount(outgoing: boolean) {
    Row({ space: 16 }) {
      Text(outgoing ? '转出账户' : '转入账户').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
      Blank()
      Text((outgoing ? this.entry?.accountName : this.entry?.toAccountName) || '—').fontSize('14fp')
        .fontColor($r('app.color.xq_font_primary')).textAlign(TextAlign.End).maxLines(3).constraintSize({ maxWidth: '68%' })
        .id(outgoing ? 'entry-detail-from-account' : 'entry-detail-to-account')
    }.width('100%').padding({ top: 9, bottom: 9 })
  }

  @Builder
  private receipt() {
    if (this.entry !== undefined) {
      Column({ space: 0 }) {
        if (this.entry.kind === 'transfer') {
          Image($r('app.media.lucide_arrow_left_right1')).width(32).height(32).fillColor($r('app.color.xq_icon_primary'))
            .margin({ top: 4, bottom: 10 })
        } else { Image(categoryIcon(this.entry.iconKey)).width(32).height(32).margin({ top: 4, bottom: 10 }) }
        Text(this.entry.kind === 'transfer' ? transferPurposeLabel(this.entry.transferPurpose || 'transfer') : this.entry.categoryName).fontSize('18fp').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.xq_font_primary')).maxLines(2).textAlign(TextAlign.Center)
        Text(this.entry.kind === 'transfer' ? '实际转出' : this.entry.kind === 'income' ? '收入' : '实付金额').fontSize('12fp')
          .fontColor($r('app.color.xq_font_tertiary')).margin({ top: 16, bottom: 6 })
        Row({ space: 4 }) {
          if (this.entry.kind !== 'transfer') {
            Text(this.entry.kind === 'income' ? '+' : '−').fontSize('18fp')
              .fontColor(this.entry.kind === 'transfer' ? $r('app.color.xq_font_primary') : this.entry.kind === 'income' ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
          }
          Text(this.entry.currencySymbol || this.entry.currencyCode).fontSize('14fp').margin({ bottom: 5 })
            .fontColor(this.entry.kind === 'transfer' ? $r('app.color.xq_font_primary') : this.entry.kind === 'income' ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
          Text(this.amount(this.entry.kind === 'transfer' ? (this.entry.transferOutMinor || this.entry.paidMinor) : this.entry.paidMinor)).fontFamily('XiaoQiaoDINBold').fontWeight(FontWeight.Bold)
            .fontSize('38fp').minFontSize('22fp').maxFontSize('38fp').maxLines(1).id('entry-detail-amount')
            .fontColor(this.entry.kind === 'transfer' ? $r('app.color.xq_font_primary') : this.entry.kind === 'income' ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
        }.alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.Center).width('100%')
        if (BigInt(this.entry.discountMinor) > BigInt(0)) {
          Row({ space: 8 }) {
            Text(this.entry.currencySymbol + this.amount(this.entry.grossMinor)).decoration({ type: TextDecorationType.LineThrough })
              .fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
            Text('优惠 ' + this.amount(this.entry.discountMinor)).id('entry-detail-discount')
              .fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
          }.margin({ top: 10 })
        }
        Text(this.dateText()).fontSize('12fp').fontColor($r('app.color.xq_font_tertiary'))
          .margin({ top: 12, bottom: 20 }).id('entry-detail-date')
        Stack() {
          Row().width('100%').height(1).border({ width: { top: 1 }, style: BorderStyle.Dashed,
            color: $r('app.color.xq_comp_divider') })
          Row() {
            Circle().width(16).height(16).fill($r('app.color.xq_app_surface_page'))
            Blank()
            Circle().width(16).height(16).fill($r('app.color.xq_app_surface_page'))
          }.width('100%').padding({ left: 0, right: 0 })
        }.width('calc(100% + 64vp)').height(16).margin({ bottom: 8 })
        this.field('账本', this.entry.bookName)
        if (this.entry.kind === 'transfer') {
          this.transferAccount(true)
          this.transferAccount(false)
          this.field('转入金额', '¥' + this.amount(this.entry.transferInMinor || this.entry.paidMinor))
          this.field('手续费', '¥' + this.amount(this.entry.transferFeeMinor || '0'))
          if (BigInt(this.entry.transferCouponMinor || '0') > BigInt(0)) {
            this.field('还款优惠', '¥' + this.amount(this.entry.transferCouponMinor || '0'))
          }
          if (BigInt(this.entry.transferFeeMinor || '0') > BigInt(0)) {
            this.field('手续费预算', this.entry.feeInBudget ? '计入' : '不计入')
          }
        } else {
          this.field('收支分类', this.entry.categoryPath)
          if (this.entry.spendingNatureName !== undefined && this.entry.spendingNatureName.length > 0) {
            this.field('预算分类', this.entry.spendingNatureName)
          }
          this.field('资金账户', this.entry.accountName || '不使用账户')
          this.field('计入预算', this.entry.includeInBudget ? '计入' : '不计入')
        }
        this.field('计入资产', this.entry.includeInAssets ? '计入' : '不计入')
        if ((this.entry.tags || []).length > 0) {
          this.field('标签', (this.entry.tags || []).map((tag: TagChoice) => '#' + tag.name).join('  '))
        }
        if (this.entry.balanceMode === 'preserve') {
          Text('历史导入账目，不改变账户余额').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
            .width('100%').padding({ top: 8, bottom: 12 })
        }
        Divider().color($r('app.color.xq_comp_background_tertiary')).margin({ top: 8, bottom: 16 })
        Text('备注').fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
        Text(this.entry.note || '未填写').fontSize('14fp').lineHeight('22fp')
          .fontColor($r('app.color.xq_font_primary')).width('100%').margin({ top: 8 }).id('entry-detail-note')
        // Page-colored cuts form the perforated paper edge without a bitmap asset.
        Row() {
          ForEach(Array.from({ length: 24 }, (_: number, index: number) => index), (index: number) => {
            Circle().width(12).height(12).fill($r('app.color.xq_app_surface_page'))
          }, (index: number) => index.toString())
        }.width('calc(100% + 32vp)').justifyContent(FlexAlign.SpaceBetween).height(12)
          .margin({ top: 20, bottom: -30 })
      }.width('100%').padding({ left: 24, right: 24, top: 24, bottom: 24 }).borderRadius(4)
        .backgroundColor($r('app.color.xq_app_surface_card')).id('entry-detail-receipt')
    }
  }

  build() {
    HdsNavigation() {
      Column() {
        Scroll(this.scroller) {
          Column({ space: 16 }) {
            if (this.loading) {
              Text('正在读取账目…').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).padding(32)
            } else if (this.error.length > 0) {
              Text(this.error).fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).padding(20)
              Button('重新读取').onClick(() => { this.onRetry(); }).id('entry-detail-retry')
            } else { this.receipt() }
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 16 })
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off).clip(false)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).id('entry-detail-scroll')
        if (!this.loading && this.error.length === 0 && this.entry !== undefined) {
          Row({ space: 12 }) {
            Button('删除账目', { type: ButtonType.Capsule }).height(48).layoutWeight(1)
              .fontSize('16fp').fontColor($r('app.color.xq_warning')).backgroundColor($r('app.color.xq_app_surface_card'))
              .enabled(!this.busy).onClick(() => { this.onDelete(); }).id('entry-detail-delete')
            Button('编辑账目', { type: ButtonType.Capsule }).height(48).layoutWeight(2)
              .fontSize('16fp').fontColor(Color.White).backgroundColor($r('app.color.xq_brand'))
              .enabled(!this.busy && this.entry.canEdit).onClick(() => { this.onEdit(); }).id('entry-detail-edit')
          }.padding({ left: 16, right: 16, top: 12, bottom: 8 }).width('100%')
        }
      }.width('100%').height('100%').constraintSize({ maxWidth: 720 }).align(Alignment.Top)
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '账目详情' }, divider: { showType: DividerShowType.OFF },
          backIcon: { componentId: 'entry-detail-close', label: '返回账目', action: () => { if (!this.busy) { this.onClose(); } } } },
        style: { systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR },
          originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } } } })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]).id('entry-detail-page')
  }
}
