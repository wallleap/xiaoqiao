import { CategoryIconBadge } from './CategoryIconBadge';
import { AccountAvatar } from './AccountAvatar';
import { MoneyAmountField } from './MoneyAmountField';
import { PrepaidEventCommand } from '../domain/model/Prepaid';
import { CURRENCIES, CurrencyDefinition, currencyUnit, currencyDefinition, crossRate } from '../core/money/Currencies';
import { ExchangeRate } from '../core/money/ExchangeRate';
import { FxConversion } from '../core/money/FxConversion';
import { OfficialExchangeRates } from '../data/exchange/OfficialExchangeRates';
import { LedgerLocation, locationFromDegrees } from '../domain/model/LedgerLocation';
import { HdsNavigation, HdsNavigationTitleMode, DividerShowType, hdsMaterial } from '@kit.UIDesignKit';
import { sceneMap } from '@kit.MapKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { FrameCallback, KeyboardAvoidMode, ChipGroup, ChipSize, curves } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { CurrencyUnit } from '../core/money/CurrencyUnit';
import { TransferCommand, TransferPurpose, TRANSFER_PURPOSES, transferPurposeLabel } from '../domain/model/TransferRecord';
import { IncomeCommand } from '../domain/model/IncomeRecord';
import { ExpenseCommand } from '../domain/model/ExpenseRecord';
import { AccountProfile } from '../domain/model/AccountProfile';
import { accountIcon } from '../presentation/ledger/AccountIcons';
import { EntryDetail } from '../domain/model/EntryDetail';
import { Money } from '../core/money/Money';
import { ExpenseCategory, LedgerAccount, SpendingNatureChoice, TagChoice } from '../domain/model/LedgerSnapshot';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { ExpenseAmountInput } from '../presentation/ledger/ExpenseAmountInput';
import { AmountKeyboard } from './AmountKeyboard';
import { categoryIcon } from '../presentation/ledger/CategoryIcons';
import { spendingNatureBackground, spendingNatureText } from '../presentation/ledger/SpendingNatureStyles';
import { LedgerAttachment, LedgerAttachmentDraft } from '../domain/model/LedgerAttachment';

class AmountFocusFrame extends FrameCallback {
  private readonly action: () => void;
  constructor(action: () => void) { super(); this.action = action; }
  onFrame(_time: number): void { this.action(); }
  onIdle(_time: number): void {}
}

interface ExpenseImageAttachment extends LedgerAttachmentDraft {
  filePath: string;
  persisted: boolean;
}

enum ExpenseErrorField { Amount, Discount, Fee, Coupon, Category, Accounts, Attachments, Save }

@Component
export struct ExpenseEditor {
  @Prop chipMaterial: SystemUiMaterial | undefined = undefined;
  @Prop actionMaterial: SystemUiMaterial | undefined = undefined;
  // The material is an immutable native instance supplied when the editor opens.
  sheetMaterial: SystemUiMaterial | undefined = undefined;
  workspace: LedgerWorkspace | undefined = undefined;
  @State private currencyCode: string = 'CNY';
  private amountCurrency(): CurrencyUnit { return currencyUnit(this.currencyCode); }
  @State private bookRate: string = '';
  @State private settlementRate: string = '';
  @State private actualSettlement: string = '';
  @State private quoteDate: string = '';
  @State private quoteSource: string = 'manual';
  @State private quoteBusy: boolean = false;
  private quoteVersion: number = 0;

  bookId: string = '';
  editingEntry: EntryDetail | undefined = undefined;
  @Prop @Watch('categoryChoicesChanged') categories: ExpenseCategory[] = [];
  @Prop @Watch('categoryChoicesChanged') incomeCategories: ExpenseCategory[] = [];
  @Prop @Watch('natureChoicesChanged') spendingNatures: SpendingNatureChoice[] = [];
  @Prop @Watch('tagChoicesChanged') tags: TagChoice[] = [];
  @State private isIncome: boolean = false;
  @State private isTransfer: boolean = false;
  @Prop @Watch('accountChoicesChanged') accounts: LedgerAccount[] = [];
  @Prop accountProfiles: AccountProfile[] = [];
  @Prop @Watch('managementChanged') managementVisible: boolean = false;
  @Prop @Watch('managementOptionCreated') managementCreatedOption: string = '';
  onManage: (kind: string) => void = () => {};
  onClose: () => void = () => {};
  onSavingChange: (saving: boolean) => void = () => {};
  onSaved: (date: string) => void = () => {};
  @State private expression: string = '0';
  @State private discount: string = '0';
  @State private transferPurpose: string = 'transfer';
  @State private transferFee: string = '0';
  @State private transferCoupon: string = '0';
  @State private transferTarget: number = 0;
  @State private feeBudget: boolean = true;
  @State private editingDiscount: boolean = false;
  @State private amountFocusHighlight: boolean = false;
  private amountFocusTimer: number = -1;
  @State private note: string = '';
  @State private merchantName: string = '';
  @State private addressText: string = '';
  initialPrepaid: boolean = false;
  @State private prepaid: boolean = false;
  @State private prepaidName: string = '';
  private readonly prepaidEventId: string = util.generateRandomUUID();
  @State private reimbursementPending: boolean = false;
  @State private location: LedgerLocation | undefined = undefined;
  @State private mapBusy: boolean = false;
  private mapRequestVersion: number = 0;
  @State private attachments: ExpenseImageAttachment[] = [];
  @State private attachmentBusy: boolean = false;
  @State private selectedId: string = '';
  @State private selectedNatureId: string = '';
  @State private selectedTagIds: string[] = [];
  @State private accountId: string = '';
  @State private toAccountId: string = '';
  @State private occurredAtMs: number = Date.now();
  @State private occurredAtLabel: string = '';
  @State private includeBudget: boolean = true;
  @State private includeAssets: boolean = true;
  @State private saving: boolean = false;
  @State private saved: boolean = false;
  @State private conflicted: boolean = false;
  private dateEdited: boolean = false;
  @State private errorText: string = '';
  @State private errorField: ExpenseErrorField = ExpenseErrorField.Amount;
  @State private showOptions: boolean = false;
  @State private showTagPicker: boolean = false;
  @State private tagSearch: string = '';
  private managementOpening: boolean = false;
  private pendingCreatedOptions: string[] = [];
  private managementAccountTarget: number = 1;
  @State private activeHelp: string = '';
  @State private optionKind: number = 0;
  @State private parentId: string = '';
  @State private compactCategories: boolean = false;
  @State private categoryCollapse: number = 0;
  @State private categoryPage: number = 0;
  private categoryDragY: number = 0;
  private categoryMotionVersion: number = 0;
  @State private keyboardVisible: boolean = true;
  @State private noteEditing: boolean = false;
  @State private selectedKinds: number[] = [0];
  private readonly scroller: Scroller = new Scroller();
  private readonly amountController: TextInputController = new TextInputController();
  private previousAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;
  private active: boolean = false;
  private saveId: string = util.generateRandomUUID();

  aboutToAppear(): void {
    const entry = this.editingEntry;
    this.prepaid = entry === undefined && this.initialPrepaid;
    this.isIncome = entry?.kind === 'income';
    this.isTransfer = entry?.kind === 'transfer';
    this.selectedKinds = [this.isTransfer ? 2 : this.isIncome ? 1 : 0];
    this.selectedId = this.activeCategories().length > 0 ? this.activeCategories()[0].id : '';
    if (entry !== undefined) {
      this.currencyCode = entry.currencyId;
      this.bookRate = entry.bookFx?.rate || '';
      this.settlementRate = entry.accountFx?.rate || '';
      this.quoteDate = entry.bookFx?.date || entry.accountFx?.date || '';
      this.quoteSource = entry.bookFx?.source || entry.accountFx?.source || 'manual';
      if (entry.accountCurrencyId !== undefined && entry.accountCurrencyId !== entry.currencyId && entry.accountMinor !== undefined) {
        this.actualSettlement = Money.fromMinorText(entry.accountMinor, currencyUnit(entry.accountCurrencyId)).toDecimalString();
      }
      this.transferPurpose = entry.transferPurpose || 'transfer';
      this.transferFee = Money.fromMinorText(entry.transferFeeMinor || '0', this.amountCurrency()).toDecimalString();
      this.transferCoupon = Money.fromMinorText(entry.transferCouponMinor || '0', this.amountCurrency()).toDecimalString();
      this.feeBudget = entry.feeInBudget !== false;
      this.saveId = entry.id;
      this.expression = Money.fromMinorText(entry.grossMinor, this.amountCurrency()).toDecimalString();
      this.discount = Money.fromMinorText(entry.discountMinor, this.amountCurrency()).toDecimalString();
      this.selectedId = entry.categoryId; this.accountId = entry.accountId; this.toAccountId = entry.toAccountId || '';
      this.selectedNatureId = entry.spendingNatureId || '';
      this.selectedTagIds = (entry.tags || []).map((tag: TagChoice) => tag.id);
      this.reimbursementPending = entry.reimbursementPending === true;
      this.includeAssets = entry.includeInAssets; this.includeBudget = entry.includeInBudget;
      this.occurredAtMs = entry.occurredAtMs; this.note = entry.note;
      this.merchantName = entry.merchantName || ''; this.addressText = entry.addressText || '';
      this.location = entry.location;
      this.attachments = (entry.attachments || []).map((attachment: LedgerAttachment): ExpenseImageAttachment => ({
        relativePath: attachment.relativePath, sha256: attachment.sha256, bytes: attachment.bytes,
        mimeType: attachment.mimeType, filePath: attachment.filePath, persisted: true }));
    }
    this.occurredAtLabel = this.dateLabel();
    this.active = true;
    this.previousAvoidMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.focusAmountAfterFrame();
  }

  aboutToDisappear(): void {
    this.active = false; this.quoteVersion++;
    this.mapRequestVersion++; this.mapBusy = false;
    clearTimeout(this.amountFocusTimer);
    this.amountController.stopEditing();
    this.getUIContext().setKeyboardAvoidMode(this.previousAvoidMode);
    if (!this.saved) { this.discardPendingAttachments(); }
  }

  private focusAmount(): void {
    if (!this.active || this.saved || this.managementVisible || this.managementOpening) { return; }
    this.editingDiscount = false; this.transferTarget = 0;
    this.getUIContext().getFocusController().requestFocus('expense-amount');
  }

  private categoryChoicesChanged(): void {
    this.applyCreatedOptions();
    if (this.isTransfer) { return; }
    if (this.selectedId.length > 0 && !this.activeCategories().some((item: ExpenseCategory) => item.id === this.selectedId)) {
      this.selectedId = '';
      this.showError(ExpenseErrorField.Category, '所选分类已不可用，请重新选择');
    }
    this.categoryPage = Math.min(this.categoryPage, Math.max(0, Math.ceil(this.roots().length / this.categoryPageSize()) - 1));
  }

  private accountChoicesChanged(): void {
    this.applyCreatedOptions();
    let removed = false;
    if (this.accountId.length > 0 && !this.accounts.some((item: LedgerAccount) => item.id === this.accountId)) {
      this.accountId = ''; removed = true;
    }
    if (this.toAccountId.length > 0 && !this.accounts.some((item: LedgerAccount) => item.id === this.toAccountId)) {
      this.toAccountId = ''; removed = true;
    }
    if (removed) { this.showError(ExpenseErrorField.Accounts, '所选账户已不可用，请重新选择'); }
  }

  private natureChoicesChanged(): void {
    this.applyCreatedOptions();
    if (this.selectedNatureId.length > 0 && !this.spendingNatures.some((item: SpendingNatureChoice) => item.id === this.selectedNatureId)) {
      this.selectedNatureId = '';
    }
  }

  private tagChoicesChanged(): void {
    this.applyCreatedOptions();
    this.selectedTagIds = this.selectedTagIds.filter((id: string) => this.tags.some((item: TagChoice) => item.id === id));
  }

  private managementChanged(): void {
    if (!this.managementVisible) { this.managementOpening = false; this.applyCreatedOptions(); }
  }

  private managementOptionCreated(): void {
    if (this.managementCreatedOption.length === 0) { return; }
    this.pendingCreatedOptions.push(this.managementCreatedOption);
    this.applyCreatedOptions();
  }

