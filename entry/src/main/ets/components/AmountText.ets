/** Amount digits use the bundled D-DIN PRO Regular; symbols retain the system font. */
@Component
export struct AmountText {
  @Prop amount: string = '0.00';
  amountSize: number = 38;
  color: ResourceColor = $r('app.color.xq_font_primary');
  sign: string = '';

  build() {
    Row({ space: 2 }) {
      if (this.sign.length > 0) {
        Text(this.sign).fontSize('14fp').fontColor(this.color)
      }
      Text('¥').fontSize('12fp').fontColor(this.color).margin({ bottom: 4 })
      Text(this.amount)
        .fontFamily('XiaoQiaoDINRegular')
        .fontSize(`${this.amountSize}fp`)
        .minFontSize(`${this.amountSize >= 30 ? 24 : Math.min(this.amountSize, 12)}fp`)
        .maxFontSize(`${this.amountSize}fp`)
        .maxLines(1)
        .fontWeight(FontWeight.Regular)
        .fontColor(this.color)
        .accessibilityText(`${this.sign}人民币${this.amount}元`)
        .onClick(() => {
          this.getUIContext().getPromptAction().showDialog({ title: '完整金额', message: `${this.sign}¥${this.amount}`,
            buttons: [{ text: '知道了', color: $r('app.color.xq_font_emphasize') }] });
        })
    }.alignItems(VerticalAlign.Bottom)
  }
}
