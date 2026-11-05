/** Amount digits use bundled D-DIN PRO; symbols retain the system font. */
@Component
export struct AmountText {
  @Prop amount: string = '0.00';
  amountSize: number = 38;
  /** Optional smaller fraction, including its decimal point. Zero keeps the uniform amount style. */
  fractionSize: number = 0;
  bold: boolean = false;
  currencyBottom: number = 4;
  color: ResourceColor = $r('app.color.xq_font_primary');
  sign: string = '';
  onOpen: (() => void) | undefined = undefined;

  build() {
    Row({ space: 2 }) {
      if (this.sign.length > 0) {
        Text(this.sign).fontSize('14fp').fontColor(this.color)
      }
      Text('¥').fontSize('12fp').fontColor(this.color).margin({ bottom: this.currencyBottom })
      Text() {
        if (this.fractionSize > 0 && this.amount.indexOf('.') >= 0) {
          Span(this.amount.substring(0, this.amount.indexOf('.')))
          Span(this.amount.substring(this.amount.indexOf('.'))).fontSize(`${this.fractionSize}fp`)
        } else {
          Span(this.amount)
        }
      }
        .fontFamily(this.bold ? 'XiaoQiaoDINBold' : 'XiaoQiaoDINRegular')
        .fontSize(`${this.amountSize}fp`)
        .minFontSize(`${this.amountSize >= 30 ? 24 : Math.min(this.amountSize, 12)}fp`)
        .maxFontSize(`${this.amountSize}fp`)
        .maxLines(1)
        .fontWeight(this.bold ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.color)
        .accessibilityText(`${this.sign}人民币${this.amount}元`)
        .onClick(() => {
          if (this.onOpen !== undefined) { this.onOpen(); return; }
          this.getUIContext().getPromptAction().showDialog({ title: '完整金额', message: `${this.sign}¥${this.amount}`,
            buttons: [{ text: '知道了', color: $r('app.color.xq_font_emphasize') }] });
        })
    }.alignItems(VerticalAlign.Bottom)
  }
}
