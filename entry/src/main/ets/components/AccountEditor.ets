import { CURRENCIES, CurrencyDefinition, currencyUnit } from '../core/money/Currencies';
import { AccountCalibrationPage } from './AccountCalibrationPage';
import { AccountAdjustmentHistoryPage } from './AccountAdjustmentHistoryPage';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { ChipGroup, ChipSize } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { AccountProfile, AccountCommand, AccountDraft, ACCOUNT_STYLES, AccountStyle } from '../domain/model/AccountProfile';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { Money } from '../core/money/Money';
import { CurrencyUnit } from '../core/money/CurrencyUnit';
import { AccountAvatar } from './AccountAvatar';
import { MoneyAmountField } from './MoneyAmountField';
import { ExpenseAmountInput } from '../presentation/ledger/ExpenseAmountInput';

@Component
export struct AccountEditor {
  @Prop operationBusy: boolean = false;
  workspace: LedgerWorkspace | undefined = undefined;
  original: AccountProfile | undefined = undefined;
  sheetMaterial: SystemUiMaterial | undefined = undefined;
  onClose: () => void = () => {};
  onCreated: (id: string) => void = () => {};
  onSaved: () => void = () => {};
  onArchive: () => void = () => {};
  onBusy: (busy: boolean) => void = () => {};
  @State private balancePage: number = 0;
  @State private name: string = '';
  @State private kind: string = 'asset';
  @State private styleKey: string = 'cash';
  @State private opening: string = '0';
  @State private includeNet: boolean = true;
  @State private showStyles: boolean = false;
  @State private styleQuery: string = '';
  @State private styleVariant: string = 'monochrome';
  @State private showHistoricalStyles: boolean = false;
  @State private busy: boolean = false;
  @State private conflict: boolean = false;
  @State private error: string = '';
  private readonly draftId: string = util.generateRandomUUID();
  private readonly scroller: Scroller = new Scroller();
  @State private currencyCode: string = 'CNY';
  private amountCurrency(): CurrencyUnit { return currencyUnit(this.currencyCode); }
  private readonly openingController: TextInputController = new TextInputController();

