import { ExpenseAmountInput } from '../presentation/ledger/ExpenseAmountInput';
import { MoneyAmountField } from './MoneyAmountField';
import { currencyUnit } from '../core/money/Currencies';
import { ExchangeRate } from '../core/money/ExchangeRate';
import { OfficialExchangeRates } from '../data/exchange/OfficialExchangeRates';
import { util } from '@kit.ArkTS';
import { EntryDetail } from '../domain/model/EntryDetail';
import { LedgerAccount } from '../domain/model/LedgerSnapshot';
import { ExpenseRecovery, RecoveryCommand, RecoveryKind, recoveryError } from '../domain/model/ExpenseRecovery';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { Money } from '../core/money/Money';
import { CurrencyUnit } from '../core/money/CurrencyUnit';

export type RecoveryMenuAction = RecoveryKind | 'togglePending';

/** Connects the title-bar menu to the existing receipt panel without recreating the form. */
export class ExpenseRecoveryController {
  private handler: ((action: RecoveryMenuAction) => void) | undefined = undefined;
  attach(handler: (action: RecoveryMenuAction) => void): void { this.handler = handler; }
  detach(handler: (action: RecoveryMenuAction) => void): void {
    if (this.handler === handler) { this.handler = undefined; }
  }
  request(action: RecoveryMenuAction): void { this.handler?.(action); }
}

@Component
export struct ExpenseRecoveryPanel {
  @Require @Prop entry: EntryDetail;
  accounts: LedgerAccount[] = [];
  workspace: LedgerWorkspace | undefined = undefined;
  onChanged: () => Promise<void> = async () => {};
  controller: ExpenseRecoveryController | undefined = undefined;
  onBusyChange: (busy: boolean) => void = () => {};
  @State private showForm: boolean = false;
  @State @Watch('workingChanged') private working: boolean = false;
  @State private kind: RecoveryKind = 'refund';
  @State private amountText: string = '';
  @State private dateText: string = '';
  @State private timeText: string = '';
  @State private noteText: string = '';
  @State private accountRate: string = '';
  @State private actualAccount: string = '';
  @State private rateDate: string = '';
  @State private rateSource: string = 'manual';
  @State private accountId: string = '';
  @State private formError: string = '';
  @State private amountError: string = '';
  private active: boolean = false;
  private readonly formScroller: Scroller = new Scroller();
  private readonly amountController: TextInputController = new TextInputController();
  private readonly noteController: TextInputController = new TextInputController();
  private editing: ExpenseRecovery | undefined = undefined;
  private draftId: string = '';

  private readonly menuHandler = (action: RecoveryMenuAction): void => {
    if (!this.active || this.working || this.showForm || this.remaining() <= BigInt(0)) { return; }
    if (action === 'togglePending') { this.togglePending(); }
    else { this.open(action); }
  };

  aboutToAppear(): void { this.active = true; this.controller?.attach(this.menuHandler); }
  aboutToDisappear(): void {
    this.active = false; this.stopInputs(); this.controller?.detach(this.menuHandler); this.onBusyChange(false);
  }
  private workingChanged(): void { this.onBusyChange(this.working); }

  private stopInputs(): void { this.amountController.stopEditing(); this.noteController.stopEditing(); }

  private decimal(minor: string): string {
    return Money.fromMinorText(minor, currencyUnit(this.entry.currencyId)).toDecimalString();
  }

  private total(kind: string = ''): bigint {
    let value = BigInt(0);
    for (const item of this.entry.recoveries || []) {
      if (kind.length === 0 || item.kind === kind) { value += BigInt(item.amountMinor); }
    }
    return value;
  }

  private remaining(): bigint { return BigInt(this.entry.paidMinor) - this.total(); }
  private available(): bigint { return this.remaining() + BigInt(this.editing?.amountMinor || '0'); }

