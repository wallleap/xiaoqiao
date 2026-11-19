import { CategoryIconBadge } from './CategoryIconBadge';
import { currencyUnit } from '../core/money/Currencies';
import { ExpenseRecoveryController, ExpenseRecoveryPanel, RecoveryMenuAction } from './ExpenseRecoveryPanel';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { LedgerAccount } from '../domain/model/LedgerSnapshot';
import { EntryLocationMap } from './EntryLocationMap';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { transferPurposeLabel } from '../domain/model/TransferRecord';
import { EntryDetail } from '../domain/model/EntryDetail';
import { TagChoice } from '../domain/model/LedgerSnapshot';
import { Money } from '../core/money/Money';
import { CurrencyUnit } from '../core/money/CurrencyUnit';
import { categoryIcon } from '../presentation/ledger/CategoryIcons';
import { LedgerAttachment } from '../domain/model/LedgerAttachment';

@Component
export struct EntryDetailPage {
  @Prop entry: EntryDetail | undefined = undefined;
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop busy: boolean = false;
  workspace: LedgerWorkspace | undefined = undefined;
  accounts: LedgerAccount[] = [];
  onRecoveryChanged: () => Promise<void> = async () => {};
  onClose: () => void = () => {};
  onEdit: () => void = () => {};
  onDelete: () => void = () => {};
  onRetry: () => void = () => {};
  private readonly recoveryController: ExpenseRecoveryController = new ExpenseRecoveryController();
  @State private recoveryWorking: boolean = false;
  @State private showAttachmentPreview: boolean = false;
  @State private previewAttachment: LedgerAttachment | undefined = undefined;
  @State private failedAttachmentPaths: string[] = [];
  @State private previewFailed: boolean = false;
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

  private canManageRecovery(): boolean {
    const entry = this.entry;
    return !this.loading && !this.busy && !this.recoveryWorking && this.error.length === 0 &&
      this.workspace !== undefined && entry !== undefined && entry.kind === 'expense' && entry.canEdit;
  }

  private recoveryRemaining(): bigint {
    let received = BigInt(0);
    for (const item of this.entry?.recoveries || []) { received += BigInt(item.amountMinor); }
    return BigInt(this.entry?.paidMinor || '0') - received;
  }

  private requestRecovery(action: RecoveryMenuAction): void {
    if (!this.canManageRecovery() || this.recoveryRemaining() <= BigInt(0)) { return; }
    this.recoveryController.request(action);
  }

  @Builder
  private moreMenu() {
    Menu() {
      if (this.recoveryRemaining() <= BigInt(0)) { MenuItem({ content: '已全额收回' }).enabled(false) }
      MenuItem({ content: '记报销' }).enabled(this.canManageRecovery() && this.recoveryRemaining() > BigInt(0))
        .onClick(() => { this.requestRecovery('reimbursement'); }).id('entry-detail-menu-reimbursement')
      MenuItem({ content: '记退款' }).enabled(this.canManageRecovery() && this.recoveryRemaining() > BigInt(0))
        .onClick(() => { this.requestRecovery('refund'); }).id('entry-detail-menu-refund')
      MenuItem({ content: this.entry?.reimbursementPending ? '取消待报销' : '标记待报销' })
        .enabled(this.canManageRecovery() && this.recoveryRemaining() > BigInt(0))
        .onClick(() => { this.requestRecovery('togglePending'); }).id('entry-detail-menu-pending')
    }.width(224)
  }

