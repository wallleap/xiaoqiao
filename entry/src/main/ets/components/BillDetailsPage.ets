import { DEFAULT_TRANSACTION_COLORS, TransactionColors, TransactionColorKind } from '../presentation/ledger/TransactionColors';
import { MonthlyBudget } from '../domain/model/MonthlyBudget';
import { CategoryIconBadge } from './CategoryIconBadge';
import { BillCalendarDay, billCalendarDays, billDateKey, trimBillDecimal, compactBillAmount } from '../presentation/ledger/BillCalendar';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { LedgerEntry, LedgerKind, DailyTotals, presentEntry, filterEntries, dailyTotals, displayAmount } from '../presentation/ledger/LedgerOverview';
import { currencyUnit, currencyDefinition } from '../core/money/Currencies';
import { LedgerFlowQuery, LedgerFlowDay, LedgerSearchCursor } from '../domain/model/LedgerSearch';
import { currentRange, shiftedRange, rangeTitle, StatisticsDateRange, StatisticsRange, localDate, parseLocalDate } from '../presentation/statistics/StatisticsPeriod';
import { Money } from '../core/money/Money';
import { ItemRestriction, SegmentButton, SegmentButtonOptions, SegmentButtonTextItem } from '@kit.ArkUI';

interface BillCalendarCell {
  day: BillCalendarDay;
  incomeMinor: string;
  expenseMinor: string;
}