  private options(): SelectOption[] {
    const values: SelectOption[] = [{ value: '不使用账户' }];
    for (const account of this.accounts) {
      values.push({ value: account.name + ' · ' + account.currencyId });
    }
    if (this.editing !== undefined && this.editing.accountId.length > 0 &&
      !this.accounts.some((item: LedgerAccount) => item.id === this.editing?.accountId)) {
      values.push({ value: this.editing.accountName + '（已归档）' });
    }
    return values;
  }

  private accountIds(): string[] {
    const ids = [''];
    for (const account of this.accounts) { ids.push(account.id); }
    if (this.editing !== undefined && this.editing.accountId.length > 0 && !ids.includes(this.editing.accountId)) {
      ids.push(this.editing.accountId);
    }
    return ids;
  }

  private open(kind: RecoveryKind, item?: ExpenseRecovery): void {
    if (this.working) { return; }
    this.editing = item; this.draftId = item?.id || util.generateRandomUUID();
    this.kind = kind; this.amountText = item === undefined ? '' : this.decimal(item.amountMinor);
    const date = item === undefined ? new Date() : new Date(item.occurredAtMs + item.offsetMinutes * 60000);
    const local = item === undefined ? new Date(date.getTime() - date.getTimezoneOffset() * 60000) : date;
    this.dateText = local.toISOString().substring(0, 10); this.timeText = local.toISOString().substring(11, 16);
    this.accountId = item === undefined ? this.entry.accountId || '' : item.accountId;
    if (!this.accountIds().includes(this.accountId)) { this.accountId = ''; }
    this.accountRate = item?.accountFx?.rate || ''; this.rateDate = item?.accountFx?.date || ''; this.rateSource = item?.accountFx?.source || 'manual';
    this.actualAccount = item?.accountMinor !== undefined && item.accountCurrencyId !== undefined && item.accountCurrencyId !== this.entry.currencyId ? Money.fromMinorText(item.accountMinor, currencyUnit(item.accountCurrencyId)).toDecimalString() : '';
    this.noteText = item?.note || ''; this.formError = ''; this.amountError = ''; this.showForm = true;
  }

  private async refresh(): Promise<void> {
    try { await this.onChanged(); }
    catch (_) { this.getUIContext().getPromptAction().showToast({ message: '回款已更新，页面刷新失败，请返回后重新读取' }); }
  }

  private accountLabel(): string {
    const index = Math.max(0, this.accountIds().indexOf(this.accountId));
    const value = this.options()[index].value;
    return typeof value === 'string' ? value : '到账账户';
  }

  private kindLabel(): string { return this.kind === 'refund' ? '退款' : '报销'; }

  private pickAccount(): void {
    if (this.working) { return; }
    this.stopInputs();
    const ids = this.accountIds();
    const names = this.options().map((option: SelectOption) => typeof option.value === 'string' ? option.value : '到账账户');
    this.getUIContext().showTextPickerDialog({ range: names, selected: Math.max(0, ids.indexOf(this.accountId)),
      selectedTextStyle: { color: $r('app.color.xq_font_emphasize') },
      acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      cancelButtonStyle: { fontColor: $r('app.color.xq_font_secondary') },
      onAccept: (result: TextPickerResult) => {
        if (!this.active || !this.showForm) { return; }
        const index = typeof result.index === 'number' ? result.index : result.index[0];
        this.accountId = ids[index] || ''; this.accountRate = ''; this.actualAccount = '';
      }
    });
  }

  private pickDateTime(): void {
    if (this.working) { return; }
    this.stopInputs();
    let accepted: Date | undefined = undefined;
    this.getUIContext().showDatePickerDialog({ selected: new Date(this.dateText + 'T' + this.timeText + ':00'),
      selectedTextStyle: { color: $r('app.color.xq_font_emphasize') },
      acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      cancelButtonStyle: { fontColor: $r('app.color.xq_font_secondary') },
      onDateAccept: (date: Date) => { accepted = date; },
      onDidDisappear: () => {
        if (!this.active || !this.showForm || accepted === undefined) { return; }
        this.pickTime(accepted);
      }
    });
  }

