import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType } from '@kit.UIDesignKit';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { LedgerSnapshot } from '../domain/model/LedgerSnapshot';
import { BudgetNatureLine } from '../domain/model/SpendingNature';
import { CurrencyUnit } from '../core/money/CurrencyUnit';
import { Money } from '../core/money/Money';
import { ExpenseAmountInput } from '../presentation/ledger/ExpenseAmountInput';
import { displayAmount } from '../presentation/ledger/LedgerOverview';
import { spendingNatureBackground, spendingNatureText } from '../presentation/ledger/SpendingNatureStyles';
import { MoneyAmountField } from './MoneyAmountField';

@Component
export struct BudgetPage {
  workspace: LedgerWorkspace | undefined = undefined;
  monthKey: string = '';
  monthLabel: string = '';
  sheetMaterial: SystemUiMaterial | undefined = undefined;
  onClose: () => void = () => {};
  @State private snapshot: LedgerSnapshot | undefined = undefined;
  @State private totalInput: string = '0';
  @State private loading: boolean = true;
  @State private busy: boolean = false;
  @State private editing: BudgetNatureLine | undefined = undefined;
  @State private natureInput: string = '0';
  @State private showNatureEditor: boolean = false;
  @State private error: string = '';
  private readonly currency: CurrencyUnit = new CurrencyUnit('CNY', 'CNY', 2);
  private readonly totalController: TextInputController = new TextInputController();
  private readonly natureController: TextInputController = new TextInputController();
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.load(); }

  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }

  private async load(): Promise<void> {
    if (this.workspace === undefined) { this.loading = false; return; }
    this.loading = true; this.error = '';
    try {
      this.snapshot = await this.workspace.snapshot(this.monthKey.replace('年', '-').replace('月', '-01'));
      this.totalInput = Money.fromMinorText(this.snapshot.budgetTotalMinor, this.currency).toDecimalString();
    } catch (_) { this.error = '预算暂时无法读取，请返回后重试'; }
    finally { this.loading = false; }
  }

  private validTotal(): boolean {
    try { ExpenseAmountInput.nonnegative(this.totalInput, this.currency); return true; } catch (_) { return false; }
  }

  private validNature(): boolean {
    try { ExpenseAmountInput.nonnegative(this.natureInput, this.currency); return true; } catch (_) { return false; }
  }

  private sumAllocated(): bigint {
    return (this.snapshot?.budgetNatureLines || []).reduce((sum: bigint, line: BudgetNatureLine) =>
      sum + BigInt(line.amountMinor), BigInt(0));
  }

  private unallocated(): string {
    const value = BigInt(this.snapshot?.budgetTotalMinor || '0') - this.sumAllocated();
    return value > BigInt(0) ? value.toString() : '0';
  }

  private async saveTotal(): Promise<void> {
    if (this.busy || this.workspace === undefined) { return; }
    this.busy = true; this.error = '';
    try {
      await this.workspace.setMonthlyBudget(this.monthKey, this.totalInput);
      this.totalController.stopEditing();
      this.onClose();
    } catch (_) {
      this.error = '总预算不能低于已分配的分类预算，请先调整分类额度';
    } finally { this.busy = false; }
  }

  private editNature(line: BudgetNatureLine): void {
    this.editing = line;
    this.natureInput = Money.fromMinorText(line.amountMinor, this.currency).toDecimalString();
    this.error = '';
    this.showNatureEditor = true;
  }

  private async saveNature(): Promise<void> {
    if (this.busy || this.workspace === undefined || this.editing === undefined) { return; }
    this.busy = true; this.error = '';
    try {
      await this.workspace.setBudgetNatureAmount(this.monthKey, this.editing.natureId, this.natureInput);
      this.natureController.stopEditing();
      this.showNatureEditor = false;
      await this.load();
    } catch (_) {
      this.error = '分类额度不能超过总预算与其它分类额度之和';
    } finally { this.busy = false; }
  }

  private sheetOptions(): SheetOptions {
    const options: SheetOptions = { height: 360, showClose: true };
    if (this.sheetMaterial !== undefined) { options.systemMaterial = this.sheetMaterial; }
    else { options.backgroundColor = $r('app.color.xq_app_surface_card'); }
    return options;
  }

  @Builder
  private natureEditor() {
    Column({ space: 16 }) {
      Text((this.editing?.name || '') + '预算').fontSize('20fp').fontWeight(FontWeight.Bold).width('100%')
      Text('设置该预算分类本月可使用的额度；修改不会改变已发生账目。').fontSize('12fp')
        .fontColor($r('app.color.xq_font_secondary')).width('100%')
      MoneyAmountField({ value: $natureInput, fieldId: 'budget-nature-input', currency: this.currency,
        controller: this.natureController, disabled: this.busy, canSubmit: this.validNature() && !this.busy,
        submitLabel: '保存', onSubmit: () => { this.saveNature(); } })
      if (this.error.length > 0) {
        Text(this.error).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%')
      }
      Button('取消', { type: ButtonType.Capsule }).width('100%').height(44)
        .fontColor($r('app.color.xq_font_primary')).backgroundColor($r('app.color.xq_app_surface_keyboard'))
        .enabled(!this.busy).onClick(() => { this.showNatureEditor = false; })
    }.padding(24).width('100%').height('100%')
  }

  @Builder
  private natureRow(line: BudgetNatureLine) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(line.name).fontSize('16fp').fontWeight(FontWeight.Medium).fontColor(spendingNatureText(line.colorKey))
        if (line.archived) { Text('已归档').fontSize('10fp').fontColor($r('app.color.xq_font_tertiary')) }
        Blank()
        Text(line.amountMinor === '0' ? '未设额度' : '¥' + displayAmount(line.amountMinor))
          .fontSize('16fp').fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_primary'))
      }.width('100%')
      Row() {
        Text('已用 ¥' + displayAmount(line.usedMinor)).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        Blank()
        Text(line.amountMinor === '0' ? '仅计入未分配' : (BigInt(line.usedMinor) > BigInt(line.amountMinor) ? '已超分类额度' : '分类预算内'))
          .fontSize('12fp').fontColor(BigInt(line.usedMinor) > BigInt(line.amountMinor) && line.amountMinor !== '0' ?
            $r('app.color.xq_warning') : $r('app.color.xq_font_secondary'))
      }.width('100%')
      if (line.amountMinor !== '0') {
        Progress({ value: Number(Math.max(0, Math.min(100, Number(line.usedMinor) * 100 / Math.max(1, Number(line.amountMinor))))),
          total: 100, type: ProgressType.Linear }).height(4).color(spendingNatureText(line.colorKey))
          .backgroundColor($r('app.color.xq_comp_background_tertiary')).width('100%')
      }
    }.padding(16).width('100%').borderRadius(16).backgroundColor(spendingNatureBackground(line.colorKey))
      .id('budget-nature-' + line.natureId).onClick(() => { this.editNature(line); })
  }

  build() {
    HdsNavigation() {
      Column() {
        Scroll(this.scroller) {
          Column({ space: 16 }) {
            Column({ space: 12 }) {
              Text('本月总预算').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
              MoneyAmountField({ value: $totalInput, fieldId: 'ledger-budget-input', currency: this.currency,
                controller: this.totalController, disabled: this.busy, canSubmit: this.validTotal() && !this.busy,
                submitLabel: '保存', onSubmit: () => { this.saveTotal(); } })
              Row() {
                Text('分类预算合计').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
                Blank()
                Text('¥' + displayAmount(this.sumAllocated().toString())).fontSize('12fp')
                  .fontFamily('XiaoQiaoDINRegular').fontColor($r('app.color.xq_font_primary'))
              }.width('100%')
              Row() {
                Text('未分配').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
                Blank()
                Text('¥' + displayAmount(this.unallocated())).fontSize('12fp')
                  .fontFamily('XiaoQiaoDINRegular').fontColor($r('app.color.xq_font_primary'))
              }.width('100%')
            }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
            if (this.error.length > 0) {
              Text(this.error).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%')
            }
            Row() {
              Text('分类预算').fontSize('18fp').fontWeight(FontWeight.Medium)
              Blank()
              Text('点击设置额度').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
            }.width('100%')
            if (this.loading) {
              Text('正在读取预算…').fontSize('14fp').padding(24)
            } else if (this.snapshot !== undefined) {
              ForEach(this.snapshot.budgetNatureLines, (line: BudgetNatureLine) => {
                this.natureRow(line)
              }, (line: BudgetNatureLine) => line.natureId + ':' + line.amountMinor)
            }
            Text('分类额度合计不能超过总预算；没有预算分类的支出只计入总预算的未分配部分。')
              .fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
          }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 32 })
        }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }.width('100%').height('100%')
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '修改月预算' }, divider: { showType: DividerShowType.OFF },
          backIcon: { componentId: 'budget-close', action: () => { if (!this.busy) { this.onClose(); } } } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
          backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showNatureEditor, this.natureEditor(), this.sheetOptions()).id('budget-page')
  }
}
