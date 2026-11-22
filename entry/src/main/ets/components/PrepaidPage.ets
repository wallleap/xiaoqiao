import { DEFAULT_TRANSACTION_COLORS, TransactionColors, TransactionColorKind } from '../presentation/ledger/TransactionColors';
import { enabledCurrencies } from '../core/money/CurrencySettings';
import { ExpenseAmountInput } from '../presentation/ledger/ExpenseAmountInput';
import { MoneyAmountField } from './MoneyAmountField';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { util } from '@kit.ArkTS';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { PrepaidProject, PrepaidEvent, PrepaidDetail, PrepaidProjectCommand, PrepaidEventCommand, PrepaidEventKind,
  prepaidToday, prepaidStatus, validPrepaidDate } from '../domain/model/Prepaid';
import { LedgerAttachmentDraft } from '../domain/model/LedgerAttachment';
import { LedgerAccount, ExpenseCategory, SpendingNatureChoice } from '../domain/model/LedgerSnapshot';
import { Money } from '../core/money/Money';
import { CurrencyDefinition, currencyUnit, crossRate } from '../core/money/Currencies';
import { ExchangeRate } from '../core/money/ExchangeRate';
import { OfficialExchangeRates } from '../data/exchange/OfficialExchangeRates';

@Component
export struct PrepaidPage {
  @StorageProp('transactionColorSelection') private transactionColorSelection: string = DEFAULT_TRANSACTION_COLORS;
  private transactionColor(kind: TransactionColorKind): Resource { return TransactionColors.color(kind,this.transactionColorSelection); }
  initialProjectId: string = '';
  returnToCaller: boolean = false;
  initialAction: string = '';
  onInitialActionHandled: () => void = () => {};
  workspace: LedgerWorkspace | undefined = undefined;
  @Prop accounts: LedgerAccount[] = [];
  @Prop categories: ExpenseCategory[] = [];
  @Prop incomeCategories: ExpenseCategory[] = [];
  @Prop spendingNatures: SpendingNatureChoice[] = [];
  onClose: () => void = () => {};
  onCreate: () => void = () => {};
  onRegisterBack: (handler: () => boolean) => void = () => {};
  sheetMaterial: SystemUiMaterial | undefined = undefined;
  onChanged: () => Promise<void> = async () => {};
  onBusy: (value: boolean) => void = () => {};
  @State private projects: PrepaidProject[] = [];
  @State private detail: PrepaidDetail | undefined = undefined;
  @State private loading: boolean = false;
  @State private working: boolean = false;
  @State private error: string = '';
  @State private message: string = '';
  @State private filter: string = 'open';
  @State private showForm: boolean = false;
  @State private action: string = 'create';
  @State private nameText: string = '';
  @State private merchantText: string = '';
  @State private currencyCode: string = 'CNY';
  @State private expiryText: string = '';
  @State private projectNote: string = '';
  @State private includeNet: boolean = true;
  @State private amountText: string = '';
  @State private dateText: string = '';
  @State private noteText: string = '';
  @State private accountId: string = '';
  @State private categoryId: string = '';
  @State private incomeCategoryId: string = '';
  @State private natureId: string = '';
  @State private includeBudget: boolean = true;
  @State private bookRate: string = '';
  @State private cashRate: string = '';
  @State private actualCash: string = '';
  @State private quoteDate: string = '';
  @State private quoteSource: string = 'manual';
  @State private images: LedgerAttachmentDraft[] = [];
  @State private formError: string = '';
  private formProjectId: string = '';
  private eventId: string = '';
  private formRevision: number = 1;
  private active: boolean = false;
  private request: number = 0;
  private readonly scroller: Scroller = new Scroller();
  private readonly formScroller: Scroller = new Scroller();