  private applyCreatedOptions(): void {
    if (this.managementVisible) { return; }
    this.pendingCreatedOptions = this.pendingCreatedOptions.filter((value: string) => {
      const separator = value.indexOf(':');
      const kind = value.substring(0, separator); const id = value.substring(separator + 1);
      if (kind === 'categories') {
        const income = this.incomeCategories.some((item: ExpenseCategory) => item.id === id);
        const item = (income ? this.incomeCategories : this.categories).find((item: ExpenseCategory) => item.id === id);
        if (item === undefined || this.isTransfer) { return true; }
        this.isIncome = income; this.selectedId = id;
        let rootId = item.id;
        const visited: Set<string> = new Set<string>();
        let parentId = item.parentId;
        while (parentId.length > 0 && !visited.has(parentId)) {
          visited.add(parentId); rootId = parentId;
          parentId = this.activeCategories().find((parent: ExpenseCategory) => parent.id === rootId)?.parentId || '';
        }
        const page = this.roots().findIndex((root: ExpenseCategory) => root.id === rootId);
        if (page >= 0) { this.categoryPage = Math.floor(page / this.categoryPageSize()); }
        this.clearFieldError(ExpenseErrorField.Category);
      } else if (kind === 'accounts') {
        if (!this.accounts.some((item: LedgerAccount) => item.id === id)) { return true; }
        if (this.managementAccountTarget === 2) { this.toAccountId = id; } else { this.accountId = id; }
        this.clearFieldError(ExpenseErrorField.Accounts);
      } else if (kind === 'natures') {
        if (!this.spendingNatures.some((item: SpendingNatureChoice) => item.id === id)) { return true; }
        this.selectedNatureId = id;
      } else if (kind === 'tags') {
        if (!this.tags.some((item: TagChoice) => item.id === id)) { return true; }
        if (!this.selectedTagIds.includes(id)) { this.selectedTagIds = this.selectedTagIds.concat([id]); }
      }
      return false;
    });
  }

  private openManagement(kind: string): void {
    if (this.saving || this.saved || this.conflicted || this.mapBusy || this.attachmentBusy || this.managementOpening) { return; }
    this.managementOpening = true;
    this.pendingCreatedOptions = [];
    this.managementAccountTarget = this.optionKind === 2 ? 2 : 1;
    this.activeHelp = '';
    this.showOptions = false;
    this.showTagPicker = false;
    this.amountController.stopEditing();
    this.getUIContext().getFocusController().clearFocus();
    this.keyboardVisible = false;
    this.noteEditing = false;
    this.onManage(kind);
  }

  @Builder
  private managementButton(label: string, kind: string, componentId: string) {
    Button(label, { type: ButtonType.Capsule }).height(28).fontSize('12fp').fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.xq_font_emphasize')).backgroundColor(Color.Transparent)
      .enabled(!this.saving && !this.saved && !this.conflicted && !this.mapBusy && !this.attachmentBusy)
      .id(componentId).onClick(() => { this.openManagement(kind); })
  }

  private focusAmountFromPaid(): void {
    if (!this.active || this.saved || this.saving) { return; }
    this.focusAmount();
    this.amountController.caretPosition(this.expression.length);
    clearTimeout(this.amountFocusTimer);
    this.amountFocusHighlight = true;
    this.amountFocusTimer = setTimeout(() => {
      if (!this.active) { return; }
      this.getUIContext().animateTo({ duration: 400, curve: Curve.EaseOut }, () => {
        this.amountFocusHighlight = false;
      });
    }, 700);
  }

  private focusAmountAfterFrame(): void {
    this.getUIContext().postFrameCallback(new AmountFocusFrame(() => { this.focusAmount(); }));
  }

