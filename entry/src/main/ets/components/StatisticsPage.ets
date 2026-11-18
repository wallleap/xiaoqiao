import { ItemRestriction, SegmentButton, SegmentButtonOptions, SegmentButtonTextItem } from '@kit.ArkUI';
import { DividerShowType, HdsNavigation, HdsNavigationTitleMode, hdsMaterial, ScrollEffectType } from '@kit.UIDesignKit';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { LedgerStatistics, StatisticsBucket, StatisticsBudgetCategory, StatisticsCategory,
  StatisticsEntry, StatisticsKind, StatisticsTagCategory } from '../domain/model/LedgerStatistics';
import { categoryIcon } from '../presentation/ledger/CategoryIcons';
import { displayAmount } from '../presentation/ledger/LedgerOverview';
import { spendingNatureBackground, spendingNatureText } from '../presentation/ledger/SpendingNatureStyles';
import { tagTextColor } from '../presentation/ledger/TagStyles';
import { currentRange, localDate, parseLocalDate, rangeTitle, shiftedRange,
  StatisticsDateRange, StatisticsRange } from '../presentation/statistics/StatisticsPeriod';

interface CategoryRingSlice {
  key: string;
  name: string;
  amountMinor: string;
  share: number;
  startAngle: number;
  sweepAngle: number;
  color: string;
}

const CATEGORY_RING_COLORS: string[] = ['#FF5425', '#E5A132', '#32A88A', '#4C87DC', '#9672CF', '#939BA8'];

interface TrendPoint {
  x: number;
  y: number;
}

interface TagRankingItem {
  tag: StatisticsTagCategory;
  kind: StatisticsKind;
}

