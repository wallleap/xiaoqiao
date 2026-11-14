import { SegmentButton, SegmentButtonOptions } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { AccountOverview, AccountProfile } from '../domain/model/AccountProfile';
import { AccountAvatar } from './AccountAvatar';
import { Money } from '../core/money/Money';
import { CurrencyUnit } from '../core/money/CurrencyUnit';

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
  onEdit: (account: AccountProfile) => void = () => {};
  onRetry: () => void = () => {};
  private readonly scroller: Scroller = new Scroller();

  private amount(minor: string): string {
    const parts = Money.fromMinorText(minor, new CurrencyUnit('CNY', 'CNY', 2)).toDecimalString().split('.');
    return parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',') + '.' + parts[1];
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
      Text(this.amount((asset ? this.overview?.assetsMinor : this.overview?.liabilitiesMinor) || '0'))
        .fontSize('20fp').fontFamily('XiaoQiaoDINMedium').id(asset ? 'accounts-total-assets' : 'accounts-total-liabilities')
        .fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('14fp').maxFontSize('20fp')
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          if (this.loading && this.overview === undefined) {
            Text('正在读取账户…').fontSize('14fp').padding(24)
          } else if (this.error.length > 0) {
            Text(this.error).fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).padding(16)
            Button('重新读取').onClick(() => { this.onRetry(); }).id('accounts-retry')
          } else {
            Column({ space: 16 }) {
              Text('净资产 · CNY').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
              Text(this.amount(this.overview?.netMinor || '0')).fontSize('36fp').fontFamily('XiaoQiaoDINBold')
                .fontWeight(FontWeight.Bold).fontColor($r('app.color.xq_font_primary')).width('100%')
                .maxLines(1).minFontSize('20fp').maxFontSize('36fp').id('accounts-net')
              Row({ space: 24 }) {
                this.total(true)
                this.total(false)
              }.width('100%')
              if (this.overview?.accounts.some((item: AccountProfile) => item.archived && item.includeInNetAssets)) {
                Text('含已归档账户余额').fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
              }
            }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
            Row() {
              Text(this.showArchived ? '已归档账户' : '我的账户').fontSize('18fp').fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.xq_font_primary'))
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
            ForEach(this.visible(), (account: AccountProfile) => {
              Row({ space: 12 }) {
                AccountAvatar({ iconKey: account.iconKey, brandColor: account.brandColor, iconVariant: account.iconVariant })
                Column({ space: 4 }) {
                  Text(account.name).fontSize('16fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary')).maxLines(1)
                  Text((account.kind === 'liability' ? '负债账户' : '资产账户') + (account.includeInNetAssets ? ' · CNY' : ' · 不计总资产'))
                    .fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Column({ space: 4 }) {
                  Text(this.amount(account.balanceMinor)).fontSize('20fp').fontFamily('XiaoQiaoDINMedium')
                    .fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('14fp').maxFontSize('20fp')
                  if (account.kind === 'liability' && BigInt(account.balanceMinor) > BigInt(0)) {
                    Text('溢缴余额').fontSize('10fp').fontColor($r('app.color.xq_font_secondary'))
                  }
                }.alignItems(HorizontalAlign.End).constraintSize({ maxWidth: '46%' })
                Image($r('app.media.lucide_chevron_right1')).width(14).height(14).fillColor($r('app.color.xq_icon_tertiary'))
              }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
                .id('account-row-' + account.id).onClick(() => { this.onEdit(account); })
            }, (account: AccountProfile) => account.id + ':' + account.revision + ':' + account.balanceMinor)
            Button('添加账户', { type: ButtonType.Capsule }).fontSize('16fp').height(48).width('100%')
              .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).id('accounts-create')
              .enabled(!this.loading).onClick(() => { this.onCreate(); })
          }
        }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 128 })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI).hideBackButton(true)
      .titleBar({ enableComponentSafeArea: true, avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '资产' }, divider: { showType: DividerShowType.OFF } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]).id('accounts-page')
  }
}
