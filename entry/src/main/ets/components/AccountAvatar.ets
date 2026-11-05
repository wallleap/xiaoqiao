import { accountIcon } from '../presentation/ledger/AccountIcons';

@Component
export struct AccountAvatar {
  @Prop iconKey: string = 'bank_card';
  @Prop brandColor: string = '#5378B8';
  @Prop iconVariant: string = 'monochrome';
  @Prop diameter: number = 44;
  build() {
    Row() {
      Image(accountIcon(this.iconKey)).width(this.diameter * 0.58).height(this.diameter * 0.58)
    }.justifyContent(FlexAlign.Center).width(this.diameter).height(this.diameter).borderRadius(this.diameter / 2)
      .backgroundColor(this.iconVariant === 'color' ? $r('app.color.xq_comp_background_primary') : this.brandColor)
  }
}
