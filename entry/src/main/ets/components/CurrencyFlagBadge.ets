import { configuredFlag } from '../core/money/CurrencySettings';
import { CURRENCY_FLAGS, CurrencyFlagAsset, currencyFlag, regionFlag } from '../presentation/exchange/CurrencyFlags';

/** Original flag colors in a 4:3 frame; never tint a flag to match the theme. */
@Component
export struct CurrencyFlagBadge {
  @Prop currencyCode: string = 'CNY';
  @Prop refreshToken: number = 0;
  @Prop flagWidth: number = 28;

  private image(_refreshToken: number): Resource | undefined {
    const region = configuredFlag(this.currencyCode);
    if (region !== undefined) { return regionFlag(region); }
    return CURRENCY_FLAGS.some((item: CurrencyFlagAsset) => item.currencyCode === this.currencyCode) ? currencyFlag(this.currencyCode) : undefined;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.image(this.refreshToken) !== undefined) {
        Image(this.image(this.refreshToken) || $r('app.media.lucide_globe1')).width(this.flagWidth).height(this.flagWidth * 0.75).objectFit(ImageFit.Contain).draggable(false)
      } else {
        Text(this.currencyCode).fontSize('9fp').fontWeight(FontWeight.Medium).maxLines(1)
          .fontColor($r('app.color.xq_font_secondary'))
      }
    }.width(this.flagWidth).height(this.flagWidth * 0.75).borderRadius(3).clip(true)
      .backgroundColor($r('app.color.xq_app_surface_card'))
      .border({ width: 0.5, color: $r('app.color.xq_app_divider_subtle') }).flexShrink(0)
      .accessibilityLevel('no')
  }
}
