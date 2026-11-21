import { enabledCurrencies } from '../core/money/CurrencySettings';
import { CurrencyDefinition, currencyUnit } from '../core/money/Currencies';
import { AccountCalibrationPage } from './AccountCalibrationPage';
import { AccountAdjustmentHistoryPage } from './AccountAdjustmentHistoryPage';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { AccountBankPicker } from './AccountBankPicker';
import { preferredBankStyle } from '../domain/model/BankAccountStyles';
import { ACCOUNT_TYPES, ACCOUNT_TYPE_GROUPS, ACCOUNT_TYPE_GROUP_NAMES, AccountTypeDefinition, accountType, isBankAccountType } from '../domain/model/AccountTypes';
import { util } from '@kit.ArkTS';
import { AccountProfile, AccountCommand, AccountDraft, ACCOUNT_STYLES, AccountStyle } from '../domain/model/AccountProfile';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { Money } from '../core/money/Money';
import { CurrencyUnit } from '../core/money/CurrencyUnit';
import { AccountAvatar } from './AccountAvatar';
import { MoneyAmountField } from './MoneyAmountField';
import { ExpenseAmountInput } from '../presentation/ledger/ExpenseAmountInput';

interface AccountTypeSelectionSnapshot {
  typeKey: string;
  styleKey: string;
  issuerKey: string;
  cardTail: string;
}

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
  @State private step: number = 0;
  @State private bankQuery: string = '';
  @State private typeKey: string = '';
  @State private issuerKey: string = '';
  @State private cardTail: string = '';
  @State private note: string = '';
  private bankReturnStep: number = 0;
  private typeSelectionSnapshot: AccountTypeSelectionSnapshot | undefined = undefined;
  @State private balancePage: number = 0;
  @State private name: string = '';
  @State private kind: string = 'asset';
  @State private styleKey: string = 'cash';
  @State private opening: string = '0';
  @State private includeNet: boolean = true;
  @State private busy: boolean = false;
  @State private conflict: boolean = false;
  @State private error: string = '';
  private readonly draftId: string = util.generateRandomUUID();
  private readonly scroller: Scroller = new Scroller();
  private readonly typeScroller: Scroller = new Scroller();
  private readonly bankScroller: Scroller = new Scroller();
  @State private currencyCode: string = 'CNY';
  private amountCurrency(): CurrencyUnit { return currencyUnit(this.currencyCode); }
  private readonly openingController: TextInputController = new TextInputController();

  aboutToAppear(): void {
    if (this.original !== undefined) {
      this.step = 2;
      this.typeKey = this.original.accountType || (this.original.kind === 'liability' ? 'other_credit' : 'other_asset');
      this.issuerKey = this.original.issuerKey || ''; this.cardTail = this.original.cardTail || ''; this.note = this.original.note || '';
      this.currencyCode = this.original.currencyId;
      this.name = this.original.name; this.kind = this.original.kind; this.styleKey = this.original.iconKey;
      this.includeNet = this.original.includeInNetAssets;
    }
  }
  private metadataDirty(): boolean {
    return this.original !== undefined && (this.name.trim() !== this.original.name || this.styleKey !== this.original.iconKey || this.includeNet !== this.original.includeInNetAssets || this.note.trim() !== (this.original.note || '') || this.cardTail !== (this.original.cardTail || '') || this.issuerKey !== (this.original.issuerKey || '') || this.typeKey !== (this.original.accountType || (this.original.kind === 'liability' ? 'other_credit' : 'other_asset')));
  }
  private typeColor(type: AccountTypeDefinition): string { return ACCOUNT_STYLES.find((item: AccountStyle) => item.key === type.styleKey)?.color || type.color; }
  private typeName(): string { return accountType(this.typeKey)?.name || '账户'; }
  private types(group: string): AccountTypeDefinition[] {
    return ACCOUNT_TYPES.filter((item: AccountTypeDefinition) => item.group === group &&
      (this.original === undefined || item.kind === this.original.kind));
  }
  private typeGroups(): string[] { return ACCOUNT_TYPE_GROUPS.filter((group: string) => this.types(group).length > 0); }
  private openTypeSelection(): void {
    if (this.busy || this.operationBusy || this.conflict) { return; }
    this.typeSelectionSnapshot = { typeKey: this.typeKey, styleKey: this.styleKey, issuerKey: this.issuerKey, cardTail: this.cardTail };
    try { this.getUIContext().getFocusController().clearFocus(); } catch (_) {}
    this.step = 0;
  }
  private chooseType(type: AccountTypeDefinition): void {
    if (this.original !== undefined && type.kind !== this.original.kind) { return; }
    if (this.typeKey !== type.key) {
      if (this.original === undefined) { this.name = type.name; this.opening = '0'; }
      this.issuerKey = ''; this.cardTail = '';
      this.styleKey = type.styleKey; this.kind = type.kind;
    }
    this.typeKey = type.key; this.error = '';
    this.bankQuery = ''; this.bankReturnStep = 0; this.step = isBankAccountType(type.key) ? 1 : 2;
    if (this.step === 2) { this.typeSelectionSnapshot = undefined; }
  }
  private chooseBank(key: string): void {
    const previousBank = ACCOUNT_STYLES.find((item: AccountStyle) => item.key === this.issuerKey)?.name || '其他银行';
    const previousName = previousBank + (this.kind === 'liability' ? '信用卡' : '储蓄卡');
    const suggestedName = this.name === this.typeName() || this.name === previousName ||
      this.name === previousName + (this.cardTail.length === 4 ? '（' + this.cardTail + '）' : '') || !this.name.trim();
    if (this.issuerKey !== key) { this.cardTail = ''; }
    this.issuerKey = key;
    const bank = ACCOUNT_STYLES.find((item: AccountStyle) => item.key === key);
    this.styleKey = key === 'other_bank' ? (this.kind === 'liability' ? 'credit_card' : 'bank_card') : (preferredBankStyle(key)?.key || key);
    if (this.original === undefined && suggestedName) {
      this.name = (bank?.name || '其他银行') + (this.kind === 'liability' ? '信用卡' : '储蓄卡') +
        (this.cardTail.length === 4 ? '（' + this.cardTail + '）' : '');
    }
    this.step = 2;
    this.typeSelectionSnapshot = undefined;
  }
  private changeTail(value: string): void {
    const bankName = ACCOUNT_STYLES.find((item: AccountStyle) => item.key === this.issuerKey)?.name || '其他银行';
    const suggested = bankName + (this.kind === 'liability' ? '信用卡' : '储蓄卡');
    const previous = suggested + (this.cardTail.length === 4 ? '（' + this.cardTail + '）' : '');
    const tail = value.replace(/[^0-9]/g, '').slice(0, 4);
    if (this.original === undefined && (this.name === suggested || this.name === previous)) {
      this.name = suggested + (tail.length === 4 ? '（' + tail + '）' : '');
    }
    this.cardTail = tail;
  }
  private back(): void {
    if (this.busy || this.operationBusy) { return; }
    if (this.step === 0 && this.original !== undefined) {
      const snapshot = this.typeSelectionSnapshot;
      if (snapshot !== undefined) {
        this.typeKey = snapshot.typeKey; this.styleKey = snapshot.styleKey;
        this.issuerKey = snapshot.issuerKey; this.cardTail = snapshot.cardTail;
      }
      this.typeSelectionSnapshot = undefined; this.step = 2;
    }
    else if (this.step === 1) { this.step = this.bankReturnStep; }
    else if (this.step === 2 && this.original === undefined) {
      this.bankReturnStep = 0; this.step = isBankAccountType(this.typeKey) ? 1 : 0;
    }
    else { this.onClose(); }
  }
  private pageTitle(): string { return this.step === 0 ? '选择账户类型' : (this.step === 1 ? '选择发卡行' : (this.original === undefined ? '添加' + this.typeName() : '编辑账户')); }
  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }
  private style(): AccountStyle | undefined { return ACCOUNT_STYLES.find((item: AccountStyle) => item.key === this.styleKey); }
  private async save(): Promise<void> {
    if (this.busy || this.operationBusy || this.conflict) { return; }
    this.error = '';
    if (this.step !== 2) { return; }
    if (this.name.trim().length === 0) {
      this.error = '请填写账户名称';
      this.getUIContext().getPromptAction().showToast({ message: this.error });
      this.getUIContext().getFocusController().requestFocus('account-name');
      return;
    }
    if ((this.cardTail.length > 0 && !/^[0-9]{4}$/.test(this.cardTail)) || (isBankAccountType(this.typeKey) && !this.issuerKey && this.original === undefined)) {
      this.error = this.issuerKey ? '卡号尾号请填写 4 位数字，或留空' : '请选择发卡行';
      this.getUIContext().getPromptAction().showToast({ message: this.error }); return;
    }
    let command: AccountCommand;
    try {
      let opening = ExpenseAmountInput.nonnegative(this.original === undefined ? this.opening : '0', this.amountCurrency());
      if (this.kind === 'liability') { opening = Money.fromMinorText((-opening.minor).toString(), this.amountCurrency()); }
      command = { id: this.original?.id || this.draftId, name: this.name, kind: this.kind, styleKey: this.styleKey,
        includeInNetAssets: this.includeNet, opening: opening,
        accountType: this.typeKey, issuerKey: this.issuerKey, cardTail: this.cardTail, note: this.note };
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
  private typeChooser() {
    Scroll(this.typeScroller) {
      Column({ space: 20 }) {
        if (this.original !== undefined) {
          Text(this.original.kind === 'liability' ? '可更改信用账户类型，已有余额保持不变' : '可更改资产账户类型，已有余额保持不变')
            .fontSize('13fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
        }
        ForEach(this.typeGroups(), (group: string) => {
          Column({ space: 10 }) {
            Text(ACCOUNT_TYPE_GROUP_NAMES[ACCOUNT_TYPE_GROUPS.indexOf(group)]).fontSize('14fp').fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.xq_font_secondary')).width('100%').padding({ left: 4 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.types(group), (type: AccountTypeDefinition) => {
                Column({ space: 8 }) {
                  AccountAvatar({ iconKey: type.styleKey, iconVariant: type.styleKey.endsWith('_color') ? 'color' : 'monochrome',
                    brandColor: this.typeColor(type), diameter: 44 })
                  Text(type.name).fontSize('12fp').fontColor($r('app.color.xq_font_primary')).maxLines(2).textAlign(TextAlign.Center)
                }.width('25%').height(90).justifyContent(FlexAlign.Center)
                  .onClick(() => { this.chooseType(type); }).id('account-type-' + type.key)
              }, (type: AccountTypeDefinition) => type.key)
            }.padding(12).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
          }.width('100%')
        }, (group: string) => group)
      }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 24 })
    }.width('100%').height('100%').align(Alignment.Top).clip(false)
      .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  build() {
    if (this.original !== undefined && this.balancePage === 1) {
      AccountCalibrationPage({ account: this.original, workspace: this.workspace, onClose: () => { this.balancePage = 0; },
        onSaved: () => { this.onSaved(); }, onBusy: (value: boolean) => { this.busy = value; this.onBusy(value); } })
    } else if (this.original !== undefined && this.balancePage === 2) {
      AccountAdjustmentHistoryPage({ account: this.original, workspace: this.workspace, onClose: () => { this.balancePage = 0; } })
    } else if (this.step === 1) {
      AccountBankPicker({ accountKind: this.kind, query: $bankQuery, scroller: this.bankScroller,
        searchMaterial: this.sheetMaterial, statusBarContentColor: this.statusBarColor(),
        onBack: () => { this.back(); }, onSelectBank: (key: string) => { this.chooseBank(key); } })
    } else {
    HdsNavigation() {
      if (this.step === 0) {
        // Keep the Scroll as HDS content: the title bar owns its component safe
        // area. A full-height intermediary Column must not take that position.
        this.typeChooser()
      } else {
      Column() {
        Scroll(this.scroller) {
          Column({ space: 16 }) {
            Column({ space: 16 }) {
              AccountAvatar({ iconKey: this.styleKey, brandColor: this.style()?.color || this.original?.brandColor || '#5378B8',
                iconVariant: this.style()?.variant || this.original?.iconVariant || 'monochrome', diameter: 64 })
              TextInput({ text: this.name, placeholder: '账户名称，如：微信零钱' }).fontSize('16fp').height(48)
                .backgroundColor($r('app.color.xq_app_surface_keyboard')).borderRadius(12).maxLength(40)
                .id('account-name').onChange((value: string) => { this.name = value; })
              Button('币种 · ' + this.currencyCode).fontSize('14fp').width('100%')
                .fontColor($r('app.color.xq_font_primary')).backgroundColor($r('app.color.xq_app_surface_keyboard'))
                .enabled(this.original === undefined && !this.busy).onClick(() => {
                  try { this.openingController.stopEditing(); } catch (_) {}
                  const choices = enabledCurrencies(this.original === undefined ? '' : this.currencyCode);
                  this.getUIContext().showTextPickerDialog({ range: choices.map((item: CurrencyDefinition) => item.code + ' · ' + item.name),
                    selectedTextStyle: { color: $r('app.color.xq_font_emphasize') },
                    acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
                    cancelButtonStyle: { fontColor: $r('app.color.xq_font_secondary') },
                    selected: choices.findIndex((item: CurrencyDefinition) => item.code === this.currencyCode),
                    onAccept: (result: TextPickerResult) => {
                      const index = typeof result.index === 'number' ? result.index : result.index[0];
                      this.currencyCode = choices[index].code; this.opening = '0';
                    }
                  });
                })
              if (this.original !== undefined) {
                Button('账户类型 · ' + this.typeName(), { type: ButtonType.Capsule }).fontSize('14fp').height(44).width('100%')
                  .fontColor($r('app.color.xq_font_primary')).backgroundColor($r('app.color.xq_app_surface_keyboard'))
                  .enabled(!this.busy && !this.operationBusy && !this.conflict).id('account-change-type')
                  .onClick(() => { this.openTypeSelection(); })
              } else {
              Text(this.typeName() + ' · ' + (this.kind === 'asset' ? '资产账户' : '负债账户')).fontSize('13fp').fontColor($r('app.color.xq_font_secondary'))
              }
              if (isBankAccountType(this.typeKey)) {
                Button('发卡行 · ' + (ACCOUNT_STYLES.find((item: AccountStyle) => item.key === this.issuerKey)?.name || '其他银行'))
                  .fontSize('14fp').width('100%').fontColor($r('app.color.xq_font_primary'))
                  .backgroundColor($r('app.color.xq_app_surface_keyboard'))
                  .onClick(() => { this.bankQuery = ''; this.bankReturnStep = 2; this.step = 1; })
                TextInput({ text: this.cardTail, placeholder: '卡号后 4 位（选填）' }).type(InputType.Number).maxLength(4)
                  .height(48).fontSize('16fp').backgroundColor($r('app.color.xq_app_surface_keyboard')).borderRadius(12)
                  .onChange((value: string) => { this.changeTail(value); })
              }
              TextArea({ text: this.note, placeholder: '备注（选填）' }).fontSize('14fp').height(88).maxLength(500)
                .backgroundColor($r('app.color.xq_app_surface_keyboard')).borderRadius(12)
                .onChange((value: string) => { this.note = value; })
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
      }
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: this.pageTitle() },
          divider: { showType: DividerShowType.OFF },
          backIcon: { componentId: 'account-close', action: () => { this.back(); } } },
        style: { originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
          backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.step === 0 ? this.typeScroller : this.scroller])
      .width('100%').height('100%').backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .id('account-editor')
    }
  }
}