@Component
export struct BillDetailsPage {
  @StorageProp('transactionColorSelection') private transactionColorSelection: string = DEFAULT_TRANSACTION_COLORS;
  private transactionColor(kind: TransactionColorKind): Resource { return TransactionColors.color(kind,this.transactionColorSelection); }
  workspace: LedgerWorkspace | undefined = undefined;
  rangeMaterial: SystemUiMaterial | undefined = undefined;
  @Prop @Watch('reload') refreshToken: number = 0;
  onClose: () => void = () => {};
  onSearch: () => void = () => {};
  onOpenEntry: (entry: LedgerEntry) => void = () => {};
  @State private month: string = '';
  @State @Watch('viewChanged') private viewSelection: number[] = [1];
  @State private showTitleSearch: boolean = false;
  private searchBottom: number = 0;
  @State private viewOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '流水' }, { text: '日历' }] as ItemRestriction<SegmentButtonTextItem>,
    fontSize: '13fp', selectedFontSize: '13fp',
    fontColor: $r('sys.color.font_primary'), selectedFontColor: $r('app.color.xq_font_on_primary'),
    backgroundColor: Color.Transparent, selectedBackgroundColor: $r('app.color.xq_brand')
  });
  @State private entries: LedgerEntry[] = [];
  @State private flowRange: number = 0;
  @State private showRangeSheet: boolean = false;
  @State private draftStart: string = '';
  @State private draftEnd: string = '';
  @State private flowPeriod: StatisticsDateRange = currentRange('month');
  @State private flowDays: LedgerFlowDay[] = [];
  @State private hasMore: boolean = false;
  @State private loadingMore: boolean = false;
  private flowCursor: LedgerSearchCursor | undefined = undefined;
  private active: boolean = false;
  @State private calendar: BillCalendarCell[] = [];
  @State private selectedDate: string = '';
  @State private calendarWidth: number = 320;
  @State private kind: number = LedgerKind.All;
  @State private loading: boolean = false;
  @State private error: string = '';
  private request: number = 0;
  private readonly scroller: Scroller = new Scroller();

  private updateTitleSearch(): void {
    // Search is inside the first ListItem; use its measured end, not a fixed calendar height.
    this.showTitleSearch = this.searchBottom > 0 && this.scroller.currentOffset().yOffset >= this.searchBottom;
  }

  aboutToAppear(): void {
    this.active = true;
    if (this.rangeMaterial !== undefined) { this.viewOptions.backgroundSystemMaterial = this.rangeMaterial; }
    const now = new Date();
    this.month = MonthlyBudget.monthForDate(localDate(now), this.workspace?.monthStartDay || 1);
    this.selectedDate = '';
    this.rebuildCalendar(); this.reload();
  }
  aboutToDisappear(): void { this.active = false; this.request++; }
  private isFlow(): boolean { return this.viewSelection[0] === 0; }
  private viewChanged(): void {
    this.selectedDate = ''; this.entries = []; this.searchBottom = 0; this.showTitleSearch = false;
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 }); this.reload();
  }
  private flowRangeName(): StatisticsRange {
    return this.flowRange === 1 ? 'year' : this.flowRange === 2 ? 'month' : this.flowRange === 3 ? 'week' : 'custom';
  }
  private selectFlowRange(index: number): void {
    if (index === 4) { this.pickCustomStart(); return; }
    this.flowRange = index;
    if (index !== 0) { this.flowPeriod = currentRange(this.flowRangeName(), new Date(), '', '', this.workspace?.monthStartDay || 1); }
    this.resetFlow();
  }
  private pickCustomStart(): void {
    this.draftStart = this.flowPeriod.startDate;
    const end = parseLocalDate(this.flowPeriod.endDateExclusive); end.setDate(end.getDate() - 1);
    this.draftEnd = localDate(end); this.showRangeSheet = true;
  }
  private pickRangeDate(start: boolean): void {
    this.getUIContext().showDatePickerDialog({ selected: parseLocalDate(start ? this.draftStart : this.draftEnd),
      selectedTextStyle: { color: $r('app.color.xq_font_emphasize') },
      acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      cancelButtonStyle: { fontColor: $r('app.color.xq_font_secondary') },
      onDateAccept: (date: Date) => {
        if (!this.active || !this.isFlow() || !this.showRangeSheet) { return; }
        if (start) { this.draftStart = localDate(date); } else { this.draftEnd = localDate(date); }
      } });
  }
  @Builder
  private customRangeSheet() {
    Column({ space: 20 }) {
      Text('自定义日期').fontSize('20fp').fontWeight(FontWeight.Bold).fontColor($r('app.color.xq_font_primary'))
        .width('100%').padding({ right: 48 })
      Row({ space: 12 }) {
        Column({ space: 8 }) {
          Text('开始日期').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
          Button(this.draftStart.replace(/-/g, '/')).fontSize('14fp').height(44).width('100%')
            .backgroundColor($r('app.color.xq_app_surface_card')).fontColor($r('app.color.xq_font_primary'))
            .onClick(() => { this.pickRangeDate(true); })
        }.layoutWeight(1)
        Column({ space: 8 }) {
          Text('结束日期').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
          Button(this.draftEnd.replace(/-/g, '/')).fontSize('14fp').height(44).width('100%')
            .backgroundColor($r('app.color.xq_app_surface_card')).fontColor($r('app.color.xq_font_primary'))
            .onClick(() => { this.pickRangeDate(false); })
        }.layoutWeight(1)
      }.width('100%')
      Button('确定', { type: ButtonType.Capsule }).width('100%').height(44)
        .backgroundColor($r('app.color.xq_brand')).fontColor($r('app.color.xq_font_on_primary'))
        .onClick(() => {
          this.flowPeriod = currentRange('custom', new Date(), this.draftStart, this.draftEnd);
          this.flowRange = 4; this.showRangeSheet = false; this.resetFlow();
        })
    }.width('100%').padding({ top: 28, left: 24, right: 24, bottom: 24 }).alignItems(HorizontalAlign.Start)
  }
  private resetFlow(): void {
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 }); this.showTitleSearch = false; this.reload();
  }
  private async fetchFlow(append: boolean): Promise<void> {
    if (!this.workspace || !this.active || !this.isFlow() || (append && (this.loading || this.loadingMore || !this.hasMore || !!this.error))) { return; }
    const request = append ? this.request : ++this.request;
    if (append) { this.loadingMore = true; } else {
      this.entries = []; this.flowDays = []; this.flowCursor = undefined; this.hasMore = false;
      this.loadingMore = false; this.loading = true;
    }
    this.error = '';
    const query: LedgerFlowQuery = { startDate: this.flowRange === 0 ? '' : this.flowPeriod.startDate,
      endDateExclusive: this.flowRange === 0 ? '' : this.flowPeriod.endDateExclusive, kind: this.kind };
    try {
      const page = await this.workspace.flowEntries(query, append ? this.flowCursor : undefined);
      if (!this.active || request !== this.request) { return; }
      this.entries = append ? this.entries.concat(page.entries.map(presentEntry)) : page.entries.map(presentEntry);
      const days: LedgerFlowDay[] = append ? this.flowDays.filter((day: LedgerFlowDay) => !page.days.some((next: LedgerFlowDay) => next.date === day.date)) : [];
      this.flowDays = days.concat(page.days); this.hasMore = page.hasMore; this.flowCursor = page.nextCursor;
    } catch (_) { if (this.active && request === this.request) { this.error = '流水暂时无法读取，请重试'; } }
    finally { if (this.active && request === this.request) { this.loading = false; this.loadingMore = false; } }
  }
  private totals(date: string): DailyTotals {
    if (!this.isFlow()) { return dailyTotals(this.visible(), date); }
    const day = this.flowDays.find((item: LedgerFlowDay) => item.date === date);
    return { incomeMinor: day?.incomeMinor || '0', expenseMinor: day?.expenseMinor || '0' };
  }
  private periodLabel(): string {
    if (!this.isFlow()) { const period = MonthlyBudget.period(this.month, this.workspace?.monthStartDay || 1); return this.month.replace('-', '年') + '月' + ((this.workspace?.monthStartDay || 1) === 1 ? '' : ' · ' + period.start + ' 起'); }
    if (this.flowRange === 0) { return '全部时间'; }
    if (this.flowRange === 1 || this.flowRange === 2) { return rangeTitle(this.flowRangeName(), this.flowPeriod); }
    const end = parseLocalDate(this.flowPeriod.endDateExclusive); end.setDate(end.getDate() - 1);
    return this.flowPeriod.startDate.replace(/-/g, '/') + ' — ' + localDate(end).replace(/-/g, '/');
  }
  private selectKind(index: number): void {
    if (this.kind === index) { return; }
    this.kind = index;
    if (this.isFlow()) { this.resetFlow(); }
  }

  private async reload(): Promise<void> {
    if (this.isFlow()) { await this.fetchFlow(false); return; }
    this.hasMore = false; this.loadingMore = false;
    if (!this.workspace || !this.month) { return; }
    const request = ++this.request;
    this.loading = true; this.error = '';
    try {
      const snapshot = await this.workspace.snapshot(this.month);
      if (request === this.request) { this.entries = snapshot.entries.map(presentEntry); this.rebuildCalendar(); }
    } catch (_) { if (request === this.request) { this.error = '账单暂时无法读取，请重试'; } }
    finally { if (request === this.request) { this.loading = false; } }
  }
  private visible(): LedgerEntry[] { return filterEntries(this.entries, this.kind, '', '').filter((entry: LedgerEntry) => !this.selectedDate || entry.date === this.selectedDate); }
  private dates(): string[] { return Array.from(new Set(this.visible().map((entry: LedgerEntry) => entry.date))).sort().reverse(); }
  private shift(offset: number): void {
    if (this.isFlow()) {
      if (this.flowRange === 0 || this.flowRange === 4) { return; }
      this.flowPeriod = shiftedRange(this.flowRangeName(), this.flowPeriod, offset, this.workspace?.monthStartDay || 1); this.resetFlow(); return;
    }
    const parts = this.month.split('-');
    const date = new Date(Number(parts[0]), Number(parts[1]) - 1 + offset, 1);
    this.month = date.getFullYear().toString() + '-' + (date.getMonth() + 1).toString().padStart(2, '0');
    this.selectedDate = ''; this.entries = []; this.rebuildCalendar();
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 }); this.reload();
  }
  private rebuildCalendar(): void {
    this.calendar = billCalendarDays(this.month, this.workspace?.monthStartDay || 1).map((day: BillCalendarDay): BillCalendarCell => {
      const emptyTotals: DailyTotals = { incomeMinor: '0', expenseMinor: '0' };
      const totals: DailyTotals = day.inMonth ? dailyTotals(this.entries, day.date) : emptyTotals;
      return { day: day, incomeMinor: totals.incomeMinor, expenseMinor: totals.expenseMinor };
    });
  }
  private calendarRows(): number[] {
    const rows: number[] = [];
    for (let index = 0; index < this.calendar.length / 7; index++) { rows.push(index); }
    return rows;
  }
  private calendarAmount(minor: string): string {
    const full = trimBillDecimal(minor, this.bookCode());
    const available = Math.max(1, this.calendarWidth / 7 - 6);
    const width = this.getUIContext().getMeasureUtils().measureTextSize({ textContent: full, fontSize: '9fp', fontFamily: 'XiaoQiaoDINMedium' }).width;
    if (this.getUIContext().px2vp(Number(width)) <= available) { return full; }
    for (let digits = 2; digits >= 0; digits--) {
      const compact = compactBillAmount(minor, digits, this.bookCode());
      const measured = this.getUIContext().getMeasureUtils().measureTextSize({ textContent: compact, fontSize: '9fp', fontFamily: 'XiaoQiaoDINMedium' }).width;
      if (this.getUIContext().px2vp(Number(measured)) <= available) { return compact; }
    }
    return compactBillAmount(minor, 0, this.bookCode());
  }
  private selectDay(day: BillCalendarDay): void {
    if (!day.inMonth) {
      this.month = MonthlyBudget.monthForDate(day.date, this.workspace?.monthStartDay || 1); this.entries = []; this.rebuildCalendar(); this.reload();
    }
    this.selectedDate = this.selectedDate === day.date ? '' : day.date;
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }
  @Builder
  private calendarMoney(minor: string, income: boolean) {
    Text(this.calendarAmount(minor)).fontSize('11fp').minFontSize('9fp').maxFontSize('11fp')
      .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).fontFamily('XiaoQiaoDINMedium')
      .fontColor(this.transactionColor(income ? 'income' : 'expense'))
      .width('100%').height(14).maxLines(1).textAlign(TextAlign.Center)
  }
  @Builder
  private calendarCell(cell: BillCalendarCell) {
    Column({ space: 2 }) {
      Text(cell.day.day.toString()).fontSize('14fp').fontWeight(cell.day.date === billDateKey(new Date()) ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(!cell.day.inMonth ? $r('app.color.xq_font_tertiary') : cell.day.date === billDateKey(new Date()) ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_primary'))
        .height(20)
      if (cell.day.inMonth) {
        if (!this.loading && !this.error && (cell.incomeMinor !== '0' || cell.expenseMinor !== '0')) {
          if (cell.incomeMinor !== '0') { this.calendarMoney(cell.incomeMinor, true) }
          if (cell.expenseMinor !== '0') { this.calendarMoney(cell.expenseMinor, false) }
        } else {
          Text(cell.day.secondary).fontSize('10fp').fontColor(cell.day.festival ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_tertiary'))
            .width('100%').height(16).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center)
        }
      }
    }.padding({ top: 5, left: 3, right: 3 }).height(62).layoutWeight(1).justifyContent(FlexAlign.Start)
      .backgroundColor(this.selectedDate === cell.day.date ? $r('app.color.xq_app_surface_page') : Color.Transparent)
      .borderRadius(12).border({ width: 1, color: this.selectedDate === cell.day.date ? $r('app.color.xq_brand') : Color.Transparent })
      .opacity(cell.day.inMonth ? 1 : 0.4)
      .accessibilityText(cell.day.date + (cell.day.inMonth && !this.loading && !this.error ? '，收入' + trimBillDecimal(cell.incomeMinor) + '，支出' + trimBillDecimal(cell.expenseMinor) : ''))
      .onClick(() => { this.selectDay(cell.day); })
  }
  @Builder
  private monthCalendar() {
    Column({ space: 3 }) {
      Row() {
        ForEach(['一', '二', '三', '四', '五', '六', '日'], (label: string) => {
          Text(label).fontSize('11fp').fontColor($r('app.color.xq_font_tertiary')).layoutWeight(1).textAlign(TextAlign.Center).height(24)
        }, (label: string) => label)
      }.width('100%')
      ForEach(this.calendarRows(), (row: number) => {
        Row() {
          ForEach(this.calendar.slice(row * 7, row * 7 + 7), (cell: BillCalendarCell) => { this.calendarCell(cell) },
            (cell: BillCalendarCell) => cell.day.date + ':' + cell.incomeMinor + ':' + cell.expenseMinor)
        }.width('100%')
      }, (row: number) => this.month + ':' + row.toString())
    }.padding(10).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
      .onAreaChange((_oldArea: Area, area: Area) => { this.calendarWidth = Math.max(1, Number(area.width) - 20); })
  }
  private bookCode(): string { return this.workspace?.bookCurrency.id || 'CNY'; }
  private bookAmount(minor: string): string { return displayAmount(minor, currencyUnit(this.bookCode())); }
  private amount(entry: LedgerEntry): string {
    if (entry.fx && !entry.transfer) {
      return currencyDefinition(entry.fx.currencyId).symbol + Money.fromMinorText(entry.fx.paidMinor, currencyUnit(entry.fx.currencyId)).toDecimalString();
    }
    return currencyDefinition(this.bookCode()).symbol + this.bookAmount(entry.recoveryKind ? (-BigInt(entry.minor)).toString() : entry.transfer && this.kind === LedgerKind.Expense ? entry.expenseMinor || '0' : entry.minor);
  }
  private sign(entry: LedgerEntry): string {
    if (entry.prepaidId) { return entry.prepaidKind === 'refund' ? '+' : '−'; }
    return entry.recoveryKind || entry.income ? '+' : entry.transfer && this.kind !== LedgerKind.Expense ? '' : '−';
  }
  @Builder
  private entryRow(entry: LedgerEntry) {
    Row({ space: 12 }) {
      CategoryIconBadge({ icon: entry.icon, badgeSize: 44, glyphSize: 28 })
      Column({ space: 5 }) {
        Text(entry.title).fontSize('15fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(entry.time + (entry.account && entry.account !== '不使用账户' ? ' · ' + entry.account : ''))
          .fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if ((entry.recoveryBadges || []).length > 0) {
          Text((entry.recoveryBadges || []).join(' · ')).fontSize('10fp').fontColor($r('app.color.xq_font_emphasize'))
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(this.sign(entry) + this.amount(entry)).fontSize('16fp').fontFamily('XiaoQiaoDINMedium')
        .fontColor(this.transactionColor(entry.prepaidId ? (entry.prepaidKind === 'refund' ? 'income' : 'transfer') : entry.transfer ? 'transfer' : entry.income || entry.recoveryKind ? 'income' : 'expense'))
        .maxLines(1).constraintSize({ maxWidth: '42%' })
    }.width('100%').padding({ top: 16, bottom: 16 }).onClick(() => { this.onOpenEntry(entry); })
  }
  @Builder
  private viewAction() {
    Row() {
      if (this.showTitleSearch) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.lucide_search1')).width(20).height(20).fillColor($r('app.color.xq_icon_primary'))
        }.width(40).height(40).padding(0)
          .backgroundColor(this.rangeMaterial !== undefined ? Color.Transparent : $r('app.color.xq_app_surface_card'))
          .systemMaterial(this.rangeMaterial).accessibilityText('搜索账单')
          .onClick(() => { this.onSearch(); }).id('bill-details-title-search')
      } else {
        SegmentButton({ options: this.viewOptions, selectedIndexes: $viewSelection })
          .width(148).constraintSize({ maxWidth: '100%' }).id('bill-details-view')
      }
    }.width('100%').justifyContent(FlexAlign.End).padding({ left: 176, right: 16 })
      .hitTestBehavior(HitTestMode.Transparent)
  }
  @Builder
  private monthButton(direction: number) {
    Button({ type: ButtonType.Circle }) {
      Image(direction < 0 ? $r('app.media.lucide_chevron_left1') : $r('app.media.lucide_chevron_right1'))
        .width(20).height(20).fillColor($r('app.color.xq_icon_secondary'))
    }.width(40).height(40).padding(0)
      .backgroundColor(this.rangeMaterial !== undefined ? Color.Transparent : $r('app.color.xq_app_surface_card'))
      .systemMaterial(this.rangeMaterial)
      .enabled(!this.isFlow() || (this.flowRange !== 0 && this.flowRange !== 4))
      .opacity(this.isFlow() && (this.flowRange === 0 || this.flowRange === 4) ? 0.35 : 1)
      .accessibilityText(direction < 0 ? '上一周期' : '下一周期').onClick(() => { this.shift(direction); })
  }
  @Builder
  private monthNavigator() {
    Column() {
      Row({ space: 8 }) {
        this.monthButton(-1)
        Text(this.periodLabel()).fontSize('14fp').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.xq_font_primary')).layoutWeight(1).textAlign(TextAlign.Center)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => { if (this.isFlow() && this.flowRange === 4) { this.pickCustomStart(); } })
        this.monthButton(1)
      }.width('100%').constraintSize({ maxWidth: 400 })
    }.width('100%').height(56).padding({ left: 32, right: 32, top: 8, bottom: 8 })
      .backgroundColor(Color.Transparent)
  }
  @Builder
  private fixedPeriodControls() {
    Column() {
      if (this.isFlow()) { this.flowRangeControls() }
      this.monthNavigator()
    }.width('100%').height(this.isFlow() ? 104 : 56)
  }
  @Builder
  private flowRangeControls() {
    Row({ space: 4 }) {
      ForEach(['全部', '年', '月', '周', '自定义'], (label: string, index: number) => {
        if (this.flowRange === index) {
          Button(label, { type: ButtonType.Capsule }).layoutWeight(1).height(32).fontSize('12fp').padding({ left: 4, right: 4 })
            .backgroundColor($r('app.color.xq_brand')).fontColor($r('app.color.xq_font_on_primary'))
            .onClick(() => { this.selectFlowRange(index); })
        } else {
        Button(label, { type: ButtonType.Capsule }).layoutWeight(1).height(32).fontSize('12fp').padding({ left: 4, right: 4 })
          .backgroundColor(this.rangeMaterial !== undefined ? Color.Transparent : $r('app.color.xq_app_surface_card'))
          .systemMaterial(this.rangeMaterial)
          .fontColor($r('app.color.xq_font_secondary'))
          .onClick(() => { this.selectFlowRange(index); })
        }
      }, (label: string) => label)
    }.width('100%').height(48).padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }
  build() {
    HdsNavigation() {
      List({ scroller: this.scroller }) {
        ListItem() {
          Column({ space: 12 }) {
        if (!this.isFlow()) { this.monthCalendar() }
        Button({ type: ButtonType.Normal }) {
          Row({ space: 10 }) {
            Image($r('app.media.lucide_search1')).width(18).height(18).fillColor($r('app.color.xq_icon_secondary'))
            Text('搜索备注、收支分类、账户或标签').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
              .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Start)
          }.width('100%')
        }.height(44).width('100%').padding({ left: 16, right: 16 }).borderRadius(22)
          .backgroundColor($r('app.color.xq_app_surface_card')).id('bill-details-search')
          .onAreaChange((_oldArea: Area, area: Area) => {
            this.searchBottom = Number(area.position.y) + Number(area.height);
            this.updateTitleSearch();
          })
          .accessibilityText('搜索账单').onClick(() => { this.onSearch(); })
        Row({ space: 8 }) {
          ForEach(['全部', '支出', '收入'], (label: string, index: number) => {
            Button(label, { type: ButtonType.Capsule }).height(36).fontSize('14fp')
              .backgroundColor(this.kind === index ? $r('app.color.xq_brand') : $r('app.color.xq_app_surface_card'))
              .fontColor(this.kind === index ? Color.White : $r('app.color.xq_font_secondary')).onClick(() => { this.selectKind(index); })
          }, (label: string) => label)
          Blank()
          Text(this.visible().length.toString() + (this.isFlow() && this.hasMore ? '+ 笔' : ' 笔')).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        }.width('100%')
          }.width('100%').padding({ top: 12, bottom: 12 })
        }
          if (this.loading) { ListItem() { Text('正在读取账单…').fontSize('14fp').padding(24) } }
          else if (this.error && this.entries.length === 0) {
            ListItem() { Button(this.error + ' · 重试').fontSize('14fp').onClick(() => { this.reload(); }) }
          } else if (this.visible().length === 0) {
            ListItem() { Text('暂无符合条件的账单').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%').textAlign(TextAlign.Center).padding(32) }
          } else {
            ForEach(this.dates(), (date: string) => {
              ListItem() {
                Column({ space: 0 }) {
                  Row() {
                    Text(date.replace(/-/g, '/')).fontSize('13fp').fontWeight(FontWeight.Medium).layoutWeight(1)
                    Text('收 ' + this.bookAmount(this.totals(date).incomeMinor) + '  支 ' + this.bookAmount(this.totals(date).expenseMinor))
                      .fontSize('11fp').fontColor($r('app.color.xq_font_secondary'))
                  }.width('100%').padding({ top: 24, bottom: 12 })
                  Column() {
                    ForEach(this.visible().filter((entry: LedgerEntry) => entry.date === date), (entry: LedgerEntry) => {
                      this.entryRow(entry)
                      Divider().color($r('app.color.xq_app_divider_subtle'))
                    }, (entry: LedgerEntry) => entry.id)
                  }.padding({ left: 14, right: 14 }).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
                }.width('100%')
              }
            }, (date: string) => date)
            if (this.loadingMore) {
              ListItem() { Text('正在加载…').fontSize('12fp').width('100%').textAlign(TextAlign.Center).padding(24) }
            } else if (this.error) {
              ListItem() { Button('加载失败，点击重试').onClick(() => { this.error = ''; this.fetchFlow(true); }) }
            } else if (!this.hasMore) {
            ListItem() {
              Text('没有更多了').fontSize('12fp').fontColor($r('app.color.xq_font_tertiary'))
                .width('100%').textAlign(TextAlign.Center).padding({ top: 24, bottom: 16 })
            }
            }
          }
      }.padding({ left: 16, right: 16 }).width('100%').height('100%')
        .onDidScroll(() => { this.updateTitleSearch(); })
        .onReachEnd(() => { if (this.isFlow()) { this.fetchFlow(true); } })
        .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).contentEndOffset(24).clip(false)
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .dynamicHideTitleBar({ hideTitleArea: false, hideBottomBuilder: false, hideStatusBar: false })
      .titleBar({ enableComponentSafeArea: true, content: { title: { mainTitle: '账单明细' },
        stackBuilder: this.viewAction.bind(this),
        bottomBuilder: { builder: this.fixedPeriodControls.bind(this), height: this.isFlow() ? 104 : 56 },
        divider: { showType: DividerShowType.OFF }, backIcon: { action: () => { this.onClose(); } } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showRangeSheet, this.customRangeSheet(), { height: 320, showClose: true,
        backgroundColor: $r('app.color.xq_app_surface_page') })
  }
}