  private pickTime(selectedDate: Date): void {
    const dateText = `${selectedDate.getFullYear()}-${String(selectedDate.getMonth() + 1).padStart(2, '0')}-${String(selectedDate.getDate()).padStart(2, '0')}`;
    this.getUIContext().showTimePickerDialog({ selected: new Date(dateText + 'T' + this.timeText + ':00'), useMilitaryTime: true,
      selectedTextStyle: { color: $r('app.color.xq_font_emphasize') },
      acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      cancelButtonStyle: { fontColor: $r('app.color.xq_font_secondary') },
      onAccept: (result: TimePickerResult) => {
        if (!this.active || !this.showForm) { return; }
        this.dateText = dateText;
        this.timeText = String(result.hour ?? 0).padStart(2, '0') + ':' + String(result.minute ?? 0).padStart(2, '0');
      }
    });
  }

  private validateAmount(): Money | undefined {
    this.amountError = '';
    try {
      const amount = ExpenseAmountInput.nonnegative(this.amountText, currencyUnit(this.entry.currencyId));
      amount.toSafeMinorNumber();
      if (amount.minor <= BigInt(0)) { this.amountError = '请输入大于 0 的到账金额'; return undefined; }
      if (amount.minor > this.available()) {
        this.amountError = `本次最多可${this.kind === 'refund' ? '退' : '报销'} ${this.entry.currencyCode} ${this.decimal(this.available().toString())}`;
        return undefined;
      }
      return amount;
    } catch (_) { this.amountError = '请输入有效金额，小数位须符合原支出币种'; return undefined; }
  }

  private async loadAccountRate(): Promise<void> {
    if (this.working) { return; }
    const target = this.accounts.find((item: LedgerAccount) => item.id === this.accountId)?.currencyId;
    if (target === undefined) { return; }
    this.working = true;
    try {
      const quote = await OfficialExchangeRates.quote(this.entry.currencyId, target, this.dateText);
      if (this.active) { this.accountRate = quote.rate; this.rateDate = quote.date; this.rateSource = quote.source; }
    } catch (_) { if (this.active) { this.formError = '参考汇率暂不可用，可手动填写'; } }
    finally { if (this.active) { this.working = false; } }
  }

