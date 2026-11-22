import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { AccountProfile, AccountOrderItem } from '../domain/model/AccountProfile';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { AccountAvatar } from './AccountAvatar';

@Component
export struct AccountSortPage {
  accounts: AccountProfile[] = [];
  workspace: LedgerWorkspace | undefined = undefined;
  onClose: () => void = () => {};
  onSaved: () => void = () => {};
  onRegisterBack: (handler: () => boolean) => void = () => {};
  @State private rows: AccountProfile[] = [];
  @State private saving: boolean = false;
  @State private dragging: boolean = false;
  @State private confirming: boolean = false;
  @State private error: string = '';
  private originalIds: string[] = [];
  private active: boolean = false;
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.active = true;
    this.rows = this.accounts.filter((item: AccountProfile) => !item.archived);
    this.originalIds = this.rows.map((item: AccountProfile) => item.id);
    this.onRegisterBack((): boolean => { this.closePage(); return true; });
  }
  aboutToDisappear(): void { this.active = false; this.onRegisterBack((): boolean => false); }
  private dirty(): boolean { return this.rows.some((item: AccountProfile, index: number) => item.id !== this.originalIds[index]); }
  private move(from: number, to: number): void {
    if (this.saving || this.confirming || !Number.isInteger(from) || !Number.isInteger(to) ||
      from < 0 || to < 0 || from >= this.rows.length || to >= this.rows.length || from === to) { return; }
    const next = this.rows.slice();
    const moved = next.splice(from, 1)[0]; next.splice(to, 0, moved); this.rows = next;
  }
  private async closePage(): Promise<void> {
    if (this.saving || this.dragging || this.confirming) { return; }
    if (!this.dirty()) { this.onClose(); return; }
    this.confirming = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({ title: '放弃本次排序？',
        message: '账户顺序尚未保存，离开后将保留原顺序。',
        buttons: [{ text: '继续排序', color: $r('app.color.xq_font_primary') }, { text: '放弃', color: $r('app.color.xq_warning') }] });
      if (result.index === 1 && this.active) { this.onClose(); }
    } catch (_) { /* Dismissing keeps the local order. */ }
    finally { if (this.active) { this.confirming = false; } }
  }
  private async save(): Promise<void> {
    if (this.workspace === undefined || this.saving || this.dragging || this.confirming || !this.dirty()) { return; }
    this.saving = true; this.error = '';
    try {
      await this.workspace.reorderAccounts(this.rows.map((item: AccountProfile): AccountOrderItem => ({ id: item.id, revision: item.revision })));
    } catch (_) {
      if (this.active) { this.error = '排序未保存，账户可能已变更。请返回后重新进入排序再试。'; this.saving = false; }
      return;
    }
    if (this.active) { this.saving = false; this.onSaved(); }
  }
  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }
  build() {
    HdsNavigation() {
      Column({ space: 12 }) {
        Text('长按账户拖动排序，保存后用于资产列表和记账选账户。').fontSize('13fp')
          .fontColor($r('app.color.xq_font_secondary')).width('100%').padding({ left: 8, right: 8 })
        List({ space: 12, scroller: this.scroller }) {
          ForEach(this.rows, (item: AccountProfile) => {
            ListItem() {
              Row({ space: 12 }) {
                AccountAvatar({ iconKey: item.iconKey, iconVariant: item.iconVariant, brandColor: item.brandColor, diameter: 40 })
                Column({ space: 4 }) {
                  Text(item.name).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.currencyId).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Image($r('app.media.lucide_grip_vertical1')).width(20).height(24).fillColor($r('app.color.xq_icon_secondary'))
              }.width('100%').padding(16).constraintSize({ minHeight: 72 }).borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
            }.id('account-sort-row-' + item.id).accessibilityText(item.name + '，长按拖动排序')
          }, (item: AccountProfile) => item.id)
            .onMove((from: number, to: number) => { this.move(from, to); }, {
              onDragStart: () => { this.dragging = true; }, onDrop: () => { this.dragging = false; }
            })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off).clip(false)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).enabled(!this.saving && !this.confirming)
        if (this.rows.length < 2) { Text('至少两个使用中的账户才需要排序').fontSize('13fp').fontColor($r('app.color.xq_font_secondary')) }
        if (this.error.length > 0) { Text(this.error).fontSize('13fp').fontColor($r('app.color.xq_warning')).width('100%').padding({ left: 8, right: 8 }) }
        Button(this.saving ? '保存中…' : '保存排序', { type: ButtonType.Capsule }).width('100%').height(48)
          .fontSize('14fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_on_primary')).backgroundColor($r('app.color.xq_brand'))
          .enabled(this.rows.some((item: AccountProfile, index: number) => item.id !== this.originalIds[index]) && !this.saving && !this.dragging && !this.confirming && this.workspace !== undefined)
          .onClick(() => { this.save(); }).id('account-sort-save')
      }.width('100%').height('100%').padding({ left: 16, right: 16, top: 12, bottom: 32 })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true, content: { title: { mainTitle: '账户排序' }, divider: { showType: DividerShowType.OFF },
        backIcon: { action: () => { this.closePage(); } } }, style: {
          originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]).id('account-sort-page')
  }
}
