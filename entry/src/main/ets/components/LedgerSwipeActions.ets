import { curves } from '@kit.ArkUI';

/** Keeps the HDS card's intrinsic height and the parent List's vertical scrolling. */
@Component
export struct LedgerSwipeActions {
  @Prop entryId: string = '';
  @Link @Watch('activeChanged') activeId: string;
  @Prop busy: boolean = false;
  @Prop menuMaterial: SystemUiMaterial | undefined = undefined;
  @BuilderParam content: () => void;
  onDelete: () => void = () => {};
  onEdit: () => void = () => {};
  @Prop editable: boolean = false;
  @Prop prepaid: boolean = false;
  onPrepaidAction: (action: string) => void = () => {};
  @State private swipeOffset: number = 0;
  @State private contentHeight: number = 0;
  private startOffset: number = 0;
  private dragging: boolean = false;
  private readonly actionWidth: number = 128;

  private settle(open: boolean): void {
    this.getUIContext().animateTo({ curve: curves.springMotion(0.28, 0.90) }, () => {
      this.swipeOffset = open ? -this.actionWidth : 0;
    });
  }

  private activeChanged(): void {
    if (this.activeId !== this.entryId) { this.settle(false); }
  }

  @Builder
  private contextMenu() {
    Menu() {
      if (this.prepaid) {
        MenuItem({ content: '核销' }).enabled(this.editable && !this.busy).onClick(() => { this.onPrepaidAction('consume'); })
        MenuItem({ content: '退款' }).enabled(this.editable && !this.busy).onClick(() => { this.onPrepaidAction('refund'); })
        MenuItem({ content: '追加付款' }).enabled(this.editable && !this.busy).onClick(() => { this.onPrepaidAction('fund'); })
        MenuItem({ content: '编辑项目' }).enabled(this.editable && !this.busy).onClick(() => { this.onPrepaidAction('edit'); })
        MenuItem({ content: '查看流水' }).enabled(!this.busy).onClick(() => { this.onPrepaidAction('view'); })
      } else {
      MenuItem({ content: '编辑' }).enabled(this.editable && !this.busy).id('ledger-menu-edit-' + this.entryId)
        .onClick(() => { this.onEdit(); })
      MenuItem({ content: '删除' }).contentFontColor($r('app.color.xq_warning')).enabled(!this.busy)
        .id('ledger-menu-delete-' + this.entryId).onClick(() => { this.onDelete(); })
      }
    }.width(224)
  }

  build() {
    Stack({ alignContent: Alignment.End }) {
      Row({ space: 4 }) {
        Button(this.prepaid ? '核销' : '编辑').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
          .backgroundColor($r('app.color.xq_background_secondary')).enabled(this.editable && !this.busy)
          .width(60).height('100%').borderRadius(12).id('ledger-edit-' + this.entryId)
          .onClick(() => { this.activeId = ''; this.settle(false); if (this.prepaid) { this.onPrepaidAction('consume'); } else { this.onEdit(); } })
        Button(this.prepaid ? '查看' : '删除').fontSize('14fp').fontColor(Color.White)
          .backgroundColor(this.prepaid ? $r('app.color.xq_brand') : $r('app.color.xq_warning')).enabled(!this.busy)
          .width(60).height('100%').borderRadius(12).id('ledger-delete-' + this.entryId)
          .onClick(() => { if (this.prepaid) { this.activeId = ''; this.settle(false); this.onPrepaidAction('view'); } else { this.onDelete(); } })
      }.width(this.actionWidth).height(this.contentHeight).padding({ left: 4 })
        .visibility(this.swipeOffset < 0 ? Visibility.Visible : Visibility.Hidden)
        .hitTestBehavior(this.swipeOffset <= -this.actionWidth + 1 ? HitTestMode.Default : HitTestMode.None)
        .accessibilityLevel(this.swipeOffset <= -this.actionWidth + 1 ? 'auto' : 'no-hide-descendants')
      Column() { this.content() }.width('100%').translate({ x: this.swipeOffset })
        .onAreaChange((_old: Area, area: Area) => {
          const height = Number(area.height);
          if (height !== this.contentHeight) { this.contentHeight = height; }
        })
        .bindContextMenu(this.contextMenu, ResponseType.LongPress, {
          preview: MenuPreviewMode.IMAGE, previewBorderRadius: 16, borderRadius: 20,
          mask: true, systemMaterial: this.menuMaterial,
          aboutToAppear: () => {
            this.activeId = '';
            this.swipeOffset = 0;
          }
        })
        .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 10 })
          .onActionStart(() => {
            if (this.busy) { return; }
            this.dragging = true;
            this.startOffset = this.swipeOffset;
            this.activeId = this.entryId;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.busy) { this.swipeOffset = Math.max(-this.actionWidth, Math.min(0, this.startOffset + event.offsetX)); }
          })
          .onActionEnd((event: GestureEvent) => {
            if (this.busy) { return; }
            this.dragging = false;
            const open = event.velocityX < -300 || (event.velocityX <= 300 && this.swipeOffset < -this.actionWidth / 2);
            if (!open) { this.activeId = ''; }
            this.settle(open);
          })
          .onActionCancel(() => {
            if (this.dragging) {
              this.dragging = false;
              this.activeId = ''; this.settle(false);
            }
          }))
    }.width('100%').borderRadius(16).clip(true).id('ledger-swipe-' + this.entryId)
  }
}
