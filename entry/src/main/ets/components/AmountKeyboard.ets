@Builder
function emptyKeyboardSlot() {}

@Component
export struct AmountKeyboard {
  @Prop prefix: string = 'amount';
  @Prop disabled: boolean = false;
  @Prop canSubmit: boolean = true;
  @Prop submitLabel: string = '保存';
  @BuilderParam accessory: () => void = emptyKeyboardSlot;
  @BuilderParam footer: () => void = emptyKeyboardSlot;
  onKey: (key: string) => void = () => {};
  private readonly keys: string[][] = [['1', '2', '3', '⌫'], ['4', '5', '6', '−'], ['7', '8', '9', '+'], ['清空', '0', '.', '保存']];

  @Builder
  private keyboard() {
    Column({ space: 6 }) {
      ForEach(this.keys, (row: string[]) => {
        Row({ space: 6 }) {
          ForEach(row, (key: string) => {
            Button({ type: ButtonType.Normal }) {
              if (key === '+' || key === '−' || key === '⌫') {
                Image(key === '+' ? $r('app.media.lucide_plus1') : key === '−' ?
                  $r('app.media.lucide_minus1') : $r('app.media.lucide_delete1'))
                  .width(24).height(24).fillColor($r('app.color.xq_icon_primary'))
              } else {
                Text(key === '保存' ? this.submitLabel : key)
                  .fontSize(key === '保存' || key === '清空' ? '16fp' : '24fp')
                  .fontFamily(key === '保存' || key === '清空' ? '' : 'XiaoQiaoDINMedium')
                  .fontWeight(FontWeight.Medium)
                  .fontColor(key === '保存' ? Color.White : $r('app.color.xq_font_primary'))
              }
            }.id(this.prefix + '-key-' + key).layoutWeight(1).height(48).borderRadius(12)
              .accessibilityText(key === '+' ? '加' : key === '−' ? '减' : key === '⌫' ? '删除一位' : key)
              .backgroundColor(key === '保存' ? $r('app.color.xq_brand') : $r('app.color.xq_app_surface_keyboard'))
              .fontColor(key === '保存' ? Color.White : $r('app.color.xq_font_primary'))
              .enabled(!this.disabled && (key !== '保存' || this.canSubmit))
              .onClick(() => { this.onKey(key); })
          }, (key: string) => key)
        }.width('100%')
      }, (row: string[]) => row.join(','))
    }.width('100%').id(this.prefix + '-keyboard')
  }

  build() {
    Column() {
      Column({ space: 6 }) {
        this.accessory()
        this.keyboard()
        this.footer()
      }.width('100%').padding({ top: 20, left: 16, right: 16, bottom: 32 })
        .backgroundColor($r('app.color.xq_app_surface_card'))
        .borderRadius({ topLeft: 24, topRight: 24 }).clip(true)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]).id(this.prefix + '-keyboard-panel')
    }.width('100%').padding({ top: 4 }).backgroundColor($r('app.color.xq_app_surface_page'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]).id(this.prefix + '-native-keyboard')
  }
}