@Component
export struct StatisticsPage {
  workspace: LedgerWorkspace | undefined = undefined;
  @Prop @Watch('pageContextChanged') active: boolean = false;
  @Prop @Watch('pageContextChanged') bookId: string = '';
  @Prop @Watch('pageContextChanged') refreshToken: number = 0;
  @Prop bookName: string = '';
  sheetMaterial: SystemUiMaterial | undefined = undefined;
  @Prop @Watch('applyRangeMaterial') rangeMaterial: SystemUiMaterial | undefined = undefined;
  onOpenEntry: (id: string) => void = () => {};
  @State private kind: number = 0;
  @State private range: number = 1;
  @State @Watch('rangeSelectionChanged') private rangeSelection: number[] = [1];
  @State private rangeOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '周' }, { text: '月' }, { text: '年' }, { text: '自定义' }] as ItemRestriction<SegmentButtonTextItem>,
    fontSize: '13fp', selectedFontSize: '13fp',
    fontColor: $r('sys.color.font_primary'), selectedFontColor: $r('app.color.xq_font_on_primary'),
    backgroundColor: Color.Transparent, selectedBackgroundColor: $r('app.color.xq_brand')
  });
  @State private dateRange: StatisticsDateRange = currentRange('month');
  @State @Watch('redrawLineCharts') private statistics: LedgerStatistics | undefined = undefined;
  @State @Watch('redrawLineCharts') private incomeStatistics: LedgerStatistics | undefined = undefined;
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
  @State private showAllIncomeCategories: boolean = false;
  @State @Watch('redrawLineCharts') private lineChartWidth: number = 280;
  @State private expenseTrendIndex: number = -1;
  @State private incomeTrendIndex: number = -1;
  @State private selectedExpenseSlice: string = '';
  @State private selectedIncomeSlice: string = '';
  @State private selectedBarKey: string = '';
  @State private selectedBarIncome: boolean = false;
  @State private barChartWidth: number = 280;
  private requestId: number = 0;
  private readonly scroller: Scroller = new Scroller();
  private readonly expenseLineContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private readonly incomeLineContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private expenseLineReady: boolean = false;
  private incomeLineReady: boolean = false;

  aboutToAppear(): void {
    this.applyRangeMaterial();
    const range = currentRange('month');
    this.customStart = range.startDate;
    this.customEnd = this.lastInclusive(range.endDateExclusive);
    this.dateRange = range;
    if (this.active) { this.load(); }
  }

  private applyRangeMaterial(): void {
    const options = SegmentButtonOptions.tab({
      buttons: [{ text: '周' }, { text: '月' }, { text: '年' }, { text: '自定义' }] as ItemRestriction<SegmentButtonTextItem>,
      fontSize: '13fp', selectedFontSize: '13fp',
      fontColor: $r('sys.color.font_primary'), selectedFontColor: $r('app.color.xq_font_on_primary'),
      backgroundColor: Color.Transparent, selectedBackgroundColor: $r('app.color.xq_brand')
    });
    // Material instances are supplied only by the existing API 26 capability-gated factory.
    if (this.rangeMaterial !== undefined) { options.backgroundSystemMaterial = this.rangeMaterial; }
    this.rangeOptions = options;
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

  private periodTitle(): string {
    if (this.rangeValue() !== 'custom' && this.rangeValue() !== 'week') { return rangeTitle(this.rangeValue(), this.dateRange); }
    return this.dateRange.startDate.replace(/-/g, '/') + ' — ' +
      this.lastInclusive(this.dateRange.endDateExclusive).replace(/-/g, '/');
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
    this.expenseTrendIndex = -1; this.incomeTrendIndex = -1; this.selectedBarKey = '';
    this.selectedExpenseSlice = ''; this.selectedIncomeSlice = '';
    this.error = '';
    try {
      const range = this.dateRange;
      const results = await Promise.all([
        workspace.statistics(range.startDate, range.endDateExclusive, 'expense', range.bucketUnit),
        workspace.statistics(range.startDate, range.endDateExclusive, 'income', range.bucketUnit)
      ]);
      if (request === this.requestId) { this.statistics = results[0]; this.incomeStatistics = results[1]; }
    } catch (_) {
      if (request === this.requestId) { this.error = '统计数据暂时无法读取，请稍后重试'; }
    } finally {
      if (request === this.requestId) { this.loading = false; }
    }
  }

  private rangeSelectionChanged(): void {
    if (this.rangeSelection.length === 1 && this.rangeSelection[0] !== this.range) {
      this.selectRange(this.rangeSelection);
    }
  }

  private selectRange(selected: number[]): void {
    if (selected.length !== 1) { return; }
    const next = selected[0];
    if (next === 3) {
      this.customError = '';
      this.sheetMode = 0;
      this.showSheet = true;
      return;
    }
    if (next === this.range) { return; }
    this.range = next;
    this.dateRange = currentRange(this.rangeValue());
    this.statistics = undefined; this.incomeStatistics = undefined;
    this.showAllCategories = false; this.showAllIncomeCategories = false;
    this.load();
  }

  private shiftPeriod(direction: number): void {
    if (this.rangeValue() === 'custom') { return; }
    this.dateRange = shiftedRange(this.rangeValue(), this.dateRange, direction);
    this.statistics = undefined; this.incomeStatistics = undefined;
    this.showAllCategories = false; this.showAllIncomeCategories = false;
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
    this.statistics = undefined; this.incomeStatistics = undefined;
    this.showAllCategories = false; this.showAllIncomeCategories = false;
    this.load();
  }

  private openEntries(category: StatisticsCategory, kind: StatisticsKind): void {
    this.kind = kind === 'income' ? 1 : 0;
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

  private openTagEntries(tag: StatisticsTagCategory, kind: StatisticsKind): void {
    this.kind = kind === 'income' ? 1 : 0;
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

  private bucketMinor(key: string, income: boolean): string {
    return (income ? this.incomeStatistics : this.statistics)?.buckets.find((item: StatisticsBucket) => item.key === key)?.amountMinor || '0';
  }

  private positiveMinor(value: string): string {
    return BigInt(value) > BigInt(0) ? value : '0';
  }

  private barHeight(value: string): number {
    let maximum = BigInt(0);
    for (const item of [...(this.statistics?.buckets || []), ...(this.incomeStatistics?.buckets || [])]) {
      const amount = BigInt(item.amountMinor);
      if (amount > maximum) { maximum = amount; }
    }
    const amount = BigInt(this.positiveMinor(value));
    if (amount <= BigInt(0) || maximum <= BigInt(0)) { return 0; }
    return Math.max(4, Number(amount * BigInt(52) / maximum));
  }

  private balanceMinor(): string {
    return (BigInt(this.incomeStatistics?.totalMinor || '0') - BigInt(this.statistics?.totalMinor || '0')).toString();
  }

  private rankedCategories(income: boolean): StatisticsCategory[] {
    return ((income ? this.incomeStatistics : this.statistics)?.categories || []).slice()
      .sort((left: StatisticsCategory, right: StatisticsCategory): number => {
        const a = BigInt(left.amountMinor); const b = BigInt(right.amountMinor);
        return a === b ? 0 : a > b ? -1 : 1;
      });
  }

  private rankedTags(): TagRankingItem[] {
    const values: TagRankingItem[] = [];
    for (const tag of this.statistics?.tagCategories || []) { values.push({ tag: tag, kind: 'expense' }); }
    for (const tag of this.incomeStatistics?.tagCategories || []) { values.push({ tag: tag, kind: 'income' }); }
    return values.sort((left: TagRankingItem, right: TagRankingItem): number => {
      const a = BigInt(left.tag.amountMinor); const b = BigInt(right.tag.amountMinor);
      return a === b ? 0 : a > b ? -1 : 1;
    });
  }

  @Builder
  private rangeChips() {
    SegmentButton({ options: this.rangeOptions, selectedIndexes: $rangeSelection,
      onItemClicked: (index: number) => { if (index === 3 && this.range === 3) { this.selectRange([3]); } }
    }).width(272).constraintSize({ maxWidth: '100%' }).id('statistics-range')
  }

  @Builder
  private rangeAction() {
    Row() { this.rangeChips() }.width('100%').justifyContent(FlexAlign.End)
      .padding({ left: 64, right: 16 }).hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private periodButton(direction: number) {
    if (this.rangeMaterial !== undefined) {
      Button({ type: ButtonType.Circle }) {
        Image(direction < 0 ? $r('app.media.lucide_chevron_left1') : $r('app.media.lucide_chevron_right1'))
          .width(20).height(20).fillColor($r('app.color.xq_icon_secondary'))
      }.width(40).height(40).padding(0).backgroundColor(Color.Transparent).systemMaterial(this.rangeMaterial)
        .enabled(this.range !== 3).opacity(this.range === 3 ? 0.35 : 1)
        .accessibilityText(direction < 0 ? '上一周期' : '下一周期').onClick(() => { this.shiftPeriod(direction); })
    } else {
      Button({ type: ButtonType.Circle }) {
        Image(direction < 0 ? $r('app.media.lucide_chevron_left1') : $r('app.media.lucide_chevron_right1'))
          .width(20).height(20).fillColor($r('app.color.xq_icon_secondary'))
      }.width(40).height(40).padding(0).backgroundColor($r('app.color.xq_app_surface_card'))
        .enabled(this.range !== 3).opacity(this.range === 3 ? 0.35 : 1)
        .accessibilityText(direction < 0 ? '上一周期' : '下一周期').onClick(() => { this.shiftPeriod(direction); })
    }
  }

  @Builder
  private periodNavigator() {
    Row({ space: 8 }) {
      this.periodButton(-1)
      Text(this.periodTitle()).fontSize('14fp').fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.xq_font_primary')).textAlign(TextAlign.Center).layoutWeight(1)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .id('statistics-period-title').accessibilityDescription(this.range === 3 ? '点击修改自定义日期范围' : '')
        .onClick(() => { if (this.range === 3) { this.selectRange([3]); } })
      this.periodButton(1)
    }.width('100%').constraintSize({ maxWidth: 400 })
  }

  @Builder
  private fixedPeriodNavigator() {
    Column() { this.periodNavigator() }.width('100%').height(56)
      .padding({ left: 32, right: 32, top: 8, bottom: 8 })
      .backgroundColor(Color.Transparent)
  }

  @Builder
  private summaryAmount(label: string, minor: string, income: boolean, componentId: string) {
    Column({ space: 4 }) {
      Text(label).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
      Text('¥' + this.amount(minor)).fontSize('22fp').fontFamily('XiaoQiaoDINMedium')
        .fontWeight(FontWeight.Medium).fontColor(income ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
        .maxLines(1).minFontSize('14fp').maxFontSize('22fp').id(componentId)
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private trendBar(value: string, income: boolean) {
    Column() {
      if (BigInt(value) > BigInt(0)) {
        Row().width('88%').height(this.barHeight(value)).borderRadius(2)
          .backgroundColor(income ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
      }
    }.height(60).width('100%').justifyContent(income ? FlexAlign.End : FlexAlign.Start)
  }

  private selectBar(x: number, y: number, toggle: boolean = true): void {
    const buckets = this.statistics?.buckets || [];
    if (buckets.length === 0 || (toggle && y < 44)) { return; }
    const index = Math.max(0, Math.min(buckets.length - 1, Math.floor(x / Math.max(1, this.barChartWidth) * buckets.length)));
    const income = y < 105;
    if (toggle && this.selectedBarKey === buckets[index].key && this.selectedBarIncome === income) {
      this.selectedBarKey = '';
    } else {
      this.selectedBarKey = buckets[index].key; this.selectedBarIncome = income;
    }
  }

  private dragBar(event: GestureEvent): void {
    const finger = event.fingerList[0];
    if (finger !== undefined) { this.selectBar(finger.localX, finger.localY, false); }
  }

  private barTooltipX(): number {
    const buckets = this.statistics?.buckets || [];
    const index = buckets.findIndex((bucket: StatisticsBucket) => bucket.key === this.selectedBarKey);
    return Math.max(0, Math.min(this.barChartWidth - 132, (index + 0.5) * this.barChartWidth / Math.max(1, buckets.length) - 66));
  }

  @Builder
  private trendCard() {
    Column({ space: 16 }) {
      Row() {
        this.summaryAmount('支出总额', this.statistics?.totalMinor || '0', false, 'statistics-total')
        this.summaryAmount('收入总额', this.incomeStatistics?.totalMinor || '0', true, 'statistics-income-total')
      }.width('100%')
      Row() {
        Text('结余  ¥' + this.amount(this.balanceMinor())).fontSize('14fp').fontFamily('XiaoQiaoDINMedium')
          .fontColor($r('app.color.xq_font_primary')).layoutWeight(1).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).id('statistics-balance')
        Text(this.bookName.length > 0 ? this.bookName : '当前账本').fontSize('12fp')
          .fontColor($r('app.color.xq_font_tertiary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '35%' })
      }.width('100%')
      Row({ space: 6 }) {
        Circle().width(6).height(6).fill($r('app.color.xq_brand'))
        Text('支出').fontSize('11fp').fontColor($r('app.color.xq_font_secondary')).margin({ right: 8 })
        Circle().width(6).height(6).fill($r('app.color.xq_app_income'))
        Text('收入').fontSize('11fp').fontColor($r('app.color.xq_font_secondary'))
      }.width('100%')
      if (this.rankedCategories(false).length === 0 && this.rankedCategories(true).length === 0 &&
        ![...(this.statistics?.buckets || []), ...(this.incomeStatistics?.buckets || [])].some((item: StatisticsBucket) => BigInt(item.amountMinor) !== BigInt(0))) {
        Column({ space: 10 }) {
          Image($r('app.media.lucide_chart_no_axes_column1')).width(44).height(44).fillColor($r('app.color.xq_icon_tertiary'))
          Text('暂无收支数据').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).id('statistics-empty')
        }.width('100%').padding({ top: 18, bottom: 18 })
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Row({ space: 2 }) {
            ForEach(this.statistics?.buckets || [], (bucket: StatisticsBucket) => {
              Column() {
                this.trendBar(this.bucketMinor(bucket.key, true), true)
                Divider().strokeWidth(1).color($r('app.color.xq_app_divider_subtle'))
                this.trendBar(bucket.amountMinor, false)
              }.layoutWeight(1).borderRadius(4)
                .backgroundColor(this.selectedBarKey === bucket.key ? $r('app.color.xq_app_filter_unselected') : Color.Transparent)
                .accessibilityText(bucket.label + ' 支出 ' + this.amount(this.positiveMinor(bucket.amountMinor)) +
                ' 收入 ' + this.amount(this.positiveMinor(this.bucketMinor(bucket.key, true)))).id('statistics-bucket-' + bucket.key)
            }, (bucket: StatisticsBucket) => bucket.key)
          }.width('100%').height(124).position({ x: 0, y: 44 }).hitTestBehavior(HitTestMode.None)
          if (this.selectedBarKey.length > 0) {
            Column({ space: 2 }) {
              Text(this.selectedBarKey + (this.selectedBarIncome ? ' · 收入' : ' · 支出'))
                .fontSize('10fp').fontColor(Color.White).maxLines(1)
              Text('¥' + this.amount(this.positiveMinor(this.bucketMinor(this.selectedBarKey, this.selectedBarIncome))))
                .fontSize('12fp').fontFamily('XiaoQiaoDINMedium').fontColor(Color.White)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.width(132).height(40).justifyContent(FlexAlign.Center).borderRadius(8)
              .backgroundColor(this.selectedBarIncome ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
              .position({ x: this.barTooltipX(), y: 0 }).hitTestBehavior(HitTestMode.None)
              .id('statistics-bar-tooltip')
          }
        }.width('100%').height(168)
          .onAreaChange((_oldArea: Area, area: Area) => { this.barChartWidth = Math.max(1, Number(area.width)); })
          .onClick((event: ClickEvent) => { this.selectBar(event.x, event.y); })
          .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 4 })
            .onActionStart((event: GestureEvent) => { this.dragBar(event); })
            .onActionUpdate((event: GestureEvent) => { this.dragBar(event); })
            .onActionEnd((event: GestureEvent) => { this.dragBar(event); }))
          .accessibilityText('横向拖动选择日期，上方为收入、下方为支出，也可点击查看金额')
        Row() {
          Text(this.axisStartLabel()).fontSize('10fp').fontColor($r('app.color.xq_font_tertiary')).layoutWeight(1).textAlign(TextAlign.Start)
          Text(this.axisMiddleLabel()).fontSize('10fp').fontColor($r('app.color.xq_font_tertiary')).layoutWeight(1).textAlign(TextAlign.Center)
          Text(this.axisEndLabel()).fontSize('10fp').fontColor($r('app.color.xq_font_tertiary')).layoutWeight(1).textAlign(TextAlign.End)
        }.width('100%').height(16)
      }
      Text('上方为收入，下方为支出；图表仅展示正向金额，支出总额已扣除报销与退款。').fontSize('11fp')
        .fontColor($r('app.color.xq_font_tertiary')).width('100%')
    }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card')).id('statistics-trend')
  }

  private lineBuckets(income: boolean): StatisticsBucket[] {
    return ((income ? this.incomeStatistics : this.statistics)?.buckets || []).map((bucket: StatisticsBucket): StatisticsBucket => ({
      key: bucket.key, label: bucket.label, amountMinor: this.positiveMinor(bucket.amountMinor)
    }));
  }

  private linePoints(income: boolean): TrendPoint[] {
    const buckets = this.lineBuckets(income);
    let minimum = BigInt(0); let maximum = BigInt(0);
    for (const bucket of buckets) {
      const value = BigInt(bucket.amountMinor);
      if (value < minimum) { minimum = value; }
      if (value > maximum) { maximum = value; }
    }
    const span = maximum - minimum;
    return buckets.map((bucket: StatisticsBucket, index: number): TrendPoint => ({
      x: buckets.length <= 1 ? this.lineChartWidth / 2 : 8 + index * Math.max(0, this.lineChartWidth - 16) / (buckets.length - 1),
      y: span === BigInt(0) ? 140 : 36 + Number((maximum - BigInt(bucket.amountMinor)) * BigInt(10000) / span) / 10000 * 104
    }));
  }

  private lineBaseline(): number { return 140; }

  private redrawLineCharts(): void {
    if (this.expenseLineReady) { this.drawLineChart(false); }
    if (this.incomeLineReady) { this.drawLineChart(true); }
  }

  private traceLine(context: CanvasRenderingContext2D, points: TrendPoint[]): void {
    context.beginPath();
    context.moveTo(points[0].x, points[0].y);
    for (let index = 1; index < points.length; index++) {
      const previous = points[index - 1]; const current = points[index];
      const middle = (previous.x + current.x) / 2;
      context.bezierCurveTo(middle, previous.y, middle, current.y, current.x, current.y);
    }
  }

  private drawLineChart(income: boolean): void {
    const context = income ? this.incomeLineContext : this.expenseLineContext;
    context.clearRect(0, 0, this.lineChartWidth, 156);
    const points = this.linePoints(income);
    if (points.length === 0) { return; }
    const host = this.getUIContext().getHostContext();
    const color = host === undefined ? (income ? 0x008664 : 0xFF5425) :
      host.resourceManager.getColorSync(income ? $r('app.color.xq_app_income').id : $r('app.color.xq_brand').id);
    const rgb = ((color >>> 16) & 255) + ',' + ((color >>> 8) & 255) + ',' + (color & 255);
    const baseline = this.lineBaseline();
    const zeroStop = Math.max(0, Math.min(1, (baseline - 36) / 104));
    const gradient = context.createLinearGradient(0, 36, 0, 140);
    if (zeroStop > 0) { gradient.addColorStop(0, 'rgba(' + rgb + ',0.28)'); }
    gradient.addColorStop(zeroStop, 'rgba(' + rgb + ',0)');
    if (zeroStop < 1) { gradient.addColorStop(1, 'rgba(' + rgb + ',0.28)'); }
    this.traceLine(context, points);
    context.lineTo(points[points.length - 1].x, baseline);
    context.lineTo(points[0].x, baseline);
    context.closePath();
    context.fillStyle = gradient;
    context.fill();
    context.beginPath();
    context.moveTo(8, baseline); context.lineTo(this.lineChartWidth - 8, baseline);
    context.strokeStyle = 'rgba(' + rgb + ',0.12)'; context.lineWidth = 1;
    context.stroke();
    this.traceLine(context, points);
    context.strokeStyle = 'rgb(' + rgb + ')'; context.lineWidth = 2;
    context.lineJoin = 'round'; context.lineCap = 'round';
    context.stroke();
  }

  private selectedTrendIndex(income: boolean): number {
    return income ? this.incomeTrendIndex : this.expenseTrendIndex;
  }

  private selectedTrendPoint(income: boolean): TrendPoint {
    return this.linePoints(income)[this.selectedTrendIndex(income)] || { x: 8, y: 140 };
  }

  private selectedTrendBucket(income: boolean): StatisticsBucket | undefined {
    return this.lineBuckets(income)[this.selectedTrendIndex(income)];
  }

  private selectTrendPoint(income: boolean, x: number): void {
    const count = this.lineBuckets(income).length;
    if (count === 0) { return; }
    const index = Math.max(0, Math.min(count - 1, Math.round((x - 8) / Math.max(1, this.lineChartWidth - 16) * (count - 1))));
    if (income) { this.incomeTrendIndex = index; } else { this.expenseTrendIndex = index; }
  }

  private dragTrend(income: boolean, event: GestureEvent): void {
    const finger = event.fingerList[0];
    if (finger !== undefined) { this.selectTrendPoint(income, finger.localX); }
  }

  @Builder
  private lineTrendCard(income: boolean) {
    Column({ space: 8 }) {
      Row() {
        Text(income ? '收入走势' : '支出走势').fontSize('18fp').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.xq_font_primary')).layoutWeight(1)
        Text('¥' + this.amount((income ? this.incomeStatistics : this.statistics)?.totalMinor || '0'))
          .fontSize('16fp').fontFamily('XiaoQiaoDINMedium')
          .fontColor(income ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '50%' })
      }.width('100%')
      if (!this.lineBuckets(income).some((bucket: StatisticsBucket) => BigInt(bucket.amountMinor) !== BigInt(0))) {
        Text(income ? '这个周期暂无收入走势' : '这个周期暂无支出走势').fontSize('14fp')
          .fontColor($r('app.color.xq_font_secondary')).width('100%').padding({ top: 36, bottom: 36 }).textAlign(TextAlign.Center)
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Canvas(income ? this.incomeLineContext : this.expenseLineContext).width('100%').height(156)
            .onReady(() => {
              if (income) { this.incomeLineReady = true; } else { this.expenseLineReady = true; }
              this.drawLineChart(income);
            }).hitTestBehavior(HitTestMode.None)
          if (this.lineBuckets(income).length === 1 && this.selectedTrendBucket(income) === undefined) {
            Circle().width(8).height(8).fill(income ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
              .position({ x: this.linePoints(income)[0].x - 4, y: this.linePoints(income)[0].y - 4 }).hitTestBehavior(HitTestMode.None)
          }
          if (this.selectedTrendBucket(income) !== undefined) {
            Circle().width(8).height(8).fill(income ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
              .stroke($r('app.color.xq_app_surface_card')).strokeWidth(2)
              .position({ x: this.selectedTrendPoint(income).x - 4, y: this.selectedTrendPoint(income).y - 4 }).hitTestBehavior(HitTestMode.None)
            Column({ space: 2 }) {
              Text(this.selectedTrendBucket(income)?.key || '').fontSize('10fp').fontColor(Color.White).maxLines(1)
              Text('¥' + this.amount(this.selectedTrendBucket(income)?.amountMinor || '0')).fontSize('12fp')
                .fontColor(Color.White).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.width(104).height(44).justifyContent(FlexAlign.Center).borderRadius(8)
              .backgroundColor(income ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
              .position({ x: Math.max(0, Math.min(this.lineChartWidth - 104, this.selectedTrendPoint(income).x - 52)),
                y: Math.max(0, this.selectedTrendPoint(income).y - 52) }).hitTestBehavior(HitTestMode.None)
          }
        }.width('100%').height(156)
          .onAreaChange((_oldArea: Area, area: Area) => {
            const width = Math.max(1, Number(area.width));
            if (width !== this.lineChartWidth) { this.lineChartWidth = width; }
          })
          .onClick((event: ClickEvent) => { this.selectTrendPoint(income, event.x); })
          .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 4 })
            .onActionStart((event: GestureEvent) => { this.dragTrend(income, event); })
            .onActionUpdate((event: GestureEvent) => { this.dragTrend(income, event); })
            .onActionEnd((event: GestureEvent) => { this.dragTrend(income, event); }))
          .accessibilityText((income ? '收入走势' : '支出走势') + '，横向拖动或点击查看日期和金额')
        Row() {
          Text(this.lineBuckets(income)[0]?.label || '').fontSize('10fp').fontColor($r('app.color.xq_font_tertiary')).layoutWeight(1)
          Text(this.lineBuckets(income)[Math.floor((this.lineBuckets(income).length - 1) / 2)]?.label || '')
            .fontSize('10fp').fontColor($r('app.color.xq_font_tertiary')).layoutWeight(1).textAlign(TextAlign.Center)
          Text(this.lineBuckets(income)[this.lineBuckets(income).length - 1]?.label || '')
            .fontSize('10fp').fontColor($r('app.color.xq_font_tertiary')).layoutWeight(1).textAlign(TextAlign.End)
        }.width('100%')
      }
    }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
      .id(income ? 'statistics-income-trend' : 'statistics-expense-trend')
  }

  @Builder
  private categoryRow(category: StatisticsCategory, kind: StatisticsKind) {
    Row({ space: 12 }) {
      Stack() {
        if (category.key === 'transfer_fee') {
          Image($r('app.media.colorful_icon00372')).width(24).height(24).objectFit(ImageFit.Contain)
        } else {
          Image(categoryIcon(category.iconKey, kind === 'income')).width(28).height(28).objectFit(ImageFit.Contain)
        }
      }.width(44).height(44).borderRadius(22).backgroundColor($r('app.color.xq_app_surface_page'))
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text(category.name).fontSize('16fp').fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.xq_font_primary')).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('¥' + this.amount(category.amountMinor)).fontSize('16fp').fontFamily('XiaoQiaoDINMedium')
            .fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary')).maxLines(1)
            .minFontSize('12fp').maxFontSize('16fp').constraintSize({ maxWidth: '45%' })
          Image($r('app.media.lucide_chevron_right1')).width(16).height(16)
            .fillColor($r('app.color.xq_icon_tertiary'))
        }.width('100%')
        Progress({ value: Math.max(0, Math.min(100, category.share)), total: 100, type: ProgressType.Linear })
          .width('100%').height(4).color(kind === 'income' ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
          .backgroundColor($r('app.color.xq_comp_background_tertiary'))
      }.layoutWeight(1)
    }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      .id('statistics-category-' + category.key).onClick(() => { this.openEntries(category, kind); })
  }

  private ringTotal(income: boolean): bigint {
    let total = BigInt(0);
    for (const category of this.rankedCategories(income)) {
      const amount = BigInt(category.amountMinor);
      if (amount > BigInt(0)) { total += amount; }
    }
    return total;
  }

  private ringSlices(income: boolean): CategoryRingSlice[] {
    const categories = this.rankedCategories(income).filter((category: StatisticsCategory) => BigInt(category.amountMinor) > BigInt(0));
    const total = this.ringTotal(income);
    if (total <= BigInt(0)) { return []; }
    const values = categories.slice(0, 5);
    if (categories.length > 5) {
      let other = BigInt(0);
      for (const category of categories.slice(5)) { other += BigInt(category.amountMinor); }
      values.push({ key: '__ring_other__', name: '其他', iconKey: '', amountMinor: other.toString(), share: 0 });
    }
    let start = -90;
    return values.map((category: StatisticsCategory, index: number): CategoryRingSlice => {
      const share = Number(BigInt(category.amountMinor) * BigInt(1000000) / total) / 10000;
      const sweep = index === values.length - 1 ? 270 - start : share * 3.6;
      const slice: CategoryRingSlice = { key: category.key, name: category.name, amountMinor: category.amountMinor,
        share: share, startAngle: start, sweepAngle: sweep, color: CATEGORY_RING_COLORS[index] };
      start += sweep;
      return slice;
    });
  }

  private ringPoint(radius: number, angle: number): TrendPoint {
    const radians = angle * Math.PI / 180;
    return { x: vp2px(72 + radius * Math.cos(radians)), y: vp2px(72 + radius * Math.sin(radians)) };
  }

  private ringPath(slice: CategoryRingSlice, income: boolean): string {
    const radius = this.selectedRingKey(income) === slice.key ? 66 : 60;
    const start = this.ringPoint(radius, slice.startAngle);
    const middle = this.ringPoint(radius, slice.startAngle + slice.sweepAngle / 2);
    const end = this.ringPoint(radius, slice.startAngle + slice.sweepAngle);
    const innerEnd = this.ringPoint(42, slice.startAngle + slice.sweepAngle);
    const innerMiddle = this.ringPoint(42, slice.startAngle + slice.sweepAngle / 2);
    const innerStart = this.ringPoint(42, slice.startAngle);
    const outer = vp2px(radius); const inner = vp2px(42);
    return 'M ' + start.x + ' ' + start.y + ' A ' + outer + ' ' + outer + ' 0 0 1 ' + middle.x + ' ' + middle.y +
      ' A ' + outer + ' ' + outer + ' 0 0 1 ' + end.x + ' ' + end.y + ' L ' + innerEnd.x + ' ' + innerEnd.y +
      ' A ' + inner + ' ' + inner + ' 0 0 0 ' + innerMiddle.x + ' ' + innerMiddle.y +
      ' A ' + inner + ' ' + inner + ' 0 0 0 ' + innerStart.x + ' ' + innerStart.y + ' Z';
  }

  private selectedRingKey(income: boolean): string {
    return income ? this.selectedIncomeSlice : this.selectedExpenseSlice;
  }

  private selectedRingSlice(income: boolean): CategoryRingSlice | undefined {
    return this.ringSlices(income).find((slice: CategoryRingSlice) => slice.key === this.selectedRingKey(income));
  }

  private selectRingSlice(income: boolean, slice: CategoryRingSlice, toggle: boolean = true): void {
    const next = toggle && this.selectedRingKey(income) === slice.key ? '' : slice.key;
    if (income) { this.selectedIncomeSlice = next; } else { this.selectedExpenseSlice = next; }
  }

  private clickRing(income: boolean, x: number, y: number, dragging: boolean = false): void {
    const dx = x - 72; const dy = y - 72;
    const radius = Math.sqrt(dx * dx + dy * dy);
    if (dragging ? radius < 16 : radius < 42 || radius > 66) { return; }
    const angle = (Math.atan2(dy, dx) * 180 / Math.PI + 450) % 360;
    const slice = this.ringSlices(income).find((item: CategoryRingSlice) =>
      angle >= item.startAngle + 90 && angle < item.startAngle + 90 + item.sweepAngle);
    if (slice !== undefined && (dragging || radius <= 60 || this.selectedRingKey(income) === slice.key)) {
      this.selectRingSlice(income, slice, !dragging);
    }
  }

  private dragRing(income: boolean, event: GestureEvent): void {
    const finger = event.fingerList[0];
    if (finger !== undefined) { this.clickRing(income, finger.localX, finger.localY, true); }
  }

  @Builder
  private categoryRing(income: boolean) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Stack() {
          Circle().width(102).height(102).fill(Color.Transparent)
            .stroke($r('app.color.xq_comp_background_tertiary')).strokeWidth(18).hitTestBehavior(HitTestMode.None)
          ForEach(this.ringSlices(income), (slice: CategoryRingSlice) => {
            Path().commands(this.ringPath(slice, income)).width(144).height(144).fill(slice.color).strokeWidth(0).hitTestBehavior(HitTestMode.None)
              .accessibilityText(slice.name + ' ' + this.percent(slice.share))
          }, (slice: CategoryRingSlice) => slice.key + ':' + slice.amountMinor)
          Column({ space: 4 }) {
            Text(this.rankedCategories(income).some((category: StatisticsCategory) => BigInt(category.amountMinor) < BigInt(0)) ?
              '正净额合计' : income ? '分类收入' : '分类支出').fontSize('10fp').fontColor($r('app.color.xq_font_secondary'))
            Text(this.amount(this.ringTotal(income).toString())).fontSize('14fp').fontFamily('XiaoQiaoDINMedium')
              .fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('10fp').maxFontSize('14fp')
          }.width(78).hitTestBehavior(HitTestMode.None)
        }.width(144).height(144).flexShrink(0)
          .onClick((event: ClickEvent) => { this.clickRing(income, event.x, event.y); })
          .priorityGesture(PanGesture({ direction: PanDirection.All, distance: 4 })
            .onActionStart((event: GestureEvent) => { this.dragRing(income, event); })
            .onActionUpdate((event: GestureEvent) => { this.dragRing(income, event); })
            .onActionEnd((event: GestureEvent) => { this.dragRing(income, event); }))
        Column({ space: 10 }) {
          ForEach(this.ringSlices(income), (slice: CategoryRingSlice) => {
            Row({ space: 6 }) {
              Circle().width(7).height(7).fill(slice.color).flexShrink(0)
              Text(slice.name).fontSize('12fp').fontColor($r('app.color.xq_font_primary')).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.percent(slice.share)).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
            }.width('100%').constraintSize({ minHeight: 28 })
              .backgroundColor(this.selectedRingKey(income) === slice.key ? $r('app.color.xq_app_surface_page') : Color.Transparent)
              .borderRadius(6)
              .accessibilityText(slice.name + ' ' + this.percent(slice.share) + '，选中查看金额')
              .onClick(() => { this.selectRingSlice(income, slice); })
          }, (slice: CategoryRingSlice) => slice.key + ':' + slice.amountMinor)
          if (this.ringSlices(income).length === 0) {
            Text('暂无可绘制的正净额').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      if (this.selectedRingSlice(income) !== undefined) {
        Row({ space: 8 }) {
          Circle().width(8).height(8).fill(this.selectedRingSlice(income)?.color || '#939BA8')
          Column({ space: 4 }) {
            Text(this.amount(this.selectedRingSlice(income)?.amountMinor || '0')).fontSize('18fp')
              .fontFamily('XiaoQiaoDINMedium').fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.xq_font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Row({ space: 8 }) {
              Text(this.selectedRingSlice(income)?.name || '').fontSize('12fp').layoutWeight(1)
                .fontColor($r('app.color.xq_font_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.percent(this.selectedRingSlice(income)?.share || 0)).fontSize('12fp')
                .fontColor($r('app.color.xq_font_secondary'))
            }.width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').padding(12).borderRadius(8).backgroundColor($r('app.color.xq_app_surface_page'))
          .border({ width: { left: 3 }, color: this.selectedRingSlice(income)?.color || '#939BA8' })
          .id(income ? 'statistics-income-ring-selection' : 'statistics-expense-ring-selection')
      }
      if (this.rankedCategories(income).some((category: StatisticsCategory) => BigInt(category.amountMinor) < BigInt(0))) {
        Text('环形占比仅包含净额为正的分类，净回款分类仍保留在下方排行。').fontSize('11fp')
          .fontColor($r('app.color.xq_font_tertiary')).width('100%')
      }
    }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      .id(income ? 'statistics-income-category-ring' : 'statistics-expense-category-ring')
  }

  @Builder
  private categoryRanking(income: boolean) {
    Column({ space: 10 }) {
      Row() {
        Text(income ? '收入分类排行' : '支出分类排行').fontSize('18fp').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.xq_font_primary'))
        Blank()
        Text('按一级分类汇总').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        if (this.rankedCategories(income).length > 5) {
          Button((income ? this.showAllIncomeCategories : this.showAllCategories) ? '收起' : '查看全部', { type: ButtonType.Capsule })
            .height(28).padding({ left: 8, right: 8 }).fontSize('12fp')
            .fontColor($r('app.color.xq_font_emphasize')).backgroundColor(Color.Transparent)
            .id(income ? 'statistics-income-category-toggle' : 'statistics-category-toggle')
            .onClick(() => {
              if (income) { this.showAllIncomeCategories = !this.showAllIncomeCategories; }
              else { this.showAllCategories = !this.showAllCategories; }
            })
        }
      }.width('100%')
      if (this.rankedCategories(income).length === 0) {
        Text(income ? '这个周期还没有收入' : '这个周期还没有支出').fontSize('14fp')
          .fontColor($r('app.color.xq_font_secondary')).width('100%').padding({ top: 20, bottom: 20 })
      } else {
        this.categoryRing(income)
        ForEach((income ? this.showAllIncomeCategories : this.showAllCategories) ? this.rankedCategories(income) :
          this.rankedCategories(income).slice(0, 5), (category: StatisticsCategory) => {
          this.categoryRow(category, income ? 'income' : 'expense')
        }, (category: StatisticsCategory) => category.key + ':' + category.amountMinor)
      }
    }.width('100%').id(income ? 'statistics-income-category-ranking' : 'statistics-category-ranking')
  }

  @Builder
  private budgetRow(category: StatisticsBudgetCategory) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Row() {
          Text(category.name).fontSize('14fp').fontWeight(FontWeight.Regular).height(32)
            .fontColor(spendingNatureText(category.colorKey)).backgroundColor(spendingNatureBackground(category.colorKey))
            .padding({ left: 12, right: 12 }).borderRadius(16).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '100%' })
        }.layoutWeight(1)
        Text('¥' + this.amount(category.amountMinor)).fontSize('16fp').fontFamily('XiaoQiaoDINMedium')
          .fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('12fp').maxFontSize('16fp')
          .constraintSize({ maxWidth: '45%' })
      }.width('100%').alignItems(VerticalAlign.Center)
      Row({ space: 12 }) {
        Progress({ value: Math.max(0, Math.min(100, category.share)), total: 100, type: ProgressType.Linear })
          .layoutWeight(1).height(4).color(spendingNatureText(category.colorKey))
          .backgroundColor($r('app.color.xq_comp_background_tertiary'))
        Text(this.percent(category.share)).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
      }.width('100%').alignItems(VerticalAlign.Center)
    }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      .id('statistics-budget-' + category.key)
  }

  @Builder
  private budgetRanking() {
    if ((this.statistics?.budgetCategories || []).length > 0) {
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
  private tagRow(tag: StatisticsTagCategory, kind: StatisticsKind) {
    Row({ space: 12 }) {
      Circle().width(8).height(8).fill(tagTextColor(tag.colorKey)).flexShrink(0)
      Column({ space: 4 }) {
        Text('#' + tag.name).fontSize('16fp')
          .fontColor($r('app.color.xq_font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text((kind === 'income' ? '收入 · ' : '支出 · ') + `${tag.entryCount} 笔`).fontSize('12fp')
          .fontColor($r('app.color.xq_font_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('¥' + this.amount(tag.amountMinor)).fontSize('16fp').fontFamily('XiaoQiaoDINMedium')
        .fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('12fp').maxFontSize('16fp').constraintSize({ maxWidth: '40%' })
      Image($r('app.media.lucide_chevron_right1')).width(16).height(16)
        .fillColor($r('app.color.xq_icon_tertiary'))
    }.padding({ left: 16, right: 16, top: 12, bottom: 12 }).constraintSize({ minHeight: 64 })
      .width('100%').alignItems(VerticalAlign.Center)
      .id('statistics-tag-' + (kind === 'income' ? 'income-' : '') + tag.key).onClick(() => { this.openTagEntries(tag, kind); })
  }

  @Builder
  private tagRanking() {
    if (this.rankedTags().length > 0) {
      Column({ space: 10 }) {
        Row() {
          Text('标签排行').fontSize('18fp').fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.xq_font_primary'))
          Blank()
          Text('多标签账目分别计入').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        }.width('100%')
        Column() {
          ForEach(this.rankedTags().slice(0, 5), (item: TagRankingItem, index: number) => {
            this.tagRow(item.tag, item.kind)
            if (index < Math.min(5, this.rankedTags().length) - 1) {
              Divider().color($r('app.color.xq_comp_divider')).margin({ left: 36, right: 16 })
            }
          }, (item: TagRankingItem) => item.kind + ':' + item.tag.key + ':' + item.tag.amountMinor + ':' + item.tag.entryCount)
        }.width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card')).clip(true)
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
          Button(this.customStart.replace(/-/g, '/'), { type: ButtonType.Normal }).width('100%').height(48)
            .fontSize('16fp').fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_primary'))
            .backgroundColor($r('app.color.xq_app_surface_page')).id('statistics-custom-start')
            .onClick(() => { this.pickCustomDate(true); })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 6 }) {
          Text('结束日期').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
          Button(this.customEnd.replace(/-/g, '/'), { type: ButtonType.Normal }).width('100%').height(48)
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
          Image($r('app.media.colorful_icon00372')).width(22).height(22).objectFit(ImageFit.Contain)
        } else {
          Image(categoryIcon(entry.iconKey, this.kind === 1)).width(26).height(26).objectFit(ImageFit.Contain)
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
          Text(this.periodTitle() + ' · ' + (this.kind === 1 ? '收入' : '支出'))
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
    const options: SheetOptions = { height: this.sheetMode === 0 ? 360 : 620, showClose: true,
      onDisappear: () => {
        if (this.rangeSelection[0] !== this.range) { this.rangeSelection = [this.range]; }
      } };
    if (this.sheetMaterial !== undefined) { options.systemMaterial = this.sheetMaterial; }
    else { options.backgroundColor = $r('app.color.xq_app_surface_card'); }
    return options;
  }

  @Builder
  private content() {
    Scroll(this.scroller) {
      Column({ space: 16 }) {
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
          this.lineTrendCard(false)
          this.lineTrendCard(true)
          this.categoryRanking(false)
          this.categoryRanking(true)
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
      .dynamicHideTitleBar({ hideTitleArea: false, hideBottomBuilder: false, hideStatusBar: false })
      .titleBar({ enableComponentSafeArea: true, avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '统计' }, stackBuilder: this.rangeAction.bind(this),
          bottomBuilder: { builder: this.fixedPeriodNavigator.bind(this), height: 56 },
          divider: { showType: DividerShowType.OFF } },
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
