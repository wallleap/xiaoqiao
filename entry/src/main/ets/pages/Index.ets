import { transferPurposeLabel } from '../domain/model/TransferRecord';
import { ChipGroup, ChipSize, curves, window } from '@kit.ArkUI';
import { HdsTabs, hdsMaterial, HdsNavigation, HdsNavigationTitleMode, HdsListItemCard,
  PrefixCustomBuilder, SuffixCustomBuilder, HdsSnackBar, SnackBarOperationType, ScrollEffectType, DividerShowType } from '@kit.UIDesignKit';
import { AccountsPage } from '../components/AccountsPage';
import { LocalBackupPage } from '../components/LocalBackupPage';
import { MoneyAmountField } from '../components/MoneyAmountField';
import { AccountEditor } from '../components/AccountEditor';
import { AccountProfile, AccountOverview } from '../domain/model/AccountProfile';
import { AmountText } from '../components/AmountText';
import { ExpenseEditor } from '../components/ExpenseEditor';
import { EntryDetailPage } from '../components/EntryDetailPage';
import { LedgerSwipeActions } from '../components/LedgerSwipeActions';
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { FilterMaterials } from '../presentation/materials/FilterMaterials';
import { LedgerDatabase } from '../data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { LedgerSnapshot, ExpenseCategory, LedgerAccount } from '../domain/model/LedgerSnapshot';
import { EntryDetail } from '../domain/model/EntryDetail';
import { MonthlyBudget, BudgetProgress, DEFAULT_MONTHLY_BUDGET_MINOR } from '../domain/model/MonthlyBudget';
import { Money } from '../core/money/Money';
import { ExpenseAmountInput } from '../presentation/ledger/ExpenseAmountInput';
import { LedgerEntry, LedgerKind, displayAmount, filterEntries, previewEntries, presentEntry, dailyTotals, isToday, navigationHandoff } from '../presentation/ledger/LedgerOverview';

interface EntryDeleteTarget { id: string; category: string; minor: string; }

@Entry
@Component
struct Index {
  @StorageProp('ledgerPreview') private preview: boolean = false;
  @StorageProp('ledgerScrollPreview') private scrollPreview: boolean = false;
  @StorageProp('ledgerForceLegacyMaterials') private forceLegacyMaterials: boolean = false;
  @State private selectedTab: number = 0;
  @State private backupBusy: boolean = false;
  @State private accountOverview: AccountOverview | undefined = undefined;
  @State private accountError: string = '';
  @State private showAccountEditor: boolean = false;
  @State private editingAccount: AccountProfile | undefined = undefined;
  @State private accountSaving: boolean = false;
  @State private kind: LedgerKind = LedgerKind.All;
  @State private displayedKind: LedgerKind = LedgerKind.All;
  @State private kindDirection: number = 1;
  @State private keyword: string = '';
  @State private showSearch: boolean = false;
  @State private showSelection: boolean = false;
  @State private selectionKind: number = 0;
  @State private account: string = '';
  @State private pendingAccount: string = '';
  @State private viewportWidth: number = 390;
  @State private recordWidth: number = 358;
  @State private bodyViewportHeight: number = 0;
  @State private headerScrolled: boolean = false;
  @State private periodOpacity: number = 1;
  @State private ledger: LedgerSnapshot | undefined = undefined;
  @State private loadError: string = '';
  @State private upgradeRequired: boolean = false;
  @State private loading: boolean = true;
  @State private showExpense: boolean = false;
  @State private showDetail: boolean = false;
  @State private detail: EntryDetail | undefined = undefined;
  @State private editingEntry: EntryDetail | undefined = undefined;
  @State private detailLoading: boolean = false;
  @State private detailError: string = '';
  private detailId: string = '';
  private detailRequest: number = 0;
  @State private savingExpense: boolean = false;
  @State private selectedMonth: string = '';
  @State private budgetInput: string = '';
  private readonly budgetController: TextInputController = new TextInputController();
  @State private budgetError: string = '';
  @State private budgetSaving: boolean = false;
  @State private materialReady: boolean = false;
  @State private filtersInNavigation: boolean = false;
  @State private navigationTitleOpacity: number = 1;
  @State private navigationFilterOffset: number = 56;
  @State private filterHeight: number = 60;
  @State private activeSwipeId: string = '';
  @State private deleting: boolean = false;
  private deletePromptOpen: boolean = false;
  private filterStartOffset: number = Number.POSITIVE_INFINITY;
  private filterMaterials: FilterMaterials | undefined = undefined;
  private workspace: LedgerWorkspace | undefined = undefined;
  private readonly bodyScroller: ListScroller = new ListScroller();
  private snackBar: HdsSnackBar | undefined = undefined;
  private readonly labels: string[] = ['账目', '统计', '记一笔', '资产', '设置'];
  private readonly tabIcons: Resource[] = [$r('app.media.lucide_house1'),
    $r('app.media.lucide_chart_no_axes_combined1'), $r('app.media.lucide_plus1'),
    $r('app.media.lucide_wallet1'), $r('app.media.lucide_settings1')];

  private entries(kind: LedgerKind = this.kind): LedgerEntry[] {
    const saved = this.ledger?.entries.map(presentEntry) || [];
    return filterEntries(this.preview ? previewEntries(this.scrollPreview) : saved, kind, this.keyword, this.account);
  }

  private month(): string {
    const now = new Date();
    return this.preview ? '2026年10月' : this.selectedMonth.length > 0 ? this.selectedMonth.replace('-', '年') + '月' :
      `${now.getFullYear()}年${now.getMonth() + 1}月`;
  }

  aboutToAppear(): void {
    const fonts = this.getUIContext().getFont();
    fonts.registerFont({ familyName: 'XiaoQiaoDINRegular',
      familySrc: $rawfile('fonts/D-DIN-PRO-400-Regular.ttf') });
    fonts.registerFont({ familyName: 'XiaoQiaoDINMedium',
      familySrc: $rawfile('fonts/D-DIN-PRO-500-Medium.ttf') });
    fonts.registerFont({ familyName: 'XiaoQiaoDINBold',
      familySrc: $rawfile('fonts/D-DIN-PRO-700-Bold.ttf') });
    const now = new Date();
    this.selectedMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    this.loadLedger();
    this.loadFilterMaterials();
  }

  private async loadFilterMaterials(): Promise<void> {
    // The native uiMaterial module itself is new in API 26, so guard the module import, not just its constructor.
    if (deviceInfo.sdkApiVersion < 26 || this.forceLegacyMaterials) { return; }
    try {
      const factory = await import('../presentation/materials/ImmersiveFilterMaterials');
      this.filterMaterials = factory.createFilterMaterials();
      this.materialReady = this.filterMaterials !== undefined;
    } catch (_) { this.materialReady = false; }
  }

