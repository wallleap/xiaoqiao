import { ChipGroup, ChipSize } from '@kit.ArkUI';
import { DividerShowType, HdsNavigation, HdsNavigationTitleMode, hdsMaterial, ScrollEffectType } from '@kit.UIDesignKit';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { LedgerStatistics, StatisticsBucket, StatisticsBudgetCategory, StatisticsCategory,
  StatisticsEntry, StatisticsKind, StatisticsTagCategory } from '../domain/model/LedgerStatistics';
import { categoryIcon } from '../presentation/ledger/CategoryIcons';
import { displayAmount } from '../presentation/ledger/LedgerOverview';
import { spendingNatureBackground, spendingNatureText } from '../presentation/ledger/SpendingNatureStyles';
import { tagBackground, tagTextColor } from '../presentation/ledger/TagStyles';
import { currentRange, localDate, parseLocalDate, rangeTitle, shiftedRange,
  StatisticsDateRange, StatisticsRange } from '../presentation/statistics/StatisticsPeriod';

@Component
export struct StatisticsPage {
  workspace: LedgerWorkspace | undefined = undefined;
  @Prop @Watch('pageContextChanged') active: boolean = false;
  @Prop @Watch('pageContextChanged') bookId: string = '';
  @Prop @Watch('pageContextChanged') refreshToken: number = 0;
  @Prop bookName: string = '';
  sheetMaterial: SystemUiMaterial | undefined = undefined;
  onOpenEntry: (id: string) => void = () => {};
  @State private kind: number = 0;
  @State private range: number = 1;
  @State private dateRange: StatisticsDateRange = currentRange('month');
  @State private statistics: LedgerStatistics | undefined = undefined;
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private customStart: string = currentRange('month').startDate;
  @State private customEnd: string = '';
  @State private customError: string = '';
  @State private showSheet: boolean = false;
  @State private sheetMode: number = 0;
  @State private selectedCategory: StatisticsCategory | undefined = undefined;
  @State private selectedTagId: string = '';
  @State private selectedSheetTitle: string = '';
  @State private selectedSheetAmount: string = '0';
  @State private entries: StatisticsEntry[] = [];
  @State private entriesLoading: boolean = false;
  @State private entriesError: string = '';
  @State private showAllCategories: boolean = false;
  private requestId: number = 0;
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const range = currentRange('month');
    this.customStart = range.startDate;
    this.customEnd = this.lastInclusive(range.endDateExclusive);
    this.dateRange = range;
    if (this.active) { this.load(); }
  }

  private pageContextChanged(): void {
    if (this.active && this.workspace !== undefined && this.bookId.length > 0) { this.load(); }
  }

  private lastInclusive(value: string): string {
    const end = parseLocalDate(value);
    end.setDate(end.getDate() - 1);
    return localDate(end);
  }

  private kindValue(): StatisticsKind {
    return this.kind === 1 ? 'income' : 'expense';
  }

  private rangeValue(): StatisticsRange {
    return this.range === 0 ? 'week' : this.range === 2 ? 'year' : this.range === 3 ? 'custom' : 'month';
  }

  private amount(minor: string): string {
    return displayAmount(minor);
  }

  private percent(value: number): string {
    return value.toFixed(value < 0.1 && value > 0 ? 2 : 1) + '%';
  }

  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' :
      '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }

  private async load(): Promise<void> {
    const workspace = this.workspace;
    if (!this.active || workspace === undefined || this.bookId.length === 0) { return; }
    const request = ++this.requestId;
    this.loading = true;
    this.error = '';
    try {
      const result = await workspace.statistics(this.dateRange.startDate, this.dateRange.endDateExclusive,
        this.kindValue(), this.dateRange.bucketUnit);
      if (request === this.requestId) { this.statistics = result; }
    } catch (_) {
      if (request === this.requestId) { this.error = '统计数据暂时无法读取，请稍后重试'; }
    } finally {
      if (request === this.requestId) { this.loading = false; }
    }
  }

  private selectKind(selected: number[]): void {
    if (selected.length !== 1 || selected[0] === this.kind) { return; }
    this.kind = selected[0];
    this.statistics = undefined;
    this.showAllCategories = false;
    this.load();
  }

  private selectRange(selected: number[]): void {
    if (selected.length !== 1) { return; }
    const next = selected[0];
    if (next === 3) {
      this.range = next;
      this.dateRange = currentRange('custom', new Date(), this.customStart, this.customEnd);
      this.customError = '';
      this.sheetMode = 0;
      this.showSheet = true;
      return;
    }
    if (next === this.range) { return; }
    this.range = next;
    this.dateRange = currentRange(this.rangeValue());
    this.statistics = undefined;
    this.showAllCategories = false;
    this.load();
  }

  private shiftPeriod(direction: number): void {
    if (this.rangeValue() === 'custom') { return; }
    this.dateRange = shiftedRange(this.rangeValue(), this.dateRange, direction);
    this.statistics = undefined;
    this.showAllCategories = false;
    this.load();
  }

  private pickCustomDate(start: boolean): void {
    const selected = parseLocalDate(start ? this.customStart : this.customEnd);
    this.getUIContext().showDatePickerDialog({
      selected: selected,
      selectedTextStyle: { color: $r('app.color.xq_font_emphasize') },
      acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      cancelButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      onDateAccept: (date: Date) => {
        const value = localDate(date);
        if (start) { this.customStart = value; } else { this.customEnd = value; }
        this.customError = '';
      }
    });
  }

  private applyCustomRange(): void {
    if (this.customStart > this.customEnd) {
      this.customError = '结束日期不能早于开始日期';
      return;
    }
    this.range = 3;
    this.dateRange = currentRange('custom', new Date(), this.customStart, this.customEnd);
    this.customError = '';
    this.showSheet = false;
    this.statistics = undefined;
    this.showAllCategories = false;
    this.load();
  }

  private openEntries(category: StatisticsCategory): void {
    this.selectedCategory = category;
    this.selectedTagId = '';
    this.selectedSheetTitle = category.name;
    this.selectedSheetAmount = category.amountMinor;
    this.sheetMode = 1;
    this.entries = [];
    this.entriesError = '';
    this.showSheet = true;
    this.loadEntries();
  }

  private openTagEntries(tag: StatisticsTagCategory): void {
    this.selectedCategory = undefined;
    this.selectedTagId = tag.key;
    this.selectedSheetTitle = '#' + tag.name;
    this.selectedSheetAmount = tag.amountMinor;
    this.sheetMode = 1;
    this.entries = [];
    this.entriesError = '';
    this.showSheet = true;
    this.loadEntries();
  }

  private async loadEntries(): Promise<void> {
    const workspace = this.workspace;
    if (workspace === undefined || (this.selectedCategory === undefined && this.selectedTagId.length === 0)) { return; }
    this.entriesLoading = true;
    this.entriesError = '';
    try {
      this.entries = await workspace.statisticsEntries(this.dateRange.startDate, this.dateRange.endDateExclusive,
        this.kindValue(), this.selectedCategory?.key || '', this.selectedTagId);
    } catch (_) { this.entriesError = '账目明细暂时无法读取，请稍后重试'; }
    finally { this.entriesLoading = false; }
  }

  private axisStartLabel(): string {
    return this.statistics?.buckets[0]?.label || '';
  }

  private axisMiddleLabel(): string {
    const buckets = this.statistics?.buckets || [];
    return buckets.length === 0 ? '' : buckets[Math.floor((buckets.length - 1) / 2)].label;
  }

  private axisEndLabel(): string {
    const buckets = this.statistics?.buckets || [];
    return buckets.length === 0 ? '' : buckets[buckets.length - 1].label;
  }

  private barHeight(bucket: StatisticsBucket): number {
    const buckets = this.statistics?.buckets || [];
    let maximum = BigInt(0);
    for (const item of buckets) {
      const amount = BigInt(item.amountMinor);
      const magnitude = amount < BigInt(0) ? -amount : amount;
      if (magnitude > maximum) { maximum = magnitude; }
    }
    const raw = BigInt(bucket.amountMinor);
    const amount = raw < BigInt(0) ? -raw : raw;
    if (amount <= BigInt(0) || maximum <= BigInt(0)) { return 4; }
    return Math.max(4, Number(amount * BigInt(52) / maximum));
  }

  @Builder
  private termChips() {
    ChipGroup({
      items: [{ label: { text: '支出' }, allowClose: false }, { label: { text: '收入' }, allowClose: false }],
      multiple: false, selectedIndexes: [this.kind],
      itemStyle: { size: ChipSize.NORMAL, backgroundColor: $r('app.color.xq_app_filter_unselected'),
        fontColor: $r('app.color.xq_font_primary'), selectedBackgroundColor: $r('app.color.xq_brand'),
        selectedFontColor: $r('app.color.xq_font_on_primary') },
      chipGroupSpace: { startSpace: 0, endSpace: 0, itemSpace: 8 },
      chipGroupPadding: { top: 0, bottom: 0 },
      onChange: (selected: number[]) => { this.selectKind(selected); }
    }).width(184).id('statistics-kind')
  }

  @Builder
  private rangeChips() {
    Row({ space: 6 }) {
      ForEach(['周', '月', '年', '自定义'], (label: string, index: number) => {
        Button(label, { type: ButtonType.Capsule }).height(36).padding({ left: 14, right: 14 })
          .fontSize('13fp').fontWeight(index === this.range ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(index === this.range ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_secondary'))
          .backgroundColor(index === this.range ? $r('app.color.xq_comp_emphasize_secondary') :
            $r('app.color.xq_app_filter_unselected'))
          .id('statistics-range-' + index).onClick(() => { this.selectRange([index]); })
      }, (_label: string, index: number) => `${index}`)
    }.width('100%').justifyContent(FlexAlign.Center).id('statistics-range')
  }

  @Builder
  private periodNavigator() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.lucide_chevron_left1')).width(20).height(20)
          .fillColor($r('app.color.xq_icon_secondary'))
      }.width(40).height(40).padding(0).backgroundColor($r('app.color.xq_app_surface_card'))
        .enabled(this.range !== 3).opacity(this.range === 3 ? 0.35 : 1)
        .accessibilityText('上一周期').onClick(() => { this.shiftPeriod(-1); })
      Text(rangeTitle(this.rangeValue(), this.dateRange)).fontSize('14fp').fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.xq_font_primary')).textAlign(TextAlign.Center).layoutWeight(1)
        .id('statistics-period-title')
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.lucide_chevron_right1')).width(20).height(20)
          .fillColor($r('app.color.xq_icon_secondary'))
      }.width(40).height(40).padding(0).backgroundColor($r('app.color.xq_app_surface_card'))
        .enabled(this.range !== 3).opacity(this.range === 3 ? 0.35 : 1)
        .accessibilityText('下一周期').onClick(() => { this.shiftPeriod(1); })
    }.width('100%')
  }

  @Builder
  private trendCard() {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 4 }) {
          Text(this.kind === 1 ? '收入总额' : '支出总额').fontSize('12fp')
            .fontColor($r('app.color.xq_font_secondary'))
          Text() {
            Span('¥')
            Span(this.amount(this.statistics?.totalMinor || '0')).fontFamily('XiaoQiaoDINBold')
          }.fontSize('30fp').fontWeight(FontWeight.Bold).fontColor($r('app.color.xq_font_primary'))
            .maxLines(1).minFontSize('20fp').maxFontSize('30fp').id('statistics-total')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(this.bookName.length > 0 ? this.bookName : '当前账本').fontSize('12fp')
          .fontColor($r('app.color.xq_font_tertiary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '42%' })
      }.width('100%')
      if ((this.statistics?.categories || []).length === 0 && !(this.statistics?.buckets || []).some((item: StatisticsBucket) => BigInt(item.amountMinor) !== BigInt(0))) {
        Column({ space: 10 }) {
          Image($r('app.media.lucide_chart_no_axes_column1')).width(44).height(44)
            .fillColor($r('app.color.xq_icon_tertiary'))
          Text(this.kind === 1 ? '暂无收入数据' : '暂无支出数据').fontSize('14fp')
            .fontColor($r('app.color.xq_font_secondary')).id('statistics-empty')
        }.width('100%').padding({ top: 18, bottom: 18 })
      } else {
        Stack({ alignContent: Alignment.Bottom }) {
          Divider().width('100%').strokeWidth(1).color($r('app.color.xq_app_divider_subtle'))
          Row({ space: 1 }) {
            ForEach(this.statistics?.buckets || [], (bucket: StatisticsBucket) => {
              Column() {
                Column() {
                  if (BigInt(bucket.amountMinor) > BigInt(0)) {
                    Row().width('82%').height(this.barHeight(bucket)).borderRadius(3)
                      .backgroundColor(this.kind === 1 ? '#FF008664' : '#FFFF5425')
                  }
                }.height(60).width('100%').justifyContent(FlexAlign.End)
                Divider().strokeWidth(1).color($r('app.color.xq_app_divider_subtle'))
                Column() {
                  if (BigInt(bucket.amountMinor) < BigInt(0)) {
                    Row().width('82%').height(this.barHeight(bucket)).borderRadius(3).backgroundColor('#FF008664')
                  }
                }.height(60).width('100%').justifyContent(FlexAlign.Start)
              }.height(124).layoutWeight(1).accessibilityText(bucket.label + ' ' + this.amount(bucket.amountMinor))
                .id('statistics-bucket-' + bucket.key)
            }, (bucket: StatisticsBucket) => bucket.key)
          }.width('100%').height(124).alignItems(VerticalAlign.Bottom)
        }.width('100%').height(124)
        Row() {
          Text(this.axisStartLabel()).fontSize('10fp').fontColor($r('app.color.xq_font_tertiary'))
            .layoutWeight(1).textAlign(TextAlign.Start)
          Text(this.axisMiddleLabel()).fontSize('10fp').fontColor($r('app.color.xq_font_tertiary'))
            .layoutWeight(1).textAlign(TextAlign.Center)
          Text(this.axisEndLabel()).fontSize('10fp').fontColor($r('app.color.xq_font_tertiary'))
            .layoutWeight(1).textAlign(TextAlign.End)
        }.width('100%').height(16)
      }
      if (this.kind === 0) { Text('零线上方为净支出，下方为净回款').fontSize('11fp').fontColor($r('app.color.xq_font_tertiary')).width('100%') }
    }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
      .id('statistics-trend')
  }

  @Builder
  private categoryRow(category: StatisticsCategory) {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Stack() {
          if (category.key === 'transfer_fee') {
            Image($r('app.media.lucide_arrow_left_right1')).width(24).height(24)
              .fillColor($r('app.color.xq_icon_emphasize'))
          } else {
            Image(categoryIcon(category.iconKey)).width(28).height(28).objectFit(ImageFit.Contain)
          }
        }.width(44).height(44).borderRadius(22).backgroundColor($r('app.color.xq_app_surface_page'))
        Column({ space: 3 }) {
          Text(category.name).fontSize('16fp').fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.xq_font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.percent(category.share)).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text('¥' + this.amount(category.amountMinor)).fontSize('16fp').fontFamily('XiaoQiaoDINMedium')
          .fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary')).maxLines(1)
          .minFontSize('12fp').maxFontSize('16fp').constraintSize({ maxWidth: '42%' })
        Image($r('app.media.lucide_chevron_right1')).width(16).height(16)
          .fillColor($r('app.color.xq_icon_tertiary'))
      }.width('100%')
      Progress({ value: Math.max(0, Math.min(100, category.share)), total: 100, type: ProgressType.Linear })
        .width('100%').height(4).color(this.kind === 1 ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
        .backgroundColor($r('app.color.xq_comp_background_tertiary'))
    }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      .id('statistics-category-' + category.key).onClick(() => { this.openEntries(category); })
  }

  @Builder
  private categoryRanking() {
    Column({ space: 10 }) {
      Row() {
        Text('收支分类排行').fontSize('18fp').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.xq_font_primary'))
        Blank()
        Text('按一级分类汇总').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        if ((this.statistics?.categories || []).length > 5) {
          Button(this.showAllCategories ? '收起' : '查看全部', { type: ButtonType.Capsule })
            .height(28).padding({ left: 8, right: 8 }).fontSize('12fp')
            .fontColor($r('app.color.xq_font_emphasize')).backgroundColor(Color.Transparent)
            .id('statistics-category-toggle')
            .onClick(() => { this.showAllCategories = !this.showAllCategories; })
        }
      }.width('100%')
      if ((this.statistics?.categories || []).length === 0) {
        Text(this.kind === 1 ? '这个周期还没有收入' : '这个周期还没有支出').fontSize('14fp')
          .fontColor($r('app.color.xq_font_secondary')).width('100%').padding({ top: 20, bottom: 20 })
      } else {
        ForEach(this.showAllCategories ? (this.statistics?.categories || []) :
          (this.statistics?.categories || []).slice(0, 5), (category: StatisticsCategory) => {
          this.categoryRow(category)
        }, (category: StatisticsCategory) => category.key + ':' + category.amountMinor)
      }
    }.width('100%').id('statistics-category-ranking')
  }

  @Builder
  private budgetRow(category: StatisticsBudgetCategory) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(category.name).fontSize('15fp').fontWeight(FontWeight.Medium)
          .fontColor(spendingNatureText(category.colorKey)).maxLines(1)
        Text(this.percent(category.share)).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('¥' + this.amount(category.amountMinor)).fontSize('16fp').fontFamily('XiaoQiaoDINMedium')
        .fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('12fp').maxFontSize('16fp')
    }.padding(16).width('100%').borderRadius(16).backgroundColor(spendingNatureBackground(category.colorKey))
      .id('statistics-budget-' + category.key)
  }

  @Builder
  private budgetRanking() {
    if (this.kind === 0 && (this.statistics?.budgetCategories || []).length > 0) {
      Column({ space: 10 }) {
        Row() {
          Text('预算分类排行').fontSize('18fp').fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.xq_font_primary'))
          Blank()
          Text('仅统计计入预算的支出').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        }.width('100%')
        ForEach((this.statistics?.budgetCategories || []).slice(0, 5), (category: StatisticsBudgetCategory) => {
          this.budgetRow(category)
        }, (category: StatisticsBudgetCategory) => category.key + ':' + category.amountMinor)
      }.width('100%').id('statistics-budget-ranking')
    }
  }

  @Builder
  private tagRow(tag: StatisticsTagCategory) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text('#' + tag.name).fontSize('16fp').fontWeight(FontWeight.Medium)
          .fontColor(tagTextColor(tag.colorKey)).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${tag.entryCount} 笔 · ${this.percent(tag.share)}`).fontSize('12fp')
          .fontColor($r('app.color.xq_font_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('¥' + this.amount(tag.amountMinor)).fontSize('16fp').fontFamily('XiaoQiaoDINMedium')
        .fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('12fp').maxFontSize('16fp')
      Image($r('app.media.lucide_chevron_right1')).width(16).height(16)
        .fillColor($r('app.color.xq_icon_tertiary'))
    }.padding(16).width('100%').borderRadius(16).backgroundColor(tagBackground(tag.colorKey))
      .id('statistics-tag-' + tag.key).onClick(() => { this.openTagEntries(tag); })
  }

  @Builder
  private tagRanking() {
    if ((this.statistics?.tagCategories || []).length > 0) {
      Column({ space: 10 }) {
        Row() {
          Text('标签排行').fontSize('18fp').fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.xq_font_primary'))
          Blank()
          Text('多标签账目分别计入').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        }.width('100%')
        ForEach((this.statistics?.tagCategories || []).slice(0, 5), (tag: StatisticsTagCategory) => {
          this.tagRow(tag)
        }, (tag: StatisticsTagCategory) => tag.key + ':' + tag.amountMinor + ':' + tag.entryCount)
      }.width('100%').id('statistics-tag-ranking')
    }
  }

  @Builder
  private customSheet() {
    Column({ space: 18 }) {
      Text('自定义统计范围').fontSize('20fp').fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.xq_font_primary')).width('100%')
      Text('选择起止日期，结束日期当天会包含在统计中。').fontSize('12fp')
        .fontColor($r('app.color.xq_font_secondary')).width('100%')
      Row({ space: 12 }) {
        Column({ space: 6 }) {
          Text('开始日期').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
          Button(this.customStart.replace(/-/g, '.'), { type: ButtonType.Normal }).width('100%').height(48)
            .fontSize('16fp').fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_primary'))
            .backgroundColor($r('app.color.xq_app_surface_page')).id('statistics-custom-start')
            .onClick(() => { this.pickCustomDate(true); })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 6 }) {
          Text('结束日期').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
          Button(this.customEnd.replace(/-/g, '.'), { type: ButtonType.Normal }).width('100%').height(48)
            .fontSize('16fp').fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_primary'))
            .backgroundColor($r('app.color.xq_app_surface_page')).id('statistics-custom-end')
            .onClick(() => { this.pickCustomDate(false); })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      if (this.customError.length > 0) {
        Text(this.customError).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%')
      }
      Row({ space: 12 }) {
        Button('取消', { type: ButtonType.Capsule }).layoutWeight(1).height(44)
          .fontColor($r('app.color.xq_font_primary')).backgroundColor($r('app.color.xq_app_surface_page'))
          .onClick(() => { this.showSheet = false; })
        Button('查看统计', { type: ButtonType.Capsule }).layoutWeight(1).height(44)
          .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).id('statistics-custom-apply')
          .onClick(() => { this.applyCustomRange(); })
      }.width('100%')
    }.padding(24).width('100%').height('100%')
  }

  @Builder
  private entryRow(entry: StatisticsEntry) {
    Row({ space: 12 }) {
      Stack() {
        if (entry.categoryKey === 'transfer_fee') {
          Image($r('app.media.lucide_arrow_left_right1')).width(22).height(22)
            .fillColor($r('app.color.xq_icon_emphasize'))
        } else {
          Image(categoryIcon(entry.iconKey)).width(26).height(26).objectFit(ImageFit.Contain)
        }
      }.width(40).height(40).borderRadius(20).backgroundColor($r('app.color.xq_app_surface_page'))
      Column({ space: 4 }) {
        Text(entry.title).fontSize('16fp').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.xq_font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(entry.date + ' · ' + entry.categoryName).fontSize('12fp')
          .fontColor($r('app.color.xq_font_secondary')).maxLines(1)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('¥' + this.amount(entry.amountMinor)).fontSize('16fp').fontFamily('XiaoQiaoDINMedium')
        .fontColor(this.kind === 1 ? $r('app.color.xq_app_income') : $r('app.color.xq_font_primary'))
        .maxLines(1).minFontSize('12fp').maxFontSize('16fp')
      Image($r('app.media.lucide_chevron_right1')).width(16).height(16)
        .fillColor($r('app.color.xq_icon_tertiary'))
    }.padding({ top: 12, bottom: 12, left: 4, right: 4 }).width('100%')
      .id('statistics-entry-' + entry.id).onClick(() => {
        this.showSheet = false;
        this.onOpenEntry(entry.id);
      })
  }

  @Builder
  private entriesSheet() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text(this.selectedSheetTitle || '账目明细').fontSize('20fp').fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.xq_font_primary'))
          Text(rangeTitle(this.rangeValue(), this.dateRange) + ' · ' + (this.kind === 1 ? '收入' : '支出'))
            .fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text('¥' + this.amount(this.selectedSheetAmount)).fontSize('18fp')
          .fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_primary'))
      }.width('100%').padding({ right: 40 })
      Divider().strokeWidth(0.5).color($r('app.color.xq_app_divider_subtle'))
      if (this.entriesLoading) {
        Text('正在读取明细…').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
          .padding(24).width('100%').textAlign(TextAlign.Center)
      } else if (this.entriesError.length > 0) {
        Text(this.entriesError).fontSize('14fp').fontColor($r('app.color.xq_warning')).width('100%')
        Button('重试').onClick(() => { this.loadEntries(); })
      } else {
        List() {
          ForEach(this.entries, (entry: StatisticsEntry) => {
            ListItem() { this.entryRow(entry) }
          }, (entry: StatisticsEntry) => entry.id)
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
        if (this.entries.length === 0) {
          Text('当前条件下没有明细').fontSize('14fp')
            .fontColor($r('app.color.xq_font_secondary')).width('100%').textAlign(TextAlign.Center).padding(24)
        }
      }
    }.padding(24).width('100%').height('100%').id('statistics-entries-sheet')
  }

  @Builder
  private sheetContent() {
    if (this.sheetMode === 0) { this.customSheet() } else { this.entriesSheet() }
  }

  private sheetOptions(): SheetOptions {
    const options: SheetOptions = { height: this.sheetMode === 0 ? 360 : 620, showClose: true };
    if (this.sheetMaterial !== undefined) { options.systemMaterial = this.sheetMaterial; }
    else { options.backgroundColor = $r('app.color.xq_app_surface_card'); }
    return options;
  }

  @Builder
  private content() {
    Scroll(this.scroller) {
      Column({ space: 16 }) {
        Column({ space: 10 }) {
          this.termChips()
          this.rangeChips()
        }.width('100%').alignItems(HorizontalAlign.Center)
        this.periodNavigator()
        if (this.loading && this.statistics === undefined) {
          Text('正在汇总账目…').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
            .width('100%').padding(32).textAlign(TextAlign.Center)
        } else if (this.error.length > 0) {
          Column({ space: 12 }) {
            Text(this.error).fontSize('14fp').fontColor($r('app.color.xq_warning'))
            Button('重新读取').onClick(() => { this.load(); }).id('statistics-retry')
          }.width('100%').padding(24)
        } else {
          this.trendCard()
          this.categoryRanking()
          this.tagRanking()
          this.budgetRanking()
          Text('标签排行中，多标签账目会在每个标签分别计入；转账本金不计入收支和标签金额。')
            .fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')).lineHeight('18fp')
            .width('100%').padding({ left: 4, right: 4 })
        }
      }.width('100%').constraintSize({ maxWidth: 720 })
        .padding({ left: 16, right: 16, top: 8, bottom: 128 })
    }.id('statistics-scroll').width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  build() {
    HdsNavigation() {
      this.content()
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI).hideBackButton(true)
      .titleBar({ enableComponentSafeArea: true, avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '统计' }, divider: { showType: DividerShowType.OFF } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() },
        { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showSheet, this.sheetContent(), this.sheetOptions())
      .id('statistics-page')
  }
}
