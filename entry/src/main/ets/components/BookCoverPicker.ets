import { BOOK_PALETTES, BookPalette } from '../domain/model/BookCoverCatalog';
import { BOOK_ICON_CHOICES, BookIconChoice, bookCoverColors } from '../presentation/books/BookCoverResources';
import { BookCoverBadge } from './BookCoverBadge';

@Component
export struct BookCoverPicker {
  @Link paletteKey: string;
  @Link iconKey: string;
  @Prop disabled: boolean = false;
  @Prop currentBook: boolean = false;
  @State private query: string = '';
  @State private shown: number = 48;

  private icons(): BookIconChoice[] {
    const query = this.query.trim().toLowerCase().replace(/-/g, '_');
    return BOOK_ICON_CHOICES.filter((item: BookIconChoice) => !query || item.key.includes(query));
  }

  build() {
    Column({ space: 16 }) {
      Row({ space: 20 }) {
        BookCoverBadge({ paletteKey: this.paletteKey, iconKey: this.iconKey, current: this.currentBook, coverWidth: 72 })
        Column({ space: 6 }) {
          Text('账本封面').fontSize('16fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
          Text('图标与封面同色，自动适配深色模式').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding({ top: 4, bottom: 4 })
      Text('配色').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(BOOK_PALETTES, (palette: BookPalette) => {
          Column({ space: 6 }) {
            Stack({ alignContent: Alignment.Center }) {
              BookCoverBadge({ paletteKey: palette.key, iconKey: this.iconKey,
                current: this.paletteKey === palette.key, coverWidth: 34 })
            }.width(44).height(48)
            Text(palette.name).fontSize('11fp').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(this.paletteKey === palette.key ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_secondary'))
              .height(20).width('100%').textAlign(TextAlign.Center)
          }.width('25%').padding({ top: 8, bottom: 8 }).enabled(!this.disabled)
            .onClick(() => { this.paletteKey = palette.key; })
            .accessibilityText(palette.name + (this.paletteKey === palette.key ? '，已选中' : ''))
            .id('book-palette-' + palette.key)
        }, (palette: BookPalette) => palette.key)
      }.width('100%')
      Text('图标').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      Search({ value: this.query, placeholder: '搜索 Lucide 图标英文名称，如 house、plane' })
        .height(40).textFont({ size: '12fp' }).placeholderFont({ size: '12fp' })
        .backgroundColor($r('app.color.xq_app_surface_keyboard')).enabled(!this.disabled)
        .onChange((value: string) => { this.query = value; this.shown = 48; })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.icons().slice(0, this.shown), (icon: BookIconChoice) => {
          Column() {
            Image(icon.resource).width(24).height(24).objectFit(ImageFit.Contain)
              .fillColor(bookCoverColors(this.paletteKey).ink)
          }.width('16.666%').height(44).borderRadius(10)
            .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
            .backgroundColor(icon.key === this.iconKey ? bookCoverColors(this.paletteKey).cover : Color.Transparent)
            .enabled(!this.disabled).onClick(() => { this.iconKey = icon.key; })
            .accessibilityText(icon.key.replace('lucide_', '') + (icon.key === this.iconKey ? '，已选中' : ''))
            .id('book-icon-' + icon.key)
        }, (icon: BookIconChoice) => icon.key)
      }.width('100%')
      if (this.icons().length === 0) {
        Text('没有匹配的图标').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
      } else if (this.shown < this.icons().length) {
        Button('显示更多图标').height(36).fontSize('13fp').backgroundColor(Color.Transparent)
          .fontColor($r('app.color.xq_font_emphasize')).enabled(!this.disabled)
          .onClick(() => { this.shown = this.icons().length; })
      }
    }.width('100%')
  }
}