  private async loadLedger(): Promise<void> {
    this.loading = true;
    this.loadError = ''; this.upgradeRequired = false;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      // Nonpersistent override exists only for isolated device tests; normal launch always uses xiaoqiao.db.
      const name = AppStorage.get<string>('ledgerDatabaseName') || 'xiaoqiao.db';
      this.workspace = await LedgerWorkspace.open(context, name);
      this.ledger = await this.workspace.snapshot(this.selectedMonth);
      await this.refreshAccountOverview(this.workspace);
    } catch (error) {
      const code = (error as Error).message;
      this.upgradeRequired = code === 'LEDGER_UPGRADE_REQUIRED';
      if (code === 'BACKUP_RECOVERY_REQUIRED') { this.showRecoveryError(); }
      else { this.loadError = this.upgradeRequired ? '升级本地账本后，可使用转账手续费和还款优惠' : '账本暂时无法读取，已有数据不会被覆盖。请重试'; }
    } finally { this.loading = false; }
  }

  private showRecoveryError(): void {
    this.loadError = '账本恢复中断，恢复前副本已保留。请退出应用并重新打开。';
    this.accountError = this.loadError;
  }

  private async refreshAccountOverview(workspace: LedgerWorkspace): Promise<void> {
    try {
      this.accountOverview = await workspace.accountOverview();
      this.accountError = '';
    } catch (_) { this.accountError = '账户暂时无法读取，请重试'; }
  }

  private async refreshAfterDeletion(workspace: LedgerWorkspace): Promise<void> {
    try {
      this.ledger = await workspace.snapshot(this.selectedMonth);
      this.loadError = '';
    } catch (_) { this.loadError = '账目已删除，但列表刷新失败，请重试读取'; }
  }

  private confirmDatabaseUpgrade(): void {
    if (this.loading) { return; }
    this.getUIContext().getPromptAction().showDialog({ title: '升级本地账本？',
      message: '先在本机备份，再增加转账用途、手续费和优惠字段。原账目及余额会核对保留，失败会回滚并保留备份。',
      buttons: [{ text: '取消', color: $r('app.color.xq_font_primary') }, { text: '备份并升级', color: $r('app.color.xq_font_emphasize') }]
    }).then(async (result) => {
      if (result.index !== 1) { return; }
      this.loading = true;
      try {
        const host = this.getUIContext().getHostContext() as common.UIAbilityContext;
        await LedgerDatabase.upgrade(host); await this.loadLedger();
      } catch (_) { this.loadError = '升级未完成，请保留本地数据后重试'; }
      finally { this.loading = false; }
    }).catch(() => {});
  }

  private openAccount(account: AccountProfile | undefined = undefined): void {
    if (this.preview || this.loading || this.workspace === undefined || this.accountError.length > 0) {
      this.notify('请先关闭预览并等待账户读取完成'); return;
    }
    const current = account === undefined ? undefined : this.accountOverview?.accounts.find((item: AccountProfile) => item.id === account.id);
    if (account !== undefined && current === undefined) { this.notify('账户已变更，请刷新后重试'); return; }
    this.editingAccount = current; this.showAccountEditor = true;
  }

  private async accountSaved(): Promise<void> {
    this.showAccountEditor = false; this.editingAccount = undefined;
    await this.loadLedger(); this.notify('账户已保存');
  }

  private archiveAccount(): void {
    const account = this.editingAccount;
    if (account === undefined || this.accountSaving) { return; }
    const archive = !account.archived;
    this.getUIContext().getPromptAction().showDialog({ title: archive ? '归档这个账户吗？' : '恢复使用这个账户？',
      message: archive ? '归档后不再用于日常记账，余额和历史账目会保留。' : '恢复后可以在记账时选择这个账户。',
      buttons: [{ text: '取消', color: $r('app.color.xq_font_primary') },
        { text: archive ? '归档' : '恢复使用', color: $r('app.color.xq_font_emphasize') }]
    }).then(async (result) => {
      if (result.index !== 1 || this.workspace === undefined) { return; }
      this.accountSaving = true;
      try {
        await this.workspace.archiveAccount(account.id, account.revision, archive);
        this.showAccountEditor = false; this.editingAccount = undefined; await this.loadLedger();
        this.notify(archive ? '账户已归档' : '账户已恢复');
      } catch (_) { this.notify('账户已变更或暂时无法保存，请返回刷新后重试'); }
      finally { this.accountSaving = false; }
    }).catch(() => {});
  }

  @Builder
  private accountsPage() {
    AccountsPage({ overview: this.accountOverview, loading: this.loading, error: this.upgradeRequired ? '请先返回账目页，备份并升级本地账本' : this.accountError,
      onCreate: () => { this.openAccount(); }, onEdit: (account: AccountProfile) => { this.openAccount(account); },
      onRetry: () => { this.loadLedger(); } })
  }

  @Builder
  private accountEditorPage() {
    AccountEditor({ workspace: this.workspace, original: this.editingAccount, operationBusy: this.accountSaving,
      sheetMaterial: this.materialReady && !this.forceLegacyMaterials ? this.filterMaterials?.menu : undefined,
      onClose: () => { if (!this.accountSaving) { this.showAccountEditor = false; this.editingAccount = undefined; } },
      onBusy: (busy: boolean) => { this.accountSaving = busy; }, onSaved: () => { this.accountSaved(); },
      onArchive: () => { this.archiveAccount(); } })
  }

  private openExpense(): void {
    if (this.backupBusy) { return; }
    if (this.preview) { this.notify('预览样例不写入数据库，请关闭预览后记账'); return; }
    if (this.loading || this.workspace === undefined || this.loadError.length > 0 || this.ledger === undefined) {
      this.notify('请先等待账本读取完成，或重试读取'); return;
    }
    this.editingEntry = undefined;
    this.showDetail = false;
    this.showExpense = true;
  }

  private async openDetail(id: string, edit: boolean = false): Promise<void> {
    if (this.preview) { this.notify('预览样例不打开真实账目'); return; }
    if (this.workspace === undefined || this.detailLoading || this.deleting) { return; }
    this.activeSwipeId = ''; this.detailId = id; this.detail = undefined;
    this.showDetail = true; this.detailLoading = true; this.detailError = '';
    const request = ++this.detailRequest;
    try {
      const detail = await this.workspace.entryDetail(id);
      if (request !== this.detailRequest || !this.showDetail) { return; }
      this.detail = detail;
      if (edit) { this.editDetail(); }
    } catch (_) {
      if (request === this.detailRequest) { this.detailError = '账目可能已删除，或暂时无法读取。请返回或重新读取'; }
    } finally { if (request === this.detailRequest) { this.detailLoading = false; } }
  }

  private editDetail(): void {
    if (this.detail === undefined || !this.detail.canEdit || this.deleting) { return; }
    this.editingEntry = this.detail; this.showExpense = true;
  }

  private closeDetail(): void {
    this.detailRequest++; this.detailLoading = false; this.showDetail = false; this.detail = undefined;
  }

  private closeEditor(): void {
    this.showExpense = false; this.editingEntry = undefined;
    if (this.showDetail) { this.openDetail(this.detailId); }
  }

  private async expenseSaved(date: string): Promise<void> {
    const edited = this.editingEntry !== undefined;
    this.selectedTab = 0;
    this.showExpense = false; this.editingEntry = undefined;
    this.selectedMonth = date.substring(0, 7);
    this.kind = LedgerKind.All; this.displayedKind = LedgerKind.All;
    this.account = ''; this.keyword = ''; this.showSearch = false;
    this.bodyScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    await this.loadLedger();
    if (edited) { await this.openDetail(this.detailId); this.notify('账目已更新'); }
  }

  private editCategories(income: boolean = false): ExpenseCategory[] {
    const values = (income ? this.ledger?.incomeCategories : this.ledger?.categories)?.slice() || [];
    const entry = this.editingEntry;
    if (entry !== undefined && entry.kind !== 'transfer' && (entry.kind === 'income') === income && !values.some((item: ExpenseCategory) => item.id === entry.categoryId)) {
      values.push({ id: entry.categoryId, name: entry.categoryName, parentId: '', iconKey: entry.iconKey });
    }
    return values;
  }

  private editAccounts(): LedgerAccount[] {
    const values = this.ledger?.accounts.slice() || [];
    const entry = this.editingEntry;
    if (entry !== undefined && entry.accountId.length > 0 && !values.some((item: LedgerAccount) => item.id === entry.accountId)) {
      values.push({ id: entry.accountId, name: entry.accountName, currencyId: entry.currencyId, kind: entry.accountKind });
    }
    if (entry?.kind === 'transfer' && entry.toAccountId && !values.some((item: LedgerAccount) => item.id === entry.toAccountId)) {
      values.push({ id: entry.toAccountId, name: entry.toAccountName || '转入账户', currencyId: entry.currencyId, kind: entry.toAccountKind });
    }
    return values;
  }

  @Builder
  private detailPage() {
    EntryDetailPage({ entry: this.detail, loading: this.detailLoading, error: this.detailError, busy: this.deleting,
      onClose: () => { this.closeDetail(); }, onEdit: () => { this.editDetail(); },
      onRetry: () => { this.openDetail(this.detailId); }, onDelete: () => {
        if (this.detail !== undefined) {
          this.confirmDelete({ id: this.detail.id, category: this.detail.kind === 'transfer' ? transferPurposeLabel(this.detail.transferPurpose || 'transfer') : this.detail.categoryPath, minor: this.detail.kind === 'transfer' ? (this.detail.transferOutMinor || this.detail.bookMinor) : this.detail.bookMinor });
        }
      } })
  }

  private async confirmDelete(entry: EntryDeleteTarget): Promise<void> {
    if (this.preview) { this.notify('预览样例不删除数据'); return; }
    const workspace = this.workspace;
    if (this.deleting || this.deletePromptOpen || workspace === undefined || this.loading) { return; }
    this.deletePromptOpen = true;
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        title: '确定删除这笔账目吗？',
        message: `${entry.category}・¥${displayAmount(entry.minor)}\n账目删除之后不能恢复，请谨慎删除`,
        buttons: [{ text: '取消', color: $r('app.color.xq_font_secondary') },
          { text: '删除', color: $r('app.color.xq_warning') }]
      });
      if (choice.index !== 1) { return; }
      this.deleting = true;
      try { await workspace.deleteEntry(entry.id); }
      catch (_) { this.notify('删除失败，账目未删除，请重试'); return; }
      this.activeSwipeId = '';
      if (this.showDetail && this.detailId === entry.id) { this.closeDetail(); }
      // Refresh both views after the committed write without replacing the list with a loading view.
      await Promise.all([this.refreshAfterDeletion(workspace), this.refreshAccountOverview(workspace)]);
      this.notify(this.loadError.length > 0 || this.accountError.length > 0 ? '账目已删除，部分数据刷新失败' : '已删除账目');
    } catch (_) { /* Dismissing the native confirmation does not write any data. */ }
    finally { this.deleting = false; this.deletePromptOpen = false; }
  }

  private budgetProgress(): BudgetProgress {
    return MonthlyBudget.progress(this.preview ? '300000' : this.ledger?.budgetTotalMinor || DEFAULT_MONTHLY_BUDGET_MINOR,
      this.preview ? '248600' : this.ledger?.budgetUsedMinor || '0');
  }

  private budgetRemaining(): string {
    const remaining = BigInt(this.budgetProgress().remainingMinor);
    return displayAmount((remaining < BigInt(0) ? -remaining : remaining).toString());
  }

  private openBudget(): void {
    if (this.preview) { this.notify('预览样例不修改预算'); return; }
    const workspace = this.workspace;
    if (workspace === undefined || this.ledger === undefined || this.loading || this.loadError.length > 0) {
      this.notify('请先等待账本读取完成，或重试读取'); return;
    }
    this.budgetInput = Money.fromMinorText(this.ledger.budgetTotalMinor, workspace.currency).toDecimalString();
    this.budgetError = ''; this.selectionKind = 2; this.showSelection = true;
  }

  private async saveBudget(): Promise<void> {
    const workspace = this.workspace;
    if (this.budgetSaving || workspace === undefined) { return; }
    this.budgetError = '';
    let amount: string;
    try { amount = ExpenseAmountInput.nonnegative(this.budgetInput, workspace.currency).toDecimalString(); }
    catch (_) { this.budgetError = '请输入 0 或以上的有效金额，最多两位小数，且不超过金额上限'; return; }
    this.budgetController.stopEditing();
    this.budgetSaving = true;
    try {
      await workspace.setMonthlyBudget(this.selectedMonth, amount);
      await this.loadLedger();
      this.showSelection = false;
    } catch (_) { this.budgetError = '预算未能保存，请稍后重试'; }
    finally { this.budgetSaving = false; }
  }

  private validBudget(): boolean {
    if (this.workspace === undefined) { return false; }
    try { ExpenseAmountInput.nonnegative(this.budgetInput, this.workspace.currency); return true; } catch (_) { return false; }
  }

  private primaryStatusBarColor(): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) { return '#E5000000'; }
    const color = context.resourceManager.getColorSync($r('app.color.xq_font_primary').id);
    return '#' + (color >>> 0).toString(16).padStart(8, '0');
  }

  private async restoreStatusBar(): Promise<void> {
    try {
      const host = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const mainWindow = await window.getLastWindow(host);
      // A freshly recreated navigation can briefly retain the previous page's status-bar style.
      await mainWindow.setWindowSystemBarProperties({
        statusBarContentColor: this.selectedTab === 0 && this.headerScrolled ? '#FFFFFFFF' : this.primaryStatusBarColor()
      });
    } catch (_) { /* HdsNavigation still owns subsequent native scroll-style updates. */ }
  }

  @Builder
  private expensePage() {
    if (this.workspace !== undefined && this.ledger !== undefined) {
      ExpenseEditor({ workspace: this.workspace, bookId: this.ledger.bookId,
        chipMaterial: this.materialReady && !this.forceLegacyMaterials ? this.filterMaterials?.chip : undefined,
        actionMaterial: this.materialReady && !this.forceLegacyMaterials ? this.filterMaterials?.action : undefined,
        sheetMaterial: this.materialReady && !this.forceLegacyMaterials ? this.filterMaterials?.menu : undefined,
        editingEntry: this.editingEntry, categories: this.editCategories(), incomeCategories: this.editCategories(true), accounts: this.editAccounts(),
        onSavingChange: (saving: boolean) => { this.savingExpense = saving; },
        onClose: () => { this.closeEditor(); }, onSaved: (date: string) => { this.expenseSaved(date); } })
    }
  }

  onBackPress(): boolean {
    if (this.showAccountEditor) { if (!this.accountSaving) { this.showAccountEditor = false; this.editingAccount = undefined; } return true; }
    if (this.showExpense) { if (!this.savingExpense) { this.closeEditor(); } return true; }
    if (this.showDetail) { if (!this.deleting) { this.closeDetail(); } return true; }
    return false;
  }

  aboutToDisappear(): void {
    this.snackBar?.dismiss();
  }

  private notify(message: string): void {
    if (this.snackBar === undefined) {
      this.snackBar = new HdsSnackBar(this.getUIContext());
    }
    this.snackBar.dismiss();
    this.snackBar.show({}, { content: message }, {
      operationType: SnackBarOperationType.CLOSE_BUTTON_ONLY,
      onCloseButtonClick: () => { this.snackBar?.dismiss(); }, closeButtonAccessibilityText: '关闭提示'
    }, { duration: 3000 });
  }

  @Builder
  private searchGlyph() {
    Image($r('app.media.lucide_search1')).width(22).height(22)
      .fillColor(this.headerScrolled ? $r('app.color.xq_icon_on_primary') : $r('app.color.xq_icon_primary'))
  }

  @Builder
  private searchAction() {
    if (this.materialReady && !this.forceLegacyMaterials) {
      Button({ type: ButtonType.Circle }) { this.searchGlyph() }
        .width(40).height(40).padding(0).backgroundColor(Color.Transparent)
        .systemMaterial(this.filterMaterials?.action)
        .id('搜索账目').accessibilityText('搜索账目').onClick(() => { this.toggleSearch(); })
    } else {
      Button({ type: ButtonType.Circle }) { this.searchGlyph() }
        .width(40).height(40).padding(0).backgroundColor($r('app.color.xq_app_surface_card'))
        .id('搜索账目').accessibilityText('搜索账目').onClick(() => { this.toggleSearch(); })
    }
  }

  private toggleSearch(): void {
    if (this.showSearch) { this.keyword = ''; }
    this.showSearch = !this.showSearch;
    this.bodyScroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  @Builder
  private bookTitle() {
    Row() {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          Text(this.preview ? '日常账本' : this.ledger?.bookName || '日常账本').fontSize('24fp').fontWeight(FontWeight.Bold)
            .fontColor(this.headerScrolled ? $r('app.color.xq_font_on_primary') : $r('app.color.xq_font_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Image($r('app.media.lucide_chevron_down1')).width(18).height(18)
            .fillColor(this.headerScrolled ? $r('app.color.xq_icon_on_primary') : $r('app.color.xq_icon_primary'))
        }
      }.id('ledger-book-selector').backgroundColor(Color.Transparent).padding(0).height(48)
        .constraintSize({ maxWidth: 'calc(100% - 48vp)' })
      .accessibilityText('选择账本，当前日常账本').onClick(() => { this.selectionKind = 0; this.showSelection = true; })
      Blank()
      this.searchAction()
    }.width('100%').padding({ left: this.viewportWidth >= 600 ? 32 : 16, right: this.viewportWidth >= 600 ? 32 : 16 })
      .opacity(this.navigationTitleOpacity).id('ledger-title-content')
      .hitTestBehavior(this.navigationTitleOpacity > 0 ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  private header() {
    Row({ space: 8 }) {
      Text(this.month()).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
      Text('·').fontSize('12fp').fontColor($r('app.color.xq_font_tertiary'))
      Text('CNY').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
    }.id('ledger-period').width('100%').margin({ top: 2, bottom: 16 })
      .opacity(this.periodOpacity).visibility(this.periodOpacity > 0 ? Visibility.Visible : Visibility.Hidden)
    if (this.showSearch) {
      Search({ value: this.keyword, placeholder: '搜索备注、分类或账户' })
        .id('ledger-search').onChange((value: string) => { this.keyword = value; })
        .height(48).margin({ bottom: 16 })
    }
  }

  @Builder
  private summaryFigure(income: boolean) {
    Text(this.preview ? (income ? '8,600.00' : '2,486.00') :
      displayAmount((income ? this.ledger?.incomeMinor : this.ledger?.expenseMinor) || '0'))
      .fontFamily('XiaoQiaoDINRegular').fontSize('14fp').fontWeight(FontWeight.Regular)
      .id(income ? 'ledger-income-total' : 'ledger-expense-total')
      .minFontSize('12fp').maxFontSize('14fp').maxLines(1).constraintSize({ maxWidth: 92 })
      .fontColor($r('app.color.xq_font_on_secondary'))
      .accessibilityText('人民币' + (this.preview ? (income ? '8,600.00' : '2,486.00') :
        displayAmount((income ? this.ledger?.incomeMinor : this.ledger?.expenseMinor) || '0')) + '元')
      .onClick(() => {
        const amount = this.preview ? (income ? '8,600.00' : '2,486.00') :
          displayAmount((income ? this.ledger?.incomeMinor : this.ledger?.expenseMinor) || '0');
        this.getUIContext().getPromptAction().showDialog({ title: '完整金额', message: `¥${amount}`,
          buttons: [{ text: '知道了', color: $r('app.color.xq_font_emphasize') }] });
      })
  }

  @Builder
  private summary() {
    Column({ space: 16 }) {
      Row() {
        Text(this.budgetProgress().overBudget ? '本月预算超支' : '本月预算剩余').fontSize('14fp')
          .fontColor($r('app.color.xq_font_on_secondary'))
        Blank()
        Button({ type: ButtonType.Normal }) {
          Row({ space: 6 }) {
            Text() {
              Span('预算 ¥')
              Span(this.preview ? '3,000.00' : displayAmount(this.ledger?.budgetTotalMinor || DEFAULT_MONTHLY_BUDGET_MINOR))
                .fontFamily('XiaoQiaoDINRegular')
            }.fontSize('12fp')
              .fontColor($r('app.color.xq_font_on_secondary'))
            Image($r('app.media.lucide_pencil1')).width(14).height(14)
              .fillColor($r('app.color.xq_icon_on_secondary'))
          }
        }.height(32).padding(0).backgroundColor(Color.Transparent)
        .id('ledger-edit-budget').accessibilityText('修改本月预算')
        .onClick(() => { this.openBudget(); })
      }.width('100%')
      Row({ space: 12 }) {
        if (this.preview || this.ledger !== undefined) {
          AmountText({ amount: this.budgetRemaining(), amountSize: 38, fractionSize: 24, bold: true, color: $r('app.color.xq_font_on_primary') }).layoutWeight(1)
          Stack() {
            Progress({ value: this.budgetProgress().ringValue, total: 100, type: ProgressType.Ring })
              .width(64).height(64).color($r('app.color.xq_app_summary_accent'))
              .backgroundColor($r('app.color.xq_app_summary_track')).style({ strokeWidth: 6 })
            Text() {
              if (this.budgetProgress().overBudget) {
                Span('已超支')
              } else if (this.budgetProgress().percentText.endsWith('%')) {
                Span(this.budgetProgress().percentText.slice(0, -1))
                Span('%').fontSize('9fp')
              } else {
                Span(this.budgetProgress().percentText)
              }
            }
              .fontFamily('XiaoQiaoDINMedium').fontSize('12fp').fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.xq_app_summary_accent'))
          }.accessibilityText('预算已使用 ' + this.budgetProgress().percentText)
        } else {
          Text('—').fontSize('38fp').fontColor($r('app.color.xq_font_on_primary'))
        }
      }.width('100%').constraintSize({ minHeight: 64 })
      Row({ space: 16 }) {
        Row({ space: 6 }) {
          Image($r('app.media.lucide_arrow_down1')).width(16).height(16).fillColor('#55C9A5')
          Text('收入').fontSize('12fp').fontColor($r('app.color.xq_font_on_secondary'))
          this.summaryFigure(true)
        }.layoutWeight(1).accessibilityText('本月收入')
        Row({ space: 6 }) {
          Image($r('app.media.lucide_arrow_up1')).width(16).height(16).fillColor($r('app.color.xq_app_summary_accent'))
          Text('支出').fontSize('12fp').fontColor($r('app.color.xq_font_on_secondary'))
          this.summaryFigure(false)
        }.layoutWeight(1).justifyContent(FlexAlign.End).accessibilityText('本月支出')
      }.width('100%')
    }.id('ledger-summary').padding(16).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_summary'))
      .linearGradient({ angle: 122, colors: [[$r('app.color.xq_app_surface_summary'), 0],
        [$r('app.color.xq_app_summary_gradient_end'), 1]] })
  }

  @Builder
  private entryAmount(entry: LedgerEntry, pageKind: LedgerKind) {
    Column({ space: 3 }) {
      AmountText({ amount: displayAmount(entry.transfer && pageKind === LedgerKind.Expense ? (entry.expenseMinor || '0') : entry.minor), amountSize: 16, bold: true, currencyBottom: 0,
        sign: entry.transfer && pageKind !== LedgerKind.Expense ? '' : entry.income ? '+' : '−',
        onOpen: () => { this.openDetail(entry.id); },
        color: entry.transfer && pageKind !== LedgerKind.Expense ? $r('app.color.xq_font_primary') : entry.income ? $r('app.color.xq_app_income') : $r('app.color.xq_brand') })
      if (entry.transfer && BigInt(entry.transferFeeMinor || '0') > BigInt(0)) {
        Text(pageKind === LedgerKind.Expense ? '转出 ' + displayAmount(entry.minor) : '手续费 ' + displayAmount(entry.transferFeeMinor || '0')).fontSize('12fp')
          .fontColor($r('app.color.xq_font_secondary')).maxLines(1).id(`ledger-transfer-fee-${entry.id}`)
      }
      if (!entry.income && BigInt(entry.discountMinor) > BigInt(0)) {
        Row({ space: 6 }) {
          Text('¥' + displayAmount(entry.grossMinor)).fontFamily('XiaoQiaoDINRegular').fontSize('12fp')
            .fontColor($r('app.color.xq_font_tertiary')).decoration({ type: TextDecorationType.LineThrough })
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1).id(`ledger-original-${entry.id}`)
          Text() {
            Span('优惠 ')
            Span(displayAmount(entry.discountMinor)).fontFamily('XiaoQiaoDINRegular')
          }.fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1).id(`ledger-discount-value-${entry.id}`)
        }.justifyContent(FlexAlign.End).id(`ledger-discount-${entry.id}`)
      }
    }.alignItems(HorizontalAlign.End).padding({ top: 8, bottom: 8, right: 16 })
      .constraintSize({ maxWidth: 160 })
  }

  private entrySubtitle(entry: LedgerEntry): string {
    // The existing read model uses this label for a missing account; suppress it only in the card display.
    const account = entry.transfer ? entry.account + ' → ' + (entry.toAccount || '转入账户') : entry.account.trim();
    return account.length > 0 && account !== '不使用账户' ? `${entry.time} · ${account}` : entry.time;
  }

  @Builder
  private categoryBadge(entry: LedgerEntry) {
    Row() {
      Stack() {
        if (entry.transfer) {
          Image(entry.icon).width(28).height(28).fillColor($r('app.color.xq_icon_primary')).id(`ledger-category-glyph-${entry.id}`)
        } else {
          Image(entry.icon).width(28).height(28).objectFit(ImageFit.Contain).id(`ledger-category-glyph-${entry.id}`)
        }
      }.width(48).height(48).borderRadius(24).backgroundColor($r('app.color.xq_app_surface_page'))
        .id(`ledger-category-disc-${entry.id}`)
    }.width(68).height(48).padding({ left: 12, right: 8 })
  }

  @Builder
  private entryContent(entry: LedgerEntry) {
    Row({ space: 0 }) {
      this.categoryBadge(entry)
      Column({ space: 4 }) {
        Text(entry.title).fontSize('16fp').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.xq_font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.entrySubtitle(entry)).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).id(`ledger-entry-subtitle-${entry.id}`)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width(Math.max(120, this.recordWidth - 176)).padding({ top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ledgerRow(entry: LedgerEntry, pageKind: LedgerKind) {
    HdsListItemCard({
      cardId: entry.id,
      cardWidth: this.recordWidth, cardBorderRadius: 16,
      cardPrefixMargin: 16, cardSuffixMargin: 16,
      cardBackgroundColor: $r('app.color.xq_comp_common_contrary'),
      prefixItem: new PrefixCustomBuilder(() => { this.entryContent(entry); }),
      suffixItem: new SuffixCustomBuilder(() => { this.entryAmount(entry, pageKind); })
    }).id(entry.id).width('100%').onClick(() => { this.openDetail(entry.id); })
  }

  @Builder
  private emptyState(pageKind: LedgerKind) {
    Column({ space: 12 }) {
      Image($r('app.media.illustration_no_record')).width(160).height(160).objectFit(ImageFit.Contain)
        .id('ledger-empty-illustration')
      Column({ space: 6 }) {
        Text(this.preview || pageKind !== LedgerKind.All || this.keyword.length > 0 || this.account.length > 0 ? '没有符合条件的账目' : '从第一笔开始')
          .fontSize('16fp').fontWeight(FontWeight.Regular).lineHeight('22fp')
          .fontColor($r('app.color.xq_font_secondary')).textAlign(TextAlign.Center).width('100%')
        Text(this.preview || pageKind !== LedgerKind.All || this.keyword.length > 0 || this.account.length > 0 ? '试试其他关键词或筛选条件' : '把日常收支，慢慢记清楚')
          .fontSize('12fp').fontWeight(FontWeight.Regular).lineHeight('18fp')
          .fontColor($r('app.color.xq_font_tertiary')).textAlign(TextAlign.Center).width('100%')
      }.width('100%')
      if (!this.preview && pageKind === LedgerKind.All && this.keyword.length === 0 && this.account.length === 0) {
        Button('开始记第一笔账', { type: ButtonType.Capsule }).fontSize('16fp').fontColor(Color.White)
          .padding({ top: 10, bottom: 10, left: 32, right: 32 })
          .linearGradient({ angle: 110, colors: [[$r('app.color.xq_app_gradient_start'), 0],
            [$r('app.color.xq_app_gradient_end'), 1]] }).margin({ top: 12 })
          .onClick(() => { this.openExpense(); })
      }
    }.width('100%').padding({ top: 24, bottom: 24, left: 16, right: 16 })
  }

  @Builder
  private filterGlyph() {
    Image($r('app.media.lucide_funnel1')).width(22).height(22)
      .fillColor(this.account.length > 0 ? $r('app.color.xq_icon_emphasize') : $r('app.color.xq_icon_primary'))
      .id('ledger-filter-glyph')
  }

  @Builder
  private filterSuffix() {
    if (this.materialReady && !this.forceLegacyMaterials) {
      Button({ type: ButtonType.Circle }) { this.filterGlyph() }
        .width(40).height(40).padding(0).backgroundColor(Color.Transparent)
        .systemMaterial(this.filterMaterials?.action).id('ledger-filter-action')
        .accessibilityText(this.account.length > 0 ? '筛选账目，已生效' : '筛选账目')
        .onClick(() => { this.openAccountFilter(); })
    } else {
      Button({ type: ButtonType.Circle }) { this.filterGlyph() }
        .width(40).height(40).padding(0).backgroundColor($r('app.color.xq_app_surface_card'))
        .id('ledger-filter-action')
        .accessibilityText(this.account.length > 0 ? '筛选账目，已生效' : '筛选账目')
        .onClick(() => { this.openAccountFilter(); })
    }
  }

  private openAccountFilter(): void {
    this.pendingAccount = this.account; this.selectionKind = 1; this.showSelection = true;
  }

  private selectKind(selected: number[]): void {
    if (selected.length !== 1) { return; }
    const next = selected[0] === 1 ? LedgerKind.Expense : selected[0] === 2 ? LedgerKind.Income : LedgerKind.All;
    if (next === this.kind) { return; }
    this.activeSwipeId = '';
    this.kindDirection = next > this.kind ? 1 : -1;
    this.kind = next;
    // Update only the content key in the animation scope. ChipGroup keeps its native selected-state feedback.
    this.getUIContext().animateTo({ curve: curves.springMotion(0.34, 0.90, 0.12) }, () => {
      this.displayedKind = next;
    });
  }

  private recordTransition(): TransitionEffect {
    const distance = this.recordWidth * 0.18;
    return TransitionEffect.asymmetric(
      TransitionEffect.translate({ x: this.kindDirection * distance }).combine(TransitionEffect.OPACITY),
      TransitionEffect.translate({ x: -this.kindDirection * distance }).combine(TransitionEffect.OPACITY));
  }

  @Builder
  private animatedRecords() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach([this.displayedKind], (pageKind: LedgerKind) => {
        Column() { this.records(pageKind) }.width('100%')
          .hitTestBehavior(pageKind === this.kind ? HitTestMode.Default : HitTestMode.None)
          .accessibilityLevel(pageKind === this.kind ? 'auto' : 'no-hide-descendants')
          .transition(this.recordTransition()).id(`ledger-record-page-${pageKind}`)
      }, (pageKind: LedgerKind) => `${pageKind}`)
    }.width('100%').clip(true).id('ledger-record-transition')
  }

  @Builder
  private filterChips() {
    if (this.materialReady && !this.forceLegacyMaterials) {
      ChipGroup({
        items: [{ label: { text: '全部' }, allowClose: false }, { label: { text: '支出' }, allowClose: false },
          { label: { text: '收入' }, allowClose: false }],
        multiple: false, selectedIndexes: [this.kind],
        itemStyle: { size: ChipSize.NORMAL, backgroundColor: $r('app.color.xq_app_filter_unselected'),
          fontColor: $r('app.color.xq_font_primary'), selectedBackgroundColor: $r('app.color.xq_brand'),
          selectedFontColor: $r('app.color.xq_font_on_primary') },
        backgroundSystemMaterial: this.filterMaterials?.chip,
        chipGroupSpace: { startSpace: 0, endSpace: 0, itemSpace: 8 },
        chipGroupPadding: { top: 4, bottom: 4 },
        onChange: (selected: number[]) => { this.selectKind(selected); }
      }).id('ledger-filters').width('100%')
    } else {
      ChipGroup({
        items: [
          { label: { text: '全部' }, allowClose: false },
          { label: { text: '支出' }, allowClose: false },
          { label: { text: '收入' }, allowClose: false }
        ],
        multiple: false,
        selectedIndexes: [this.kind],
        itemStyle: {
          size: ChipSize.NORMAL,
          backgroundColor: $r('app.color.xq_app_filter_unselected'),
          fontColor: $r('app.color.xq_font_primary'),
          selectedBackgroundColor: $r('app.color.xq_brand'),
          selectedFontColor: $r('app.color.xq_font_on_primary')
        },
        chipGroupSpace: { startSpace: 0, endSpace: 0, itemSpace: 8 },
        chipGroupPadding: { top: 4, bottom: 4 },
        onChange: (selected: number[]) => {
          this.selectKind(selected);
        }
      }).id('ledger-filters').width('100%')
    }
  }

  @Builder
  private filterSurface() {
    Row({ space: 12 }) {
      Column() { this.filterChips() }.layoutWeight(1)
      this.filterSuffix()
    }.width('100%').alignItems(VerticalAlign.Center)
      .padding({ bottom: this.filtersInNavigation ? 0 : 12 })
      .id(this.materialReady && !this.forceLegacyMaterials ? 'ledger-filter-surface-native' : 'ledger-filter-surface-legacy')
      .onAreaChange((_previous: Area, current: Area) => {
        const height = Number(current.height);
        if (!this.filtersInNavigation && height > 0 && height !== this.filterHeight) { this.filterHeight = height; }
      })
  }

  @Builder
  private filterRow() {
    Row({ space: 0 }) {
      if (this.viewportWidth >= 720) { Blank().width(344) }
      Column() { this.filterSurface() }.layoutWeight(1)
    }.width('100%')
  }

  @Builder
  private navigationFilters() {
    Column() { this.filterSurface() }.width('100%').height(56).justifyContent(FlexAlign.Center)
      .padding({ left: this.viewportWidth >= 600 ? 32 : 16, right: this.viewportWidth >= 600 ? 32 : 16 })
      .translate({ y: this.navigationFilterOffset })
      .id('ledger-navigation-filters')
  }

  @Builder
  private navigationTitle() {
    Row() {
      if (this.filtersInNavigation) { this.navigationFilters() } else { this.bookTitle() }
    }.width('100%').height(56).clip(false).id('ledger-navigation-title')
  }

  private updateFilterPlacement(): void {
    const offset = this.bodyScroller.currentOffset().yOffset;
    const scrolled = offset > 0;
    if (this.headerScrolled !== scrolled) { this.headerScrolled = scrolled; }
    // The period starts 14vp below the fixed title; finish fading before their bounds meet.
    const opacity = Math.max(0, Math.min(1, 1 - Math.max(0, offset) / 12));
    if (this.periodOpacity !== opacity) { this.periodOpacity = opacity; }
    // The first ListItem is before the filter placeholder. Do not use the moving toolbar's bounds.
    const handoff = navigationHandoff(offset, this.filterStartOffset, 56);
    this.navigationTitleOpacity = handoff.titleOpacity;
    this.navigationFilterOffset = handoff.filterOffset;
    if (handoff.inNavigation !== this.filtersInNavigation) { this.filtersInNavigation = handoff.inNavigation; }
  }

  @Builder
  private dailyFigure(date: string, income: boolean, pageKind: LedgerKind) {
    Text() {
      Span(income ? '收 ' : '支 ').fontColor(income ? $r('app.color.xq_app_income') : $r('app.color.xq_brand'))
      Span(displayAmount(income ? dailyTotals(this.entries(pageKind), date).incomeMinor :
        dailyTotals(this.entries(pageKind), date).expenseMinor)).fontFamily('XiaoQiaoDINRegular')
    }.fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).maxLines(1)
      .minFontSize('10fp').maxFontSize('12fp').textAlign(TextAlign.End).flexShrink(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis }).id(`ledger-day-${income ? 'income' : 'expense'}-${date}`)
  }

  @Builder
  private dateHeader(date: string, pageKind: LedgerKind) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        if (isToday(date)) {
          Text('今天').fontSize('16fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
        }
        Text(date.substring(5).replace('-', '月') + '日')
          .fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
      }.alignItems(HorizontalAlign.Start)
      Blank()
      if (isToday(date)) {
        Column({ space: 2 }) {
          this.dailyFigure(date, true, pageKind)
          this.dailyFigure(date, false, pageKind)
        }.alignItems(HorizontalAlign.End).constraintSize({ maxWidth: '75%' })
      } else {
        Row({ space: '16.8fp' }) {
          this.dailyFigure(date, true, pageKind)
          this.dailyFigure(date, false, pageKind)
        }.constraintSize({ maxWidth: '75%' })
      }
    }.width('100%').padding({ top: 16, left: 12, right: 12 })
      .alignItems(VerticalAlign.Center).id(`ledger-day-${date}`)
  }

  @Builder
  private records(pageKind: LedgerKind) {
    Column({ space: 12 }) {
      if (this.account.length > 0) {
        Text(`账户：${this.account}`).fontSize('12fp').fontColor($r('app.color.xq_font_emphasize')).width('100%')
      }
      if (!this.preview && this.loading) {
        Text('正在读取账本…').fontSize('14fp').padding(32)
      } else if (!this.preview && this.loadError.length > 0) {
        Text(this.loadError).fontSize('14fp').fontColor($r('app.color.xq_warning')).padding(16)
        Button(this.upgradeRequired ? '备份并升级账本' : '重试读取').onClick(() => {
          if (this.upgradeRequired) { this.confirmDatabaseUpgrade(); } else { this.loadLedger(); }
        }).id('ledger-upgrade-or-retry')
      } else if (this.entries(pageKind).length === 0) {
        this.emptyState(pageKind)
      } else {
        Column({ space: 0 }) {
          ForEach(this.entries(pageKind), (entry: LedgerEntry, index: number) => {
            if (index === 0 || entry.date !== this.entries(pageKind)[index - 1].date) {
              Column() { this.dateHeader(entry.date, pageKind) }.width('100%')
                .margin({ top: index === 0 ? 0 : 12, bottom: 12 })
            }
            if (index > 0 && entry.date === this.entries(pageKind)[index - 1].date) {
              Row() {
                Divider().strokeWidth(0.5).color($r('app.color.xq_app_divider_subtle'))
              }.height(8).width('100%').padding({ left: 12, right: 12 })
                .id('ledger-entry-divider-' + entry.id)
            }
            LedgerSwipeActions({ entryId: entry.id, activeId: $activeSwipeId, busy: this.deleting,
              editable: !this.preview, onEdit: () => { this.openDetail(entry.id, true); },
              menuMaterial: this.materialReady && !this.forceLegacyMaterials ? this.filterMaterials?.menu : undefined,
              content: () => { this.ledgerRow(entry, pageKind); }, onDelete: () => {
                this.confirmDelete({ id: entry.id, category: entry.category, minor: entry.minor });
              } }).width('100%')
          }, (entry: LedgerEntry) => entry.id)
        }.width('100%')
      }
    }.width('100%')
      // Fill the remaining viewport so a shorter filter result cannot clamp the list above the docking threshold.
      // Include the 56vp handoff travel so empty results can retain the fully docked position.
      .constraintSize({ minHeight: Math.max(0, this.bodyViewportHeight - this.filterHeight - 112 + 56 + 2) })
      .onAreaChange((_previous: Area, current: Area) => {
      const available = Number(current.width);
      if (available > 0 && available !== this.recordWidth) { this.recordWidth = available; }
    })
  }

  @Builder
  private overview() {
    List({ scroller: this.bodyScroller }) {
      ListItem() {
        Column({ space: 0 }) {
        this.header()
          if (this.viewportWidth < 720 && !this.upgradeRequired) { this.summary() }
        }.width('100%').padding({ top: 12, bottom: 24 })
          .onAreaChange((_previous: Area, current: Area) => {
            this.filterStartOffset = Number(current.height);
            this.updateFilterPlacement();
          })
      }
      ListItem() {
        Column() {
          if (!this.filtersInNavigation) { this.filterRow() }
        }.width('100%').height(this.filterHeight).id('ledger-filter-placeholder')
      }
      ListItemGroup() {
        ListItem() {
          if (this.viewportWidth >= 720) {
            Row({ space: 24 }) {
              Column() { if (!this.upgradeRequired) { this.summary() } }.width(320).alignSelf(ItemAlign.Start)
              Column() { this.animatedRecords() }.layoutWeight(1)
            }.width('100%').alignItems(VerticalAlign.Top)
          } else { this.animatedRecords() }
        }
      }.width('100%')
    }.id('ledger-scroll').width('100%').height('100%').constraintSize({ maxWidth: 1040 })
      // HDS keeps the initial content below its title safe area; scrolling may paint behind it.
      .clip(false).cachedCount(3, true)
      .padding({ left: this.viewportWidth >= 600 ? 32 : 16, right: this.viewportWidth >= 600 ? 32 : 16 })
      .listDirection(Axis.Vertical).enableScrollInteraction(true)
      // HDS title-bar component safe area supplies the top inset.
      .contentEndOffset(112)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onAreaChange((_previous: Area, current: Area) => {
        const height = Number(current.height);
        if (height > 0 && height !== this.bodyViewportHeight) { this.bodyViewportHeight = height; }
      })
      .onDidScroll(() => { this.updateFilterPlacement(); })
      .scrollBar(BarState.Off).align(Alignment.Top)
  }

  @Builder
  private tabItem(index: number) {
    if (index === 2) {
      Button({ type: ButtonType.Circle }) {
        Image(this.tabIcons[index]).width(28).height(28).fillColor(Color.White)
      }.width(52).height(52).accessibilityText('记一笔')
        .linearGradient({ angle: 110, colors: [[$r('app.color.xq_app_gradient_start'), 0],
          [$r('app.color.xq_app_gradient_end'), 1]] })
        .id('ledger-add-expense').onClick(() => { this.openExpense(); })
    } else {
      Column({ space: 4 }) {
        Image(this.tabIcons[index]).width(22).height(22)
          .fillColor(index === this.selectedTab ? $r('app.color.xq_icon_emphasize') : $r('app.color.xq_icon_secondary'))
        Text(this.labels[index]).fontSize('10fp')
          .fontColor(index === this.selectedTab ? $r('app.color.xq_font_emphasize') : $r('app.color.xq_font_secondary'))
      }.id(`ledger-tab-${index}`).height(56).width('100%').justifyContent(FlexAlign.Center)
    }
  }

  private selectionSheetOptions(): SheetOptions {
    const options: SheetOptions = {
      height: this.selectionKind === 0 ? 280 : this.selectionKind === 2 ? 360 : 440, showClose: true,
      keyboardAvoidMode: this.selectionKind === 2 ? SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE : SheetKeyboardAvoidMode.TRANSLATE_AND_SCROLL
    };
    if (this.materialReady && !this.forceLegacyMaterials && this.filterMaterials !== undefined) {
      options.systemMaterial = this.filterMaterials.menu;
    } else {
      options.backgroundColor = $r('app.color.xq_app_surface_card');
    }
    return options;
  }

  @Builder
  private bookSheet() {
    Column({ space: 16 }) {
      Text('选择账本').fontSize('20fp').fontWeight(FontWeight.Bold).width('100%')
      Row() {
        Text('日常账本').fontSize('16fp').layoutWeight(1)
        Text('当前账本').fontSize('12fp').fontColor($r('app.color.xq_font_emphasize'))
      }.height(56).width('100%').onClick(() => { this.showSelection = false; })
      Text('账本管理将在后续接入').fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
    }.padding(24).width('100%')
  }

  @Builder
  private filterSheet() {
    Column({ space: 20 }) {
      Text('筛选账目').fontSize('20fp').fontWeight(FontWeight.Bold).width('100%')
      Text('资金账户').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      ForEach(this.preview ? ['', '微信零钱', '日常储蓄卡'] : ['', ...(this.ledger?.accounts.map((item) => item.name) || [])], (name: string) => {
        Row() {
          Text(name.length > 0 ? name : '全部账户').fontSize('16fp').layoutWeight(1)
          Radio({ value: name, group: 'account' })
            .radioStyle({ checkedBackgroundColor: $r('app.color.xq_brand'), indicatorColor: Color.White })
            .checked(this.pendingAccount === name)
            .onChange((checked: boolean) => { if (checked) { this.pendingAccount = name; } })
        }.width('100%').height(44).onClick(() => { this.pendingAccount = name; })
      }, (name: string) => name)
      Row({ space: 12 }) {
        Button('重置').layoutWeight(1).height(48)
          .backgroundColor($r('app.color.xq_app_surface_page')).fontColor($r('app.color.xq_font_primary')).onClick(() => { this.pendingAccount = ''; })
        Button('完成').layoutWeight(1).height(48).backgroundColor($r('app.color.xq_brand')).fontColor(Color.White)
          .onClick(() => { this.account = this.pendingAccount; this.showSelection = false; })
      }.width('100%')
    }.width('100%').padding(24)
  }

  @Builder
  private budgetSheet() {
    Column({ space: 16 }) {
      Scroll() {
        Column({ space: 16 }) {
          Text('修改月预算').fontSize('20fp').fontWeight(FontWeight.Bold).width('100%')
          Text(this.month() + ' · 人民币').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
          Row({ space: 12 }) {
            MoneyAmountField({ value: $budgetInput, fieldId: 'ledger-budget-input', fontSize: '24fp',
              fontFamily: 'XiaoQiaoDINRegular', fieldHeight: 56, controller: this.budgetController,
              disabled: this.budgetSaving, onSubmit: () => { this.saveBudget(); } }).layoutWeight(1)
            Button(this.budgetSaving ? '保存中' : '保存').id('ledger-budget-save').width(80).height(48)
              .fontSize('16fp').fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.budgetSaving && this.validBudget())
              .onClick(() => { this.saveBudget(); })
          }.width('100%')
          Text('仅修改当前月份的预算，不改变账目或账户余额。').fontSize('12fp')
            .fontColor($r('app.color.xq_font_secondary')).width('100%')
          if (this.budgetError.length > 0) {
            Text(this.budgetError).fontSize('12fp').fontColor($r('app.color.xq_warning')).id('ledger-budget-error')
          }
        }.width('100%')
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.padding(24).width('100%').height('100%')
  }

  @Builder
  private selectionSheet() {
    if (this.selectionKind === 0) {
      this.bookSheet()
    } else if (this.selectionKind === 2) {
      this.budgetSheet()
    } else {
      this.filterSheet()
    }
  }

  @Builder
  private homeNavigation() {
    HdsNavigation() {
      this.overview()
    }
    .mode(NavigationMode.Stack).hideBackButton(true).titleMode(HdsNavigationTitleMode.MINI)
    .dynamicHideTitleBar({ hideTitleArea: false, hideBottomBuilder: false, hideStatusBar: false })
    .bindToScrollable([this.bodyScroller])
    .systemBarStyle({ statusBarContentColor: this.primaryStatusBarColor() }, {
      statusBarContentColor: '#FFFFFFFF'
    })
    .titleBar({
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      content: {
        title: { mainTitle: '' },
        divider: { showType: DividerShowType.OFF },
        stackBuilder: this.navigationTitle.bind(this)
      },
      style: {
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
        },
        originalStyle: {
          contentStyle: {
            titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') },
            menuStyle: { iconColor: $r('app.color.xq_icon_primary') }
          }
        },
        scrollEffectStyle: {
          // ArkUI uses ARGB: pure black at approximately 10% opacity.
          backgroundStyle: { backgroundColor: '#1A000000' },
          contentStyle: {
            titleStyle: { mainTitleColor: $r('app.color.xq_font_on_primary') },
            menuStyle: { iconColor: $r('app.color.xq_icon_on_primary') }
          }
        }
      }
    })
    .backgroundColor($r('app.color.xq_comp_common_contrary'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onAppear(() => { this.restoreStatusBar(); })
    .bindSheet($$this.showSelection, this.selectionSheet(), this.selectionSheetOptions())
  }

  @Builder
  private homeTabs() {
    HdsTabs({ barPosition: BarPosition.End, index: this.selectedTab }) {
      TabContent() { this.homeNavigation() }.tabBar(this.tabItem(0))
      TabContent() {}.tabBar(this.tabItem(1))
      TabContent() {}.tabBar(this.tabItem(2))
      TabContent() { this.accountsPage() }.tabBar(this.tabItem(3))
      TabContent() {
        LocalBackupPage({
          getBackup: () => this.workspace?.localBackup,
          ready: !this.preview && !this.loading && !this.deleting && this.loadError.length === 0 && this.ledger !== undefined,
          onBusy: (busy: boolean) => { this.backupBusy = busy; },
          onRecoveryRequired: () => { this.showRecoveryError(); },
          onRestored: async (): Promise<boolean> => {
            this.kind = LedgerKind.All; this.displayedKind = LedgerKind.All;
            this.account = ''; this.keyword = ''; this.showSearch = false;
            await this.loadLedger();
            return this.loadError.length === 0 && this.accountError.length === 0;
          }
        })
      }.tabBar(this.tabItem(4))
    }.width('100%').height(LayoutPolicy.matchParent).scrollable(false).barHeight(64)
      .barOverlap(true).vertical(false)
      .barFloatingStyle({ barSideMargin: 16, barBottomMargin: 28,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        } })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .onContentWillChange((_current: number, next: number): boolean => {
        if (this.backupBusy) { return false; }
        if (next === 0 || next === 3 || next === 4) { this.selectedTab = next; return true; }
        if (next === 2) { this.openExpense(); } else { this.notify(`${this.labels[next]}页面尚未接入`); }
        return false;
      })
      .backgroundColor($r('app.color.xq_comp_common_contrary'))
      .onAreaChange((_oldArea: Area, newArea: Area) => { this.viewportWidth = Number(newArea.width); })
  }

  build() {
    if (this.showAccountEditor) { this.accountEditorPage() }
    else if (this.showExpense) { this.expensePage() }
    else if (this.showDetail) { this.detailPage() }
    else { this.homeTabs() }
  }
}