  private statusBarColor(): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) { return '#E5000000'; }
    return '#' + (context.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }

  private activeCategories(): ExpenseCategory[] { return this.isIncome ? this.incomeCategories : this.categories; }
  private effectiveDiscount(): string { return this.isIncome || this.isTransfer ? '0' : this.discount; }

  private selectKind(selected: number[]): void {
    if (selected.length !== 1 || this.saving || this.editingEntry !== undefined) { return; }
    if (selected[0] === this.selectedKinds[0]) { return; }
    this.prepaid = false;
    this.isIncome = selected[0] === 1; this.isTransfer = selected[0] === 2;
    this.selectedKinds = [selected[0]];
    this.editingDiscount = false; this.transferTarget = 0; this.errorText = ''; this.parentId = ''; this.showOptions = false;
    this.selectedId = this.activeCategories()[0]?.id || '';
    if (this.isIncome || this.isTransfer) { this.selectedNatureId = ''; }
    this.categoryPage = 0;
  }

  private selected(): ExpenseCategory | undefined {
    return this.activeCategories().find((item: ExpenseCategory) => item.id === this.selectedId);
  }

  private toggleTag(id: string): void {
    if (this.selectedTagIds.includes(id)) {
      this.selectedTagIds = this.selectedTagIds.filter((value: string) => value !== id);
    } else if (this.selectedTagIds.length < 20) {
      this.selectedTagIds = [...this.selectedTagIds, id];
    }
  }

  private attachmentDrafts(): LedgerAttachmentDraft[] {
    return this.attachments.map((attachment: ExpenseImageAttachment): LedgerAttachmentDraft => ({
      relativePath: attachment.relativePath, sha256: attachment.sha256,
      bytes: attachment.bytes, mimeType: attachment.mimeType }));
  }

  private async chooseMapLocation(): Promise<void> {
    if (!this.active || this.mapBusy || this.attachmentBusy || this.saving || this.saved || this.conflicted) { return; }
    if (!canIUse('SystemCapability.Map.Core')) {
      this.inform('当前设备不支持地图选点，请手动填写地址。'); return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) { this.inform('暂时无法打开地图，请手动填写地址。'); return; }
    this.amountController.stopEditing();
    this.keyboardVisible = false;
    this.mapBusy = true;
    const version = ++this.mapRequestVersion;
    const options: sceneMap.LocationChoosingOptions = {
      searchEnabled: true, showNearbyPoi: true, snapshotEnabled: false,
      cancelCallback: () => {
        if (version === this.mapRequestVersion) { this.mapBusy = false; }
      }
    };
    if (this.location !== undefined) {
      options.location = { latitude: this.location.latitudeE6 / 1000000, longitude: this.location.longitudeE6 / 1000000 };
    }
    try {
      const result = await sceneMap.chooseLocation(context, options);
      if (!this.active || version !== this.mapRequestVersion || !this.mapBusy) { return; }
      const address = result.address.trim();
      if (address.length === 0) { this.inform('所选位置没有可用地址，请重新选点或手动填写。'); return; }
      const location = locationFromDegrees(result.location.latitude, result.location.longitude);
      this.addressText = address;
      this.location = location;
      // A free map point can be named “标记点”; only a POI can supply a merchant name.
      if (this.merchantName.trim().length === 0 && (result.siteId || '').length > 0) {
        this.merchantName = (result.name || '').trim();
      }
    } catch (error) {
      if (!this.active || version !== this.mapRequestVersion || !this.mapBusy) { return; }
      const code = (error as BusinessError).code;
      const message = code === 1002600003 ? '地图身份校验未通过，请检查应用地图配置。' :
        code === 1002600004 ? '当前应用尚未开通地图服务。' :
        code === 1002600002 ? '地图连接失败，请检查网络后重试。' :
        code === 801 ? '当前设备不支持地图选点。' : '地图选点暂不可用，请稍后重试。';
      this.inform(message + '已保留原内容，也可以手动填写地址。');
    } finally {
      if (version === this.mapRequestVersion) { this.mapBusy = false; }
    }
  }

  private changeAddress(value: string): void {
    if (value.trim() !== this.addressText.trim()) { this.location = undefined; }
    this.addressText = value;
  }

  private async chooseImages(): Promise<void> {
    const workspace = this.workspace;
    if (workspace === undefined || this.attachmentBusy || this.saving || this.saved || this.conflicted ||
      this.attachments.length >= 9) { return; }
    this.amountController.stopEditing();
    this.attachmentBusy = true;
    this.clearFieldError(ExpenseErrorField.Attachments);
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.maxSelectNumber = 9 - this.attachments.length;
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.isSearchSupported = true;
      const view = new photoAccessHelper.PhotoViewPicker();
      const selected = await view.select(options);
      if (!this.active) { return; }
      for (const source of selected.photoUris) {
        const draft = await workspace.saveImageAttachment(source, 'original');
        if (!this.active) {
          await workspace.discardUnpersistedImage(draft);
          return;
        }
        if (this.attachments.some((attachment: ExpenseImageAttachment) => attachment.sha256 === draft.sha256)) { continue; }
        this.attachments = [...this.attachments, { relativePath: draft.relativePath, sha256: draft.sha256, bytes: draft.bytes,
          mimeType: draft.mimeType, filePath: workspace.backup.resources.root + '/' + draft.relativePath,
          persisted: false }];
        if (this.attachments.length >= 9) { break; }
      }
    } catch (error) {
      if (!this.active) { return; }
      const message = (error as Error).message;
      const reason = message === 'PACKAGE_SIZE' ? '图片为空或超过 32 MiB，请选择较小的图片' :
        message === 'RESOURCE_FORMAT' ? '图片格式无法识别，请选择 PNG、JPG 或 WebP 图片' :
        '图片读取或保存失败，请检查图片是否可用及设备存储空间';
      this.showError(ExpenseErrorField.Attachments, reason + '。已添加的图片会保留，请检查后重试');
    } finally { this.attachmentBusy = false; }
  }

  private removeAttachment(sha256: string): void {
    if (this.saving || this.saved || this.conflicted) { return; }
    const removed = this.attachments.find((attachment: ExpenseImageAttachment) => attachment.sha256 === sha256);
    this.attachments = this.attachments.filter((attachment: ExpenseImageAttachment) => attachment.sha256 !== sha256);
    if (removed !== undefined && !removed.persisted && this.workspace !== undefined) {
      this.workspace.discardUnpersistedImage(removed).catch(() => {});
    }
    this.clearFieldError(ExpenseErrorField.Attachments);
  }

  private async discardPendingAttachments(): Promise<void> {
    const workspace = this.workspace;
    if (workspace === undefined) { return; }
    for (const attachment of this.attachments) {
      if (attachment.persisted) { continue; }
      try { await workspace.discardUnpersistedImage(attachment); } catch (_) { /* Best-effort orphan cleanup. */ }
    }
  }

  private roots(): ExpenseCategory[] { return this.activeCategories().filter((item: ExpenseCategory) => item.parentId.length === 0); }

  private categoryPageSize(): number { return this.compactCategories ? 4 : 8; }

  private updateCategoryCollapse(value: number): void {
    this.categoryMotionVersion++;
    const next = Math.max(0, Math.min(80, value));
    const compact = next >= 80;
    if (compact !== this.compactCategories) {
      this.categoryPage = compact ? this.categoryPage * 2 : Math.floor(this.categoryPage / 2);
      this.compactCategories = compact;
    }
    this.categoryCollapse = next;
  }

  private consumeCategoryScroll(delta: number): number {
    if (delta > 0) {
      const consumed = Math.min(delta, 80 - this.categoryCollapse);
      this.updateCategoryCollapse(this.categoryCollapse + consumed);
      return delta - consumed;
    }
    const formOffset = Math.max(0, this.scroller.currentOffset().yOffset);
    const available = Math.max(0, -delta - formOffset);
    const consumed = Math.min(available, this.categoryCollapse);
    this.updateCategoryCollapse(this.categoryCollapse - consumed);
    return delta + consumed;
  }

  private settleCategories(): void {
    if (this.categoryCollapse <= 0 || this.categoryCollapse >= 80) { return; }
    const target = this.categoryCollapse >= 40 ? 80 : 0;
    const version = ++this.categoryMotionVersion;
    this.getUIContext().animateTo({ curve: curves.springMotion(0.28, 0.90), onFinish: () => {
      if (this.active && this.categoryMotionVersion === version) { this.updateCategoryCollapse(target); }
    } }, () => {
      this.categoryCollapse = target;
    });
  }

  private children(): ExpenseCategory[] { return this.activeCategories().filter((item: ExpenseCategory) => item.parentId === this.parentId); }

  private choose(item: ExpenseCategory): void {
    this.selectedId = item.id; // Parent is already selected; dismissing the sheet keeps it.
    this.clearFieldError(ExpenseErrorField.Category);
    if (this.activeCategories().some((child: ExpenseCategory) => child.parentId === item.id)) {
      this.parentId = item.id;
      this.optionKind = 0;
      this.showOptions = true;
    } else { this.showOptions = false; }
  }

  private wallDate(): Date {
    const entry = this.editingEntry;
    if (entry !== undefined && !this.dateEdited) {
      return new Date(this.occurredAtMs + (entry.offsetMinutes + new Date(this.occurredAtMs).getTimezoneOffset()) * 60000);
    }
    return new Date(this.occurredAtMs);
  }

  private localDate(): string {
    const date = this.wallDate();
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  private dateLabel(): string {
    const date = this.wallDate();
    return this.localDate() + ' ' + String(date.getHours()).padStart(2, '0') + ':' + String(date.getMinutes()).padStart(2, '0');
  }

  private isRepayment(): boolean { return this.transferPurpose === 'credit_repayment' || this.transferPurpose === 'loan_repayment'; }

  private transferOutgoing(expression: string = this.expression, fee: string = this.transferFee,
    coupon: string = this.transferCoupon, pending: boolean = false): Money {
    const normalize = (text: string): string => pending && /[+−]$/.test(text) ? text.slice(0, -1) : text;
    const principal = ExpenseAmountInput.evaluate(normalize(expression), this.amountCurrency());
    const feeMoney = ExpenseAmountInput.evaluateDiscount(normalize(fee), this.amountCurrency());
    const couponMoney = ExpenseAmountInput.evaluateDiscount(normalize(coupon), this.amountCurrency());
    if (couponMoney.minor > principal.minor || (!this.isRepayment() && couponMoney.minor > BigInt(0))) { throw new Error('INVALID_TRANSFER_COUPON'); }
    const outgoing = principal.add(feeMoney).subtract(couponMoney);
    outgoing.toSafeMinorNumber();
    return outgoing;
  }

  private transferOutgoingText(): string {
    try { return this.transferOutgoing().toDecimalString(); } catch (_) { return '—'; }
  }

  private editTransferExtra(target: number): void {
    const next = this.transferTarget === target ? 0 : target;
    this.focusAmount();
    this.transferTarget = next;
  }

  private paidText(): string {
    try {
      return ExpenseAmountInput.paidAmount(this.expression, this.effectiveDiscount(), this.amountCurrency()).toDecimalString();
    } catch (_) { return '—'; }
  }

  private canSaveAmounts(expression: string, discount: string): boolean {
    try {
      if (this.isTransfer) { this.transferOutgoing(expression); }
      return ExpenseAmountInput.evaluate(expression, this.amountCurrency()).minor > BigInt(0) &&
        ExpenseAmountInput.paidAmount(expression, this.isIncome || this.isTransfer ? '0' : discount, this.amountCurrency()).minor > BigInt(0);
    } catch (_) { return false; }
  }

  private inform(message: string): void {
    this.getUIContext().getPromptAction().showDialog({ title: '说明', message: message,
      buttons: [{ text: '知道了', color: $r('app.color.xq_font_emphasize') }] });
  }

  private showError(field: ExpenseErrorField, message: string): void {
    this.errorField = field;
    this.errorText = message;
    if (field === ExpenseErrorField.Accounts) { this.scroller.scrollTo({ xOffset: 0, yOffset: 0 }); }
  }

  private clearFieldError(field: ExpenseErrorField): void {
    if (this.errorField === field) { this.errorText = ''; }
  }

  private press(key: string): void {
    if (this.saving || this.saved || this.conflicted) { return; }
    if (key === '保存') { this.save(); return; }
    this.errorText = '';
    if (this.isTransfer) {
      const current = this.transferTarget === 1 ? this.transferFee : this.transferTarget === 2 ? this.transferCoupon : this.expression;
      try {
        const next = key === '清空' ? '0' : this.transferTarget === 0 ? ExpenseAmountInput.append(current, key, this.amountCurrency().scale) : ExpenseAmountInput.appendDiscount(current, key, this.amountCurrency().scale);
        if (key !== '⌫' && key !== '清空') {
          this.transferOutgoing(this.transferTarget === 0 ? next : this.expression, this.transferTarget === 1 ? next : this.transferFee, this.transferTarget === 2 ? next : this.transferCoupon, true);
        }
        if (this.transferTarget === 1) { this.transferFee = next; } else if (this.transferTarget === 2) { this.transferCoupon = next; } else { this.expression = next; }
      } catch (_) {
        const field = this.transferTarget === 1 ? ExpenseErrorField.Fee :
          this.transferTarget === 2 ? ExpenseErrorField.Coupon : ExpenseErrorField.Amount;
        const label = this.transferTarget === 1 ? '手续费' : this.transferTarget === 2 ? '还款优惠' : '转账金额';
        this.showError(field, label + '超出范围，或还款优惠大于还款金额');
      }
      return;
    }
    if (key === '清空') {
      if (this.editingDiscount) { this.discount = '0'; } else { this.expression = '0'; }
      return;
    }
    try {
      const next = ExpenseAmountInput.appendChecked(this.expression, this.effectiveDiscount(), key, this.amountCurrency(), this.editingDiscount);
      if (this.editingDiscount) { this.discount = next; } else { this.expression = next; }
    } catch (error) {
      const code = (error as Error).message;
      let message = this.editingDiscount ? '优惠金额无法计算或超出范围，请修改输入' : '金额无法计算或超出范围，请修改输入';
      if (code === 'CURRENCY_MISMATCH' || code === 'INVALID_CURRENCY' || code === 'UNSUPPORTED_CURRENCY') {
        message = '金额币种配置异常，请重新选择币种';
      } else if (code === 'AMOUNT_PRECISION_EXCEEDED') { message = this.currencyCode + ' 最多支持 ' + this.amountCurrency().scale.toString() + ' 位小数'; }
      this.showError(this.editingDiscount ? ExpenseErrorField.Discount : ExpenseErrorField.Amount, message);
    }
  }

  private fxDate(): string { return this.localDate(); }
  private settlementCode(): string {
    const id = this.isTransfer ? this.toAccountId : this.accountId;
    return this.accounts.find((item: LedgerAccount) => item.id === id)?.currencyId ||
      (id && id === (this.isTransfer ? this.editingEntry?.toAccountId : this.editingEntry?.accountId) ? this.editingEntry?.accountCurrencyId : undefined) || this.currencyCode;
  }
  private bookAmountText(): string {
    try {
      const paid = ExpenseAmountInput.paidAmount(this.expression, this.effectiveDiscount(), this.amountCurrency());
      return '折合人民币 ¥' + this.converted(paid, 'CNY', this.bookRate).toDecimalString();
    } catch (_) { return '填写汇率后显示人民币折算金额'; }
  }
  private fxQuote(rate: string, actual: boolean = false): FxConversion {
    return { rate: rate, date: this.quoteDate || this.fxDate(), source: actual ? 'manual' : this.quoteSource, actual: actual };
  }
  private converted(amount: Money, code: string, rate: string): Money {
    const target = currencyUnit(code);
    if (amount.currency.matches(target)) { return amount; }
    return new ExchangeRate(amount.currency, target, rate).convert(amount);
  }
  private settlementAmount(amount: Money): Money {
    const code = this.settlementCode();
    if (code !== this.currencyCode && this.actualSettlement.length > 0) { return ExpenseAmountInput.nonnegative(this.actualSettlement, currencyUnit(code)); }
    return this.converted(amount, code, this.settlementRate);
  }
  private selectCurrency(): void {
    if (this.saving || this.editingEntry !== undefined || this.quoteBusy) { return; }
    this.amountController.stopEditing();
    this.getUIContext().showTextPickerDialog({ range: CURRENCIES.map((item: CurrencyDefinition) => item.code + ' · ' + item.name),
      selectedTextStyle: { color: $r('app.color.xq_font_emphasize') },
      acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      cancelButtonStyle: { fontColor: $r('app.color.xq_font_secondary') },
      selected: Math.max(0, CURRENCIES.findIndex((item: CurrencyDefinition) => item.code === this.currencyCode)),
      onAccept: (result: TextPickerResult) => {
        const index = typeof result.index === 'number' ? result.index : result.index[0];
        this.currencyCode = CURRENCIES[index].code;
        this.expression = '0'; this.discount = '0'; this.transferFee = '0'; this.transferCoupon = '0';
        this.bookRate = ''; this.settlementRate = ''; this.actualSettlement = ''; this.quoteDate = ''; this.quoteSource = 'manual';
        this.quoteVersion++;
        if (this.isTransfer) { this.accountId = ''; }
      }
    });
  }
  private async loadRates(): Promise<void> {
    if (this.quoteBusy || this.saving) { return; }
    this.quoteBusy = true;
    const version = ++this.quoteVersion;
    const source = this.currencyCode; const target = this.settlementCode(); const date = this.fxDate();
    try {
      const book = await OfficialExchangeRates.quote(source, 'CNY', date);
      const settlement = await OfficialExchangeRates.quote(source, target, date);
      if (this.active && version === this.quoteVersion && source === this.currencyCode && target === this.settlementCode() && date === this.fxDate()) {
        this.bookRate = book.rate; this.settlementRate = settlement.rate;
        this.quoteDate = book.source === 'same_currency' ? settlement.date : book.date;
        this.quoteSource = book.source === 'ECB_CACHE' || settlement.source === 'ECB_CACHE' ? 'ECB_CACHE' : 'ECB';
        this.actualSettlement = '';
      }
    } catch (_) { if (this.active) { this.showError(ExpenseErrorField.Amount, '参考汇率暂不可用，可手动填写汇率后保存'); } }
    finally { if (this.active) { this.quoteBusy = false; } }
  }
  @Builder
  private fxCard() {
    Column({ space: 12 }) {
      Row() {
        Text('币种').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
        Blank()
        Button(this.currencyCode + ' · ' + currencyDefinition(this.currencyCode).name).fontSize('14fp')
          .backgroundColor(Color.Transparent).fontColor($r('app.color.xq_font_primary'))
          .enabled(!this.saving && this.editingEntry === undefined).onClick(() => { this.selectCurrency(); })
      }.width('100%')
      if (this.currencyCode !== 'CNY' || this.settlementCode() !== this.currencyCode) {
        if (this.currencyCode !== 'CNY') {
          TextInput({ text: this.bookRate, placeholder: '1 ' + this.currencyCode + ' = ? CNY' }).fontSize('14fp').type(InputType.NUMBER_DECIMAL)
            .enabled(!this.saving && !this.quoteBusy).onChange((value: string) => { this.bookRate = value; this.quoteSource = 'manual'; this.quoteDate = this.fxDate(); })
        }
        if (this.settlementCode() !== this.currencyCode) {
          TextInput({ text: this.settlementRate, placeholder: '到账汇率：1 ' + this.currencyCode + ' = ? ' + this.settlementCode() })
            .fontSize('14fp').type(InputType.NUMBER_DECIMAL).enabled(!this.saving && !this.quoteBusy)
            .onChange((value: string) => { this.settlementRate = value; this.quoteSource = 'manual'; this.quoteDate = this.fxDate(); })
          MoneyAmountField({ value: $actualSettlement, fieldId: 'expense-actual-settlement', currency: currencyUnit(this.settlementCode()),
            fontSize: '14fp', allowEmpty: true, placeholder: '实际到账／扣款金额 ' + this.settlementCode() + '（可选）',
            disabled: this.saving || this.quoteBusy })
        }
        Text(this.bookAmountText()).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).width('100%')
        Button(this.quoteBusy ? '读取汇率中…' : '获取官方参考汇率').fontSize('13fp').backgroundColor(Color.Transparent)
          .fontColor($r('app.color.xq_font_emphasize')).enabled(!this.saving && !this.quoteBusy).onClick(() => { this.loadRates(); })
        Text((this.quoteDate ? this.quoteDate + ' · ' : '') + (this.quoteSource === 'manual' ? '手动汇率' : '欧洲中央银行 ECB · 官网免费参考汇率') + '，保存后固定此笔折算金额')
          .fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
      }
    }.width('100%').padding(16).borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
  }

  private prepaidMode(): boolean { return this.prepaid && !this.isIncome && !this.isTransfer && this.editingEntry === undefined; }
  private prepaidCost(amount: Money): Money {
    const cash = this.settlementAmount(amount);
    if (cash.currency.code === 'CNY') { return cash; }
    const book = this.currencyCode === 'CNY' ? '1' : this.bookRate;
    const rate = cash.currency.code === this.currencyCode ? '1' : this.settlementRate;
    return new ExchangeRate(cash.currency,currencyUnit('CNY'),crossRate(book,rate)).convert(cash);
  }
  private async savePrepaid(workspace: LedgerWorkspace, command: ExpenseCommand): Promise<void> {
    if (command.accountPaid === undefined || command.accountId === undefined) { throw new Error('ACCOUNT_UNAVAILABLE'); }
    const paid = command.gross.subtract(command.discount);
    const payment: PrepaidEventCommand = {
      id: this.prepaidEventId, projectId: command.id, bookId: command.bookId, expectedRevision: 1, kind: 'fund',
      amount: paid, accountId: command.accountId, cash: command.accountPaid, cashBook: command.bookPaid,
      rateSource: this.actualSettlement ? 'manual' : this.quoteSource, rateDate: this.quoteDate || command.localDate,
      bookRate: this.currencyCode === 'CNY' ? '1' : this.bookRate, cashRate: this.settlementCode() === this.currencyCode ? '1' : this.settlementRate,
      categoryId: this.selectedId, incomeCategoryId: '', spendingNatureId: this.selectedNatureId, includeInBudget: this.includeBudget,
      occurredAtMs: command.occurredAtMs, localDate: command.localDate, offsetMinutes: command.offsetMinutes, note: command.note, attachments: command.attachments,
      entryContext: { categoryId: this.selectedId, categoryName: this.selected()?.name || '', spendingNatureId: this.selectedNatureId,
        includeInBudget: this.includeBudget, grossMinor: command.gross.minor.toString(), discountMinor: command.discount.minor.toString(),
        addressText: this.addressText.trim(), location: this.location, tagIds: this.selectedTagIds.slice(),
        tagNames: this.tags.filter((item: TagChoice) => this.selectedTagIds.includes(item.id)).map((item: TagChoice) => item.name) }
    };
    await workspace.createPrepaid({ id: command.id, bookId: command.bookId,
      name: this.prepaidName.trim() || this.merchantName.trim() || this.selected()?.name || '预付款', merchant: this.merchantName.trim(),
      currencyId: this.currencyCode, expiryDate: '', note: this.note.trim(), includeInNetAssets: this.includeAssets },payment);
    this.getUIContext().getPromptAction().showToast({ message: '已保存预付款，核销时计支出；可在账目页“预付款与核销”入口管理' });
  }

  @Builder
  private prepaidMarker() {
    if (!this.isIncome && !this.isTransfer && this.editingEntry === undefined) {
      Column({space:8}) {
        Row() {
          Text('预付款／待核销').fontSize('14fp').fontColor($r('app.color.xq_font_primary')).layoutWeight(1)
          Toggle({type:ToggleType.Switch,isOn:this.prepaid}).selectedColor($r('app.color.xq_brand')).enabled(!this.saving&&!this.saved&&!this.conflicted)
            .onChange((value:boolean)=>{this.prepaid=value;if (value) {this.reimbursementPending=false;}this.errorText='';}).id('expense-prepaid')
        }.width('100%')
        if (this.prepaidMode()) {
          TextInput({text:this.prepaidName,placeholder:'预付项目名称（选填）'}).fontSize('14fp').maxLength(40).backgroundColor($r('app.color.xq_app_surface_page')).borderRadius(12)
            .enabled(!this.saving&&!this.saved&&!this.conflicted).onChange((value:string)=>{this.prepaidName=value;}).onFocus(()=>{this.keyboardVisible=false;})
          Text('本次只付款并保留预付余额，核销时才计支出和预算；下方分类为核销预设。到期日可在项目中设置。')
            .fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
        }
      }.width('100%')
    }
  }
  @Builder
  private prepaidRules() {
    Column({space:12}) {
      Row() { Text('核销时计入预算').fontSize('14fp').layoutWeight(1); Toggle({type:ToggleType.Switch,isOn:this.includeBudget}).selectedColor($r('app.color.xq_brand')).enabled(!this.saving).onChange((value:boolean)=>{this.includeBudget=value;}) }.width('100%')
      Row() { Text('预付款计入净资产').fontSize('14fp').layoutWeight(1); Toggle({type:ToggleType.Switch,isOn:this.includeAssets}).selectedColor($r('app.color.xq_brand')).enabled(!this.saving).onChange((value:boolean)=>{this.includeAssets=value;}) }.width('100%')
    }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
  }

  private async save(): Promise<void> {
    if (this.quoteBusy || this.mapBusy || this.attachmentBusy || this.saving || this.saved || this.conflicted) { return; }
    this.errorText = '';
    let command: ExpenseCommand;
    try {
      if (this.isTransfer) {
        this.transferOutgoing();
        if (this.isRepayment() && this.accounts.find((item: LedgerAccount) => item.id === this.toAccountId)?.kind !== 'liability') {
          this.showError(ExpenseErrorField.Accounts, '请选择负债账户作为还款账户'); return;
        }
      }
      const gross = ExpenseAmountInput.evaluate(this.expression, this.amountCurrency());
      const reduction = ExpenseAmountInput.evaluateDiscount(this.effectiveDiscount() || '0', this.amountCurrency());
      const paid = ExpenseAmountInput.paidAmount(this.expression, this.effectiveDiscount(), this.amountCurrency());
      if (gross.minor <= BigInt(0) || reduction.minor < BigInt(0) || paid.minor <= BigInt(0)) {
        const field = !this.isIncome && !this.isTransfer && gross.minor > BigInt(0) ?
          ExpenseErrorField.Discount : ExpenseErrorField.Amount;
        this.showError(field, field === ExpenseErrorField.Discount ? '优惠须小于原金额' : '金额须大于 0'); return;
      }
      if (!this.isTransfer && !this.prepaidMode() && this.selectedId.length === 0) { this.showError(ExpenseErrorField.Category, '请选择收支分类'); return; }
      if (this.isTransfer && (!this.accountId || !this.toAccountId || this.accountId === this.toAccountId)) {
        this.showError(ExpenseErrorField.Accounts, '请选择两个不同的转出和转入账户'); return;
      }
      if (this.prepaidMode() && !this.accountId) {
        this.showError(ExpenseErrorField.Accounts, '预付款需要选择付款账户');
        this.keyboardVisible = false;
        this.optionKind = 1;
        this.showOptions = true;
        return;
      }
      const account = this.accountId.length > 0 ? this.accountId : undefined;
      command = { id: this.saveId, bookId: this.bookId, categoryId: this.isTransfer ? 'transfer' : this.selectedId, gross: gross,
        discount: reduction, bookPaid: this.prepaidMode() ? this.prepaidCost(paid) : this.converted(paid, 'CNY', this.bookRate),
        bookFx: this.fxQuote(this.bookRate), accountFx: this.fxQuote(this.settlementRate, this.actualSettlement.length > 0),
        accountId: this.isTransfer ? undefined : account,
        accountPaid: this.isTransfer || account === undefined ? undefined : this.settlementAmount(paid),
        reimbursementPending: !this.isIncome && !this.isTransfer && this.reimbursementPending,
        includeInAssets: this.includeAssets, includeInBudget: !this.isIncome && !this.isTransfer && this.includeBudget,
        spendingNatureId: !this.isIncome && !this.isTransfer && this.selectedNatureId.length > 0 ? this.selectedNatureId : undefined,
        tagIds: this.selectedTagIds,
        attachments: this.attachmentDrafts(),
        merchantName: this.merchantName.trim(), addressText: this.addressText.trim(), location: this.location || null,
        note: this.note.trim(),
        occurredAtMs: new Date(this.occurredAtMs).getTime(), localDate: this.localDate(),
        timezone: this.editingEntry !== undefined && !this.dateEdited ? this.editingEntry.timezone : Intl.DateTimeFormat().resolvedOptions().timeZone,
        offsetMinutes: this.editingEntry !== undefined && !this.dateEdited ? this.editingEntry.offsetMinutes : -new Date(this.occurredAtMs).getTimezoneOffset() };
    } catch (_) { this.showError(ExpenseErrorField.Amount, '请检查金额、小数位和汇率；外币须填写汇率后保存'); return; }
    this.saving = true;
    this.onSavingChange(true);
    try {
      const workspace = this.workspace;
      if (workspace === undefined) { throw new Error('WORKSPACE_UNAVAILABLE'); }
      if (this.prepaidMode()) { await this.savePrepaid(workspace,command); }
      else if (this.isTransfer) {
        const transfer: TransferCommand = { id: command.id, bookId: command.bookId, fromAccountId: this.accountId,
          toAccountId: this.toAccountId, amount: command.gross, purpose: this.transferPurpose,
          received: this.settlementAmount(command.gross), bookAmount: command.bookPaid, bookFx: command.bookFx,
          settlementFx: this.fxQuote(this.settlementRate, this.actualSettlement.length > 0),
          bookFee: this.converted(ExpenseAmountInput.evaluateDiscount(this.transferFee, this.amountCurrency()), 'CNY', this.bookRate),
          fee: ExpenseAmountInput.evaluateDiscount(this.transferFee, this.amountCurrency()),
          coupon: ExpenseAmountInput.evaluateDiscount(this.transferCoupon, this.amountCurrency()), feeInBudget: this.feeBudget, includeInAssets: command.includeInAssets,
          tagIds: this.selectedTagIds, attachments: command.attachments,
          merchantName: command.merchantName, addressText: command.addressText, location: command.location,
          note: command.note, occurredAtMs: command.occurredAtMs, localDate: command.localDate,
          timezone: command.timezone, offsetMinutes: command.offsetMinutes };
        if (this.editingEntry !== undefined) { await workspace.updateTransfer(transfer, this.editingEntry.revision); }
        else { await workspace.saveTransfer(transfer); }
      } else if (this.isIncome) {
        const income: IncomeCommand = { id: command.id, bookId: command.bookId, categoryId: command.categoryId,
          amount: command.gross, bookAmount: command.bookPaid, bookFx: command.bookFx, accountFx: command.accountFx, accountId: command.accountId, accountAmount: command.accountPaid,
          includeInAssets: command.includeInAssets, tagIds: this.selectedTagIds,
          merchantName: command.merchantName, addressText: command.addressText, location: command.location,
          attachments: command.attachments, note: command.note, occurredAtMs: command.occurredAtMs,
          localDate: command.localDate, timezone: command.timezone, offsetMinutes: command.offsetMinutes };
        if (this.editingEntry !== undefined) { await workspace.updateIncome(income, this.editingEntry.revision); }
        else { await workspace.saveIncome(income); }
      } else if (this.editingEntry !== undefined) { await workspace.updateExpense(command, this.editingEntry.revision); }
      else { await workspace.saveExpense(command); }
      this.saved = true;
      this.onSaved(command.localDate);
    } catch (error) {
      if (this.prepaidMode()) { this.showError(ExpenseErrorField.Save,'预付款保存未确认，请到“预付款与核销”中检查，避免重复付款'); return; }
      if (this.editingEntry !== undefined && (error as Error).message === 'TRANSACTION_CHANGED') {
        this.conflicted = true;
        this.showError(ExpenseErrorField.Save, '账目已变更或删除，请返回详情刷新后再编辑');
        return;
      }
      if ((error as Error).message.includes('RECOVERY_EXCEEDS_PAID')) {
        this.showError(ExpenseErrorField.Save, '实付金额不能低于已经报销和退款的合计金额，请先调整回款记录'); return;
      }
      // A retained id prevents a retry from recording the same command twice after an uncertain failure.
      this.showError(ExpenseErrorField.Save, '保存未确认，请勿重复记账。关闭后检查首页，或稍后重试');
    } finally { this.saving = false; this.onSavingChange(false); }
  }

  @Builder
  private errorMessage() {
    Text(this.errorText).width('100%').fontSize('12fp').fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.xq_warning')).id('expense-error')
  }

  @Builder
  private categoryItem(item: ExpenseCategory, compact: boolean = false, secondRow: boolean = false) {
    Column({ space: compact ? 2 : 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        CategoryIconBadge({ icon: categoryIcon(item.iconKey, this.isIncome), badgeSize: compact ? 36 : 44, glyphSize: compact ? 26 : 30 })
        if (this.activeCategories().some((child: ExpenseCategory) => child.parentId === item.id)) {
          Image($r('app.media.lucide_ellipsis1')).width(14).height(14)
            .fillColor($r('app.color.xq_icon_emphasize')).offset({ x: 8, y: -4 })
        }
      }
      if (!compact) {
        Text(item.name).fontSize('12fp').maxLines(1)
          .fontColor(this.selectedId === item.id ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_secondary'))
      }
    }.width(compact ? 56 : '25%').height(compact ? 48 : 80).justifyContent(FlexAlign.Center)
      .opacity(secondRow ? 1 - this.categoryCollapse / 80 : 1)
      .id('expense-category-' + item.id + (compact ? '-compact' : ''))
      .accessibilityText('收支分类' + item.name).onClick(() => { this.choose(item); })
  }

  @Builder
  private categoryCard() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Row() {
          Text(this.prepaidMode() ? '核销分类（预设）' : this.isIncome ? '收入分类' : '支出分类').fontSize('14fp').fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.xq_font_primary')).margin({ left: 8 }).id('expense-category-title')
          Blank()
          this.managementButton('管理分类', 'categories', 'expense-manage-categories')
        }.height(28).width('100%')
        Swiper() {
          ForEach(Array.from({ length: Math.ceil(this.roots().length / this.categoryPageSize()) }, (_value: number, index: number) => index), (page: number) => {
            Column() {
              Column() {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.roots().slice(page * this.categoryPageSize(), (page + 1) * this.categoryPageSize()),
                    (item: ExpenseCategory, index: number) => { this.categoryItem(item, false, index >= 4) },
                    (item: ExpenseCategory) => item.id)
                }.width('100%').height(this.compactCategories ? 80 : 160).flexShrink(0)
              }.width('100%').height(160 - this.categoryCollapse).clip(true).flexShrink(0)
            }.width('100%').height(180 - this.categoryCollapse).clip(true)
          }, (page: number) => this.categoryPageSize() + '-' + page)
        }.height(180 - this.categoryCollapse).index(this.categoryPage).loop(false)
          .onChange((page: number) => { this.categoryPage = page; })
          .id(this.compactCategories ? 'expense-categories-compact' : 'expense-categories-expanded')
          .indicator(Indicator.dot().itemWidth(5).itemHeight(5).selectedItemWidth(12)
          .selectedItemHeight(5).selectedColor($r('app.color.xq_brand')))
        if (this.errorText.length > 0 && this.errorField === ExpenseErrorField.Category) {
          Row() { this.errorMessage() }.width('100%').padding({ left: 8, right: 8, bottom: 8 })
        }
      }.padding({ top: 12, left: 8, right: 8, bottom: 4 }).width('100%')
        .backgroundColor($r('app.color.xq_app_surface_card')).borderRadius(20)
      Polygon().points([[0, 10], [12, 0], [24, 10]]).width(24).height(10)
        .fill($r('app.color.xq_app_surface_card')).margin({ right: 16 }).offset({ y: -8 })
    }.id('expense-categories').width('100%').margin({ top: 14, bottom: 12 })
      .parallelGesture(PanGesture({ direction: PanDirection.Vertical, distance: 8 })
        .onActionStart(() => { this.categoryDragY = 0; })
        .onActionUpdate((event: GestureEvent) => {
          const remaining = this.consumeCategoryScroll(this.categoryDragY - event.offsetY);
          this.categoryDragY = event.offsetY;
          if (Math.abs(remaining) > 0.01) { this.scroller.scrollBy(0, remaining); }
        })
        .onActionEnd(() => { this.settleCategories(); })
        .onActionCancel(() => { this.settleCategories(); }))
  }

  @Builder
  private field(label: string, value: string, action: () => void) {
    Row({ space: 12 }) {
      Text(label).fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
      Blank()
      Text(value).fontSize('14fp').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor($r('app.color.xq_font_primary')).constraintSize({ maxWidth: '70%' })
      Image($r('app.media.lucide_chevron_down1')).width(14).height(14).fillColor($r('app.color.xq_icon_tertiary'))
    }.height(48).width('100%').onClick(action)
  }

  @Builder
  private spendingNatureSelector() {
    Column({ space: 12 }) {
      Row({ space: 6 }) {
        Text('预算分类').fontSize('14fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
        Image($r('app.media.lucide_info1')).width(16).height(16).fillColor($r('app.color.xq_icon_tertiary'))
          .accessibilityText('查看预算分类说明')
          .onClick(() => { this.activeHelp = this.activeHelp === 'nature' ? '' : 'nature'; })
          .bindPopup(this.activeHelp === 'nature', {
            message: '用于月度分类预算和支出目的分析；可以不选，不影响金额、账户或收支分类。',
            placement: Placement.Top, autoCancel: true,
            onStateChange: (event) => { if (!event.isVisible && this.activeHelp === 'nature') { this.activeHelp = ''; } }
          })
        Blank()
        if (this.selectedNatureId.length > 0) {
          Button('清除', { type: ButtonType.Capsule }).height(28).fontSize('12fp')
            .fontColor($r('app.color.xq_font_secondary')).backgroundColor(Color.Transparent)
            .id('expense-nature-clear').onClick(() => { this.selectedNatureId = ''; })
        }
        this.managementButton('管理', 'natures', 'expense-manage-natures')
      }.height(28).width('100%')
      if (this.spendingNatures.length === 0) {
        Text('暂无预算分类，可通过右上角管理入口新建。').fontSize('12fp')
          .fontColor($r('app.color.xq_font_secondary')).width('100%')
      }
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.spendingNatures, (nature: SpendingNatureChoice) => {
          Button(nature.name, { type: ButtonType.Capsule }).height(38).fontSize('14fp')
            .fontColor(spendingNatureText(nature.colorKey))
            .backgroundColor(spendingNatureBackground(nature.colorKey))
            .border({ width: 1.5,
              color: this.selectedNatureId === nature.id ? spendingNatureText(nature.colorKey) : spendingNatureBackground(nature.colorKey) })
            .margin({ right: 8, bottom: 8 })
            .id('expense-nature-' + nature.id)
            .onClick(() => { this.selectedNatureId = nature.id; })
        }, (nature: SpendingNatureChoice) => nature.id)
      }.width('100%')
    }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      .id('expense-spending-nature')
  }

  private openTagPicker(): void {
    if (this.saving || this.saved || this.conflicted || this.attachmentBusy || this.mapBusy) { return; }
    this.amountController.stopEditing();
    this.getUIContext().getFocusController().clearFocus();
    this.keyboardVisible = false; this.noteEditing = false;
    this.tagSearch = ''; this.showTagPicker = true;
  }

  private tagSheetOptions(): SheetOptions {
    const options: SheetOptions = { height: 480, showClose: true };
    if (this.sheetMaterial !== undefined) { options.systemMaterial = this.sheetMaterial; }
    else { options.backgroundColor = $r('app.color.xq_app_surface_card'); }
    return options;
  }

  @Builder
  private tagSelector() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      ForEach(this.tags.filter((tag: TagChoice) => this.selectedTagIds.includes(tag.id)), (tag: TagChoice) => {
        Button({ type: ButtonType.Capsule }) {
          Row({ space: 4 }) {
            Text('#' + tag.name).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
              .constraintSize({ maxWidth: 180 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Image($r('app.media.lucide_x1')).width(12).height(12).fillColor($r('app.color.xq_icon_secondary'))
          }
        }.height(28).padding({ left: 8, right: 8 }).margin({ right: 8, bottom: 8 })
          .backgroundColor($r('app.color.xq_app_surface_page'))
          .accessibilityText('移除标签' + tag.name).id('expense-tag-' + tag.id)
          .onClick(() => { this.toggleTag(tag.id); })
      }, (tag: TagChoice) => tag.id)
      Button('＋ 添加标签', { type: ButtonType.Capsule }).height(28).padding({ left: 10, right: 10 })
        .margin({ right: 8, bottom: 8 }).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        .backgroundColor($r('app.color.xq_app_surface_page'))
        .id('expense-add-tags').onClick(() => { this.openTagPicker(); })
        .bindSheet($$this.showTagPicker, this.tagPicker(), this.tagSheetOptions())
    }.width('100%').id('expense-tags')
  }

  @Builder
  private tagPicker() {
    Column({ space: 12 }) {
      Row() {
        Text('选择标签').fontSize('20fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
        Blank()
        this.managementButton('管理', 'tags', 'expense-manage-tags')
      }.width('100%').padding({ right: 40 })
      TextInput({ text: this.tagSearch, placeholder: '搜索标签' }).height(40).fontSize('14fp')
        .backgroundColor($r('app.color.xq_app_surface_page')).borderRadius(12)
        .onChange((value: string) => { this.tagSearch = value; }).id('expense-tag-search')
      Scroll() {
        Column() {
          ForEach(this.tags.filter((tag: TagChoice) => tag.name.toLowerCase().includes(this.tagSearch.trim().toLowerCase())), (tag: TagChoice) => {
            Row({ space: 12 }) {
              Text('# ' + tag.name).fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
                .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Checkbox({ name: tag.id }).select(this.selectedTagIds.includes(tag.id))
                .selectedColor($r('app.color.xq_brand'))
                .enabled(this.selectedTagIds.includes(tag.id) || this.selectedTagIds.length < 20)
                .onChange((selected: boolean) => { if (selected !== this.selectedTagIds.includes(tag.id)) { this.toggleTag(tag.id); } })
                .accessibilityText(tag.name).id('expense-tag-choice-' + tag.id)
            }.height(48).width('100%')
          }, (tag: TagChoice) => tag.id)
          if (this.tags.length === 0) {
            Button('添加标签').fontSize('14fp').fontColor($r('app.color.xq_font_emphasize'))
              .backgroundColor(Color.Transparent).onClick(() => { this.openManagement('tags'); })
          } else if (!this.tags.some((tag: TagChoice) => tag.name.toLowerCase().includes(this.tagSearch.trim().toLowerCase()))) {
            Text('没有匹配的标签').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).padding(16)
          }
        }.width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off)
      Button('完成（已选 ' + this.selectedTagIds.length + '）', { type: ButtonType.Capsule })
        .width('100%').height(44).fontSize('14fp').fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.xq_font_on_primary')).backgroundColor($r('app.color.xq_brand'))
        .id('expense-tag-done').onClick(() => { this.showTagPicker = false; })
    }.width('100%').height('100%').padding(24)
  }

  @Builder
  private ruleSelect(budget: boolean) {
    if (this.sheetMaterial !== undefined) {
      Select([{ value: '计入' }, { value: '不计入' }]).selected((budget ? this.includeBudget : this.includeAssets) ? 0 : 1)
        .value((budget ? this.includeBudget : this.includeAssets) ? '计入' : '不计入')
        .font({ size: '14fp' }).fontColor($r('app.color.xq_font_primary')).height(40).width(88)
        .optionFontColor($r('app.color.xq_font_primary'))
        .selectedOptionFontColor($r('app.color.xq_font_emphasize'))
        .selectedOptionBgColor($r('app.color.xq_comp_emphasize_tertiary'))
        .backgroundColor(Color.Transparent).id(budget ? 'expense-budget-rule' : 'expense-assets-rule')
        .menuSystemMaterial(this.sheetMaterial)
        .onSelect((index: number) => {
          if (budget) { this.includeBudget = index === 0; } else { this.includeAssets = index === 0; }
        })
    } else {
      Select([{ value: '计入' }, { value: '不计入' }]).selected((budget ? this.includeBudget : this.includeAssets) ? 0 : 1)
        .value((budget ? this.includeBudget : this.includeAssets) ? '计入' : '不计入')
        .font({ size: '14fp' }).fontColor($r('app.color.xq_font_primary')).height(40).width(88)
        .optionFontColor($r('app.color.xq_font_primary'))
        .selectedOptionFontColor($r('app.color.xq_font_emphasize'))
        .selectedOptionBgColor($r('app.color.xq_comp_emphasize_tertiary'))
        .backgroundColor(Color.Transparent).id(budget ? 'expense-budget-rule' : 'expense-assets-rule')
        .onSelect((index: number) => {
          if (budget) { this.includeBudget = index === 0; } else { this.includeAssets = index === 0; }
        })
    }
  }

  @Builder
  private rules() {
    Row({ space: 8 }) {
      if (!this.isIncome && !this.isTransfer) {
        Text('预算').fontSize('14fp').fontWeight(FontWeight.Regular).fontColor($r('app.color.xq_font_secondary'))
        Image($r('app.media.lucide_info1')).width(16).height(16).fillColor($r('app.color.xq_icon_tertiary'))
          .accessibilityText('查看预算说明')
          .onClick(() => { this.activeHelp = this.activeHelp === 'budget' ? '' : 'budget'; })
          .bindPopup(this.activeHelp === 'budget', {
            message: '计入后，实付金额参与预算统计；不计入则不占用预算。',
            placement: Placement.Top, autoCancel: true,
            onStateChange: (event) => { if (!event.isVisible && this.activeHelp === 'budget') { this.activeHelp = ''; } }
          })
        this.ruleSelect(true)
        Blank()
      }
      Text('资产').fontSize('14fp').fontWeight(FontWeight.Regular).fontColor($r('app.color.xq_font_secondary'))
      Image($r('app.media.lucide_info1')).width(16).height(16).fillColor($r('app.color.xq_icon_tertiary'))
        .accessibilityText('查看资产说明')
        .onClick(() => { this.activeHelp = this.activeHelp === 'assets' ? '' : 'assets'; })
        .bindPopup(this.activeHelp === 'assets', {
          message: this.isTransfer ? '计入后，同时改变转出和转入账户余额；不计入则双方余额都不改变。' :
            '计入后，影响所选账户余额；不计入或未选择账户时不影响余额。',
          placement: Placement.Top, autoCancel: true,
          onStateChange: (event) => { if (!event.isVisible && this.activeHelp === 'assets') { this.activeHelp = ''; } }
        })
      this.ruleSelect(false)
    }.width('100%').height(52).padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.xq_app_surface_card')).borderRadius(16)
  }

  private pickDate(): void {
    this.amountController.stopEditing();
    let accepted: Date | undefined = undefined;
    this.getUIContext().showDatePickerDialog({ selected: this.wallDate(),
      selectedTextStyle: { color: $r('app.color.xq_font_emphasize') },
      acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      cancelButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      onDateAccept: (date: Date) => {
        const next = this.wallDate();
        if (next.getFullYear() !== date.getFullYear() || next.getMonth() !== date.getMonth() || next.getDate() !== date.getDate()) {
          next.setFullYear(date.getFullYear(), date.getMonth(), date.getDate());
          this.dateEdited = true; this.occurredAtMs = next.getTime();
        }
        this.occurredAtLabel = this.dateLabel();
        accepted = this.wallDate();
      },
      onDidDisappear: () => {
        if (!this.active) { return; }
        if (accepted !== undefined) { this.pickTime(accepted); }
        else { this.focusAmountAfterFrame(); }
      }
    });
  }

  private pickTime(selected: Date): void {
    this.getUIContext().showTimePickerDialog({ selected: selected, useMilitaryTime: true,
      selectedTextStyle: { color: $r('app.color.xq_font_emphasize') },
      acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      cancelButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      onAccept: (result: TimePickerResult) => {
        const value = this.wallDate();
        if (value.getHours() !== (result.hour ?? 0) || value.getMinutes() !== (result.minute ?? 0)) {
          value.setHours(result.hour ?? 0, result.minute ?? 0, 0, 0);
          this.dateEdited = true; this.occurredAtMs = value.getTime();
        }
        this.occurredAtLabel = this.dateLabel();
      },
      onDidDisappear: () => { this.focusAmountAfterFrame(); }
    });
  }

  @Builder
  private transferAccountSide(outgoing: boolean) {
    Column({ space: 10 }) {
      Text(outgoing ? '转出账户' : '转入账户').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        .id(outgoing ? 'expense-account-label' : 'expense-to-account-label')
      Row({ space: 8 }) {
        // Read selection state here instead of passing a captured ID through a Builder.
        if (this.accountProfiles.find((item: AccountProfile) => item.id === (outgoing ? this.accountId : this.toAccountId)) !== undefined) {
          AccountAvatar({
            iconKey: this.accountProfiles.find((item: AccountProfile) => item.id === (outgoing ? this.accountId : this.toAccountId))!.iconKey,
            brandColor: this.accountProfiles.find((item: AccountProfile) => item.id === (outgoing ? this.accountId : this.toAccountId))!.brandColor,
            iconVariant: this.accountProfiles.find((item: AccountProfile) => item.id === (outgoing ? this.accountId : this.toAccountId))!.iconVariant,
            diameter: 18 }).flexShrink(0)
        }
        Text(this.accounts.find((item: LedgerAccount) => item.id === (outgoing ? this.accountId : this.toAccountId))?.name || '选择账户')
          .fontSize('16fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
          .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .id(outgoing ? 'expense-account-value' : 'expense-to-account-value')
        Image($r('app.media.lucide_chevron_down1')).width(14).height(14).fillColor($r('app.color.xq_icon_tertiary'))
      }.width('100%').constraintSize({ minHeight: 28 })
    }.layoutWeight(1).alignItems(HorizontalAlign.Start).constraintSize({ minHeight: 64 })
      .id(outgoing ? 'transfer-account-from' : 'transfer-account-to')
      .onClick(() => { this.optionKind = outgoing ? 1 : 2; this.showOptions = true; })
  }

  @Builder
  private attachmentSection() {
    Column({ space: 12 }) {
      Row() {
        Text('图片附件').fontSize('14fp').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.xq_font_primary'))
        Blank()
        Text(`${this.attachments.length} / 9`).fontSize('12fp').fontWeight(FontWeight.Regular)
          .fontColor($r('app.color.xq_font_tertiary'))
      }.width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.attachments, (attachment: ExpenseImageAttachment) => {
          Stack({ alignContent: Alignment.TopEnd }) {
            Image('file://' + attachment.filePath).width('100%').height('100%')
              .objectFit(ImageFit.Cover).backgroundColor($r('app.color.xq_app_surface_page'))
              .accessibilityText('已添加的账目图片')
            Button({ type: ButtonType.Circle }) {
              Image($r('app.media.lucide_x1')).width(14).height(14).fillColor(Color.White)
            }.width(24).height(24).padding(0).backgroundColor('#99000000').margin(4)
              .enabled(!this.attachmentBusy && !this.saving && !this.saved && !this.conflicted)
              .accessibilityText('删除图片').onClick(() => { this.removeAttachment(attachment.sha256); })
          }.width(84).height(84).borderRadius(8).clip(true).margin({ right: 10, bottom: 10 })
        }, (attachment: ExpenseImageAttachment) => attachment.sha256)
        if (this.attachments.length < 9) {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 6 }) {
              if (this.attachmentBusy) {
                LoadingProgress().width(24).height(24).color($r('app.color.xq_icon_secondary'))
                Text('读取中').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
              } else {
                Image($r('app.media.lucide_camera1')).width(28).height(28)
                  .fillColor($r('app.color.xq_icon_tertiary'))
              }
            }.width('100%').height('100%').justifyContent(FlexAlign.Center)
          }.width(84).height(84).padding(0).borderRadius(8)
            .backgroundColor($r('app.color.xq_app_surface_page')).margin({ right: 10, bottom: 10 })
            .enabled(!this.attachmentBusy && !this.saving && !this.saved && !this.conflicted)
            .accessibilityText(this.attachmentBusy ? '正在读取图片' : '添加原图')
            .id('expense-attachment-add').onClick(() => { this.chooseImages(); })
        }
      }.width('100%').id('expense-attachment-list')
      if (this.errorText.length > 0 && this.errorField === ExpenseErrorField.Attachments) { this.errorMessage() }
    }.width('100%').id('expense-attachment-card')
  }

  @Builder
  private supplementaryCard() {
    Column({ space: 12 }) {
      TextArea({ text: this.note, placeholder: '点击输入备注' }).id('expense-note').height(112).width('100%')
        .fontSize('14fp').fontWeight(FontWeight.Regular).fontColor($r('app.color.xq_font_primary'))
        .placeholderFont({ size: '14fp', weight: FontWeight.Regular })
        .placeholderColor($r('app.color.xq_font_secondary'))
        .backgroundColor($r('app.color.xq_app_surface_page')).borderRadius(8).padding(12).maxLength(500)
        .onFocus(() => { this.keyboardVisible = false; })
        .onEditChange((editing: boolean) => { this.noteEditing = editing; })
        .onChange((value: string) => { this.note = value; })
      this.tagSelector()
      Divider().color($r('app.color.xq_comp_background_tertiary'))
      this.attachmentSection()
    }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      .id('expense-supplementary-card')
  }

  @Builder
  private form() {
    Column({ space: 12 }) {
      this.fxCard()
      if (this.isTransfer) {
        Row() {
          Text('用途').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
          Blank()
          Text(transferPurposeLabel(this.transferPurpose)).fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
          Image($r('app.media.lucide_chevron_down1')).width(14).height(14).fillColor($r('app.color.xq_icon_tertiary'))
        }.height(48).padding({ left: 16, right: 16 }).width('100%').borderRadius(16)
          .backgroundColor($r('app.color.xq_app_surface_card')).id('transfer-purpose')
          .onClick(() => { this.optionKind = 3; this.showOptions = true; })
        Column({ space: 4 }) {
          Row({ space: 12 }) {
            this.transferAccountSide(true)
            Button({ type: ButtonType.Circle }) {
              Image($r('app.media.lucide_arrow_left_right1')).width(22).height(22).fillColor($r('app.color.xq_icon_secondary'))
            }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
              .enabled(!this.saving && !this.saved && !this.conflicted).id('transfer-swap-accounts')
              .accessibilityText('交换转出和转入账户').onClick(() => {
                if (this.isRepayment() && this.accounts.find((item: LedgerAccount) => item.id === this.accountId)?.kind !== 'liability') {
                  this.showError(ExpenseErrorField.Accounts, '还款的转入账户须为负债账户'); return;
                }
                const previous = this.accountId; this.accountId = this.toAccountId; this.toAccountId = previous;
                this.clearFieldError(ExpenseErrorField.Accounts);
              })
            this.transferAccountSide(false)
          }.width('100%')
          if (this.errorText.length > 0 && this.errorField === ExpenseErrorField.Accounts) { this.errorMessage() }
        }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
          .id('transfer-accounts-card')
        Row() {
          Text(this.isRepayment() ? '本金与还款优惠不计收支' : '本金不计入收支').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
          Blank()
          Text('手续费计入支出').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        }.width('100%').padding({ left: 4, right: 4 })
      }
      Column() {
        if (!this.isTransfer) {
          // Direct state binding keeps account changes visible after the Sheet closes.
          Row({ space: 12 }) {
            Text(this.isIncome ? '收款账户' : '付款账户').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
              .id('expense-account-label')
            Blank()
            Row({ space: 6 }) {
              if (this.accountProfiles.find((item: AccountProfile) => item.id === this.accountId) !== undefined) {
                AccountAvatar({ iconKey: this.accountProfiles.find((item: AccountProfile) => item.id === this.accountId)!.iconKey,
                  brandColor: this.accountProfiles.find((item: AccountProfile) => item.id === this.accountId)!.brandColor,
                  iconVariant: this.accountProfiles.find((item: AccountProfile) => item.id === this.accountId)!.iconVariant,
                  diameter: 18 }).flexShrink(0)
              }
              Text(this.accounts.find((item: LedgerAccount) => item.id === this.accountId)?.name || (this.prepaidMode() ? '请选择付款账户' : '不使用账户'))
                .fontSize('14fp').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor($r('app.color.xq_font_primary')).flexShrink(1).id('expense-account-value')
            }.constraintSize({ maxWidth: '70%' }).alignItems(VerticalAlign.Center)
            Image($r('app.media.lucide_chevron_down1')).width(14).height(14).fillColor($r('app.color.xq_icon_tertiary'))
          }.height(48).width('100%').onClick(() => { this.optionKind = 1; this.showOptions = true; })
          if (this.errorText.length > 0 && this.errorField === ExpenseErrorField.Accounts) {
            this.errorMessage()
          }
          Divider().color($r('app.color.xq_comp_background_tertiary'))
        }
        Row({ space: 10 }) {
          Text('时间').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
          Blank()
          Text(this.occurredAtLabel).fontSize('14fp').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.xq_font_primary'))
            .constraintSize({ maxWidth: '70%' }).id('expense-date-value')
          Image($r('app.media.lucide_chevron_down1')).width(14).height(14).fillColor($r('app.color.xq_icon_tertiary'))
        }.height(48).width('100%').onClick(() => { this.pickDate(); })
        Divider().color($r('app.color.xq_comp_background_tertiary'))
        Row({ space: 12 }) {
          Text('商户').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
          TextInput({ text: this.merchantName, placeholder: '填写商户（选填）' })
            .id('expense-merchant').accessibilityText('商户').layoutWeight(1).height(48).fontSize('14fp')
            .fontWeight(FontWeight.Regular).fontColor($r('app.color.xq_font_primary'))
            .placeholderFont({ size: '14fp', weight: FontWeight.Regular })
            .placeholderColor($r('app.color.xq_font_secondary'))
            .backgroundColor(Color.Transparent).padding(0)
            .onFocus(() => { this.keyboardVisible = false; })
            .onEditChange((editing: boolean) => { this.noteEditing = editing; })
            .onChange((value: string) => { this.merchantName = value; })
            .onSubmit(() => { this.focusAmountAfterFrame(); })
        }.width('100%')
        Divider().color($r('app.color.xq_comp_background_tertiary'))
        Row({ space: 12 }) {
          Text('地址').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
          TextInput({ text: this.addressText, placeholder: '填写地址（选填）' })
            .id('expense-address').accessibilityText('地址').layoutWeight(1).height(48).fontSize('14fp')
            .fontWeight(FontWeight.Regular).fontColor($r('app.color.xq_font_primary'))
            .placeholderFont({ size: '14fp', weight: FontWeight.Regular })
            .placeholderColor($r('app.color.xq_font_secondary'))
            .backgroundColor(Color.Transparent).padding(0)
            .onFocus(() => { this.keyboardVisible = false; })
            .onEditChange((editing: boolean) => { this.noteEditing = editing; })
            .onChange((value: string) => { this.changeAddress(value); })
            .onSubmit(() => { this.focusAmountAfterFrame(); })
          Button(this.mapBusy ? '打开中' : '地图选点', { type: ButtonType.Capsule })
            .fontSize('14fp').fontWeight(FontWeight.Medium).height(32).padding({ left: 10, right: 10 })
            .fontColor($r('app.color.xq_font_emphasize')).backgroundColor(Color.Transparent)
            .enabled(!this.mapBusy && !this.attachmentBusy && !this.saving && !this.saved && !this.conflicted)
            .id('expense-map-location').onClick(() => { this.chooseMapLocation(); })
        }.width('100%')
      }.padding({ left: 16, right: 16 }).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      if (!this.isIncome && !this.isTransfer) { this.spendingNatureSelector() }
      if (!this.isIncome && !this.isTransfer) {
        Column({ space: 12 }) {
          this.prepaidMarker()
          if (this.editingEntry === undefined) {
            Divider().color($r('app.color.xq_app_surface_page'))
          }
          Row() {
            Text('待报销').fontSize('14fp').fontWeight(FontWeight.Regular).fontColor($r('app.color.xq_font_primary'))
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.reimbursementPending })
              .selectedColor($r('app.color.xq_brand'))
              .enabled(!this.saving && !this.saved && !this.conflicted)
              .onChange((value: boolean) => {
                this.reimbursementPending = value;
                if (value) { this.prepaid = false; }
                this.errorText = '';
              })
              .id('expense-reimbursement-pending')
          }.width('100%')
        }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      }
      if (this.isTransfer) {
        Row() {
          Text('手续费计入预算').fontSize('14fp').fontColor($r('app.color.xq_font_primary'))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.feeBudget }).selectedColor($r('app.color.xq_brand'))
            .onChange((value: boolean) => { this.feeBudget = value; }).id('transfer-fee-budget')
        }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      }
      if (this.prepaidMode()) { this.prepaidRules() } else { this.rules() }
      this.supplementaryCard()
    }.width('100%').padding({ bottom: 24 })
  }

  private accountOptions(): LedgerAccount[] {
    return this.accounts.filter((item: LedgerAccount) =>
      (!this.isTransfer || this.optionKind !== 2 || !this.isRepayment() || item.kind === 'liability') &&
      (!this.isTransfer || item.id !== (this.optionKind === 2 ? this.accountId : this.toAccountId)));
  }

  private accountCardProfile(id: string): AccountProfile | undefined {
    return this.accountProfiles.find((item: AccountProfile) => item.id === id);
  }

  private coloredAccountCard(id: string): boolean {
    const profile = this.accountCardProfile(id);
    return profile !== undefined && profile.iconVariant !== 'color';
  }

  private accountCardBalance(id: string): string {
    const profile = this.accountCardProfile(id);
    if (profile === undefined) { return '余额暂不可用'; }
    const balance = Money.fromMinorText(profile.balanceMinor, currencyUnit(profile.currencyId));
    const parts = (balance.minor < BigInt(0) ? balance.negate() : balance).toDecimalString().split('.');
    return (balance.minor < BigInt(0) ? '−' : '') + parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',') + (parts.length > 1 ? '.' + parts[1] : '') + ' ' + profile.currencyId;
  }

  @Builder
  private accountOption(id: string, name: string) {
    Button({ type: ButtonType.Normal }) {
      Stack({ alignContent: Alignment.End }) {
        Row({ space: 10 }) {
          if (id.length === 0) {
            Image($r('app.media.lucide_wallet1')).width(30).height(30)
              .fillColor($r('app.color.xq_icon_secondary'))
          } else if (this.coloredAccountCard(id)) {
            Image(accountIcon(this.accountCardProfile(id)?.iconKey || 'bank_card')).width(32).height(32)
              .fillColor(Color.White)
          } else {
            AccountAvatar({ iconKey: this.accountCardProfile(id)?.iconKey || 'bank_card',
              brandColor: this.accountCardProfile(id)?.brandColor || '#5378B8', iconVariant: 'color', diameter: 44 })
          }
          Column({ space: 4 }) {
            Text(name).fontSize('14fp').fontWeight(FontWeight.Medium)
              .fontColor(this.coloredAccountCard(id) ? Color.White : $r('app.color.xq_font_primary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').textAlign(TextAlign.Start)
            if (id.length > 0) {
              Text(this.accountCardBalance(id)).fontSize('12fp').fontWeight(FontWeight.Regular)
                .fontColor(this.coloredAccountCard(id) ? '#E6FFFFFF' : $r('app.color.xq_font_secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').textAlign(TextAlign.Start)
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').height('100%').padding({ left: 16, right: 48 })
        if ((this.optionKind === 2 ? this.toAccountId : this.accountId) === id) {
          Row() {
            Image($r('app.media.lucide_check1')).width(14).height(14).fillColor('#202124')
          }.width(20).height(20).justifyContent(FlexAlign.Center).borderRadius(10)
            .backgroundColor(Color.White).border({ width: 1, color: '#D9DDE3' }).margin({ right: 16 })
        }
      }.width('100%').height('100%')
    }.height(72).width('100%').padding(0).borderRadius(14)
      .backgroundColor(this.coloredAccountCard(id) ? (this.accountCardProfile(id)?.brandColor || '#5378B8') :
        id.length === 0 ? $r('app.color.xq_app_surface_page') : $r('app.color.xq_app_surface_card'))
      .enabled(!this.saving && !this.saved && !this.conflicted)
      .accessibilityText(name + (id.length > 0 ? '，' + this.accountCardBalance(id) : ''))
      .accessibilityDescription((this.optionKind === 2 ? this.toAccountId : this.accountId) === id ? '已选中' : '未选中')
      .id('expense-account-option-' + (id || 'none'))
      .onClick(() => {
        if (this.optionKind === 2) { this.toAccountId = id; } else { this.accountId = id; }
        if (this.isTransfer && this.optionKind !== 2 && id.length > 0) {
          const code = this.accounts.find((item: LedgerAccount) => item.id === id)?.currencyId;
          if (code !== undefined && code !== this.currencyCode) { this.currencyCode = code; this.bookRate = ''; }
        }
        this.settlementRate = ''; this.actualSettlement = ''; this.quoteVersion++;
        this.clearFieldError(ExpenseErrorField.Accounts);
        this.showOptions = false;
      })
  }

  private optionSheetOptions(): SheetOptions {
    const options: SheetOptions = { height: this.optionKind === 0 ? 340 : 440, showClose: true,
      onDisappear: () => { this.focusAmountAfterFrame(); } };
    if (this.sheetMaterial !== undefined) {
      options.systemMaterial = this.sheetMaterial;
    } else {
      options.backgroundColor = $r('app.color.xq_app_surface_card');
    }
    return options;
  }

  @Builder
  private optionSheet() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(this.optionKind === 3 ? '转账用途' : this.optionKind === 0 ? (this.activeCategories().find((item: ExpenseCategory) => item.id === this.parentId)?.name || '选择收支分类') : (this.isTransfer ? (this.optionKind === 2 ? '转入账户' : '转出账户') : this.isIncome ? '收款账户' : '付款账户'))
          .fontSize('20fp').fontWeight(this.optionKind === 0 ? FontWeight.Bold : FontWeight.Medium)
          .fontColor($r('app.color.xq_font_primary')).layoutWeight(1).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.optionKind === 1 || this.optionKind === 2) {
          Button({ type: ButtonType.Capsule }) {
            Row({ space: 6 }) {
              Image($r('app.media.lucide_plus1')).width(16).height(16).fillColor($r('app.color.xq_font_emphasize'))
              Text('新增账户').fontSize('14fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_emphasize'))
            }
          }.height(36).padding({ left: 8, right: 8 })
            .backgroundColor(Color.Transparent).enabled(!this.saving && !this.mapBusy && !this.attachmentBusy)
            .id('expense-option-manage').onClick(() => { this.openManagement('accounts'); })
        }
      }.width('100%').padding({ right: this.optionKind === 0 ? 0 : 40 })
      if (this.optionKind === 3) {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(TRANSFER_PURPOSES, (item: TransferPurpose) => {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 12 }) {
                  Text(item.label).fontSize('14fp')
                    .fontWeight(this.transferPurpose === item.key ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor($r('app.color.xq_font_primary')).layoutWeight(1).textAlign(TextAlign.Start)
                  if (this.transferPurpose === item.key) {
                    Image($r('app.media.lucide_check1')).width(20).height(20).fillColor($r('app.color.xq_brand'))
                  }
                }.width('100%')
              }.height(52).width('100%').padding({ left: 16, right: 16 }).borderRadius(12)
                .backgroundColor(this.transferPurpose === item.key ? $r('app.color.xq_comp_emphasize_tertiary') : Color.Transparent)
                .accessibilityText(item.label).accessibilityDescription(this.transferPurpose === item.key ? '已选中' : '未选中')
                .id('transfer-purpose-option-' + item.key)
                .onClick(() => {
                  this.transferPurpose = item.key;
                  if (!item.repayment) { this.transferCoupon = '0'; this.clearFieldError(ExpenseErrorField.Coupon); }
                  if (item.repayment && this.accounts.find((account: LedgerAccount) => account.id === this.toAccountId)?.kind !== 'liability') { this.toAccountId = ''; }
                  this.clearFieldError(ExpenseErrorField.Accounts);
                  this.showOptions = false;
                })
            }, (item: TransferPurpose) => item.key)
          }.width('100%')
        }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off)
          .id('transfer-purpose-options')
      } else if (this.optionKind === 0) {
        Text('已选中父分类；关闭可保留，或继续选择子分类').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.children(), (item: ExpenseCategory) => { this.categoryItem(item) }, (item: ExpenseCategory) => item.id)
          }.width('100%')
        }.layoutWeight(1).width('100%')
      } else {
        Scroll() {
          Column({ space: 8 }) {
            if (!this.isTransfer && !this.prepaidMode()) { this.accountOption('', '不使用账户') }
            ForEach(this.accountOptions(), (item: LedgerAccount) => {
              this.accountOption(item.id, item.name)
            }, (item: LedgerAccount) => item.id)
            if (this.accountOptions().length === 0) {
              Text(this.prepaidMode() ? '预付款需要付款账户，请点击上方新增账户后继续保存。' : this.isTransfer ? '暂无可选账户，请新增账户或检查转出、转入账户是否不同。' : '暂无账户，可点击上方新增账户，也可以不使用账户记账。')
                .fontSize('12fp').fontWeight(FontWeight.Regular).fontColor($r('app.color.xq_font_secondary'))
                .padding(12).width('100%')
            }
          }.width('100%')
        }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring).id('expense-account-options')
      }
      if (this.optionKind === 0) {
        Row({ space: 12 }) {
          Button('管理分类', { type: ButtonType.Capsule })
            .height(44).layoutWeight(1).fontSize('14fp').fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.xq_font_on_primary')).backgroundColor($r('app.color.xq_brand'))
            .enabled(!this.saving && !this.mapBusy && !this.attachmentBusy)
            .id('expense-option-manage').onClick(() => { this.openManagement('categories'); })
          Button('关闭').layoutWeight(1).height(44).fontSize('14fp')
            .backgroundColor($r('app.color.xq_app_surface_page'))
            .fontColor($r('app.color.xq_font_primary')).onClick(() => { this.showOptions = false; })
        }.width('100%')
      }
    }.width('100%').height('100%').padding(24)
  }

  @Builder
  private resumeAmountButton() {
    if (this.sheetMaterial !== undefined) {
      Row() {
        Button('继续输入金额', { type: ButtonType.Capsule }).height(40).width('100%').fontSize('14fp').fontWeight(FontWeight.Medium)
          .backgroundColor(Color.Transparent)
          .systemMaterial(this.sheetMaterial)
          .fontColor($r('app.color.xq_font_emphasize')).id('expense-resume-amount')
          .onClick(() => { this.focusAmount(); })
      }.width('100%').height(40).borderRadius(20)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
        .id('expense-resume-surface-immersive')
    } else {
      Row() {
        Button('继续输入金额', { type: ButtonType.Capsule }).height(40).width('100%').fontSize('14fp').fontWeight(FontWeight.Medium)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.xq_font_emphasize')).id('expense-resume-amount')
          .onClick(() => { this.focusAmount(); })
      }.width('100%').height(40).borderRadius(20)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
        .border({ width: 1, color: '#66FFFFFF' })
        .shadow({ radius: 16, color: '#14000000', offsetY: 4 }).id('expense-resume-surface-blur')
    }
  }

  @Builder
  private keyboardHideIcon() {
    Image($r('app.media.lucide_chevron_down1')).width(20).height(20)
      .fillColor($r('app.color.xq_icon_secondary'))
  }

  @Builder
  private keyboardHide() {
    if (this.actionMaterial !== undefined) {
      Button({ type: ButtonType.Circle }) { this.keyboardHideIcon() }
        .width(32).height(32).padding(0).backgroundColor(Color.Transparent)
        .systemMaterial(this.actionMaterial).id('expense-hide-keyboard').accessibilityText('收起键盘')
        .onClick(() => { this.amountController.stopEditing(); })
    } else {
      Button({ type: ButtonType.Circle }) { this.keyboardHideIcon() }
        .width(32).height(32).padding(0).backgroundColor(Color.Transparent)
        .id('expense-hide-keyboard').accessibilityText('收起键盘')
        .onClick(() => { this.amountController.stopEditing(); })
    }
  }

  @Builder
  private transferExtraChip(target: number) {
    Row({ space: 6 }) {
      Text(target === 1 ? '手续费' : '还款优惠').fontSize('12fp')
      Text(target === 1 ? this.transferFee : this.transferCoupon).id(target === 1 ? 'transfer-fee-expression' : 'transfer-coupon-expression').fontSize('14fp').fontFamily('XiaoQiaoDINMedium').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
    }.height(32).padding({ left: 10, right: 10 }).constraintSize({ maxWidth: '38%' }).borderRadius(10)
      .backgroundColor(this.transferTarget === target ? $r('app.color.xq_brand') : $r('app.color.xq_app_surface_keyboard'))
      .foregroundColor(this.transferTarget === target ? $r('app.color.xq_font_on_primary') : $r('app.color.xq_font_primary'))
      .id(target === 1 ? 'transfer-fee-control' : 'transfer-coupon-control').onClick(() => { this.editTransferExtra(target); })
  }

  @Builder
  private settlement() {
    Row({ space: 8 }) {
      if (!this.isIncome && !this.isTransfer) {
        Row({ space: 8 }) {
          Text('优惠').fontSize('12fp').fontWeight(FontWeight.Medium)
            .fontColor(this.editingDiscount ? $r('app.color.xq_font_on_primary') : $r('app.color.xq_font_secondary'))
          Text(this.discount).id('expense-discount').maxLines(1).flexShrink(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize('14fp').fontFamily('XiaoQiaoDINMedium').fontWeight(FontWeight.Medium)
            .fontColor(this.editingDiscount ? $r('app.color.xq_font_on_primary') : $r('app.color.xq_font_primary'))
        }.height(32).constraintSize({ maxWidth: '48%' }).flexShrink(0)
          .padding({ left: 12, right: 12 }).borderRadius(10)
          .backgroundColor(this.editingDiscount ? $r('app.color.xq_brand') : $r('app.color.xq_app_surface_keyboard'))
          .id('expense-discount-control').accessibilityText('编辑优惠金额')
          .onClick(() => { this.editingDiscount = !this.editingDiscount; })
      }
      if (this.isTransfer) {
        this.transferExtraChip(1)
        if (this.isRepayment()) { this.transferExtraChip(2) }
      }
      Blank()
      this.keyboardHide()
    }.width('100%').height(36)
  }

  @Builder
  private keyboardToolbar() {
    this.settlement()
    if (this.errorText.length > 0 && (this.errorField === ExpenseErrorField.Discount ||
      this.errorField === ExpenseErrorField.Fee || this.errorField === ExpenseErrorField.Coupon)) {
      this.errorMessage()
    }
  }

  @Builder
  private keyboardFooter() {
    if (this.errorText.length > 0 && this.errorField === ExpenseErrorField.Save) { this.errorMessage() }
  }

  @Builder
  private amountKeyboard() {
    AmountKeyboard({
      prefix: 'expense',
      disabled: this.saving || this.saved || this.conflicted,
      canSubmit: !this.mapBusy && !this.attachmentBusy && this.canSaveAmounts(this.expression, this.discount),
      submitLabel: this.saving ? '保存中' : this.prepaidMode() ? '保存预付' : '保存',
      accessory: () => { this.keyboardToolbar() },
      footer: () => { this.keyboardFooter() },
      onKey: (key: string) => { this.press(key); }
    })
  }

  @Builder
  private title() {
    Row() {
      if (this.editingEntry !== undefined) {
        Text(this.isTransfer ? '编辑转账' : this.isIncome ? '编辑收入' : '编辑账目').fontSize('20fp').fontWeight(FontWeight.Bold).fontColor($r('app.color.xq_font_primary'))
          .id('expense-edit-title')
      } else if (this.chipMaterial !== undefined) {
        ChipGroup({
          items: [{ label: { text: '支出' }, allowClose: false }, { label: { text: '收入' }, allowClose: false },
            { label: { text: '转账' }, allowClose: false }],
          multiple: false, selectedIndexes: this.selectedKinds,
          itemStyle: { size: ChipSize.NORMAL, backgroundColor: $r('app.color.xq_app_filter_unselected'),
            fontColor: $r('app.color.xq_font_secondary'), selectedBackgroundColor: $r('app.color.xq_brand'),
            selectedFontColor: $r('app.color.xq_font_on_primary') },
          backgroundSystemMaterial: this.chipMaterial,
          chipGroupSpace: { startSpace: 0, endSpace: 0, itemSpace: 8 },
          chipGroupPadding: { top: 4, bottom: 4 },
          onChange: (selected: number[]) => { this.selectKind(selected); }
        }).width(224).id('expense-kind-selector')
      } else {
        ChipGroup({
          items: [{ label: { text: '支出' }, allowClose: false }, { label: { text: '收入' }, allowClose: false },
            { label: { text: '转账' }, allowClose: false }],
          multiple: false, selectedIndexes: this.selectedKinds,
          itemStyle: { size: ChipSize.NORMAL, backgroundColor: $r('app.color.xq_app_filter_unselected'),
            fontColor: $r('app.color.xq_font_secondary'), selectedBackgroundColor: $r('app.color.xq_brand'),
            selectedFontColor: $r('app.color.xq_font_on_primary') },
          chipGroupSpace: { startSpace: 0, endSpace: 0, itemSpace: 8 },
          chipGroupPadding: { top: 4, bottom: 4 },
          onChange: (selected: number[]) => { this.selectKind(selected); }
        }).width(224).id('expense-kind-selector')
      }
    }.width('100%').justifyContent(FlexAlign.Center)
  }

  build() {
    HdsNavigation() {
      Column() {
        Row({ space: 8 }) {
          Column() {
            Row({ space: 8 }) {
              Text(currencyDefinition(this.currencyCode).symbol).fontSize('14fp').fontColor($r('app.color.xq_font_tertiary'))
              TextInput({ text: this.expression, controller: this.amountController })
                .fontFamily('XiaoQiaoDINBold').fontWeight(FontWeight.Bold).fontSize('38fp').minFontSize('20fp').maxFontSize('38fp')
                .fontColor($r('app.color.xq_font_primary')).caretColor($r('app.color.xq_brand'))
                .backgroundColor(Color.Transparent).padding(0).borderRadius(0)
                .layoutWeight(1).id('expense-amount').copyOption(CopyOptions.None).selectionMenuHidden(true)
                .customKeyboard(this.amountKeyboard(), { supportAvoidance: true })
                .onEditChange((editing: boolean) => { this.keyboardVisible = editing; })
                .onClick(() => { this.editingDiscount = false; this.transferTarget = 0; })
                .onWillInsert((value: InsertValue): boolean => {
                  for (const character of value.insertValue) {
                    const key = character === '-' ? '−' : character;
                    if (/^[0-9.+−]$/.test(key)) { this.press(key); }
                  }
                  return false;
                })
                .onWillDelete((): boolean => { this.press('⌫'); return false; })
            }.height(48).width('100%')
            Text((this.isTransfer ? '实际转出 ' + this.transferOutgoingText() : (this.isIncome ? '收入 ' : '实付 ') + this.paidText()) + ' ' + this.currencyCode).fontSize('12fp').fontFamily('XiaoQiaoDINRegular').id('expense-paid')
              .width('100%').height(24).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Start)
              .accessibilityDescription(this.isIncome ? '点击编辑上方收入金额' : '点击编辑上方原金额').onClick(() => { this.focusAmountFromPaid(); })
            if (this.errorText.length > 0 && (this.errorField === ExpenseErrorField.Amount ||
              (!this.keyboardVisible && this.errorField !== ExpenseErrorField.Category && this.errorField !== ExpenseErrorField.Accounts))) {
              this.errorMessage()
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.isTransfer) {
            CategoryIconBadge({ icon: $r('app.media.colorful_icon00372'), badgeSize: 48, glyphSize: 32 })
          } else { CategoryIconBadge({ icon: categoryIcon(this.selected()?.iconKey || (this.isIncome ? 'other' : 'food'), this.isIncome), badgeSize: 48, glyphSize: 32 }) }
        }.padding(16).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
          .outlineWidth(2).outlineRadius(20)
          .outlineColor(this.amountFocusHighlight ? $r('app.color.xq_brand') : Color.Transparent)
          .id('expense-amount-card').onClick(() => { this.focusAmount(); })
        if (!this.isTransfer) { this.categoryCard() }
        Stack({ alignContent: Alignment.Bottom }) {
          Scroll(this.scroller) {
            Column() { this.form() }.width('100%')
              .padding({ bottom: this.keyboardVisible || this.noteEditing ? 0 : 56 })
          }.height('100%').width('100%').align(Alignment.Top).scrollBar(BarState.Off).id('expense-form-scroll')
            // Let the form scroll behind the system gesture bar; keep the floating button in the safe area.
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .onWillScroll((_x: number, y: number, _state: ScrollState, source: ScrollSource) => {
              if (this.isTransfer) { return { xOffset: 0, yOffset: y }; }
              if (source === ScrollSource.EDGE_EFFECT || source === ScrollSource.SCROLLER || source === ScrollSource.SCROLLER_ANIMATION) {
                return { xOffset: 0, yOffset: y };
              }
              return { xOffset: 0, yOffset: this.consumeCategoryScroll(y) };
            })
            .onScrollStop(() => { this.settleCategories(); })
          Column() {
            if (!this.keyboardVisible && !this.noteEditing) {
              Row({ space: 12 }) {
                Column() { this.resumeAmountButton() }.layoutWeight(1)
                if (!this.saved && !this.conflicted && this.canSaveAmounts(this.expression, this.discount)) {
                  Button(this.saving ? '保存中' : this.editingEntry !== undefined ? '保存修改' : this.prepaidMode() ? '保存预付款' : '保存账目',
                    { type: ButtonType.Capsule }).height(40).layoutWeight(1)
                    .fontSize('14fp').fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.xq_font_on_primary')).backgroundColor($r('app.color.xq_brand'))
                    .enabled(!this.saving && !this.mapBusy && !this.attachmentBusy)
                    .onClick(() => { this.save(); }).id('expense-save-without-keyboard')
                }
              }.width('100%')
            }
          }.width('100%').zIndex(1)
        }.layoutWeight(1).width('100%').margin({ top: this.isTransfer ? 12 : 0 })
      }.width('100%').height('100%').padding({ left: 16, right: 16, top: 8 })
        .constraintSize({ maxWidth: 720 }).align(Alignment.Top)
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false)
      .dynamicHideTitleBar({ hideTitleArea: false, hideBottomBuilder: false, hideStatusBar: false })
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: '' }, stackBuilder: this.title.bind(this),
        divider: { showType: DividerShowType.OFF }, backIcon: { componentId: 'expense-close', label: '关闭记一笔', action: () => { if (!this.saving) { this.onClose(); } } } },
        style: { systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
          scrollEffectOpts: { enableScrollEffect: false },
          originalStyle: { backgroundStyle: { backgroundColor: Color.Transparent },
            contentStyle: { backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .backgroundColor($r('app.color.xq_app_surface_page'))
      .height(LayoutPolicy.matchParent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .id('expense-navigation')
      .bindSheet($$this.showOptions, this.optionSheet(), this.optionSheetOptions())
  }
}