  @Builder
  private moreAction() {
    Row() {
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.lucide_ellipsis1')).width(24).height(24).fillColor($r('app.color.xq_icon_primary'))
      }.width(44).height(44).padding(10).backgroundColor(Color.Transparent)
        .enabled(this.canManageRecovery()).accessibilityText('更多操作').id('entry-detail-more')
        .bindMenu(this.moreMenu, { placement: Placement.BottomRight })
    }.width('100%').justifyContent(FlexAlign.End).padding({ right: 16 }).hitTestBehavior(HitTestMode.Transparent)
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
  private exclusionBadge(label: string, badgeId: string) {
    Text(label).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
      .backgroundColor($r('app.color.xq_app_surface_page')).borderRadius(6)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 }).margin({ right: 6, bottom: 4 }).id(badgeId)
  }

  /** Same label/value styling as the other fields; keep long notes fully readable. */
  @Builder
  private footerField(label: string, value: string, fieldId: string) {
    Row({ space: 16 }) {
      Text(label).fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
      Blank()
      Text(value).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).textAlign(TextAlign.End)
        .constraintSize({ maxWidth: '68%' }).id(fieldId)
    }.width('100%').alignItems(VerticalAlign.Top).padding({ top: 9, bottom: 9 })
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
  private attachmentGallery() {
    if ((this.entry?.attachments || []).length > 0) {
      Column({ space: 10 }) {
        Row() {
          Text('图片附件').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
          Blank()
          Text(`${(this.entry?.attachments || []).length} 张`).fontSize('12fp')
            .fontColor($r('app.color.xq_font_tertiary'))
        }.width('100%')
        Scroll() {
          Row({ space: 10 }) {
            ForEach(this.entry?.attachments || [], (attachment: LedgerAttachment) => {
              Stack() {
                if (this.failedAttachmentPaths.includes(attachment.filePath)) {
                  Text('图片加载失败').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
                } else {
                  Image('file://' + attachment.filePath).width(88).height(88).objectFit(ImageFit.Cover)
                    .onError(() => { this.failedAttachmentPaths = [...this.failedAttachmentPaths, attachment.filePath]; })
                }
              }.width(88).height(88).borderRadius(12)
                .backgroundColor($r('app.color.xq_app_surface_page'))
                .id('entry-attachment-' + attachment.id)
                .onClick(() => {
                  this.previewFailed = false;
                  this.previewAttachment = attachment;
                  this.showAttachmentPreview = true;
                })
            }, (attachment: LedgerAttachment) => attachment.id)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring).id('entry-detail-attachments')
      }.width('100%').padding({ top: 12, bottom: 12 })
    }
  }

  @Builder
  private attachmentPreview() {
    Column({ space: 16 }) {
      Row() {
        Text('图片附件').fontSize('20fp').fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.xq_font_primary'))
        Blank()
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.lucide_x1')).width(20).height(20)
            .fillColor($r('app.color.xq_icon_primary'))
        }.width(40).height(40).padding(0).backgroundColor($r('app.color.xq_app_surface_page'))
          .onClick(() => { this.showAttachmentPreview = false; })
      }.width('100%')
      if (this.previewAttachment !== undefined) {
        if (this.previewFailed) {
          Text('图片无法加载，文件可能已缺失或损坏。请尝试从完整备份恢复。')
            .fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).layoutWeight(1)
        } else {
          Image('file://' + this.previewAttachment.filePath).width('100%').layoutWeight(1)
            .objectFit(ImageFit.Contain).backgroundColor($r('app.color.xq_app_surface_page'))
            .borderRadius(16).id('entry-attachment-preview-image')
            .onError(() => { this.previewFailed = true; })
        }
      }
    }.width('100%').height('100%').padding(24)
  }

  @Builder
  private receipt() {
    if (this.entry !== undefined) {
      Column({ space: 0 }) {
        if (this.entry.kind === 'transfer') {
          CategoryIconBadge({ icon: $r('app.media.colorful_icon00372'), badgeSize: 48, glyphSize: 32 })
            .margin({ top: 4, bottom: 10 })
        } else { CategoryIconBadge({ icon: categoryIcon(this.entry.iconKey, this.entry.kind === 'income'), badgeSize: 48, glyphSize: 32 }).margin({ top: 4, bottom: 10 }) }
        Text(this.entry.kind === 'transfer' ? transferPurposeLabel(this.entry.transferPurpose || 'transfer') : this.entry.categoryName).fontSize('18fp').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.xq_font_primary')).maxLines(2).textAlign(TextAlign.Center)
        if (this.entry.kind !== 'expense') {
          Text(this.entry.kind === 'transfer' ? '实际转出' : '收入').fontSize('12fp')
            .fontColor($r('app.color.xq_font_tertiary')).margin({ top: 16, bottom: 6 })
        }
        Row({ space: 4 }) {
          // Keep sign and currency on one system-font baseline; only digits use DIN.
          Text((this.entry.kind === 'transfer' ? '' : this.entry.kind === 'income' ? '+ ' : '− ') +
            (this.entry.currencySymbol || this.entry.currencyCode)).fontSize('14fp').margin({ bottom: 5 })
            .fontColor(this.entry.kind === 'transfer' ? $r('app.color.xq_font_primary') : this.entry.kind === 'income' ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
          Text(this.amount(this.entry.kind === 'transfer' ? (this.entry.transferOutMinor || this.entry.paidMinor) : this.entry.paidMinor)).fontFamily('XiaoQiaoDINBold').fontWeight(FontWeight.Bold)
            .fontSize('38fp').minFontSize('22fp').maxFontSize('38fp').maxLines(1).id('entry-detail-amount')
            .fontColor(this.entry.kind === 'transfer' ? $r('app.color.xq_font_primary') : this.entry.kind === 'income' ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
        }.alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.Center).width('100%')
          .margin({ top: this.entry.kind === 'expense' ? 16 : 0 })
        if (BigInt(this.entry.discountMinor) > BigInt(0)) {
          Row({ space: 8 }) {
            Text(this.entry.currencySymbol + this.amount(this.entry.grossMinor)).decoration({ type: TextDecorationType.LineThrough })
              .fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
            Text('优惠 ' + this.amount(this.entry.discountMinor)).id('entry-detail-discount')
              .fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
          }.margin({ top: 10 })
        }
        Stack() {
          Row().width('100%').height(1).border({ width: { top: 1 }, style: BorderStyle.Dashed,
            color: $r('app.color.xq_comp_divider') })
          Row() {
            Circle().width(16).height(16).fill($r('app.color.xq_app_surface_page'))
            Blank()
            Circle().width(16).height(16).fill($r('app.color.xq_app_surface_page'))
          }.width('100%').padding({ left: 0, right: 0 })
        }.width('calc(100% + 64vp)').height(16).margin({ top: 20, bottom: 8 })
        this.field('账本', this.entry.bookName)
        if (this.entry.prepaidLinked) { this.field('来源', '预付款核销／退款差额，请在预付款项目中撤销') }
        if (this.entry.currencyCode !== 'CNY') {
          this.field('折合人民币', '¥' + Money.fromMinorText(this.entry.bookMinor,currencyUnit('CNY')).toDecimalString())
        }
        if (this.entry.bookFx !== undefined) {
          this.field('入账汇率', '1 ' + this.entry.currencyCode + ' = ' + this.entry.bookFx.rate + ' CNY')
          this.field('汇率来源', (this.entry.bookFx.source === 'manual' ? '手动' : 'ECB 参考汇率') + ' · ' + this.entry.bookFx.date)
        }
        if (this.entry.kind !== 'transfer' && this.entry.accountCurrencyId !== undefined && this.entry.accountCurrencyId !== this.entry.currencyId && this.entry.accountMinor !== undefined) {
          this.field('实际账户金额', this.entry.accountCurrencyId + ' ' + Money.fromMinorText(this.entry.accountMinor,currencyUnit(this.entry.accountCurrencyId)).toDecimalString())
        }
        if (this.entry.kind === 'transfer') {
          this.transferAccount(true)
          this.transferAccount(false)
          this.field('转入金额', (this.entry.accountCurrencyId || this.entry.currencyCode) + ' ' + Money.fromMinorText(this.entry.transferInMinor || this.entry.paidMinor, currencyUnit(this.entry.accountCurrencyId || this.entry.currencyCode)).toDecimalString())
          this.field('手续费', this.entry.currencySymbol + this.amount(this.entry.transferFeeMinor || '0'))
          if (BigInt(this.entry.transferCouponMinor || '0') > BigInt(0)) {
            this.field('还款优惠', this.entry.currencySymbol + this.amount(this.entry.transferCouponMinor || '0'))
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
        }
        if ((this.entry.kind === 'expense' && !this.entry.includeInBudget) || (!this.entry.includeInAssets && !this.entry.prepaidLinked)) {
          Flex({ wrap: FlexWrap.Wrap }) {
            if (this.entry.kind === 'expense' && !this.entry.includeInBudget) {
              this.exclusionBadge('不计入预算', 'entry-detail-budget-excluded')
            }
            if (!this.entry.includeInAssets && !this.entry.prepaidLinked) {
              this.exclusionBadge('不计入资产', 'entry-detail-assets-excluded')
            }
          }.width('100%').padding({ top: 4, bottom: 4 })
        }
        if ((this.entry.tags || []).length > 0) {
          this.field('标签', (this.entry.tags || []).map((tag: TagChoice) => '#' + tag.name).join('  '))
        }
        if ((this.entry.merchantName || '').length > 0) { this.field('商户', this.entry.merchantName || '') }
        if ((this.entry.addressText || '').length > 0) { this.field('地址', this.entry.addressText || '') }
        if (this.entry.location !== undefined) {
          ForEach([this.entry], (item: EntryDetail) => {
            EntryLocationMap({ location: item.location, merchantName: item.merchantName || '', addressText: item.addressText || '' })
          }, (item: EntryDetail) => item.id + ':' + item.revision)
        }
        this.attachmentGallery()
        if (this.entry.balanceMode === 'preserve') {
          Text('历史导入账目，不改变账户余额').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
            .width('100%').padding({ top: 8, bottom: 12 })
        }
        Divider().color($r('app.color.xq_comp_background_tertiary')).margin({ top: 8 })
        this.footerField('时间', this.dateText(), 'entry-detail-date')
        if (this.entry.note.trim().length > 0) { this.footerField('备注', this.entry.note, 'entry-detail-note') }
        if (this.entry.kind === 'expense' && this.entry.canEdit) {
          ForEach([this.entry], (item: EntryDetail) => {
            ExpenseRecoveryPanel({ entry: item, workspace: this.workspace, accounts: this.accounts,
              onChanged: this.onRecoveryChanged, controller: this.recoveryController,
              onBusyChange: (busy: boolean) => { this.recoveryWorking = busy; } })
          }, (item: EntryDetail) => item.id + ':' + item.revision)
        }
        // Page-colored cuts form the perforated paper edge without a bitmap asset.
        Row() {
          ForEach(Array.from({ length: 24 }, (_: number, index: number) => index), (index: number) => {
            Circle().width(12).height(12).fill($r('app.color.xq_app_surface_page'))
          }, (index: number) => index.toString())
        }.width('calc(100% + 32vp)').justifyContent(FlexAlign.SpaceBetween).height(12)
          .margin({ top: 20, bottom: -30 })
      }.width('100%').padding({ left: 24, right: 24, top: 24, bottom: 24 })
        .borderRadius({ topLeft: 20, topRight: 20, bottomLeft: 4, bottomRight: 4 })
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
          }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 16 })
        }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).id('entry-detail-scroll')
        if (!this.loading && this.error.length === 0 && this.entry !== undefined) {
          Row({ space: 12 }) {
            Button('删除账目', { type: ButtonType.Capsule }).height(48).layoutWeight(1)
              .fontSize('16fp').fontColor($r('app.color.xq_warning')).backgroundColor($r('app.color.xq_app_surface_card'))
              .enabled(!this.busy && !this.recoveryWorking && !this.entry.prepaidLinked).onClick(() => { this.onDelete(); }).id('entry-detail-delete')
            Button('编辑账目', { type: ButtonType.Capsule }).height(48).layoutWeight(2)
              .fontSize('16fp').fontColor(Color.White).backgroundColor($r('app.color.xq_brand'))
              .enabled(!this.busy && !this.recoveryWorking && this.entry.canEdit).onClick(() => { this.onEdit(); }).id('entry-detail-edit')
          }.padding({ left: 16, right: 16, top: 12, bottom: 8 }).width('100%')
            .backgroundColor($r('app.color.xq_app_surface_page')).zIndex(1)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
      }.width('100%').height('100%').constraintSize({ maxWidth: 720 }).align(Alignment.Top)
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '账目详情' }, stackBuilder: this.moreAction.bind(this), divider: { showType: DividerShowType.OFF },
          backIcon: { componentId: 'entry-detail-close', label: '返回账目', action: () => { if (!this.busy) { this.onClose(); } } } },
        style: { systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR },
          originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } } } })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .bindSheet($$this.showAttachmentPreview, this.attachmentPreview(),
        { height: '88%', showClose: false, backgroundColor: $r('app.color.xq_app_surface_card') })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]).id('entry-detail-page')
  }
}
