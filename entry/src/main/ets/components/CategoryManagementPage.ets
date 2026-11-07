import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType } from '@kit.UIDesignKit';
import { ChipGroup, ChipSize } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { CategoryCommand, CategoryProfile } from '../domain/model/CategoryProfile';
import { CATEGORY_ICON_OPTIONS, CategoryIconOption, categoryIcon } from '../presentation/ledger/CategoryIcons';

interface CategoryRowView {
  profile: CategoryProfile;
  depth: number;
  path: string;
}

interface CategorySelectOption {
  value: string;
}

@Component
export struct CategoryManagementPage {
  workspace: LedgerWorkspace | undefined = undefined;
  sheetMaterial: SystemUiMaterial | undefined = undefined;
  onClose: () => void = () => {};
  @State private values: CategoryProfile[] = [];
  @State private kind: string = 'expense';
  @State private showArchived: boolean = false;
  @State private loading: boolean = true;
  @State private showEditor: boolean = false;
  @State private editing: CategoryProfile | undefined = undefined;
  @State private name: string = '';
  @State private parentId: string = '';
  @State private iconKey: string = 'other';
  @State private busy: boolean = false;
  @State private error: string = '';
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.load(); }

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

  private depth(item: CategoryProfile): number {
    let count = 0;
    const visited: Set<string> = new Set<string>([item.id]);
    let parentId = item.parentId;
    while (parentId.length > 0 && !visited.has(parentId)) {
      const parent = this.values.find((value: CategoryProfile) => value.id === parentId);
      if (parent === undefined) { break; }
      visited.add(parentId); count++; parentId = parent.parentId;
    }
    return count;
  }

  private visibleRows(): CategoryRowView[] {
    const source = this.values.filter((item: CategoryProfile) => item.kind === this.kind && item.archived === this.showArchived);
    const result: CategoryRowView[] = [];
    const visited: Set<string> = new Set<string>();
    const visit = (item: CategoryProfile, depth: number): void => {
      if (visited.has(item.id)) { return; }
      visited.add(item.id);
      result.push({ profile: item, depth: depth, path: this.categoryPath(item) });
      source.filter((child: CategoryProfile) => child.parentId === item.id)
        .sort((left: CategoryProfile, right: CategoryProfile) =>
          left.sortOrder - right.sortOrder || left.name.localeCompare(right.name, 'zh-CN'))
        .forEach((child: CategoryProfile) => { visit(child, depth + 1); });
    };
    source.filter((item: CategoryProfile) => item.parentId.length === 0 || !source.some((parent: CategoryProfile) => parent.id === item.parentId))
      .sort((left: CategoryProfile, right: CategoryProfile) =>
        left.sortOrder - right.sortOrder || left.name.localeCompare(right.name, 'zh-CN'))
      .forEach((item: CategoryProfile) => { visit(item, 0); });
    return result;
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
    this.editing = undefined; this.name = ''; this.parentId = ''; this.iconKey = this.kind === 'income' ? 'salary' : 'other';
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
      if (this.editing === undefined) { await this.workspace.createCategory(command); }
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

  private async move(item: CategoryProfile, direction: number): Promise<void> {
    if (this.busy || this.workspace === undefined) { return; }
    this.busy = true; this.error = '';
    try {
      await this.workspace.moveCategory(item.id, item.revision, direction);
      this.values = await this.workspace.categories();
    } catch (_) { this.error = '分类顺序已变化，请刷新后重试'; }
    finally { this.busy = false; }
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
          onChange: (selected: number[]) => { this.kind = selected[0] === 1 ? 'income' : 'expense'; this.parentId = ''; }
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
  private categoryRow(row: CategoryRowView) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        if (row.depth > 0) { Blank().width(row.depth * 20) }
        Image(categoryIcon(row.profile.iconKey)).width(30).height(30)
        Column({ space: 3 }) {
          Text(row.profile.name).fontSize('16fp').fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.xq_font_primary')).maxLines(1)
          if (row.profile.parentId.length > 0) {
            Text(this.categoryPath(this.values.find((item: CategoryProfile) => item.id === row.profile.parentId) || row.profile))
              .fontSize('11fp').fontColor($r('app.color.xq_font_tertiary')).maxLines(1)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (row.profile.archived) { Text('已归档').fontSize('10fp').fontColor($r('app.color.xq_font_tertiary')) }
      }.width('100%')
      Row({ space: 8 }) {
        if (!row.profile.archived) {
          Button('上移', { type: ButtonType.Capsule }).height(30).fontSize('11fp').enabled(!this.busy)
            .backgroundColor($r('app.color.xq_app_surface_keyboard')).fontColor($r('app.color.xq_font_secondary'))
            .onClick(() => { this.move(row.profile, -1); }).id('category-up-' + row.profile.id)
          Button('下移', { type: ButtonType.Capsule }).height(30).fontSize('11fp').enabled(!this.busy)
            .backgroundColor($r('app.color.xq_app_surface_keyboard')).fontColor($r('app.color.xq_font_secondary'))
            .onClick(() => { this.move(row.profile, 1); }).id('category-down-' + row.profile.id)
        }
        Blank()
        Button('编辑', { type: ButtonType.Capsule }).height(30).fontSize('11fp').enabled(!this.busy)
          .backgroundColor($r('app.color.xq_app_surface_keyboard')).fontColor($r('app.color.xq_font_emphasize'))
          .onClick(() => { this.beginEdit(row.profile); }).id('category-edit-' + row.profile.id)
        Button(row.profile.archived ? '恢复' : '归档', { type: ButtonType.Capsule }).height(30).fontSize('11fp').enabled(!this.busy)
          .backgroundColor($r('app.color.xq_app_surface_keyboard')).fontColor($r('app.color.xq_font_secondary'))
          .onClick(() => { this.archive(row.profile); }).id('category-archive-' + row.profile.id)
      }.width('100%')
    }.padding({ left: 16, right: 16, top: 14, bottom: 14 }).width('100%')
      .borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card')).id('category-row-' + row.profile.id)
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
              onChange: (selected: number[]) => { this.kind = selected[0] === 1 ? 'income' : 'expense'; }
            }).width(240).id('category-kind-tabs')
            Blank()
            Button(this.showArchived ? '使用中' : '已归档', { type: ButtonType.Capsule }).height(32).fontSize('12fp')
              .backgroundColor(Color.Transparent).fontColor($r('app.color.xq_font_secondary'))
              .onClick(() => { this.showArchived = !this.showArchived; }).id('category-toggle-archive')
          }.width('100%')
          Button('新增分类', { type: ButtonType.Capsule }).width('100%').height(46).fontSize('15fp')
            .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.busy)
            .id('category-create').onClick(() => { this.beginCreate(); })
          if (this.loading) {
            Text('正在读取分类…').fontSize('14fp').padding(24)
          } else if (this.visibleRows().length === 0) {
            Text(this.showArchived ? '暂无归档分类' : '暂无分类').fontSize('14fp')
              .fontColor($r('app.color.xq_font_secondary')).padding(24)
          } else {
            ForEach(this.visibleRows(), (row: CategoryRowView) => { this.categoryRow(row) },
              (row: CategoryRowView) => row.profile.id + ':' + row.profile.revision)
          }
          if (this.error.length > 0) {
            Text(this.error).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%')
          }
        }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '收支分类' }, divider: { showType: DividerShowType.OFF },
          backIcon: { componentId: 'category-close', action: () => { if (!this.busy) { this.onClose(); } } } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
          backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showEditor, this.editorSheet(), this.sheetOptions()).id('category-management-page')
  }
}
