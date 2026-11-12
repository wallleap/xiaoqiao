import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { ChipGroup, ChipSize } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { AccountProfile } from '../domain/model/AccountProfile';
import { AccountCalibration, AccountCalibrationCommand } from '../domain/model/AccountCalibration';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { CurrencyUnit } from '../core/money/CurrencyUnit';
import { Money } from '../core/money/Money';
import { MoneyAmountField } from './MoneyAmountField';
import { ExpenseAmountInput } from '../presentation/ledger/ExpenseAmountInput';

@Component
export struct AccountCalibrationPage {
  account: AccountProfile | undefined = undefined;
  workspace: LedgerWorkspace | undefined = undefined;
  onClose: () => void = () => {};
  onSaved: () => void = () => {};
  onBusy: (busy: boolean) => void = () => {};
  @State private current: AccountProfile | undefined = undefined;
  @State private amount: string = '0';
  @State private negative: boolean = false;
  @State private reason: string = '';
  @State private busy: boolean = false;
  @State private conflict: boolean = false;
  @State private error: string = '';
  private readonly operationId: string = util.generateRandomUUID();
  private readonly currency: CurrencyUnit = new CurrencyUnit('CNY', 'CNY', 2);
  private readonly scroller: Scroller = new Scroller();
  private readonly amountController: TextInputController = new TextInputController();
  private readonly reasonController: TextInputController = new TextInputController();