  private async save(): Promise<void> {
    const workspace = this.workspace;
    if (workspace === undefined || this.working) { return; }
    const amount = this.validateAmount();
    if (amount === undefined) { this.formScroller.scrollTo({ xOffset: 0, yOffset: 0 }); return; }
    this.stopInputs();
    this.working = true; this.formError = '';
    try {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(this.dateText) || !/^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(this.timeText)) {
        throw new Error('INVALID_RECOVERY');
      }
      const date = new Date(this.dateText + 'T' + this.timeText + ':00');
      const command: RecoveryCommand = { id: this.draftId, transactionId: this.entry.id, bookId: this.entry.bookId,
        kind: this.kind, amountMinor: amount.minor.toString(), accountId: this.accountId,
        occurredAtMs: date.getTime(), localDate: this.dateText, offsetMinutes: -date.getTimezoneOffset(), note: this.noteText,
        expectedRevision: this.editing?.revision };
      const target = this.accounts.find((item: LedgerAccount) => item.id === this.accountId)?.currencyId || this.editing?.accountCurrencyId || this.entry.currencyId;
      if (target !== this.entry.currencyId) {
        command.accountMinor = (this.actualAccount ? ExpenseAmountInput.nonnegative(this.actualAccount, currencyUnit(target)) :
          new ExchangeRate(currencyUnit(this.entry.currencyId), currencyUnit(target), this.accountRate).convert(amount)).minor.toString();
        command.accountFx = { rate: this.accountRate, source: this.rateSource, date: this.rateDate || this.dateText, actual: this.actualAccount.length > 0 };
      }
      await workspace.saveRecovery(command);
      this.showForm = false;
      await this.refresh();
    } catch (error) {
      if ((error as Error).message.includes('RECOVERY_EXCEEDS_PAID')) {
        this.amountError = recoveryError(error as Error);
        this.formScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      }
      else { this.formError = recoveryError(error as Error); }
    }
    finally { this.working = false; }
  }

  private async remove(item: ExpenseRecovery): Promise<void> {
    const workspace = this.workspace;
    if (workspace === undefined || this.working) { return; }
    let confirmed = false;
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({ title: '删除回款',
        message: `删除这笔${item.kind === 'refund' ? '退款' : '报销'} ${this.entry.currencyCode} ${this.decimal(item.amountMinor)}？账户余额、支出和预算会同步恢复。`,
        buttons: [{ text: '取消', color: '#666666' }, { text: '删除', color: '#E84026' }] });
      confirmed = choice.index === 1;
    } catch (_) { return; }
    if (!confirmed) { return; }
    this.working = true;
    try {
      await workspace.deleteRecovery(item.id, item.revision);
      this.stopInputs(); this.showForm = false;
      await this.refresh();
    } catch (error) { this.getUIContext().getPromptAction().showToast({ message: recoveryError(error as Error) }); }
    finally { this.working = false; }
  }

  private receiptTime(item: ExpenseRecovery): string {
    const date = new Date(item.occurredAtMs + item.offsetMinutes * 60000);
    return item.localDate + ' ' + String(date.getUTCHours()).padStart(2, '0') + ':' + String(date.getUTCMinutes()).padStart(2, '0');
  }

  private async togglePending(): Promise<void> {
    if (this.workspace === undefined || this.working) { return; }
    this.working = true;
    try {
      await this.workspace.setReimbursementPending(this.entry.id, this.entry.revision, !this.entry.reimbursementPending);
      await this.refresh();
    } catch (error) { this.getUIContext().getPromptAction().showToast({ message: recoveryError(error as Error) }); }
    finally { this.working = false; }
  }

  @Builder
  private typeOption(kind: RecoveryKind, label: string) {
    Button(label, { type: ButtonType.Capsule }).layoutWeight(1).height(36).fontSize('14fp')
      .fontColor(this.kind === kind ? $r('app.color.xq_font_primary') : $r('app.color.xq_font_secondary'))
      .backgroundColor(this.kind === kind ? $r('app.color.xq_app_surface_card') : Color.Transparent)
      .accessibilityText(label + (this.kind === kind ? '，已选择' : ''))
      .onClick(() => { this.kind = kind; this.amountError = ''; this.formError = ''; })
  }

  @Builder
  private chevron() {
    Image($r('app.media.lucide_chevron_right1')).width(14).height(14).fillColor($r('app.color.xq_icon_tertiary'))
  }

  @Builder
  private form() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Button('取消', { type: ButtonType.Normal }).width(48).height(44).padding(0).fontSize('14fp')
          .fontColor($r('app.color.xq_font_secondary')).backgroundColor(Color.Transparent)
          .enabled(!this.working).onClick(() => { this.stopInputs(); this.showForm = false; })
        Text((this.editing === undefined ? '记录' : '编辑') + this.kindLabel()).fontSize('18fp')
          .fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary')).layoutWeight(1).textAlign(TextAlign.Center)
        Blank().width(48)
      }.width('100%').padding({ bottom: 12 })
      Scroll(this.formScroller) {
        Column({ space: 20 }) {
          Row({ space: 4 }) {
            this.typeOption('refund', '退款')
            this.typeOption('reimbursement', '报销')
          }.padding(4).width('100%').borderRadius(24).backgroundColor($r('app.color.xq_app_surface_page'))
          Column({ space: 8 }) {
            Text('本次收回原支出金额 · ' + this.entry.currencyCode).fontSize('13fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            Row({ space: 8 }) {
              Text(this.entry.currencySymbol).fontSize('22fp').fontColor($r('app.color.xq_font_primary')).padding({ bottom: 8 })
              MoneyAmountField({ value: $amountText, fieldId: 'recovery-amount', currency: currencyUnit(this.entry.currencyId),
                controller: this.amountController, fontSize: '36fp', fontFamily: 'XiaoQiaoDINBold', fieldHeight: 60,
                placeholder: '0.00', disabled: this.working,
                onChange: () => { this.amountError = ''; this.formError = ''; } }).layoutWeight(1)
            }.width('100%').alignItems(VerticalAlign.Bottom)
            Row({ space: 8 }) {
              Text(`最多可${this.kind === 'refund' ? '退' : '报销'} ${this.entry.currencyCode} ${this.decimal(this.available().toString())}`)
                .fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).layoutWeight(1)
              Button('全部剩余', { type: ButtonType.Capsule }).height(32).padding({ left: 10, right: 10 }).fontSize('12fp')
                .fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_page'))
                .onClick(() => { this.amountText = this.decimal(this.available().toString()); this.amountError = ''; this.formError = ''; })
            }.width('100%')
            if (this.accountId && (this.accounts.find((item: LedgerAccount) => item.id === this.accountId)?.currencyId || this.editing?.accountCurrencyId) !== this.entry.currencyId) {
              TextInput({ text: this.accountRate, placeholder: '原币 → 到账币种汇率' }).fontSize('14fp').type(InputType.NUMBER_DECIMAL)
                .enabled(!this.working).onChange((value: string) => { this.accountRate = value; this.rateSource = 'manual'; this.rateDate = this.dateText; })
              MoneyAmountField({ value: $actualAccount, fieldId: 'recovery-actual-account',
                currency: currencyUnit(this.accounts.find((item: LedgerAccount) => item.id === this.accountId)?.currencyId || this.editing?.accountCurrencyId || this.entry.currencyId),
                fontSize: '14fp', allowEmpty: true, placeholder: '实际到账金额（可选）', disabled: this.working })
              Button('获取官方参考汇率').fontSize('13fp').backgroundColor(Color.Transparent).fontColor($r('app.color.xq_font_emphasize'))
                .enabled(!this.working).onClick(() => { this.loadAccountRate(); })
            }
            if (this.amountError.length > 0) {
              Text(this.amountError).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%').id('recovery-amount-error')
            }
          }.width('100%').padding({ top: 4, bottom: 4 })
          Column({ space: 0 }) {
            Row({ space: 10 }) {
              Image($r('app.media.lucide_wallet_cards1')).width(18).height(18).fillColor($r('app.color.xq_icon_secondary'))
              Text('到账账户').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
              Blank()
              Text(this.accountLabel()).fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
                .textAlign(TextAlign.End).maxLines(2).constraintSize({ maxWidth: '50%' })
              this.chevron()
            }.width('100%').constraintSize({ minHeight: 56 }).onClick(() => { this.pickAccount(); })
              .accessibilityText('选择到账账户，当前' + this.accountLabel()).id('recovery-account')
            Divider().color($r('app.color.xq_comp_divider'))
            Row({ space: 10 }) {
              Image($r('app.media.lucide_calendar_check1')).width(18).height(18).fillColor($r('app.color.xq_icon_secondary'))
              Text('到账时间').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
              Blank()
              Text(this.dateText + ' ' + this.timeText).fontSize('13fp').fontColor($r('app.color.xq_font_primary'))
                .textAlign(TextAlign.End).maxLines(2).constraintSize({ maxWidth: '56%' })
              this.chevron()
            }.width('100%').constraintSize({ minHeight: 56 }).onClick(() => { this.pickDateTime(); })
              .accessibilityText('选择到账日期和时间').id('recovery-date')
          }.padding({ left: 14, right: 14 }).width('100%').borderRadius(14).backgroundColor($r('app.color.xq_app_surface_page'))
          Column({ space: 8 }) {
            Text('备注').fontSize('13fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            TextInput({ text: this.noteText, placeholder: '添加备注（选填）', controller: this.noteController })
              .height(48).fontSize('14fp').maxLength(500).fontColor($r('app.color.xq_font_primary'))
              .backgroundColor($r('app.color.xq_app_surface_page')).borderRadius(12)
              .onChange((value: string) => { this.noteText = value; }).onSubmit(() => { this.noteController.stopEditing(); })
          }.width('100%')
          Text(this.editing?.balanceMode === 'preserve' ? '按到账日期冲减支出和对应预算。这笔导入回款保留原账户余额，修改后仍不影响余额。' :
            '按到账日期冲减支出；原支出计入预算时，同步冲减对应预算。')
            .fontSize('12fp').lineHeight('18fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
        }.width('100%').padding({ bottom: 16 }).enabled(!this.working)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onAppear(() => { this.formScroller.scrollTo({ xOffset: 0, yOffset: 0 }); })
      Column({ space: 8 }) {
        if (this.formError.length > 0) {
          Text(this.formError).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%')
        }
        Button(this.working ? '保存中…' : this.editing === undefined ? '确认' + this.kindLabel() : '保存修改', { type: ButtonType.Capsule })
          .height(48).width('100%').fontSize('16fp').fontWeight(FontWeight.Medium)
          .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.working)
          .onClick(() => { this.save(); }).id('recovery-save')
        if (this.editing !== undefined) {
          Button('删除这笔' + this.kindLabel(), { type: ButtonType.Capsule }).height(36).width('100%').fontSize('13fp')
            .fontColor($r('app.color.xq_warning')).backgroundColor(Color.Transparent).enabled(!this.working)
            .onClick(() => { const item = this.editing; if (item !== undefined) { this.remove(item); } }).id('recovery-delete')
        }
      }.width('100%').padding({ top: 12 })
    }.padding({ left: 20, right: 20, top: 12, bottom: 20 }).width('100%').height('100%')
      .onDisAppear(() => { this.stopInputs(); })
  }

  build() {
    Column({ space: 10 }) {
      ForEach(this.entry.recoveries || [], (item: ExpenseRecovery) => {
        Column({ space: 8 }) {
          Row({ space: 10 }) {
            Column({ space: 5 }) {
              Text(item.kind === 'refund' ? '退款' : '报销到账').fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
              Text(this.receiptTime(item)).fontSize('11fp').fontColor($r('app.color.xq_font_secondary')).maxLines(2)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Column({ space: 5 }) {
              Row({ space: 4 }) {
                Text('+ ' + this.entry.currencySymbol).fontSize('12fp').fontColor($r('app.color.xq_app_income')).margin({ bottom: 1 }).flexShrink(0)
                Text(this.decimal(item.amountMinor)).fontFamily('XiaoQiaoDINMedium').fontSize('17fp')
                  .fontColor($r('app.color.xq_app_income')).maxLines(1).minFontSize('12fp').maxFontSize('17fp').flexShrink(1)
              }.alignItems(VerticalAlign.Bottom).justifyContent(FlexAlign.End)
              Text(item.accountName).fontSize('11fp').fontColor($r('app.color.xq_font_secondary')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.End)
            }.constraintSize({ maxWidth: '44%' }).alignItems(HorizontalAlign.End)
            this.chevron()
          }.width('100%')
          if (item.note.length > 0) {
            Text(item.note).fontSize('12fp').lineHeight('18fp').fontColor($r('app.color.xq_font_secondary'))
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }
        }.width('100%').padding(14).borderRadius(14).backgroundColor($r('app.color.xq_app_surface_page'))
          .accessibilityText(`编辑${item.kind === 'refund' ? '退款' : '报销'} ${this.decimal(item.amountMinor)}元，${this.receiptTime(item)}，${item.accountName}`)
          .onClick(() => { this.open(item.kind, item); }).id('recovery-item-' + item.id)
      }, (item: ExpenseRecovery) => item.id + ':' + item.revision)
    }.width('100%').padding({ top: (this.entry.recoveries || []).length > 0 ? 16 : 0,
      bottom: (this.entry.recoveries || []).length > 0 ? 12 : 0 }).enabled(!this.working && this.workspace !== undefined)
      .id('expense-recovery-panel')
      .bindSheet($$this.showForm, this.form(), { height: '85%', showClose: false,
        keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
        shouldDismiss: (action: SheetDismiss) => { if (!this.working) { this.stopInputs(); action.dismiss(); } },
        backgroundColor: $r('app.color.xq_app_surface_card') })
  }
}
