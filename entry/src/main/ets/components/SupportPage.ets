import { bundleManager, common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { SupportPageKind, HelpQuestion, FeedbackDraft, FEEDBACK_EMAIL, supportTitle, searchHelp, feedbackText, feedbackMailUri } from '../presentation/support/SupportContent';

/** Three local-information subpages share navigation and return handling, without requiring a ledger or login. */
@Component
export struct SupportPage {
  @Prop kind: SupportPageKind = 'help';
  onClose: () => void = () => {};
  onRegisterBack: (handler: () => boolean) => void = () => {};
  @State private query: string = '';
  @State private expanded: string[] = [];
  @State private titleText: string = '';
  @State private detailText: string = '';
  @State private contactText: string = '';
  @State private titleError: string = '';
  @State private detailError: string = '';
  @State private message: string = '';
  @State private error: boolean = false;
  @State private focusedField: string = '';
  @State private working: boolean = false;
  @State private confirming: boolean = false;
  @State private version: string = '读取中…';
  @State private versionLoading: boolean = false;
  @State private versionError: string = '';
  private active: boolean = false;
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.active = true;
    this.onRegisterBack((): boolean => { this.closePage(); return true; });
    this.loadVersion();
  }
  aboutToDisappear(): void { this.active = false; this.onRegisterBack((): boolean => false); }
  private async loadVersion(): Promise<void> {
    if (this.versionLoading) { return; }
    this.versionLoading = true; this.versionError = '';
    try {
      const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      if (this.active) { this.version = info.versionName + ' (' + info.versionCode.toString() + ')'; }
    } catch (_) { if (this.active) { this.version = '暂不可用'; this.versionError = '版本信息读取失败'; } }
    finally { if (this.active) { this.versionLoading = false; } }
  }
  private hasDraft(): boolean { return !!(this.titleText.trim() || this.detailText.trim() || this.contactText.trim()); }
  private async closePage(): Promise<void> {
    if (this.working || this.confirming) { return; }
    this.getUIContext().getFocusController().clearFocus();
    if (this.kind !== 'feedback' || !this.hasDraft()) { this.onClose(); return; }
    this.confirming = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({ title: '离开意见反馈？',
        message: '离开后会清空当前页面填写的内容。你可以继续编辑，或先复制内容。',
        buttons: [{ text: '继续编辑', color: $r('app.color.xq_font_primary') }, { text: '离开', color: $r('app.color.xq_warning') }] });
      if (result.index === 1 && this.active) { this.onClose(); }
    } catch (_) { /* Dismissing the dialog retains the draft. */ }
    finally { if (this.active) { this.confirming = false; } }
  }
  private draft(): FeedbackDraft {
    return { title: this.titleText, detail: this.detailText, contact: this.contactText, version: this.version };
  }
  private validFeedback(): boolean {
    this.titleError = this.titleText.trim() ? '' : '请填写反馈主题';
    this.detailError = this.detailText.trim() ? '' : '请填写反馈内容';
    return !this.titleError && !this.detailError;
  }
  private async openMail(): Promise<void> {
    if (this.working || !this.validFeedback()) { return; }
    this.getUIContext().getFocusController().clearFocus();
    this.working = true; this.message = ''; this.error = false;
    try {
      const host = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (host === undefined) { throw new Error('CONTEXT_UNAVAILABLE'); }
      await host.startAbility({ action: 'ohos.want.action.viewData', uri: feedbackMailUri(this.draft()) });
      if (this.active) { this.message = '已打开邮件草稿，请在邮件应用中确认发送。'; }
    } catch (_) {
      if (this.active) { this.message = '未能打开邮件应用。请复制反馈内容，发送至 ' + FEEDBACK_EMAIL; this.error = true; }
    } finally { if (this.active) { this.working = false; } }
  }
  private async copyFeedback(): Promise<void> {
    if (this.working || !this.validFeedback()) { return; }
    this.working = true; this.message = ''; this.error = false;
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
        '收件人：' + FEEDBACK_EMAIL + '\n\n' + feedbackText(this.draft())));
      if (this.active) { this.message = '已复制反馈内容和收件邮箱，请粘贴到邮件中发送。'; }
    } catch (_) { if (this.active) { this.message = '复制失败，请长按选择需要的内容后重试'; this.error = true; } }
    finally { if (this.active) { this.working = false; } }
  }
  private toggleQuestion(id: string): void {
    this.expanded = this.expanded.includes(id) ? this.expanded.filter((value: string) => value !== id) : [...this.expanded,id];
  }
  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8,'0');
  }
  @Builder
  private helpContent() {
    TextInput({ text: this.query, placeholder: '搜索常见问题' }).height(48).fontSize('14fp').padding({ left: 14, right: 14 })
      .fontColor($r('app.color.xq_font_primary')).placeholderColor($r('app.color.xq_font_tertiary')).caretColor($r('app.color.xq_brand'))
      .backgroundColor($r('app.color.xq_app_surface_card')).borderRadius(12)
      .border({ width: 1, color: this.focusedField === 'query' ? $r('app.color.xq_brand') : $r('app.color.xq_exchange_form_border') })
      .onFocus(() => { this.focusedField = 'query'; }).onBlur(() => { this.focusedField = ''; })
      .onChange((value: string) => { this.query = value; }).maxLength(80).id('help-query')
    ForEach(searchHelp(this.query), (item: HelpQuestion) => {
      Column() {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 12 }) {
            Text(item.question).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).layoutWeight(1).textAlign(TextAlign.Start)
            Image(this.expanded.includes(item.id) ? $r('app.media.lucide_chevron_up1') : $r('app.media.lucide_chevron_down1'))
              .width(16).height(16).fillColor($r('app.color.xq_icon_secondary')).flexShrink(0)
          }.width('100%')
        }.width('100%').constraintSize({ minHeight: 52 }).padding(16).borderRadius(0)
          .fontColor($r('app.color.xq_font_primary')).backgroundColor(Color.Transparent)
          .onClick(() => { this.toggleQuestion(item.id); }).accessibilityText(item.question + (this.expanded.includes(item.id) ? '，收起' : '，展开'))
          .id('help-question-' + item.id)
        if (this.expanded.includes(item.id)) {
          Text(item.answer).fontSize('14fp').lineHeight('22fp').fontColor($r('app.color.xq_font_secondary'))
            .width('100%').padding({ left: 16, right: 16, bottom: 16 })
        }
      }.width('100%').borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card')).clip(true)
    }, (item: HelpQuestion) => item.id)
    if (searchHelp(this.query).length === 0) {
      Text('没有匹配的问题，请换个关键词。').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%').padding(16)
    }
  }
  @Builder
  private feedbackContent() {
    Text('收件邮箱：' + FEEDBACK_EMAIL).fontSize('13fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
      .padding({ left: 8, right: 8 }).copyOption(CopyOptions.LocalDevice)
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Text('主题').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
        TextInput({ text: this.titleText, placeholder: '简要描述问题或建议' }).height(48).fontSize('14fp').padding({ left: 14, right: 14 })
          .fontColor($r('app.color.xq_font_primary')).placeholderColor($r('app.color.xq_font_tertiary')).caretColor($r('app.color.xq_brand'))
          .backgroundColor($r('app.color.xq_app_surface_page')).borderRadius(12)
          .border({ width: 1, color: this.focusedField === 'title' ? $r('app.color.xq_brand') : $r('app.color.xq_exchange_form_border') })
          .onFocus(() => { this.focusedField = 'title'; }).onBlur(() => { this.focusedField = ''; })
          .onChange((value: string) => { this.titleText = value; this.titleError = ''; }).maxLength(80).enabled(!this.working).id('feedback-title')
        if (this.titleError) { Text(this.titleError).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%') }
      }.width('100%')
      Column({ space: 8 }) {
        Text('反馈内容').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
        TextArea({ text: this.detailText, placeholder: '请说明操作步骤、实际结果和期望结果' }).height(160).fontSize('14fp').padding(14)
          .fontColor($r('app.color.xq_font_primary')).placeholderColor($r('app.color.xq_font_tertiary')).caretColor($r('app.color.xq_brand'))
          .backgroundColor($r('app.color.xq_app_surface_page')).borderRadius(12)
          .border({ width: 1, color: this.focusedField === 'detail' ? $r('app.color.xq_brand') : $r('app.color.xq_exchange_form_border') })
          .onFocus(() => { this.focusedField = 'detail'; }).onBlur(() => { this.focusedField = ''; })
          .onChange((value: string) => { this.detailText = value; this.detailError = ''; }).maxLength(2000).enabled(!this.working).id('feedback-detail')
        if (this.detailError) { Text(this.detailError).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%') }
      }.width('100%')
      Column({ space: 8 }) {
        Text('联系方式（选填）').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
        TextInput({ text: this.contactText, placeholder: '方便回复你的联系方式' }).height(48).fontSize('14fp').padding({ left: 14, right: 14 })
          .fontColor($r('app.color.xq_font_primary')).placeholderColor($r('app.color.xq_font_tertiary')).caretColor($r('app.color.xq_brand'))
          .backgroundColor($r('app.color.xq_app_surface_page')).borderRadius(12)
          .border({ width: 1, color: this.focusedField === 'contact' ? $r('app.color.xq_brand') : $r('app.color.xq_exchange_form_border') })
          .onFocus(() => { this.focusedField = 'contact'; }).onBlur(() => { this.focusedField = ''; })
          .onChange((value: string) => { this.contactText = value; }).maxLength(100).enabled(!this.working).id('feedback-contact')
      }.width('100%')
    }.width('100%').padding(16).borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
    Text('将填写内容和应用版本带入邮件草稿，请在邮件应用内确认发送。').fontSize('12fp')
      .fontColor($r('app.color.xq_font_secondary')).width('100%').padding({ left: 8, right: 8 })
    Button(this.working ? '处理中…' : '打开邮件应用', { type: ButtonType.Capsule }).width('100%').height(48)
      .fontSize('15fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_on_primary')).backgroundColor($r('app.color.xq_brand'))
      .enabled(!this.working && !this.versionLoading).onClick(() => { this.openMail(); }).id('feedback-open-mail')
    Button('复制反馈内容', { type: ButtonType.Capsule }).height(40).fontSize('14fp').fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_card'))
      .enabled(!this.working && !this.versionLoading).onClick(() => { this.copyFeedback(); }).id('feedback-copy')
    if (this.message) { Text(this.message).fontSize('13fp').fontColor(this.error ? $r('app.color.xq_warning') : $r('app.color.xq_font_secondary')).width('100%') }
  }
  @Builder
  private aboutContent() {
    Column({ space: 12 }) {
      Image($r('app.media.startIcon')).width(72).height(72).objectFit(ImageFit.Contain)
      Text($r('app.string.app_name')).fontSize('22fp').fontWeight(FontWeight.Bold).fontColor($r('app.color.xq_font_primary'))
      Text('记录收支、管理账户与预算。').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
    }.width('100%').padding(24).borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
    Column({ space: 16 }) {
      Row({ space: 16 }) {
        Text('当前版本').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).layoutWeight(1)
        Text(this.version).fontSize('14fp').fontFamily('XiaoQiaoDINRegular').fontColor($r('app.color.xq_font_primary'))
      }.width('100%')
      Divider().strokeWidth(0.5).color($r('app.color.xq_app_divider_subtle'))
      Row({ space: 16 }) {
        Text('反馈邮箱').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).layoutWeight(1)
        Text(FEEDBACK_EMAIL).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).copyOption(CopyOptions.LocalDevice)
      }.width('100%')
    }.width('100%').padding(16).borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
    if (this.versionError) {
      Text(this.versionError).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%')
      Button('重新读取版本', { type: ButtonType.Capsule }).height(40).fontSize('14fp').fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_card'))
        .enabled(!this.versionLoading).onClick(() => { this.loadVersion(); })
    }
  }
  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          if (this.kind === 'help') { this.helpContent() }
          else if (this.kind === 'feedback') { this.feedbackContent() }
          else { this.aboutContent() }
        }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true,
        content: { title: { mainTitle: supportTitle(this.kind) }, divider: { showType: DividerShowType.OFF }, backIcon: { action: () => { this.closePage(); } } },
        style: {
          originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]).id('support-' + this.kind + '-page')
  }
}
