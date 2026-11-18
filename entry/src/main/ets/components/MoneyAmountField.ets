import { CurrencyUnit } from '../core/money/CurrencyUnit';
import { ExpenseAmountInput } from '../presentation/ledger/ExpenseAmountInput';
import { AmountKeyboard } from './AmountKeyboard';

/** A nonnegative amount draft. The containing form applies its business rules before writing. */
@Component
export struct MoneyAmountField {
  @Link value: string;
  @Prop disabled: boolean = false;
  @Prop canSubmit: boolean = true;
  fieldId: string = 'amount';
  placeholder: string = '';
  allowEmpty: boolean = false;
  onChange: (value: string) => void = () => {};
  fontSize: string = '28fp';
  fontFamily: string = 'XiaoQiaoDINMedium';
  submitLabel: string = '保存';
  fieldHeight: number = 48;
  @Prop currency: CurrencyUnit = new CurrencyUnit('CNY', 'CNY', 2);
  controller: TextInputController = new TextInputController();
  onSubmit: () => void = () => {};
  @State private inputError: string = '';

  private complete(): boolean {
    if (this.allowEmpty && this.value.length === 0) { return true; }
    try { ExpenseAmountInput.nonnegative(this.value, this.currency); return true; }
    catch (_) { return false; }
  }

  private press(key: string): void {
    if (this.disabled) { return; }
    if (key === '保存') {
      if (this.complete() && this.canSubmit) {
        this.controller.stopEditing();
        this.onSubmit();
      }
      return;
    }
    this.inputError = '';
    try {
      this.value = this.allowEmpty && (key === '清空' || (key === '⌫' && this.value.length <= 1)) ? '' :
        key === '清空' ? '0' : ExpenseAmountInput.appendNonnegative(this.value, key, this.currency);
      this.onChange(this.value);
    } catch (_) { this.inputError = '请输入符合币种小数位的非负金额，且不能超出金额上限'; }
  }

  @Builder
  private keyboardAccessory() {
    Row() {
      Blank()
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.lucide_chevron_down1')).width(20).height(20).fillColor($r('app.color.xq_icon_secondary'))
      }.width(32).height(32).padding(0).backgroundColor(Color.Transparent)
        .accessibilityText('收起键盘').id(this.fieldId + '-hide-keyboard')
        .onClick(() => { this.controller.stopEditing(); })
    }.width('100%').height(36)
  }

  @Builder
  private keypad() {
    AmountKeyboard({ prefix: this.fieldId, disabled: this.disabled,
      canSubmit: this.canSubmit && this.complete(), submitLabel: this.submitLabel,
      accessory: () => { this.keyboardAccessory() }, onKey: (key: string) => { this.press(key); } })
  }

  build() {
    Column({ space: 4 }) {
      TextInput({ text: this.value, placeholder: this.placeholder, controller: this.controller }).fontSize(this.fontSize).fontFamily(this.fontFamily)
        .minFontSize('16fp').maxFontSize(this.fontSize).height(this.fieldHeight).width('100%')
        .fontColor($r('app.color.xq_font_primary')).caretColor($r('app.color.xq_brand'))
        .backgroundColor(Color.Transparent).padding(0).copyOption(CopyOptions.None).selectionMenuHidden(true)
        .id(this.fieldId).enabled(!this.disabled).customKeyboard(this.keypad(), { supportAvoidance: true })
        .onWillInsert((value: InsertValue): boolean => {
          for (const character of value.insertValue) {
            const key = character === '-' ? '−' : character;
            if (/^[0-9.+−]$/.test(key)) { this.press(key); }
          }
          return false;
        })
        .onWillDelete((): boolean => { this.press('⌫'); return false; })
        .onSubmit(() => { this.press('保存'); })
      if (this.inputError.length > 0) {
        Text(this.inputError).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%').id(this.fieldId + '-error')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
