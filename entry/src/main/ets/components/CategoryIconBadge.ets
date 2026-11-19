import { COLORFUL_CATEGORY_ICONS, ColorfulCategoryIcon } from '../presentation/ledger/ColorfulCategoryIcons';

/** The same bundled icon receives an adaptive accent background at every call site. */
@Component
export struct CategoryIconBadge {
  @Prop icon: Resource = $r('app.media.colorful_icon00204');
  @Prop badgeSize: number = 44;
  @Prop glyphSize: number = 28;
  @Prop glyphId: string = '';

  private badgeBackgroundColor(): ResourceColor {
    return COLORFUL_CATEGORY_ICONS.find((item: ColorfulCategoryIcon) => item.resource.id === this.icon.id)?.background ||
      $r('app.color.xq_app_surface_page');
  }

  private contour(): string {
    // Superellipse |x/a|^4 + |y/a|^4 = 1, sampled at 96 points.
    // A background Path keeps the foreground SVG intact, rather than clipping its artwork.
    // Path.commands uses px; width/height below use vp. Keep their geometry in sync.
    const half = this.getUIContext().vp2px(this.badgeSize) / 2;
    const points: string[] = [];
    for (let index = 0; index < 96; index++) {
      const angle = index * Math.PI * 2 / 96;
      const cos = Math.cos(angle);
      const sin = Math.sin(angle);
      const x = half + half * Math.sign(cos) * Math.sqrt(Math.abs(cos));
      const y = half + half * Math.sign(sin) * Math.sqrt(Math.abs(sin));
      points.push((index === 0 ? 'M' : 'L') + x.toFixed(3) + ',' + y.toFixed(3));
    }
    return points.join(' ') + ' Z';
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Path().commands(this.contour()).width(this.badgeSize).height(this.badgeSize).fill(this.badgeBackgroundColor()).strokeWidth(0)
        .hitTestBehavior(HitTestMode.None)
      Image(this.icon).width(this.glyphSize).height(this.glyphSize).objectFit(ImageFit.Contain).id(this.glyphId)
    }.width(this.badgeSize).height(this.badgeSize).flexShrink(0)
  }
}
