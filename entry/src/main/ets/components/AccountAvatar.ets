import { accountIcon } from '../presentation/ledger/AccountIcons';

@Component
export struct AccountAvatar {
  @Prop iconKey: string = 'bank_card';
  @Prop brandColor: string = '#5378B8';
  @Prop iconVariant: string = 'monochrome';
  @Prop diameter: number = 44;
  build() {
    Row() {
      if (this.iconKey === 'type_meituan_credit') {
        // The wordmark is about 2:1; use a wider box instead of shrinking it into a square.
        Image(accountIcon(this.iconKey, this.iconVariant)).width(this.diameter * 0.72).height(this.diameter * 0.36)
          .objectFit(ImageFit.Contain).fillColor(Color.White)
      } else if (this.iconKey.startsWith('type_') && this.iconKey !== 'type_qq_wallet' && this.iconKey !== 'type_unionpay') {
        Image(accountIcon(this.iconKey, this.iconVariant)).width(this.diameter * 0.58).height(this.diameter * 0.58).fillColor(Color.White)
      } else {
        Image(accountIcon(this.iconKey, this.iconVariant)).width(this.diameter * 0.58).height(this.diameter * 0.58)
      }
    }.justifyContent(FlexAlign.Center).width(this.diameter).height(this.diameter).borderRadius(this.diameter / 2)
      .backgroundColor(this.iconVariant === 'color' ? Color.White : this.brandColor)
  }
}
