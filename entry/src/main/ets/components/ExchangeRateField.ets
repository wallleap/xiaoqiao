import { AmountKeyboard } from './AmountKeyboard';
import { validManualRate } from '../core/money/CurrencySettings';

/** Positive decimal quote, up to 12 fractional digits; uses the app's custom keypad. */
@Component
export struct ExchangeRateField {
  @Link value: string;
  @Prop disabled: boolean = false;
  @State private fieldFocused: boolean = false;
  private readonly controller: TextInputController = new TextInputController();
  private press(key: string): void {
    if (this.disabled) { return; }
    if (key === '保存') { if (validManualRate(this.value)) { this.controller.stopEditing(); } return; }
    if (key === '清空') { this.value = ''; return; }
    if (key === '⌫') { this.value = this.value.slice(0,-1); return; }
    if (!/^[0-9.]$/.test(key)) { return; }
    const next = this.value + key;
    if (/^\d{0,16}(\.\d{0,12})?$/.test(next)) { this.value = next.startsWith('.') ? '0' + next : next; }
  }
  @Builder
  private keypad() {
    AmountKeyboard({ prefix: 'exchange-manual-rate', disabled: this.disabled, canSubmit: validManualRate(this.value),
      submitLabel: '完成', onKey: (key: string) => { this.press(key); } })
  }
  build() {
    TextInput({ text: this.value, placeholder: '点击输入汇率', controller: this.controller })
      .height(56).fontSize('24fp').fontFamily('XiaoQiaoDINMedium').padding({ left: 14, right: 14 })
      .fontColor($r('app.color.xq_font_primary')).placeholderColor($r('app.color.xq_font_secondary')).caretColor($r('app.color.xq_brand'))
      .backgroundColor($r('app.color.xq_exchange_form_field_background'))
      .border({ width: 1, color: this.fieldFocused ? $r('app.color.xq_brand') : $r('app.color.xq_exchange_form_border') }).borderRadius(12)
      .onFocus(() => { this.fieldFocused = true; }).onBlur(() => { this.fieldFocused = false; }).enabled(!this.disabled).copyOption(CopyOptions.None).selectionMenuHidden(true)
      .customKeyboard(this.keypad(), { supportAvoidance: true })
      .onWillInsert((value: InsertValue): boolean => { for (const key of value.insertValue) { this.press(key); } return false; })
      .onWillDelete((): boolean => { this.press('⌫'); return false; })
      .onSubmit(() => { this.press('保存'); }).id('exchange-manual-rate')
  }
}