  aboutToAppear(): void { this.initialize(); }
  private async initialize(): Promise<void> {
    this.busy = true; this.onBusy(true);
    try {
      if (this.workspace === undefined || this.account === undefined) { throw new Error('ACCOUNT_UNAVAILABLE'); }
      // Account lists can carry an older snapshot after transactions change. Never preview that cached balance.
      const current = (await this.workspace.accountOverview()).accounts.find((item: AccountProfile) => item.id === this.account?.id);
      if (current === undefined || current.archived) { throw new Error('ACCOUNT_CHANGED'); }
      this.current = current;
      const minor = BigInt(current.balanceMinor);
      this.negative = minor < BigInt(0) || (minor === BigInt(0) && current.kind === 'liability');
      this.amount = Money.fromMinor(minor < BigInt(0) ? -minor : minor, this.currency).toDecimalString();
      this.conflict = false; this.error = '';
    } catch (_) { this.conflict = true; this.error = '账户已归档、删除或暂时无法读取，请刷新余额或返回'; }
    finally { this.busy = false; this.onBusy(false); }
  }
  private money(minor: string): string { return Money.fromMinorText(minor, this.currency).toDecimalString(); }
  private after(): Money {
    const value = ExpenseAmountInput.nonnegative(this.amount, this.currency);
    return this.negative ? value.negate() : value;
  }
  private draft(): AccountCalibration {
    if (this.current === undefined || this.current.archived) { throw new Error('ACCOUNT_CHANGED'); }
    const command: AccountCalibrationCommand = { id: this.operationId, accountId: this.current.id,
      expectedRevision: this.current.revision, before: Money.fromMinorText(this.current.balanceMinor, this.currency),
      after: this.after(), reason: this.reason };
    return new AccountCalibration(command);
  }
  private valid(): boolean { try { this.draft(); return true; } catch (_) { return false; } }
  private afterText(): string { try { return this.after().toDecimalString(); } catch (_) { return '—'; } }
  private deltaText(): string {
    try {
      const delta = this.after().subtract(Money.fromMinorText(this.current?.balanceMinor || '0', this.currency));
      return (delta.minor > BigInt(0) ? '+' : '') + delta.toDecimalString();
    } catch (_) { return '—'; }
  }
  private async refresh(): Promise<void> {
    if (this.busy || this.workspace === undefined || this.account === undefined) { return; }
    if (this.current === undefined) { await this.initialize(); return; }
    this.busy = true; this.onBusy(true);
    try {
      const current = (await this.workspace.accountOverview()).accounts.find((item: AccountProfile) => item.id === this.account?.id);
      if (current === undefined || current.archived) { throw new Error('ACCOUNT_CHANGED'); }
      this.current = current; this.conflict = false;
      this.error = '';
    } catch (_) { this.conflict = true; this.error = '账户已归档、删除或暂时无法读取，请返回账户列表'; }
    finally { this.busy = false; this.onBusy(false); }
  }
  private async confirm(): Promise<void> {
    if (this.busy || this.conflict) { return; }
    let draft: AccountCalibration;
    try { draft = this.draft(); } catch (_) { this.error = '请填写有效且不同于当前余额的金额，最多两位小数'; return; }
    this.amountController.stopEditing(); this.reasonController.stopEditing();
    this.busy = true; this.onBusy(true); this.error = '';
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({ title: '确认校准余额？',
        message: (this.current?.name || '') + '\n当前余额 ' + draft.command.before.toDecimalString() + '\n校准后余额 ' + draft.command.after.toDecimalString() + '\n调整差额 ' + (draft.delta.minor > BigInt(0) ? '+' : '') + draft.delta.toDecimalString() + '\n不计入收支和预算，历史账目保持原样。',
        buttons: [{ text: '取消', color: $r('app.color.xq_font_secondary') }, { text: '确认校准', color: $r('app.color.xq_font_emphasize') }] });
      if (choice.index !== 1) { return; }
      try {
        if (this.workspace === undefined) { throw new Error('WORKSPACE_UNAVAILABLE'); }
        await this.workspace.calibrateAccount(draft.command); this.onSaved();
      } catch (error) {
        if (['ACCOUNT_CHANGED', 'BALANCE_CHANGED'].includes((error as Error).message)) {
          this.conflict = true; this.error = '账户或余额已变化，请刷新预览后重新确认';
        } else { this.conflict = true; this.error = '校准未确认，请先刷新余额并检查调整记录，避免重复操作'; }
      }
    } catch (_) { /* Dismissing confirmation writes nothing. */ }
    finally { this.busy = false; this.onBusy(false); }
  }
  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }

  build() {
    HdsNavigation() {
      Column() {
        Scroll(this.scroller) {
          Column({ space: 16 }) {
            Column({ space: 8 }) {
              Text(this.current?.name || this.account?.name || '').fontSize('18fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary')).maxLines(2)
              Text('当前账面余额 · CNY').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
              Text(this.current === undefined ? '—' : this.money(this.current.balanceMinor)).fontSize('30fp').fontFamily('XiaoQiaoDINBold')
                .fontColor($r('app.color.xq_font_primary')).maxLines(1).minFontSize('18fp').maxFontSize('30fp').id('calibration-before')
            }.padding(20).width('100%').alignItems(HorizontalAlign.Start).borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
            Column({ space: 16 }) {
              Text(this.current?.kind === 'liability' ? '实际待还或溢缴金额' : '实际余额或透支金额').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
              ChipGroup({ items: [{ label: { text: this.current?.kind === 'liability' ? '待还金额' : '可用余额' } }, { label: { text: this.current?.kind === 'liability' ? '溢缴余额' : '透支金额' } }],
                selectedIndexes: [this.current?.kind === 'liability' ? (this.negative ? 0 : 1) : (this.negative ? 1 : 0)],
                itemStyle: { size: ChipSize.NORMAL, backgroundColor: $r('app.color.xq_app_filter_unselected'), selectedBackgroundColor: $r('app.color.xq_brand'), fontColor: $r('app.color.xq_font_secondary'), selectedFontColor: $r('app.color.xq_font_on_primary') },
                onChange: (values: number[]) => { if (values.length === 1 && !this.busy) { this.negative = this.current?.kind === 'liability' ? values[0] === 0 : values[0] === 1; } }
              }).width('100%').id('calibration-direction')
              MoneyAmountField({ value: $amount, fieldId: 'calibration-amount', fontSize: '30fp', fontFamily: 'XiaoQiaoDINBold',
                currency: this.currency, controller: this.amountController, disabled: this.busy,
                canSubmit: !this.conflict && this.valid(), submitLabel: '预览', onSubmit: () => { this.confirm(); } })
              if (this.current !== undefined && this.afterText() !== '—' && !this.valid()) {
                Text(this.afterText() === this.money(this.current.balanceMinor) ? '金额与当前余额相同' : '调整差额超出允许范围')
                  .fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%')
              }
              TextInput({ text: this.reason, placeholder: '调整原因（可选）', controller: this.reasonController }).fontSize('14fp').maxLength(200)
                .backgroundColor($r('app.color.xq_app_surface_keyboard')).borderRadius(12).enabled(!this.busy).id('calibration-reason')
                .onChange((value: string) => { this.reason = value; })
            }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
            Column({ space: 12 }) {
              Row() {
                Text('校准后余额').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
                Blank()
                Text(this.afterText()).fontSize('18fp').fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_primary')).id('calibration-after')
              }.width('100%')
              Row() {
                Text('调整差额').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
                Blank()
                Text(this.deltaText()).fontSize('18fp').fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_primary')).id('calibration-delta')
              }.width('100%')
              Text('待还、透支以负余额记录；不计收支和预算，也不改写期初与历史账目。').fontSize('12fp').lineHeight('18fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
            }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
            if (this.error) { Text(this.error).fontSize('14fp').fontColor($r('app.color.xq_warning')).id('calibration-error') }
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 24 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off).clip(false).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        Column() {
          if (this.conflict) {
            Button(this.busy ? '读取中' : '刷新余额', { type: ButtonType.Capsule }).width('100%').height(48).fontSize('16fp')
              .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.busy)
              .onClick(() => { this.refresh(); }).id('calibration-refresh')
          } else {
            Button(this.busy ? '处理中' : '预览并校准', { type: ButtonType.Capsule }).width('100%').height(48).fontSize('16fp')
              .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.busy && this.valid())
              .onClick(() => { this.confirm(); }).id('calibration-confirm')
          }
        }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })
          .backgroundColor($r('app.color.xq_app_surface_page')).zIndex(1)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }.width('100%').height('100%').constraintSize({ maxWidth: 720 }).align(Alignment.Top)
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true, content: { title: { mainTitle: '校准余额' }, divider: { showType: DividerShowType.OFF }, backIcon: { componentId: 'calibration-close', action: () => { if (!this.busy) { this.onClose(); } } } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } }, scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]).id('account-calibration-page')
  }
}
