import { currencyUnit } from '../core/money/Currencies';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { AccountAdjustment, AdjustmentCursor } from '../domain/model/AccountCalibration';
import { AccountProfile } from '../domain/model/AccountProfile';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { Money } from '../core/money/Money';
import { CurrencyUnit } from '../core/money/CurrencyUnit';

@Component
export struct AccountAdjustmentHistoryPage {
  account: AccountProfile | undefined = undefined;
  workspace: LedgerWorkspace | undefined = undefined;
  onClose: () => void = () => {};
  @State private items: AccountAdjustment[] = [];
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private next: AdjustmentCursor | undefined = undefined;
  private readonly scroller: Scroller = new Scroller();
  private get currency(): CurrencyUnit { return currencyUnit(this.account?.currencyId || 'CNY'); }

  aboutToAppear(): void { this.load(false); }
  private async load(more: boolean): Promise<void> {
    if (this.loading || (more && this.next === undefined)) { return; }
    this.loading = true; this.error = '';
    try {
      if (this.workspace === undefined || this.account === undefined) { throw new Error('ACCOUNT_UNAVAILABLE'); }
      const page = await this.workspace.accountAdjustments(this.account.id, more ? this.next : undefined);
      this.items = more ? this.items.concat(page.items) : page.items; this.next = page.next;
    } catch (_) { this.error = '调整记录暂时无法读取，请重试'; }
    finally { this.loading = false; }
  }
  private money(minor: string): string { return Money.fromMinorText(minor, this.currency).toDecimalString(); }
  private signed(minor: string): string { return (BigInt(minor) > BigInt(0) ? '+' : '') + this.money(minor); }
  private dateText(time: number): string {
    const date = new Date(time);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }
  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Text(this.account?.name || '').fontSize('18fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary')).width('100%')
          Text('记录期初余额和历次校准，不计入收支和预算。').fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
          ForEach(this.items, (item: AccountAdjustment) => {
            Column({ space: 12 }) {
              Row({ space: 12 }) {
                Text(item.kind === 'opening' ? '期初余额' : '余额校准').fontSize('16fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
                Blank()
                Text(this.signed(item.deltaMinor)).fontSize('20fp').fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_primary'))
                  .maxLines(1).minFontSize('12fp').maxFontSize('20fp').constraintSize({ maxWidth: '60%' }).id('adjustment-delta-' + item.id)
              }.width('100%')
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text('调整前').fontSize('12fp').fontColor($r('app.color.xq_font_tertiary'))
                  Text(this.money(item.beforeMinor)).fontSize('16fp').fontFamily('XiaoQiaoDINRegular').fontColor($r('app.color.xq_font_secondary')).maxLines(1).minFontSize('10fp').maxFontSize('16fp')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Image($r('app.media.lucide_arrow_right1')).width(18).height(18).fillColor($r('app.color.xq_icon_tertiary'))
                Column({ space: 4 }) {
                  Text('调整后').fontSize('12fp').fontColor($r('app.color.xq_font_tertiary'))
                  Text(this.money(item.afterMinor)).fontSize('16fp').fontFamily('XiaoQiaoDINRegular').fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('10fp').maxFontSize('16fp')
                    .id('adjustment-after-' + item.id)
                }.layoutWeight(1).alignItems(HorizontalAlign.End)
              }.width('100%')
              Text(item.reason).fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
              Text(this.dateText(item.occurredAtMs)).fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
            }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card')).id('adjustment-row-' + item.id)
          }, (item: AccountAdjustment) => item.id)
          if (this.loading) { Text('正在读取…').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).padding(16) }
          if (this.error) {
            Text(this.error).fontSize('14fp').fontColor($r('app.color.xq_warning'))
            Button('重新读取').onClick(() => { this.load(this.items.length > 0); }).id('adjustment-history-retry')
          } else if (!this.loading && this.items.length === 0) {
            Text('暂无调整记录').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).padding(32)
          }
          if (this.next !== undefined && !this.loading && !this.error) {
            Button('加载更多').fontSize('14fp').fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_card'))
              .onClick(() => { this.load(true); }).id('adjustment-history-more')
          }
        }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 24 })
      }.width('100%').height('100%').constraintSize({ maxWidth: 720 }).align(Alignment.Top).scrollBar(BarState.Off).clip(false).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true, content: { title: { mainTitle: '余额调整记录' }, divider: { showType: DividerShowType.OFF }, backIcon: { componentId: 'adjustment-history-close', action: () => { this.onClose(); } } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } }, scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]).id('account-adjustment-history')
  }
}
