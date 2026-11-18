import { BillCalendarDay, billCalendarDays, billDateKey, trimBillDecimal, compactBillAmount } from '../presentation/ledger/BillCalendar';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { LedgerEntry, LedgerKind, DailyTotals, presentEntry, filterEntries, dailyTotals, displayAmount } from '../presentation/ledger/LedgerOverview';
import { currencyUnit, currencyDefinition } from '../core/money/Currencies';
import { Money } from '../core/money/Money';

interface BillCalendarCell {
  day: BillCalendarDay;
  incomeMinor: string;
  expenseMinor: string;
}

@Component
export struct BillDetailsPage {
  workspace: LedgerWorkspace | undefined = undefined;
  initialMonth: string = '';
  @Prop @Watch('reload') refreshToken: number = 0;
  onClose: () => void = () => {};
  onOpenEntry: (entry: LedgerEntry) => void = () => {};
  @State private month: string = '';
  @State private entries: LedgerEntry[] = [];
  @State private calendar: BillCalendarCell[] = [];
  @State private selectedDate: string = '';
  @State private calendarWidth: number = 320;
  @State private kind: number = LedgerKind.All;
  @State private keyword: string = '';
  @State private loading: boolean = false;
  @State private error: string = '';
  private request: number = 0;
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const now = new Date();
    this.month = this.initialMonth || now.getFullYear().toString() + '-' + (now.getMonth() + 1).toString().padStart(2, '0');
    this.selectedDate = billDateKey(now).startsWith(this.month + '-') ? billDateKey(now) : this.month + '-01';
    this.rebuildCalendar(); this.reload();
  }
  aboutToDisappear(): void { this.request++; }
  private async reload(): Promise<void> {
    if (!this.workspace || !this.month) { return; }
    const request = ++this.request;
    this.loading = true; this.error = '';
    try {
      const snapshot = await this.workspace.snapshot(this.month);
      if (request === this.request) { this.entries = snapshot.entries.map(presentEntry); this.rebuildCalendar(); }
    } catch (_) { if (request === this.request) { this.error = '账单暂时无法读取，请重试'; } }
    finally { if (request === this.request) { this.loading = false; } }
  }
  private visible(): LedgerEntry[] { return filterEntries(this.entries, this.kind, this.keyword, '').filter((entry: LedgerEntry) => !this.selectedDate || entry.date === this.selectedDate); }
  private dates(): string[] { return Array.from(new Set(this.visible().map((entry: LedgerEntry) => entry.date))).sort().reverse(); }
  private shift(offset: number): void {
    const parts = this.month.split('-');
    const date = new Date(Number(parts[0]), Number(parts[1]) - 1 + offset, 1);
    this.month = date.getFullYear().toString() + '-' + (date.getMonth() + 1).toString().padStart(2, '0');
    this.selectedDate = this.month + '-01'; this.entries = []; this.rebuildCalendar();
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 }); this.reload();
  }
  private rebuildCalendar(): void {
    this.calendar = billCalendarDays(this.month).map((day: BillCalendarDay): BillCalendarCell => {
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
    const full = trimBillDecimal(minor);
    const available = Math.max(1, this.calendarWidth / 7 - 6);
    const width = this.getUIContext().getMeasureUtils().measureTextSize({ textContent: full, fontSize: '9fp', fontFamily: 'XiaoQiaoDINMedium' }).width;
    if (this.getUIContext().px2vp(Number(width)) <= available) { return full; }
    for (let digits = 2; digits >= 0; digits--) {
      const compact = compactBillAmount(minor, digits);
      const measured = this.getUIContext().getMeasureUtils().measureTextSize({ textContent: compact, fontSize: '9fp', fontFamily: 'XiaoQiaoDINMedium' }).width;
      if (this.getUIContext().px2vp(Number(measured)) <= available) { return compact; }
    }
    return compactBillAmount(minor, 0);
  }
  private selectDay(day: BillCalendarDay): void {
    if (!day.inMonth) {
      this.month = day.date.substring(0, 7); this.entries = []; this.rebuildCalendar(); this.reload();
    }
    this.selectedDate = day.date;
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }
  @Builder
  private calendarMoney(minor: string, income: boolean) {
    Text(this.calendarAmount(minor)).fontSize('11fp').minFontSize('9fp').maxFontSize('11fp')
      .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).fontFamily('XiaoQiaoDINMedium')
      .fontColor(income ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
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
  private amount(entry: LedgerEntry): string {
    if (entry.fx && !entry.transfer) {
      return currencyDefinition(entry.fx.currencyId).symbol + Money.fromMinorText(entry.fx.paidMinor, currencyUnit(entry.fx.currencyId)).toDecimalString();
    }
    return '¥' + displayAmount(entry.recoveryKind ? (-BigInt(entry.minor)).toString() : entry.transfer && this.kind === LedgerKind.Expense ? entry.expenseMinor || '0' : entry.minor);
  }
  private sign(entry: LedgerEntry): string {
    if (entry.prepaidId) { return entry.prepaidKind === 'refund' ? '+' : '−'; }
    return entry.recoveryKind || entry.income ? '+' : entry.transfer && this.kind !== LedgerKind.Expense ? '' : '−';
  }
  @Builder
  private entryRow(entry: LedgerEntry) {
    Row({ space: 12 }) {
      Image(entry.icon).width(36).height(36).objectFit(ImageFit.Contain).flexShrink(0)
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
        .fontColor(entry.prepaidId || entry.transfer ? $r('app.color.xq_font_primary') : entry.income || entry.recoveryKind ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
        .maxLines(1).constraintSize({ maxWidth: '42%' })
    }.width('100%').padding({ top: 16, bottom: 16 }).onClick(() => { this.onOpenEntry(entry); })
  }
  build() {
    HdsNavigation() {
      Column({ space: 12 }) {
        Row({ space: 12 }) {
          Button('‹', { type: ButtonType.Circle }).width(36).height(36).backgroundColor($r('app.color.xq_app_surface_card'))
            .fontColor($r('app.color.xq_font_primary')).accessibilityText('上个月').onClick(() => { this.shift(-1); })
          Text(this.month.replace('-', '年') + '月').fontSize('16fp').fontWeight(FontWeight.Medium).layoutWeight(1).textAlign(TextAlign.Center)
          Button('›', { type: ButtonType.Circle }).width(36).height(36).backgroundColor($r('app.color.xq_app_surface_card'))
            .fontColor($r('app.color.xq_font_primary')).accessibilityText('下个月').onClick(() => { this.shift(1); })
        }.width('100%')
        this.monthCalendar()
        TextInput({ text: this.keyword, placeholder: '搜索分类、备注、账户、标签' }).fontSize('14fp').height(44)
          .backgroundColor($r('app.color.xq_app_surface_card')).borderRadius(12).onChange((value: string) => { this.keyword = value; })
        Row({ space: 8 }) {
          ForEach(['全部', '支出', '收入'], (label: string, index: number) => {
            Button(label, { type: ButtonType.Capsule }).height(36).fontSize('14fp')
              .backgroundColor(this.kind === index ? $r('app.color.xq_brand') : $r('app.color.xq_app_surface_card'))
              .fontColor(this.kind === index ? Color.White : $r('app.color.xq_font_secondary')).onClick(() => { this.kind = index; })
          }, (label: string) => label)
          Blank()
          Text(this.visible().length.toString() + ' 笔').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        }.width('100%')
        Row({ space: 8 }) {
          Text(this.selectedDate ? this.selectedDate.replace(/-/g, '/') : '本月账单').fontSize('13fp')
            .fontColor($r('app.color.xq_font_secondary')).layoutWeight(1)
          Button('整月', { type: ButtonType.Capsule }).height(28).fontSize('12fp').backgroundColor(Color.Transparent)
            .fontColor($r('app.color.xq_font_emphasize')).onClick(() => { this.selectedDate = ''; })
        }.width('100%')
        List({ scroller: this.scroller }) {
          if (this.loading) { ListItem() { Text('正在读取账单…').fontSize('14fp').padding(24) } }
          else if (this.error) {
            ListItem() { Button(this.error + ' · 重试').fontSize('14fp').onClick(() => { this.reload(); }) }
          } else if (this.visible().length === 0) {
            ListItem() { Text('暂无符合条件的账单').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%').textAlign(TextAlign.Center).padding(32) }
          } else {
            ForEach(this.dates(), (date: string) => {
              ListItem() {
                Column({ space: 0 }) {
                  Row() {
                    Text(date.replace(/-/g, '/')).fontSize('13fp').fontWeight(FontWeight.Medium).layoutWeight(1)
                    Text('收 ' + displayAmount(dailyTotals(this.visible(), date).incomeMinor) + '  支 ' + displayAmount(dailyTotals(this.visible(), date).expenseMinor))
                      .fontSize('11fp').fontColor($r('app.color.xq_font_secondary'))
                  }.width('100%').padding({ top: 16, bottom: 8 })
                  Column() {
                    ForEach(this.visible().filter((entry: LedgerEntry) => entry.date === date), (entry: LedgerEntry) => {
                      this.entryRow(entry)
                      Divider().color($r('app.color.xq_app_divider_subtle'))
                    }, (entry: LedgerEntry) => entry.id)
                  }.padding({ left: 14, right: 14 }).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
                }.width('100%')
              }
            }, (date: string) => date)
          }
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring).contentEndOffset(24)
      }.padding({ left: 16, right: 16, top: 12 }).width('100%').height('100%')
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true, content: { title: { mainTitle: '账单明细' }, divider: { showType: DividerShowType.OFF }, backIcon: { action: () => { this.onClose(); } } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