  aboutToAppear(): void { this.active = true; this.onRegisterBack(()=>{this.closePage();return true;}); this.openInitialAction(); }
  aboutToDisappear(): void { this.active = false; this.request++; this.onBusy(false); this.discardImages(); }
  private async openInitialAction(): Promise<void> {
    const action = this.initialAction;
    this.onInitialActionHandled();
    await this.reload(this.initialProjectId);
    if (!this.active || this.error || this.detail?.project.id !== this.initialProjectId) { return; }
    if (['consume', 'refund', 'fund', 'edit'].includes(action)) { this.openForm(action); }
  }
  private setWorking(value: boolean): void { this.working=value; this.onBusy(value); }
  private bookCode(): string { return this.workspace?.bookCurrency.id || 'CNY'; }
  private money(minor: string, code: string = this.bookCode()): string { return Money.fromMinorText(minor,currencyUnit(code)).toDecimalString(); }
  private title(): string {
    if (this.action==='create') { return '新增预付款'; }
    if (this.action==='edit') { return '编辑预付款'; }
    if (this.action==='fund') { return '追加付款'; }
    return this.action==='consume' ? '核销预付款' : '退回剩余款';
  }
  private label(kind: string): string { return kind==='fund' ? '预付' : kind==='consume' ? '核销' : '退款'; }
  private due(project: PrepaidProject): string {
    if (!project.expiryDate || BigInt(project.remainingMinor)<=BigInt(0)) { return ''; }
    const days = (Date.parse(project.expiryDate+'T00:00:00Z')-Date.parse(prepaidToday()+'T00:00:00Z'))/86400000;
    return days<0 ? '已到期 · 请核销或联系退款' : days===0 ? '今天到期' : days<=7 ? days.toString()+' 天后到期' : '';
  }
  private visible(): PrepaidProject[] { return this.projects.filter((item: PrepaidProject) => this.filter==='all' || (this.filter==='closed' ? BigInt(item.remainingMinor)===BigInt(0) && BigInt(item.fundedMinor)>BigInt(0) : BigInt(item.remainingMinor)>BigInt(0) || BigInt(item.fundedMinor)===BigInt(0))); }
  private timeline(): PrepaidEvent[] { return this.detail?.events.slice().reverse() || []; }
  private errorText(error: Error): string {
    const code=error.message || '';
    if (code.includes('PREPAID_EXCEEDS_REMAINING') || code.includes('PREPAID_ALLOCATION')) { return '核销或退款不能超过剩余金额，请刷新后再操作'; }
    if (code.includes('PREPAID_NOT_EMPTY')) { return '项目还有有效流水或未完成草稿，不能删除，请刷新后查看'; }
    if (code.includes('PREPAID_EMPTY_CONFIRMATION_REQUIRED')) { return '这已是最后一条流水，请刷新后确认撤销并删除项目'; }
    if (code.includes('PREPAID_LINKED_HISTORY')) { return '关联账目仍有其他引用，请先处理后再删除'; }
    if (code.includes('PREPAID_CLEANUP')) { return '空项目清理校验未通过，操作已回滚，请刷新后重试'; }
    if (code.includes('PREPAID_CHANGED') || code.includes('PREPAID_UNDO_ORDER')) { return '项目已变化，请刷新后再操作；只能撤销最近一条流水'; }
    if (code.includes('ACCOUNT_UNAVAILABLE')) { return '付款／到账账户不可用，请重新选择'; }
    if (code.includes('EXPENSE_HAS_RECOVERIES')) { return '关联支出已有退款或报销，请先处理关联回款'; }
    if (code.includes('PREPAID_CATEGORY')) { return '请选择有效的收支分类和预算分类'; }
    return '请检查金额、日期、币种和汇率后重试';
  }
  private async reload(id: string = ''): Promise<void> {
    if (this.workspace===undefined) { return; }
    const version=++this.request; this.loading=true; this.error='';
    try {
      const list=await this.workspace.prepaidProjects();
      const current=id || this.detail?.project.id || '';
      const detail=current ? await this.workspace.prepaidDetail(current) : undefined;
      if (this.active && version===this.request) { this.projects=list; this.detail=detail; }
    } catch (_) { if (this.active && version===this.request) { this.error='预付款暂时无法读取，请重试'; } }
    finally { if (this.active && version===this.request) { this.loading=false; } }
  }
  private async openProject(project: PrepaidProject): Promise<void> {
    if (this.working || this.loading) { return; }
    await this.reload(project.id);
  }
  private openForm(action: string): void {
    if (this.working || this.loading) { return; }
    const project=this.detail?.project;
    if (action!=='create' && project===undefined) { return; }
    if ((action==='consume' || action==='refund') && BigInt(project?.remainingMinor || '0')<=BigInt(0)) {
      this.message='当前没有可核销或退款的余额'; return;
    }
    this.action=action; this.formProjectId=action==='create' ? util.generateRandomUUID() : project?.id || '';
    this.eventId=util.generateRandomUUID(); this.formRevision=project?.revision || 1;
    this.currencyCode=action==='create' ? this.bookCode() : project?.currencyId || 'CNY';
    this.nameText=action==='create' ? '' : project?.name || ''; this.merchantText=action==='create' ? '' : project?.merchant || '';
    this.projectNote=action==='create' ? '' : project?.note || ''; this.expiryText=action==='create' ? '' : project?.expiryDate || '';
    this.includeNet=action==='create' || project?.includeInNetAssets===true;
    this.amountText=''; this.actualCash=''; this.dateText=prepaidToday(); this.noteText=''; this.formError=''; this.images=[];
    this.accountId=this.accounts.find((item: LedgerAccount) => item.currencyId===this.currencyCode)?.id || this.accounts[0]?.id || '';
    const preset=this.detail?.events.find((event:PrepaidEvent)=>event.kind==='fund' && event.entryContext!==undefined)?.entryContext;
    this.categoryId=this.categories.find((item:ExpenseCategory)=>item.id===preset?.categoryId)?.id || this.categories[0]?.id || ''; this.incomeCategoryId=this.incomeCategories[0]?.id || ''; this.natureId=this.spendingNatures.find((item:SpendingNatureChoice)=>item.id===preset?.spendingNatureId)?.id || ''; this.includeBudget=preset?.includeInBudget!==false;
    this.resetRates(); this.showForm=true;
  }
  private accountCode(): string { return this.accounts.find((item: LedgerAccount) => item.id===this.accountId)?.currencyId || this.currencyCode; }
  private resetRates(): void { this.bookRate=this.currencyCode===this.bookCode() ? '1' : ''; this.cashRate=this.accountCode()===this.currencyCode ? '1' : ''; this.quoteSource='manual'; this.quoteDate=''; this.actualCash=''; }
  private choose(title: string, values: string[], index: number, accept: (index: number) => void): void {
    if (this.working) { return; }
    this.getUIContext().getFocusController().clearFocus();
    this.getUIContext().showTextPickerDialog({ range: values, selected: Math.max(0,index),
      selectedTextStyle: { color: $r('app.color.xq_font_emphasize') }, acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      cancelButtonStyle: { fontColor: $r('app.color.xq_font_secondary') },
      onAccept: (result: TextPickerResult) => { if (this.active && this.showForm) { accept(typeof result.index==='number' ? result.index : result.index[0]); } }
    });
  }
  private chooseCurrency(): void {
    const choices = enabledCurrencies();
    this.choose('预付款币种', choices.map((item: CurrencyDefinition) => item.code+' · '+item.name),Math.max(0,choices.findIndex((item: CurrencyDefinition) => item.code===this.currencyCode)),
      (index: number) => { this.currencyCode=choices[index].code; this.amountText=''; this.resetRates(); });
  }
  private chooseAccount(): void {
    if (this.accounts.length===0) { this.formError='请先在“资产账户”中添加付款／到账账户'; return; }
    this.choose('选择账户',this.accounts.map((item: LedgerAccount) => item.name+' · '+item.currencyId),this.accounts.findIndex((item: LedgerAccount) => item.id===this.accountId),
      (index: number) => { this.accountId=this.accounts[index].id; this.resetRates(); });
  }
  private chooseCategory(income: boolean = false): void {
    const values=income ? this.incomeCategories : this.categories;
    if (values.length===0) { this.formError='请先添加对应的收支分类'; return; }
    this.choose('选择分类',values.map((item: ExpenseCategory) => item.name),values.findIndex((item: ExpenseCategory) => item.id===(income ? this.incomeCategoryId : this.categoryId)),
      (index: number) => { if (income) { this.incomeCategoryId=values[index].id; } else { this.categoryId=values[index].id; } });
  }
  private chooseNature(): void {
    this.choose('预算分类',['不设置',...this.spendingNatures.map((item: SpendingNatureChoice) => item.name)],this.spendingNatures.findIndex((item: SpendingNatureChoice) => item.id===this.natureId)+1,
      (index: number) => { this.natureId=index===0 ? '' : this.spendingNatures[index-1].id; });
  }
  private chooseDate(expiry: boolean): void {
    if (this.working) { return; }
    this.getUIContext().getFocusController().clearFocus();
    this.getUIContext().showDatePickerDialog({ selected:new Date((expiry ? this.expiryText || prepaidToday() : this.dateText)+'T12:00:00'),
      selectedTextStyle: { color:$r('app.color.xq_font_emphasize') }, acceptButtonStyle:{ fontColor:$r('app.color.xq_font_emphasize') }, cancelButtonStyle:{ fontColor:$r('app.color.xq_font_secondary') },
      onDateAccept:(date:Date) => { if (this.active && this.showForm) { const value=`${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`; if (expiry) { this.expiryText=value; } else { this.dateText=value; } } }
    });
  }
  private async loadRates(): Promise<void> {
    if (this.working) { return; }
    if (!validPrepaidDate(this.dateText)) { this.formError='请先选择有效日期'; return; }
    this.setWorking(true); this.formError='';
    try {
      const book=await OfficialExchangeRates.quote(this.currencyCode,this.bookCode(),this.dateText);
      const cash=await OfficialExchangeRates.quote(this.currencyCode,this.accountCode(),this.dateText);
      if (this.active) {
        this.bookRate=book.rate; this.cashRate=cash.rate; this.quoteDate=book.source==='same_currency' ? cash.date : book.date;
        this.quoteSource=book.source==='manual' || cash.source==='manual' ? 'manual' : book.source==='ECB_CACHE' || cash.source==='ECB_CACHE' ? 'ECB_CACHE' : 'ECB';
      }
    } catch (_) { if (this.active) { this.formError='参考汇率暂不可用，可手动填写汇率'; } }
    finally { if (this.active) { this.setWorking(false); } }
  }
  private async chooseImages(): Promise<void> {
    if (this.working || this.workspace===undefined || this.images.length>=9) { return; }
    this.getUIContext().getFocusController().clearFocus(); this.setWorking(true);
    try {
      const options=new photoAccessHelper.PhotoSelectOptions(); options.maxSelectNumber=9-this.images.length; options.MIMEType=photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      const picked=await new photoAccessHelper.PhotoViewPicker().select(options);
      for (const uri of picked.photoUris) {
        if (!this.active) { return; }
        const draft=await this.workspace.saveImageAttachment(uri,'original');
        if (!this.active) { await this.workspace.discardUnpersistedImage(draft); return; }
        if (!this.images.some((item: LedgerAttachmentDraft) => item.sha256===draft.sha256)) { this.images=[...this.images,draft]; }
      }
    } catch (_) { if (this.active) { this.formError='图片暂未添加，可重新选择'; } }
    finally { if (this.active) { this.setWorking(false); } }
  }
  private discardImages(): void {
    const images=this.images; this.images=[];
    for (const image of images) { this.workspace?.discardUnpersistedImage(image).catch(() => {}); }
  }
  private projectCommand(): PrepaidProjectCommand {
    return { id:this.formProjectId,bookId:this.workspace?.bookId() || '',name:this.nameText,merchant:this.merchantText,currencyId:this.currencyCode,
      expiryDate:this.expiryText,note:this.projectNote,includeInNetAssets:this.includeNet,expectedRevision:this.action==='edit' ? this.formRevision : undefined };
  }
  private eventCommand(): PrepaidEventCommand {
    const amount=ExpenseAmountInput.nonnegative(this.amountText,currencyUnit(this.currencyCode));
    const kind:PrepaidEventKind=this.action==='create' || this.action==='fund' ? 'fund' : this.action==='refund' ? 'refund' : 'consume';
    let cash:Money | undefined=undefined; let cashBook:Money | undefined=undefined;
    if (kind!=='consume') {
      const code=this.accountCode();
      cash=code===this.currencyCode ? amount : this.actualCash ? ExpenseAmountInput.nonnegative(this.actualCash,currencyUnit(code)) : new ExchangeRate(amount.currency,currencyUnit(code),this.cashRate).convert(amount);
      cashBook=code===this.bookCode() ? cash : new ExchangeRate(cash.currency,currencyUnit(this.bookCode()),crossRate(this.bookRate,this.cashRate)).convert(cash);
    }
    const date=new Date(this.dateText+'T12:00:00');
    return { id:this.eventId,projectId:this.formProjectId,bookId:this.workspace?.bookId() || '',expectedRevision:this.action==='create' ? 1 : this.formRevision,kind:kind,
      amount:amount,accountId:kind==='consume' ? '' : this.accountId,cash:cash,cashBook:cashBook,rateSource:this.actualCash ? 'manual' : this.quoteSource,
      rateDate:this.quoteDate || this.dateText,bookRate:this.bookRate,cashRate:this.cashRate,categoryId:this.categoryId,incomeCategoryId:this.incomeCategoryId,
      spendingNatureId:this.natureId,includeInBudget:this.includeBudget,occurredAtMs:date.getTime(),localDate:this.dateText,offsetMinutes:-date.getTimezoneOffset(),note:this.noteText,attachments:this.images };
  }
  private async save(): Promise<void> {
    if (this.working || this.workspace===undefined) { return; }
    this.getUIContext().getFocusController().clearFocus(); this.setWorking(true); this.formError=''; this.message='';
    try {
      if (this.action==='edit') { await this.workspace.editPrepaid(this.projectCommand()); }
      else if (this.action==='create') { await this.workspace.createPrepaid(this.projectCommand(),this.eventCommand()); }
      else { await this.workspace.savePrepaidEvent(this.eventCommand()); }
      this.images=[]; this.showForm=false;
      this.message='已保存';
      await this.reload(this.formProjectId);
      try { await this.onChanged(); } catch (_) { this.error='已保存，汇总刷新失败，请返回后重新读取'; }
    } catch (error) { this.formError=this.errorText(error as Error); }
    finally { if (this.active) { this.setWorking(false); } }
  }
  private async undo(): Promise<void> {
    const project=this.detail?.project; const events=this.detail?.events || []; const latest=events[events.length-1];
    if (this.working || this.loading || project===undefined || latest===undefined || this.workspace===undefined) { return; }
    this.setWorking(true); this.error=''; this.message='';
    try {
      const last = events.length === 1;
      const result=await this.getUIContext().getPromptAction().showDialog({title:last ? '撤销并删除项目？' : '撤销最近一条流水？',message:this.label(latest.kind)+' '+this.money(latest.amountMinor,project.currencyId)+' '+project.currencyId+'\n关联的预付款余额、账户流水和支出将一起撤回。'+(last ? '\n这是最后一条有效流水，撤销后将同时删除“'+project.name+'”项目及已撤销记录，无法恢复。存在未完成草稿时不会删除，本次撤销也不会执行。' : ''),
        buttons:[{text:'取消',color:$r('app.color.xq_font_primary')},{text:last ? '撤销并删除项目' : '撤销流水',color:$r('app.color.xq_warning')}]});
      if (result.index!==1) { return; }
      const deleted = await this.workspace.undoPrepaid(project.id,latest.id,project.revision,last);
      if (deleted) { await this.projectDeleted(); }
      else { this.message='已撤销'; await this.reload(project.id); await this.onChanged(); }
    } catch (error) { this.error=this.errorText(error as Error); }
    finally { if (this.active) { this.setWorking(false); } }
  }
  private async projectDeleted(): Promise<void> {
    this.detail=undefined; this.message='已删除空项目';
    await this.reload();
    try { await this.onChanged(); } catch (_) { this.error='项目已删除，汇总刷新失败，请返回后重新读取'; }
    if (this.returnToCaller) { this.setWorking(false); this.onClose(); }
  }
  private async deleteEmptyProject(): Promise<void> {
    const project=this.detail?.project;
    if (this.working || this.loading || project===undefined || this.workspace===undefined || (this.detail?.events.length || 0)>0) { return; }
    this.setWorking(true); this.error='';
    try {
      const result=await this.getUIContext().getPromptAction().showDialog({title:'删除空项目？',
        message:'将彻底删除“'+project.name+'”及已撤销记录，账户余额保持不变，无法恢复。存在有效流水或未完成草稿时禁止删除。',
        buttons:[{text:'取消',color:$r('app.color.xq_font_primary')},{text:'删除空项目',color:$r('app.color.xq_warning')}]});
      if (result.index!==1) { return; }
      await this.workspace.deleteEmptyPrepaid(project.id,project.revision);
      await this.projectDeleted();
    } catch (error) { this.error=this.errorText(error as Error); }
    finally { if (this.active) { this.setWorking(false); } }
  }
  private closePage(): void { if (this.showForm) { if (!this.working) { this.showForm=false; } return; } if (!this.working && !this.loading) { if (this.detail!==undefined && !this.returnToCaller) { this.request++; this.detail=undefined; this.error=''; this.message=''; } else { this.onClose(); } } }
  private sheetOptions(): SheetOptions {
    const options:SheetOptions={height:SheetSize.LARGE,showClose:true,shouldDismiss:(action:SheetDismiss)=>{if (!this.working) {action.dismiss();}},
      onDisappear:()=>{if (!this.working) {this.discardImages();}}};
    if (this.sheetMaterial!==undefined) {options.systemMaterial=this.sheetMaterial;}
    else {options.backgroundColor=$r('app.color.xq_app_surface_card');}
    return options;
  }
  private statusBarColor(): string {
    const host=this.getUIContext().getHostContext();
    return host===undefined ? '#E5000000' : '#'+(host.resourceManager.getColorSync($r('app.color.xq_font_primary').id)>>>0).toString(16).padStart(8,'0');
  }

