import { bookCoverColors, bookCoverIcon } from '../presentation/books/BookCoverResources';

/** A small bound book: tinted cover, spine, inset pages and matching ribbon/icon. */
@Component
export struct BookCoverBadge {
  @Prop paletteKey: string = 'butter';
  @Prop iconKey: string = 'lucide_notebook_text1';
  @Prop coverWidth: number = 48;
  @Prop current: boolean = false;

  private ribbonPath(): string {
    const unit = this.getUIContext().vp2px(this.coverWidth);
    return 'M0,0 L' + (unit * 0.16).toFixed(2) + ',0 L' + (unit * 0.16).toFixed(2) + ',' +
      (unit * 0.26).toFixed(2) + ' L' + (unit * 0.08).toFixed(2) + ',' + (unit * 0.20).toFixed(2) +
      ' L0,' + (unit * 0.26).toFixed(2) + ' Z';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Rect().width(this.coverWidth).height(this.coverWidth * 1.20).radius(this.coverWidth * 0.12)
        .fill(bookCoverColors(this.paletteKey).spine)
      Rect().width(this.coverWidth * 0.16).height(this.coverWidth * 1.08).radius(this.coverWidth * 0.06)
        .fill(bookCoverColors(this.paletteKey).pages).position({ x: this.coverWidth * 0.81, y: this.coverWidth * 0.06 })
      Rect().width(this.coverWidth * 0.88).height(this.coverWidth * 1.20).radius(this.coverWidth * 0.10)
        .fill(bookCoverColors(this.paletteKey).cover)
      Rect().width(this.coverWidth * 0.055).height(this.coverWidth * 1.20)
        .fill(bookCoverColors(this.paletteKey).spine).opacity(0.65).position({ x: this.coverWidth * 0.065, y: 0 })
      if (this.current) {
        Path().commands(this.ribbonPath()).width(this.coverWidth * 0.16).height(this.coverWidth * 0.26)
          .fill(bookCoverColors(this.paletteKey).accent).strokeWidth(0)
          .position({ x: this.coverWidth * 0.64, y: 0 })
      }
      Image(bookCoverIcon(this.iconKey)).width(this.coverWidth * 0.36).height(this.coverWidth * 0.36)
        .objectFit(ImageFit.Contain).fillColor(bookCoverColors(this.paletteKey).ink).opacity(0.10)
        .position({ x: this.coverWidth * 0.28, y: this.coverWidth * (1.20 - 0.36) / 2 })
    }.width(this.coverWidth).height(this.coverWidth * 1.20).flexShrink(0)
      .accessibilityLevel('no')
  }
}