  aboutToAppear(): void {
    if (this.original !== undefined) {
      this.currencyCode = this.original.currencyId;
      this.name = this.original.name; this.kind = this.original.kind; this.styleKey = this.original.iconKey;
      this.includeNet = this.original.includeInNetAssets;
    }
  }
  private metadataDirty(): boolean {
    return this.original !== undefined && (this.name.trim() !== this.original.name || this.styleKey !== this.original.iconKey || this.includeNet !== this.original.includeInNetAssets);
  }
  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }
  private style(): AccountStyle | undefined { return ACCOUNT_STYLES.find((item: AccountStyle) => item.key === this.styleKey); }
  private visibleStyles(): AccountStyle[] {
    const query = this.styleQuery.trim().toLowerCase();
    return ACCOUNT_STYLES.filter((style: AccountStyle) =>
      (style.variant || 'monochrome') === this.styleVariant &&
      (this.showHistoricalStyles || style.historical !== true) &&
      (!query || (style.name + ' ' + style.brand + ' ' + style.key + ' ' + (style.searchText || '')).toLowerCase().includes(query)));
  }
  private openStyleSheet(): void {
    this.styleQuery = ''; this.styleVariant = this.style()?.variant || 'monochrome';
    this.showHistoricalStyles = this.style()?.historical === true; this.showStyles = true;
  }
  private sheetOptions(): SheetOptions {
    const options: SheetOptions = { height: 440, showClose: true };
    if (this.sheetMaterial !== undefined) { options.systemMaterial = this.sheetMaterial; }
    else { options.backgroundColor = $r('app.color.xq_app_surface_card'); }
    return options;
  }
  private async save(): Promise<void> {
    if (this.busy || this.operationBusy || this.conflict) { return; }
    this.error = '';
    if (this.name.trim().length === 0) {
      this.error = '请填写账户名称';
      this.getUIContext().getPromptAction().showToast({ message: this.error });
      this.getUIContext().getFocusController().requestFocus('account-name');
      return;
    }
    let command: AccountCommand;
    try {
      let opening = ExpenseAmountInput.nonnegative(this.original === undefined ? this.opening : '0', this.amountCurrency());
      if (this.kind === 'liability') { opening = Money.fromMinorText((-opening.minor).toString(), this.amountCurrency()); }
      command = { id: this.original?.id || this.draftId, name: this.name, kind: this.kind, styleKey: this.styleKey,
        includeInNetAssets: this.includeNet, opening: opening };
      new AccountDraft(command);
    } catch (_) {
      this.error = '请检查期初金额：须为完整的非负金额，' + this.currencyCode + ' 最多支持 ' + this.amountCurrency().scale.toString() + ' 位小数，且不能超出金额上限';
      this.getUIContext().getPromptAction().showToast({ message: this.error });
      if (this.original === undefined) {
        this.getUIContext().getFocusController().requestFocus('account-opening');
      }
      return;
    }
    // A keyboard controller may be unattached when the opening amount was never focused.
    // Dismissing input is best-effort and must not prevent a valid account from being saved.
    try { this.getUIContext().getFocusController().clearFocus(); } catch (_) {}
    this.busy = true;
    try {
      this.onBusy(true);
      if (this.workspace === undefined) { throw new Error('WORKSPACE_UNAVAILABLE'); }
      if (this.original === undefined) { await this.workspace.createAccount(command); this.onCreated(command.id); }
      else { await this.workspace.updateAccount(command, this.original.revision); }
      this.onSaved();
    } catch (error) {
      if ((error as Error).message === 'ACCOUNT_CHANGED') {
        this.conflict = true; this.error = '账户已变更，请返回刷新后再编辑';
      } else { this.error = '保存未确认，请返回检查账户，避免重复添加'; }
      this.getUIContext().getPromptAction().showToast({ message: this.error });
    } finally { this.busy = false; this.onBusy(false); }
  }

  @Builder
  private styleSheet() {
    Column({ space: 16 }) {
      Text('账户图标').fontSize('20fp').fontWeight(FontWeight.Bold).width('100%').padding({ right: 48 })
      Search({ value: this.styleQuery, placeholder: '搜索银行或账户名称' }).height(40)
        .textFont({ size: '14fp' }).placeholderFont({ size: '14fp' })
        .backgroundColor($r('app.color.xq_app_surface_keyboard'))
        .onChange((value: string) => { this.styleQuery = value; })
      Row({ space: 8 }) {
        ForEach(['monochrome', 'color'], (variant: string) => {
          Button(variant === 'color' ? '彩色原标' : '单色白标', { type: ButtonType.Capsule }).fontSize('12fp').height(32)
            .backgroundColor(this.styleVariant === variant ? $r('app.color.xq_brand') : $r('app.color.xq_background_secondary'))
            .fontColor(this.styleVariant === variant ? $r('app.color.xq_font_on_primary') : $r('app.color.xq_font_secondary'))
            .onClick(() => { this.styleVariant = variant; })
        }, (variant: string) => variant)
        Blank()
        Button('历史标识', { type: ButtonType.Capsule }).fontSize('12fp').height(32)
          .backgroundColor(this.showHistoricalStyles ? $r('app.color.xq_comp_emphasize_tertiary') : Color.Transparent)
          .fontColor($r('app.color.xq_font_emphasize'))
          .accessibilityDescription(this.showHistoricalStyles ? '已显示历史标识，点击隐藏' : '点击包含历史名称的银行标识')
          .onClick(() => { this.showHistoricalStyles = !this.showHistoricalStyles; })
      }.width('100%')
      Scroll() {
        Column() {
        if (this.visibleStyles().length === 0) { Text('没有匹配的账户图标').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).padding(24) }
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.visibleStyles(), (style: AccountStyle) => {
            Column({ space: 8 }) {
              AccountAvatar({ iconKey: style.key, brandColor: style.color, iconVariant: style.variant || 'monochrome' })
              Text(style.name + (style.historical ? '（历史）' : '')).fontSize('12fp').maxLines(2).textAlign(TextAlign.Center)
                .fontColor(this.styleKey === style.key ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_secondary'))
            }.width('25%').height(92).id('account-style-' + style.key)
              .onClick(() => { this.styleKey = style.key; this.showStyles = false; })
          }, (style: AccountStyle) => style.key)
        }.width('100%')
        }.width('100%')
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.padding(24).width('100%').height('100%')
  }

  build() {
    if (this.original !== undefined && this.balancePage === 1) {
      AccountCalibrationPage({ account: this.original, workspace: this.workspace, onClose: () => { this.balancePage = 0; },
        onSaved: () => { this.onSaved(); }, onBusy: (value: boolean) => { this.busy = value; this.onBusy(value); } })
    } else if (this.original !== undefined && this.balancePage === 2) {
      AccountAdjustmentHistoryPage({ account: this.original, workspace: this.workspace, onClose: () => { this.balancePage = 0; } })
    } else {
    HdsNavigation() {
      Column() {
        Scroll(this.scroller) {
          Column({ space: 16 }) {
            Column({ space: 16 }) {
              AccountAvatar({ iconKey: this.styleKey, brandColor: this.style()?.color || this.original?.brandColor || '#5378B8',
                iconVariant: this.style()?.variant || this.original?.iconVariant || 'monochrome', diameter: 64 })
              Button('选择品牌图标', { type: ButtonType.Capsule }).fontSize('12fp')
                .fontColor($r('app.color.xq_font_emphasize')).backgroundColor(Color.Transparent)
                .id('account-choose-style').onClick(() => { this.openStyleSheet(); })
              TextInput({ text: this.name, placeholder: '账户名称，如：微信零钱' }).fontSize('16fp').height(48)
                .backgroundColor($r('app.color.xq_app_surface_keyboard')).borderRadius(12).maxLength(40)
                .id('account-name').onChange((value: string) => { this.name = value; })
              Button('币种 · ' + this.currencyCode).fontSize('14fp').width('100%')
                .fontColor($r('app.color.xq_font_primary')).backgroundColor($r('app.color.xq_app_surface_keyboard'))
                .enabled(this.original === undefined && !this.busy).onClick(() => {
                  this.openingController.stopEditing();
                  this.getUIContext().showTextPickerDialog({ range: CURRENCIES.map((item: CurrencyDefinition) => item.code + ' · ' + item.name),
                    selectedTextStyle: { color: $r('app.color.xq_font_emphasize') },
                    acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
                    cancelButtonStyle: { fontColor: $r('app.color.xq_font_secondary') },
                    selected: CURRENCIES.findIndex((item: CurrencyDefinition) => item.code === this.currencyCode),
                    onAccept: (result: TextPickerResult) => {
                      const index = typeof result.index === 'number' ? result.index : result.index[0];
                      this.currencyCode = CURRENCIES[index].code; this.opening = '0';
                    }
                  });
                })
              if (this.original === undefined) {
                ChipGroup({ items: [{ label: { text: '资产账户' } }, { label: { text: '负债账户' } }],
                  selectedIndexes: [this.kind === 'asset' ? 0 : 1], multiple: false,
                  itemStyle: { size: ChipSize.NORMAL, backgroundColor: $r('app.color.xq_app_filter_unselected'),
                    selectedBackgroundColor: $r('app.color.xq_brand'), fontColor: $r('app.color.xq_font_secondary'),
                    selectedFontColor: $r('app.color.xq_font_on_primary') },
                  onChange: (values: number[]) => { this.kind = values[0] === 1 ? 'liability' : 'asset'; }
                }).width(260).id('account-kind')
              } else {
                Text((this.kind === 'asset' ? '资产账户' : '负债账户') + ' · ' + this.amountCurrency().code).fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
              }
            }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
            Column({ space: 12 }) {
              Text(this.original === undefined ? (this.kind === 'liability' ? '期初待还金额 · ' + this.amountCurrency().code : '期初余额 · ' + this.currencyCode) : '当前余额 · ' + this.amountCurrency().code)
                .fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%').id('account-opening-label')
              if (this.original === undefined) {
                MoneyAmountField({ value: $opening, fieldId: 'account-opening', currency: this.amountCurrency(),
                  controller: this.openingController, disabled: this.busy || this.operationBusy || this.conflict,
                  onSubmit: () => { this.save(); } })
                Text(this.kind === 'liability' ? '输入待还金额，按负余额计入净资产' : '期初余额不计入收入或预算')
                  .fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
              } else {
                Text(Money.fromMinorText(this.original.balanceMinor, this.amountCurrency()).toDecimalString()).fontSize('28fp')
                  .fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_primary')).width('100%').id('account-current-balance')
                Text('余额随记账变化，校准会单独保留调整记录').fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
                Row({ space: 12 }) {
                  Button('校准余额', { type: ButtonType.Capsule }).fontSize('14fp').fontColor($r('app.color.xq_font_emphasize'))
                    .backgroundColor($r('app.color.xq_app_surface_keyboard')).layoutWeight(1).height(40).id('account-calibrate')
                    .enabled(!this.busy && !this.operationBusy && !this.conflict && !this.original.archived && !this.metadataDirty())
                    .onClick(() => { this.balancePage = 1; })
                  Button('调整记录', { type: ButtonType.Capsule }).fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
                    .backgroundColor($r('app.color.xq_app_surface_keyboard')).layoutWeight(1).height(40).id('account-adjustments')
                    .enabled(!this.busy && !this.operationBusy).onClick(() => { this.balancePage = 2; })
                }.width('100%')
                if (this.metadataDirty()) { Text('请先保存账户信息，再校准余额').fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')).width('100%') }

              }
            }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
            Row() {
              Column({ space: 4 }) {
                Text('计入总资产').fontSize('16fp').fontColor($r('app.color.xq_font_primary'))
                Text('控制资产页的净资产汇总').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.includeNet }).selectedColor($r('app.color.xq_brand'))
                .onChange((value: boolean) => { this.includeNet = value; }).id('account-include-net')
            }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
            if (this.error.length > 0) { Text(this.error).fontSize('14fp').fontColor($r('app.color.xq_warning')).id('account-error') }
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 24 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off).clip(false).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        Row({ space: 12 }) {
          if (this.original !== undefined) {
            Button(this.original.archived ? '恢复使用' : '归档账户', { type: ButtonType.Capsule }).height(48).layoutWeight(1)
              .fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).backgroundColor($r('app.color.xq_app_surface_card'))
              .enabled(!this.busy && !this.operationBusy && !this.conflict).id('account-archive').onClick(() => { this.onArchive(); })
          }
          Button(this.busy ? '保存中' : '保存账户', { type: ButtonType.Capsule }).height(48).layoutWeight(2)
            .fontSize('16fp').fontColor(Color.White).backgroundColor($r('app.color.xq_brand'))
            .enabled(!this.busy && !this.operationBusy && !this.conflict).id('account-save').onClick(() => { this.save(); })
        }.padding({ left: 16, right: 16, top: 12, bottom: 8 }).width('100%')
          .backgroundColor($r('app.color.xq_app_surface_page')).zIndex(1)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }.width('100%').height('100%').constraintSize({ maxWidth: 720 }).align(Alignment.Top)
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: this.original === undefined ? '添加账户' : '编辑账户' }, divider: { showType: DividerShowType.OFF },
          backIcon: { componentId: 'account-close', action: () => { if (!this.busy) { this.onClose(); } } } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
          backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showStyles, this.styleSheet(), this.sheetOptions()).id('account-editor')
    }
  }
}