  @Builder
  private choice(label:string,value:string,action:()=>void) {
    Row({space:12}) {
      Text(label).fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
      Text(value).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).layoutWeight(1).textAlign(TextAlign.End).maxLines(1).textOverflow({overflow:TextOverflow.Ellipsis})
      Image($r('app.media.lucide_chevron_down1')).width(14).height(14).fillColor($r('app.color.xq_icon_tertiary'))
    }.width('100%').height(46).enabled(!this.working).onClick(action)
  }
  @Builder
  private form() {
    Column({space:12}) {
      Text(this.title()).fontSize('20fp').fontWeight(FontWeight.Bold).width('100%')
        .height(this.action==='edit' ? 48 : 36).padding({right:48})
      Scroll(this.formScroller) {
        Column({space:14}) {
          if (this.action==='create' || this.action==='edit') {
            Column({space:12}) {
            Text('项目名称').fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            TextInput({text:this.nameText,placeholder:'项目名称，例如：健身课程、储值卡'}).fontSize('15fp').height(48).padding({left:14,right:14}).borderRadius(12).backgroundColor($r('app.color.xq_app_surface_page')).maxLength(40).enabled(!this.working).onChange((value:string)=>{this.nameText=value;})
            TextInput({text:this.merchantText,placeholder:'商户（选填）'}).fontSize('14fp').height(48).padding({left:14,right:14}).borderRadius(12).backgroundColor($r('app.color.xq_app_surface_page')).maxLength(100).enabled(!this.working).onChange((value:string)=>{this.merchantText=value;})
            if (this.action==='create') { this.choice('币种',this.currencyCode,()=>{this.chooseCurrency();}) }
            this.choice('到期日期',this.expiryText || '不设置',()=>{this.chooseDate(true);})
            if (this.expiryText) { Button('清除到期日期').fontSize('12fp').backgroundColor(Color.Transparent).fontColor($r('app.color.xq_font_secondary')).enabled(!this.working).onClick(()=>{this.expiryText='';}) }
            Row() { Text('计入净资产').fontSize('14fp').layoutWeight(1); Toggle({type:ToggleType.Switch,isOn:this.includeNet}).selectedColor($r('app.color.xq_brand')).enabled(!this.working).onChange((value:boolean)=>{this.includeNet=value;}) }.width('100%')
            TextArea({text:this.projectNote,placeholder:'项目备注（选填）'}).fontSize('14fp').height(88).padding(12).backgroundColor($r('app.color.xq_app_surface_page')).borderRadius(12).enabled(!this.working).maxLength(2000).onChange((value:string)=>{this.projectNote=value;})
            }.padding(16).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
          }
          if (this.action!=='edit') {
            Column({space:8}) {
            Text((this.action==='create' || this.action==='fund' ? '本次预付金额' : this.action==='consume' ? '本次核销金额' : '本次退回原余额')+' · '+this.currencyCode).fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            MoneyAmountField({value:$amountText,fieldId:'prepaid-amount',currency:currencyUnit(this.currencyCode),
              fontSize:'36fp',fieldHeight:64,placeholder:currencyUnit(this.currencyCode).scale===0 ? '0' : '0.00',
              disabled:this.working,submitLabel:this.action==='consume' ? '确认核销' : this.action==='refund' ? '确认退款' : '保存付款',
              onChange:()=>{this.formError='';},onSubmit:()=>{this.save();}})
            if (this.action==='consume' || this.action==='refund') {
              Row() {
                Text('剩余 '+this.money(this.detail?.project.remainingMinor || '0',this.currencyCode)+' '+this.currencyCode).fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).layoutWeight(1)
                Button('全部剩余', {type:ButtonType.Capsule}).height(30).padding({left:10,right:10}).fontSize('12fp').backgroundColor(Color.Transparent).fontColor($r('app.color.xq_font_emphasize')).enabled(!this.working).onClick(()=>{this.amountText=this.money(this.detail?.project.remainingMinor || '0',this.currencyCode);})
              }.width('100%')
            }
            }.padding(16).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
            Column({space:4}) {
            this.choice('日期',this.dateText,()=>{this.chooseDate(false);})
            if (this.action!=='consume') {
              this.choice(this.action==='refund' ? '到账账户' : '付款账户',this.accounts.find((item:LedgerAccount)=>item.id===this.accountId)?.name || '选择账户',()=>{this.chooseAccount();})
              if (this.currencyCode!==this.bookCode()) { TextInput({text:this.bookRate,placeholder:'参考汇率：1 '+this.currencyCode+' = ? ' + this.bookCode()}).fontSize('14fp').type(InputType.NUMBER_DECIMAL).enabled(!this.working).onChange((value:string)=>{this.bookRate=value;this.quoteSource='manual';this.quoteDate=this.dateText;}) }
              if (this.accountCode()!==this.currencyCode) {
                TextInput({text:this.cashRate,placeholder:'结算汇率：1 '+this.currencyCode+' = ? '+this.accountCode()}).fontSize('14fp').type(InputType.NUMBER_DECIMAL).enabled(!this.working).onChange((value:string)=>{this.cashRate=value;this.quoteSource='manual';this.quoteDate=this.dateText;})
                MoneyAmountField({value:$actualCash,fieldId:'prepaid-actual-cash',currency:currencyUnit(this.accountCode()),
                  fontSize:'14fp',allowEmpty:true,placeholder:'实际账户金额 '+this.accountCode()+'（选填）',disabled:this.working,
                  onChange:()=>{this.formError='';}})
              }
              if (this.currencyCode!==this.bookCode() || this.accountCode()!==this.currencyCode) {
                Button('获取参考汇率').fontSize('13fp').backgroundColor(Color.Transparent).fontColor($r('app.color.xq_font_emphasize')).enabled(!this.working).onClick(()=>{this.loadRates();})
                Text((this.quoteDate ? this.quoteDate+' · ' : '')+(this.quoteSource==='manual' ? '手动汇率' : '欧洲中央银行 ECB · 官网免费参考汇率')).fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
              }
            }
            if (this.action==='consume' || this.action==='refund') {
              this.choice(this.action==='consume' ? '支出分类' : '退款差额支出分类',this.categories.find((item:ExpenseCategory)=>item.id===this.categoryId)?.name || '选择分类',()=>{this.chooseCategory();})
              if (this.action==='refund') { this.choice('退款差额收入分类',this.incomeCategories.find((item:ExpenseCategory)=>item.id===this.incomeCategoryId)?.name || '选择分类',()=>{this.chooseCategory(true);}) }
            }
            if (this.action==='consume') {
              this.choice('预算分类',this.spendingNatures.find((item:SpendingNatureChoice)=>item.id===this.natureId)?.name || '不设置',()=>{this.chooseNature();})
              Row() { Text('计入预算').fontSize('14fp').layoutWeight(1); Toggle({type:ToggleType.Switch,isOn:this.includeBudget}).selectedColor($r('app.color.xq_brand')).enabled(!this.working).onChange((value:boolean)=>{this.includeBudget=value;}) }.width('100%')
              Text('按历史付款成本计支出，不会再次扣付款账户').fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            }
            }.padding({left:16,right:16,top:8,bottom:12}).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
            Column({space:14}) {
            TextArea({text:this.noteText,placeholder:'本次流水备注（选填）'}).fontSize('14fp').height(88).padding(12).backgroundColor($r('app.color.xq_app_surface_page')).borderRadius(12).maxLength(2000).enabled(!this.working).onChange((value:string)=>{this.noteText=value;})
            this.imageDrafts()
            }.padding(16).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
          }
          if (this.formError) { Text(this.formError).fontSize('13fp').fontColor($r('app.color.xq_warning')).width('100%') }
        }.width('100%').padding({bottom:16}).justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.Top).scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      Button(this.working ? '处理中…' : this.action==='edit' ? '保存修改' : this.action==='consume' ? '确认核销' : this.action==='refund' ? '确认退款' : '保存付款')
        .height(48).width('100%').borderRadius(24).fontSize('16fp').fontWeight(FontWeight.Medium).fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.working).onClick(()=>{this.save();})
    }.padding({left:20,right:20,top:20,bottom:24}).width('100%').height('100%')
      .justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Start)
  }
  @Builder
  private imageDrafts() {
    Column({space:8}) {
      Row() { Text('图片附件').fontSize('14fp').layoutWeight(1); Text(this.images.length.toString()+' / 9').fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')) }.width('100%')
      Flex({wrap:FlexWrap.Wrap}) {
        ForEach(this.images,(image:LedgerAttachmentDraft)=>{
          Image((this.workspace?.backup.resources.root || '')+'/'+image.relativePath).width(68).height(68).objectFit(ImageFit.Cover).borderRadius(10).margin({right:8,bottom:8})
            .accessibilityText('移除待保存图片').enabled(!this.working).onClick(()=>{this.images=this.images.filter((item:LedgerAttachmentDraft)=>item.sha256!==image.sha256);this.workspace?.discardUnpersistedImage(image).catch(()=>{});})
        },(image:LedgerAttachmentDraft)=>image.sha256)
        if (this.images.length<9) { Button('+').width(68).height(68).fontSize('28fp').borderRadius(10).backgroundColor($r('app.color.xq_app_surface_page')).enabled(!this.working).accessibilityText('添加原图附件').onClick(()=>{this.chooseImages();}) }
      }.width('100%')
      if (this.images.length>0) { Text('点击待保存图片可移除').fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')).width('100%') }
    }.width('100%')
  }
  @Builder
  private projectCard(project:PrepaidProject) {
    Column({space:12}) {
      Row({space:12}) {
        Text(project.name).fontSize('16fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary')).layoutWeight(1).maxLines(1).textOverflow({overflow:TextOverflow.Ellipsis})
        Text(prepaidStatus(project)).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
      }.width('100%')
      Text('剩余 '+this.money(project.remainingMinor,project.currencyId)+' '+project.currencyId).fontSize('24fp').fontFamily('XiaoQiaoDINMedium').fontColor($r('app.color.xq_font_primary')).width('100%')
      Text('预付 '+this.money(project.fundedMinor,project.currencyId)+' · 核销 '+this.money(project.consumedMinor,project.currencyId)+' · 退款 '+this.money(project.refundedMinor,project.currencyId)).fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      if (project.merchant) { Text(project.merchant).fontSize('13fp').fontColor($r('app.color.xq_font_secondary')).width('100%') }
      if (this.due(project)) { Text(this.due(project)).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%') }
      else if (project.expiryDate) { Text('到期 '+project.expiryDate).fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')).width('100%') }
    }.padding(18).width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card')).onClick(()=>{this.openProject(project);})
  }
  @Builder
  private detailBody() {
    if (this.detail!==undefined) {
      this.projectCard(this.detail.project)
      Text('剩余历史成本 ¥'+this.money(this.detail.project.remainingBookMinor)+(this.detail.project.includeInNetAssets ? ' · 计入净资产' : ' · 不计入净资产')).fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      if (this.detail.project.note) { Text(this.detail.project.note).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).width('100%') }
      Row({space:8}) {
        Button('追加付款', {type:ButtonType.Capsule}).layoutWeight(1).height(44).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).backgroundColor($r('app.color.xq_app_surface_card')).enabled(!this.working&&!this.loading).onClick(()=>{this.openForm('fund');})
        Button('核销', {type:ButtonType.Capsule}).layoutWeight(1).height(44).fontSize('14fp').fontWeight(FontWeight.Medium).fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.working&&!this.loading&&BigInt(this.detail?.project.remainingMinor || '0')>BigInt(0)).onClick(()=>{this.openForm('consume');})
        Button('退款', {type:ButtonType.Capsule}).layoutWeight(1).height(44).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).backgroundColor($r('app.color.xq_app_surface_card')).enabled(!this.working&&!this.loading&&BigInt(this.detail?.project.remainingMinor || '0')>BigInt(0)).onClick(()=>{this.openForm('refund');})
      }.width('100%')
      Button('编辑项目', {type:ButtonType.Capsule}).height(32).fontSize('13fp').backgroundColor(Color.Transparent).fontColor($r('app.color.xq_font_emphasize')).enabled(!this.working&&!this.loading).onClick(()=>{this.openForm('edit');})
      if (this.detail.events.length===0) {
        Button('删除空项目', {type:ButtonType.Capsule}).height(40).fontSize('14fp').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.xq_warning')).backgroundColor($r('app.color.xq_app_surface_card'))
          .enabled(!this.working&&!this.loading).onClick(()=>{this.deleteEmptyProject();}).id('prepaid-delete-empty')
      }
      Text('流水记录').fontSize('18fp').fontWeight(FontWeight.Medium).width('100%')
      ForEach(this.timeline(),(event:PrepaidEvent)=>{
        Column({space:8}) {
          Row() { Text(this.label(event.kind)).fontSize('15fp').layoutWeight(1); Text(this.money(event.amountMinor,this.detail?.project.currencyId || 'CNY')+' '+(this.detail?.project.currencyId || '')).fontSize('17fp').fontFamily('XiaoQiaoDINMedium').fontColor(this.transactionColor(event.kind === 'refund' ? 'income' : event.kind === 'consume' ? 'expense' : 'transfer')) }.width('100%')
          Text(event.localDate+' · 历史成本 ¥'+this.money(event.bookMinor)).fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
          if (event.accountId) { Text(event.accountName+' · '+(event.kind==='fund' ? '付款 ' : '到账 ')+this.money(event.cashMinor,event.accountCurrencyId)+' '+event.accountCurrencyId).fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%') }
          if (event.kind==='refund'&&event.cashBookMinor!==event.bookMinor) { Text('退款差额 '+this.money((BigInt(event.cashBookMinor)-BigInt(event.bookMinor)).toString())+' '+this.bookCode()+'，已单独记录收支').fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%') }
          if (event.entryContext?.categoryName) { Text('核销分类预设 · '+event.entryContext.categoryName).fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%') }
          if (event.entryContext?.addressText) { Text(event.entryContext.addressText).fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%') }
          if ((event.entryContext?.tagNames.length || 0)>0) { Text((event.entryContext?.tagNames || []).join(' · ')).fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%') }
          if (event.note) { Text(event.note).fontSize('13fp').width('100%') }
          Flex({wrap:FlexWrap.Wrap}) { ForEach(event.attachments,(image:LedgerAttachmentDraft)=>{Image((this.workspace?.backup.resources.root || '')+'/'+image.relativePath).width(68).height(68).objectFit(ImageFit.Cover).borderRadius(10).margin({right:8,bottom:8})},(image:LedgerAttachmentDraft)=>image.sha256) }.width('100%')
        }.width('100%').padding(16).borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
      },(event:PrepaidEvent)=>event.id)
      if (this.detail.events.length>0) { Button('撤销最近一条流水', {type:ButtonType.Capsule}).height(40).fontSize('13fp').width('100%').fontColor($r('app.color.xq_warning')).backgroundColor($r('app.color.xq_app_surface_card')).enabled(!this.working&&!this.loading).onClick(()=>{this.undo();}) }
    }
  }
  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({space:16}) {
          if (this.detail===undefined) {
            Text('预付时转为资产，核销时计支出；到期不会自动清零').fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            Row({space:8}) {
              Button('待核销').layoutWeight(1).fontSize('13fp').fontColor(this.filter==='open' ? Color.White : $r('app.color.xq_font_secondary')).backgroundColor(this.filter==='open' ? $r('app.color.xq_brand') : $r('app.color.xq_app_surface_card')).onClick(()=>{this.filter='open';})
              Button('已结清').layoutWeight(1).fontSize('13fp').fontColor(this.filter==='closed' ? Color.White : $r('app.color.xq_font_secondary')).backgroundColor(this.filter==='closed' ? $r('app.color.xq_brand') : $r('app.color.xq_app_surface_card')).onClick(()=>{this.filter='closed';})
              Button('全部').layoutWeight(1).fontSize('13fp').fontColor(this.filter==='all' ? Color.White : $r('app.color.xq_font_secondary')).backgroundColor(this.filter==='all' ? $r('app.color.xq_brand') : $r('app.color.xq_app_surface_card')).onClick(()=>{this.filter='all';})
            }.width('100%')
            ForEach(this.visible(),(project:PrepaidProject)=>{this.projectCard(project)},(project:PrepaidProject)=>project.id+':'+project.revision.toString())
            if (!this.loading&&!this.error&&this.visible().length===0) { Text('暂无'+(this.filter==='closed' ? '已结清' : '')+'预付款').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).padding(24) }
            Button('新增预付款').width('100%').height(44).fontSize('15fp').fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).enabled(!this.working&&!this.loading).onClick(()=>{this.onCreate();})
          } else { this.detailBody() }
          if (this.loading) { Text('正在读取…').fontSize('13fp').fontColor($r('app.color.xq_font_secondary')) }
          if (this.message) { Text(this.message).fontSize('13fp').fontColor($r('app.color.xq_font_secondary')).width('100%') }
          if (this.error) { Text(this.error).fontSize('13fp').fontColor($r('app.color.xq_warning')).width('100%') }
          Button('刷新').fontSize('13fp').fontColor($r('app.color.xq_font_emphasize')).backgroundColor(Color.Transparent).enabled(!this.working&&!this.loading).onClick(()=>{this.reload();})
        }.width('100%').padding({left:16,right:16,top:12,bottom:32})
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({enableComponentSafeArea:true,content:{title:{mainTitle:this.detail===undefined ? '预付款与核销' : this.detail.project.name},divider:{showType:DividerShowType.OFF},backIcon:{action:()=>{this.closePage();}}},style:{
        originalStyle:{contentStyle:{titleStyle:{mainTitleColor:$r('app.color.xq_font_primary')},backIconStyle:{iconColor:$r('app.color.xq_icon_primary')}}},
        scrollEffectStyle:{contentStyle:{titleStyle:{mainTitleColor:$r('app.color.xq_font_primary')},backIconStyle:{iconColor:$r('app.color.xq_icon_primary')}}},
        systemMaterialEffect:{materialType:hdsMaterial.MaterialType.IMMERSIVE,materialLevel:hdsMaterial.MaterialLevel.ADAPTIVE},
        scrollEffectOpts:{enableScrollEffect:true,scrollEffectType:ScrollEffectType.IMMERSIVE_GRADIENT_BLUR}}})
      .systemBarStyle({statusBarContentColor:this.statusBarColor()},{statusBarContentColor:this.statusBarColor()})
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],[LayoutSafeAreaEdge.TOP]).expandSafeArea([SafeAreaType.SYSTEM],[SafeAreaEdge.TOP,SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showForm,this.form(),this.sheetOptions())
  }
}
