import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { ChipGroup, ChipSize, ItemRestriction, SegmentButton, SegmentButtonOptions, SegmentButtonTextItem } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { CategoryCommand, CategoryOrderItem, CategoryProfile } from '../domain/model/CategoryProfile';
import { CATEGORY_ICON_OPTIONS, CategoryIconOption, categoryIcon } from '../presentation/ledger/CategoryIcons';

interface CategorySelectOption {
  value: string;
}

@Component
export struct CategoryManagementPage {
  workspace: LedgerWorkspace | undefined = undefined;
  sheetMaterial: SystemUiMaterial | undefined = undefined;
  @Prop @Watch('applyArchiveMaterial') segmentMaterial: SystemUiMaterial | undefined = undefined;
  onClose: () => void = () => {};
  onCreated: (id: string) => void = () => {};
  onRegisterBack: (handler: () => boolean) => void = () => {};
  @State private values: CategoryProfile[] = [];
  @State private kind: string = 'expense';
  @State private browsingParentId: string = '';
  @State private draggedId: string = '';
  @State private dragOffset: number = 0;
  @State private dragTarget: number = -1;
  @State private dragLifted: boolean = false;
  @State private landing: boolean = false;
  @State private resettingDrag: boolean = false;
  private dragFrom: number = -1;
  private dragRows: CategoryProfile[] = [];
  private dragScrollStart: number = 0;
  private dragTravel: number = 0;
  private dragFingerY: number = 0;
  private dragFingerStartY: number = 0;
  private viewportTop: number = 0;
  private viewportHeight: number = 0;
  private autoScrollTimer: number = -1;
  private landingTimer: number = -1;
  private resetTimer: number = -1;
  private active: boolean = false;
  private readonly rowHeight: number = 76;
  private readonly rowGap: number = 12;
  @State private showArchived: boolean = false;
  @State @Watch('archiveSelectionChanged') private archiveSelection: number[] = [0];
  @State private archiveOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '使用中' }, { text: '已归档' }] as ItemRestriction<SegmentButtonTextItem>,
    fontSize: '13fp', selectedFontSize: '13fp',
    fontColor: $r('sys.color.font_primary'), selectedFontColor: $r('app.color.xq_font_on_primary'),
    backgroundColor: Color.Transparent, selectedBackgroundColor: $r('app.color.xq_brand')
  });

  private archiveSelectionChanged(): void {
    this.showArchived = this.archiveSelection[0] === 1;
  }

  @State private loading: boolean = true;
  @State private showEditor: boolean = false;
  @State private editing: CategoryProfile | undefined = undefined;
  @State private name: string = '';
  @State private parentId: string = '';
  @State private iconKey: string = 'other';
  @State private busy: boolean = false;
  @State private error: string = '';
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.active = true;
    this.onRegisterBack((): boolean => this.navigateBack());
    this.applyArchiveMaterial(); this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    clearInterval(this.autoScrollTimer); clearTimeout(this.landingTimer); clearTimeout(this.resetTimer);
    this.onRegisterBack((): boolean => false);
  }

  private interactionLocked(): boolean { return this.loading || this.busy || this.draggedId.length > 0; }

  private navigateBack(): boolean {
    if (this.interactionLocked()) { return true; }
    if (this.showEditor) { this.showEditor = false; return true; }
    if (this.browsingParentId.length === 0) { return false; }
    this.browsingParentId = this.values.find((item: CategoryProfile) => item.id === this.browsingParentId)?.parentId || '';
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    return true;
  }

  private enterChildren(item: CategoryProfile): void {
    if (this.interactionLocked()) { return; }
    this.browsingParentId = item.id;
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  private applyArchiveMaterial(): void {
    const options = SegmentButtonOptions.tab({
      buttons: [{ text: '使用中' }, { text: '已归档' }] as ItemRestriction<SegmentButtonTextItem>,
      fontSize: '13fp', selectedFontSize: '13fp',
      fontColor: $r('sys.color.font_primary'), selectedFontColor: $r('app.color.xq_font_on_primary'),
      backgroundColor: Color.Transparent, selectedBackgroundColor: $r('app.color.xq_brand')
    });
    if (this.segmentMaterial !== undefined) { options.backgroundSystemMaterial = this.segmentMaterial; }
    this.archiveOptions = options;
  }

  @Builder
  private archiveAction() {
    Row() {
      SegmentButton({ options: this.archiveOptions, selectedIndexes: $archiveSelection })
        .width(168).constraintSize({ maxWidth: '100%' }).enabled(!this.interactionLocked()).id('category-toggle-archive')
    }.width('100%').justifyContent(FlexAlign.End).padding({ left: 160, right: 16 })
      .hitTestBehavior(HitTestMode.Transparent)
  }

  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }

  private async load(): Promise<void> {
    if (this.workspace === undefined) { this.loading = false; return; }
    this.loading = true; this.error = '';
    try { this.values = await this.workspace.categories(); }
    catch (_) { this.error = '分类暂时无法读取，请返回后重试'; }
    finally { this.loading = false; }
  }

  private categoryPath(item: CategoryProfile): string {
    const names: string[] = [item.name];
    const visited: Set<string> = new Set<string>([item.id]);
    let parentId = item.parentId;
    while (parentId.length > 0 && !visited.has(parentId)) {
      visited.add(parentId);
      const parent = this.values.find((value: CategoryProfile) => value.id === parentId);
      if (parent === undefined) { break; }
      names.unshift(parent.name); parentId = parent.parentId;
    }
    return names.join(' / ');
  }

  private browsingTitle(): string {
    const parent = this.values.find((item: CategoryProfile) => item.id === this.browsingParentId);
    return parent === undefined ? '子分类' : this.categoryPath(parent);
  }

  private hasArchivedDescendants(item: CategoryProfile): boolean {
    return this.values.some((child: CategoryProfile) => child.kind === this.kind && child.archived && this.isDescendant(child.id, item.id));
  }

  private visibleRows(): CategoryProfile[] {
    return this.values.filter((item: CategoryProfile) => item.kind === this.kind && item.parentId === this.browsingParentId &&
      (this.showArchived ? item.archived || this.hasArchivedDescendants(item) : !item.archived))
      .sort((left: CategoryProfile, right: CategoryProfile) => left.sortOrder - right.sortOrder || left.id.localeCompare(right.id));
  }

  private childCount(item: CategoryProfile): number {
    return this.values.filter((child: CategoryProfile) => child.parentId === item.id &&
      (this.showArchived ? child.archived || this.hasArchivedDescendants(child) : !child.archived)).length;
  }

  private startDrag(item: CategoryProfile, event: GestureEvent): void {
    if (this.workspace === undefined || this.interactionLocked() || this.showArchived || item.archived || this.visibleRows().length < 2) { return; }
    this.dragRows = this.visibleRows();
    this.dragFrom = this.dragRows.findIndex((row: CategoryProfile) => row.id === item.id);
    if (this.dragFrom < 0) { return; }
    this.error = ''; this.dragOffset = 0; this.dragTravel = 0;
    this.dragTarget = this.dragFrom; this.draggedId = item.id; this.dragLifted = true;
    this.dragScrollStart = this.scroller.currentOffset().yOffset;
    this.dragFingerY = event.fingerList[0]?.globalY || 0;
    this.dragFingerStartY = this.dragFingerY;
    this.autoScrollTimer = setInterval(() => { this.autoScrollDrag(); }, 16);
  }

  private updateDrag(event: GestureEvent): void {
    if (this.draggedId.length === 0 || this.landing) { return; }
    const finger = event.fingerList[0];
    this.dragFingerY = finger === undefined ? this.dragFingerY : finger.globalY;
    this.dragTravel = finger === undefined ? event.offsetY : this.dragFingerY - this.dragFingerStartY;
    this.updateDragOffset();
  }

  private updateDragOffset(): void {
    const stride = this.rowHeight + this.rowGap;
    this.dragOffset = Math.max(-this.dragFrom * stride, Math.min((this.dragRows.length - 1 - this.dragFrom) * stride,
      this.dragTravel + this.scroller.currentOffset().yOffset - this.dragScrollStart));
    this.dragTarget = Math.max(0, Math.min(this.dragRows.length - 1, this.dragFrom + Math.round(this.dragOffset / stride)));
  }

  private autoScrollDrag(): void {
    if (!this.active || this.draggedId.length === 0 || this.landing || this.viewportHeight <= 0) { return; }
    const top = this.viewportTop + 80; const bottom = this.viewportTop + this.viewportHeight - 64;
    let step = 0;
    if (this.dragFingerY < top) { step = -Math.min(10, (top - this.dragFingerY) / 5); }
    else if (this.dragFingerY > bottom) { step = Math.min(10, (this.dragFingerY - bottom) / 5); }
    if (step !== 0) { this.scroller.scrollBy(0, step); this.updateDragOffset(); }
  }

  private rowOffset(id: string): number {
    if (this.draggedId.length === 0) { return 0; }
    if (id === this.draggedId) { return this.dragOffset; }
    const index = this.dragRows.findIndex((item: CategoryProfile) => item.id === id);
    const stride = this.rowHeight + this.rowGap;
    if (this.dragTarget > this.dragFrom && index > this.dragFrom && index <= this.dragTarget) { return -stride; }
    if (this.dragTarget < this.dragFrom && index >= this.dragTarget && index < this.dragFrom) { return stride; }
    return 0;
  }

  private resetDrag(): void {
    this.resettingDrag = true;
    this.draggedId = ''; this.dragOffset = 0; this.dragTarget = -1; this.dragFrom = -1;
    this.dragLifted = false; this.landing = false; this.dragRows = [];
    this.resetTimer = setTimeout(() => { if (this.active) { this.resettingDrag = false; } }, 16);
  }

  private finishDrag(cancelled: boolean): void {
    if (this.draggedId.length === 0 || this.landing) { return; }
    clearInterval(this.autoScrollTimer);
    this.landing = true; this.dragLifted = false;
    if (cancelled) { this.dragTarget = this.dragFrom; }
    this.dragOffset = (this.dragTarget - this.dragFrom) * (this.rowHeight + this.rowGap);
    this.landingTimer = setTimeout(() => { this.persistDrag(); }, 200);
  }

  private async persistDrag(): Promise<void> {
    if (!this.active) { return; }
    if (this.workspace === undefined || this.dragTarget === this.dragFrom) { this.resetDrag(); return; }
    const order = this.dragRows.map((item: CategoryProfile): CategoryOrderItem => ({ id: item.id, revision: item.revision }));
    const moved = order.splice(this.dragFrom, 1)[0]; order.splice(this.dragTarget, 0, moved);
    this.busy = true;
    try {
      await this.workspace.reorderCategories(this.kind, this.browsingParentId, order);
      if (this.active) {
        // The write already checked every sibling revision. Apply that committed order without a fallible second read.
        this.resettingDrag = true;
        this.values = this.values.map((item: CategoryProfile): CategoryProfile => {
          const index = order.findIndex((entry: CategoryOrderItem) => entry.id === item.id);
          if (index < 0) { return item; }
          return { id: item.id, kind: item.kind, parentId: item.parentId, name: item.name, iconKey: item.iconKey,
            sortOrder: index, revision: order[index].revision + 1, archived: item.archived };
        });
        this.resetDrag();
      }
    } catch (_) {
      if (this.active) {
        this.error = '排序未完成，已恢复原顺序，请刷新后重试';
        this.dragTarget = this.dragFrom; this.dragOffset = 0;
        this.landingTimer = setTimeout(() => { if (this.active) { this.resetDrag(); } }, 200);
      }
    } finally { this.busy = false; }
  }

  private parentSelectOptions(): CategorySelectOption[] {
    const options: CategorySelectOption[] = [{ value: '无父分类' }];
    for (const item of this.parentChoices()) { options.push({ value: this.categoryPath(item) }); }
    return options;
  }

  private selectedParentLabel(): string {
    if (this.parentId.length === 0) { return '无父分类'; }
    const parent = this.values.find((item: CategoryProfile) => item.id === this.parentId);
    return parent === undefined ? '无父分类' : this.categoryPath(parent);
  }

  private isDescendant(candidateId: string, ancestorId: string): boolean {
    let cursor = candidateId; const visited: Set<string> = new Set<string>();
    while (cursor.length > 0 && !visited.has(cursor)) {
      visited.add(cursor);
      const item = this.values.find((value: CategoryProfile) => value.id === cursor);
      if (item === undefined) { return false; }
      if (item.parentId === ancestorId) { return true; }
      cursor = item.parentId;
    }
    return false;
  }

  private parentChoices(): CategoryProfile[] {
    return this.values.filter((item: CategoryProfile) => item.kind === this.kind && !item.archived &&
      (this.editing === undefined || (item.id !== this.editing.id && !this.isDescendant(item.id, this.editing.id))))
      .sort((left: CategoryProfile, right: CategoryProfile) => this.categoryPath(left).localeCompare(this.categoryPath(right), 'zh-CN'));
  }

  private beginCreate(): void {
    this.editing = undefined; this.name = ''; this.parentId = this.browsingParentId; this.iconKey = this.kind === 'income' ? 'salary' : 'other';
    this.error = ''; this.showEditor = true;
  }

  private beginEdit(item: CategoryProfile): void {
    this.editing = item; this.name = item.name; this.parentId = item.parentId; this.iconKey = item.iconKey;
    this.error = ''; this.showEditor = true;
  }

  private async save(): Promise<void> {
    if (this.busy || this.workspace === undefined) { return; }
    this.busy = true; this.error = '';
    const command: CategoryCommand = { id: this.editing?.id || util.generateRandomUUID(), kind: this.kind,
      parentId: this.parentId.length > 0 ? this.parentId : undefined, name: this.name, iconKey: this.iconKey };
    try {
      if (this.editing === undefined) { await this.workspace.createCategory(command); this.onCreated(command.id); }
      else { await this.workspace.updateCategory(command, this.editing.revision); }
      this.values = await this.workspace.categories();
      this.showEditor = false;
    } catch (error) {
      const code = (error as Error).message;
      this.error = code === 'CATEGORY_NAME_EXISTS' ? '同一级下已有同名分类' :
        code === 'CATEGORY_CYCLE' ? '不能把分类移动到自己的下级' :
        code === 'CATEGORY_CHANGED' ? '分类已更新，请关闭后重新打开' : '保存失败，请检查名称和父分类';
    } finally { this.busy = false; }
  }

  private archive(item: CategoryProfile): void {
    if (this.busy || this.workspace === undefined) { return; }
    const archived = !item.archived;
    this.getUIContext().getPromptAction().showDialog({
      title: archived ? '归档这个分类？' : '恢复这个分类？',
      message: archived ? '历史账目会保留；有子分类时需先归档子分类。' : '恢复后可以再次用于记账和分类预算。',
      buttons: [{ text: '取消', color: $r('app.color.xq_font_primary') },
        { text: archived ? '归档' : '恢复', color: $r('app.color.xq_font_emphasize') }]
    }).then(async (result) => {
      if (result.index !== 1 || this.workspace === undefined) { return; }
      this.busy = true; this.error = '';
      try {
        await this.workspace.archiveCategory(item.id, item.revision, archived);
        this.values = await this.workspace.categories();
      } catch (error) {
        const code = (error as Error).message;
        this.error = code === 'CATEGORY_HAS_CHILDREN' ? '请先归档该分类下的子分类' :
          code === 'LAST_ACTIVE_CATEGORY' ? '至少保留一个使用中的分类' : '无法更新分类状态，请重试';
      } finally { this.busy = false; }
    }).catch(() => {});
  }

  private sheetOptions(): SheetOptions {
    const options: SheetOptions = { height: 620, showClose: true };
    if (this.sheetMaterial !== undefined) { options.systemMaterial = this.sheetMaterial; }
    else { options.backgroundColor = $r('app.color.xq_app_surface_card'); }
    return options;
  }

  @Builder
  private editorSheet() {
    Column({ space: 14 }) {
      Text(this.editing === undefined ? '新增分类' : '编辑分类').fontSize('20fp').fontWeight(FontWeight.Bold).width('100%')
      if (this.editing === undefined) {
        ChipGroup({ items: [{ label: { text: '支出分类' } }, { label: { text: '收入分类' } }],
          selectedIndexes: [this.kind === 'expense' ? 0 : 1], multiple: false,
          itemStyle: { size: ChipSize.NORMAL, backgroundColor: $r('app.color.xq_app_filter_unselected'),
            selectedBackgroundColor: $r('app.color.xq_brand'), fontColor: $r('app.color.xq_font_secondary'),
            selectedFontColor: $r('app.color.xq_font_on_primary') },
          onChange: (selected: number[]) => { this.kind = selected[0] === 1 ? 'income' : 'expense'; this.parentId = ''; this.browsingParentId = ''; }
        }).width(240).id('category-kind')
      }
      TextInput({ text: this.name, placeholder: '分类名称' }).fontSize('16fp').height(48).maxLength(20)
        .borderRadius(12).backgroundColor($r('app.color.xq_app_surface_keyboard'))
        .id('category-name').onChange((value: string) => { this.name = value; this.error = ''; })
      Text('父分类').fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      Select(this.parentSelectOptions())
        .selected(this.parentId.length === 0 ? 0 : Math.max(0, this.parentChoices().findIndex((item: CategoryProfile) => item.id === this.parentId) + 1))
        .value(this.selectedParentLabel()).font({ size: '14fp' }).height(44).backgroundColor($r('app.color.xq_app_surface_keyboard'))
        .selectedOptionBgColor($r('app.color.xq_comp_emphasize_tertiary')).id('category-parent')
        .onSelect((index: number) => { this.parentId = index === 0 ? '' : this.parentChoices()[index - 1]?.id || ''; })
      Text('图标').fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      Scroll() {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(CATEGORY_ICON_OPTIONS, (option: CategoryIconOption) => {
            Column({ space: 4 }) {
              Image(categoryIcon(option.key)).width(30).height(30)
              Text(option.label).fontSize('10fp').fontColor(this.iconKey === option.key ?
                $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_secondary'))
            }.width('25%').height(62).onClick(() => { this.iconKey = option.key; }).id('category-icon-' + option.key)
          }, (option: CategoryIconOption) => option.key)
        }.width('100%')
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      if (this.error.length > 0) {
        Text(this.error).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%')
      }
      Row({ space: 12 }) {
        Button('取消', { type: ButtonType.Capsule }).layoutWeight(1).height(44)
          .fontColor($r('app.color.xq_font_primary')).backgroundColor($r('app.color.xq_app_surface_keyboard'))
          .enabled(!this.busy).onClick(() => { this.showEditor = false; })
        Button(this.busy ? '保存中' : '保存', { type: ButtonType.Capsule }).layoutWeight(1).height(44)
          .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.busy)
          .id('category-save').onClick(() => { this.save(); })
      }.width('100%')
    }.padding(24).width('100%').height('100%')
  }

  @Builder
  private categoryRow(item: CategoryProfile) {
    Row({ space: 10 }) {
      Row({ space: 10 }) {
        Image(categoryIcon(item.iconKey)).width(30).height(30).flexShrink(0)
        Column({ space: 4 }) {
          Text(item.name).fontSize('16fp').fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.xq_font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.childCount(item) > 0) {
            Text(`${this.childCount(item)} 个` + (this.showArchived ? '子分类入口' : '子分类')).fontSize('11fp')
              .fontColor($r('app.color.xq_font_tertiary')).maxLines(1)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Image($r('app.media.lucide_chevron_right1')).width(14).height(14).fillColor($r('app.color.xq_icon_tertiary'))
      }.layoutWeight(1).height('100%').alignItems(VerticalAlign.Center)
        .onClick(() => { this.enterChildren(item); }).accessibilityText(item.name + '，查看子分类')
      Button('编辑', { type: ButtonType.Capsule }).height(32).fontSize('12fp').padding({ left: 12, right: 12 })
        .enabled(!this.interactionLocked()).backgroundColor($r('app.color.xq_app_surface_keyboard'))
        .fontColor($r('app.color.xq_font_emphasize')).onClick(() => { this.beginEdit(item); }).id('category-edit-' + item.id)
      Button(item.archived ? '恢复' : '归档', { type: ButtonType.Capsule }).height(32).fontSize('12fp').padding({ left: 12, right: 12 })
        .enabled(!this.interactionLocked()).backgroundColor($r('app.color.xq_app_surface_keyboard'))
        .fontColor($r('app.color.xq_font_secondary')).onClick(() => { this.archive(item); }).id('category-archive-' + item.id)
      Image($r('app.media.lucide_grip_vertical1')).width(20).height(24).flexShrink(0)
        .fillColor($r('app.color.xq_icon_tertiary')).opacity(this.showArchived ? 0.3 : 1)
        .accessibilityText(this.showArchived ? '归档分类不可排序' : '长按拖动排序')
    }.padding({ left: 14, right: 12 }).width('100%').height(this.rowHeight).alignItems(VerticalAlign.Center)
      .borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card')).id('category-row-' + item.id)
      .translate({ y: this.rowOffset(item.id) })
      .animation({ duration: this.resettingDrag || (this.draggedId === item.id && !this.landing) ? 0 : 200, curve: Curve.EaseOut })
      .scale({ x: this.draggedId === item.id && this.dragLifted ? 1.05 : 1, y: this.draggedId === item.id && this.dragLifted ? 1.05 : 1 })
      .shadow({ radius: this.draggedId === item.id && this.dragLifted ? 20 : 0,
        color: '#40000000', offsetX: 0, offsetY: this.draggedId === item.id && this.dragLifted ? 8 : 0 })
      .animation({ duration: this.resettingDrag ? 0 : 200, curve: Curve.EaseOut })
      .zIndex(this.draggedId === item.id ? 10 : 0)
      .gesture(GestureGroup(GestureMode.Sequence,
        LongPressGesture({ duration: 300 }).onAction((event: GestureEvent) => { this.startDrag(item, event); }),
        PanGesture({ direction: PanDirection.Vertical, distance: 0 })
          .onActionUpdate((event: GestureEvent) => { this.updateDrag(event); })
          .onActionEnd(() => { this.finishDrag(false); })
          .onActionCancel(() => { this.finishDrag(true); })
      ).onCancel(() => { this.finishDrag(true); }))
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Row() {
            ChipGroup({ items: [{ label: { text: '支出分类' } }, { label: { text: '收入分类' } }],
              selectedIndexes: [this.kind === 'expense' ? 0 : 1], multiple: false,
              itemStyle: { size: ChipSize.NORMAL, backgroundColor: $r('app.color.xq_app_filter_unselected'),
                selectedBackgroundColor: $r('app.color.xq_brand'), fontColor: $r('app.color.xq_font_secondary'),
                selectedFontColor: $r('app.color.xq_font_on_primary') },
              onChange: (selected: number[]) => { if (!this.interactionLocked()) { this.kind = selected[0] === 1 ? 'income' : 'expense'; this.browsingParentId = ''; } }
            }).width(240).enabled(!this.interactionLocked()).id('category-kind-tabs')
          }.width('100%')
          if (this.browsingParentId.length > 0) {
            Row({ space: 8 }) {
              Button({ type: ButtonType.Circle }) {
                Image($r('app.media.lucide_chevron_left1')).width(18).height(18).fillColor($r('app.color.xq_icon_primary'))
              }.width(32).height(32).padding(0).backgroundColor($r('app.color.xq_app_surface_card'))
                .enabled(!this.interactionLocked()).onClick(() => { this.navigateBack(); }).accessibilityText('返回上一级分类')
              Text(this.browsingTitle())
                .fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            }.width('100%')
          }
          Button(this.browsingParentId.length > 0 ? '新增子分类' : '新增分类', { type: ButtonType.Capsule }).width('100%').height(46).fontSize('15fp')
            .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.interactionLocked())
            .id('category-create').onClick(() => { this.beginCreate(); })
          if (this.loading) {
            Text('正在读取分类…').fontSize('14fp').padding(24)
          } else if (this.visibleRows().length === 0) {
            Text(this.showArchived ? '暂无归档分类' : '暂无分类').fontSize('14fp')
              .fontColor($r('app.color.xq_font_secondary')).padding(24)
          } else {
            Column({ space: this.rowGap }) {
              ForEach(this.visibleRows(), (item: CategoryProfile) => { this.categoryRow(item) }, (item: CategoryProfile) => item.id + ':' + item.revision)
            }.width('100%').clip(false)
          }
          if (this.error.length > 0) {
            Text(this.error).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%')
            Button('刷新分类').fontSize('14fp').enabled(!this.interactionLocked()).onClick(() => { this.load(); })
          }
        }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
        .scrollable(this.draggedId.length > 0 ? ScrollDirection.None : ScrollDirection.Vertical)
        .onAreaChange((_old: Area, area: Area) => { this.viewportTop = Number(area.globalPosition.y); this.viewportHeight = Number(area.height); })
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '收支分类' }, stackBuilder: this.archiveAction.bind(this), divider: { showType: DividerShowType.OFF },
          backIcon: { componentId: 'category-close', action: () => { if (!this.navigateBack()) { this.onClose(); } } } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
          backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
            backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showEditor, this.editorSheet(), this.sheetOptions()).id('category-management-page')
  }
}
