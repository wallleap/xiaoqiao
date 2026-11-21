import { LedgerWorkspace } from '../data/rdb/LedgerWorkspace';
import { CurrencyProfile, CurrencyFlagChoice, ManualCurrencyRate, currencyProfiles, currencySettings,
  BUILTIN_CURRENCY_CODES, configuredFlag, validManualRate } from '../core/money/CurrencySettings';
import { crossRate } from '../core/money/Currencies';
import { REGION_FLAGS, RegionFlag, regionFlag, CURRENCY_FLAGS, CurrencyFlagAsset } from '../presentation/exchange/CurrencyFlags';
import { adaptiveColumns, gridColumnsTemplate } from '../presentation/layout/AdaptiveGrid';
import { CurrencyFlagBadge } from './CurrencyFlagBadge';
import { ExchangeRateField } from './ExchangeRateField';

@Component
export struct CurrencyManagerSheet {
  workspace: LedgerWorkspace | undefined = undefined;
  @Prop baseCode: string = 'CNY';
  initialTarget: string = '';
  onSaved: (createdCode?: string) => void = () => {};
  onModeChanged: (mode: string) => void = () => {};
  onClose: () => void = () => {};
  @State private mode: string = 'list';
  @State private profiles: CurrencyProfile[] = [];
  @State private keyword: string = '';
  @State private code: string = '';
  @State private name: string = '';
  @State private symbol: string = '';
  @State private minorDigits: string = '2';
  @State private region: string = '';
  @State private rate: string = '';
  @State private working: boolean = false;
  @State private error: string = '';
  @State private revision: number = 0;
  @State private flagColumns: number = 4;
  @State private focusedField: string = '';
  private original: CurrencyProfile | undefined = undefined;
  private alive: boolean = false;
  private readonly selectionVersions: Map<string, number> = new Map();

  aboutToAppear(): void {
    this.alive = true; this.profiles = currencyProfiles();
    const target = this.profiles.find((item: CurrencyProfile) => item.code === this.initialTarget);
    if (target !== undefined) { this.edit(target, true); }
  }
  aboutToDisappear(): void { this.alive = false; }
  private setMode(mode: string): void {
    if (mode === this.mode) { return; }
    this.mode = mode; this.onModeChanged(mode);
  }
  private today(): string {
    const now = new Date();
    return now.getFullYear().toString() + '-' + (now.getMonth()+1).toString().padStart(2,'0') + '-' + now.getDate().toString().padStart(2,'0');
  }
  private title(): string {
    return this.mode === 'flags' ? '选择旗帜' : this.mode === 'rate' ? '手动汇率' : this.mode === 'edit' ?
      (this.original === undefined ? '新增币种' : '编辑币种') : '管理币种';
  }
  private edit(profile: CurrencyProfile | undefined, rateOnly: boolean = false): void {
    this.original = profile; this.error = ''; this.keyword = ''; this.focusedField = '';
    this.code = profile?.code || ''; this.name = profile?.name || ''; this.symbol = profile?.symbol || ''; this.minorDigits = (profile?.scale ?? 2).toString();
    this.region = profile === undefined ? '' : configuredFlag(profile.code) ??
      CURRENCY_FLAGS.find((item: CurrencyFlagAsset) => item.currencyCode === profile.code)?.regionCode ?? '';
    const rate = currencySettings().rates.find((item: ManualCurrencyRate) =>
      (item.from === this.baseCode && item.to === this.code) || (item.to === this.baseCode && item.from === this.code));
    this.rate = rate === undefined ? '' : rate.from === this.baseCode ? rate.rate : crossRate('1',rate.rate);
    this.setMode(rateOnly ? 'rate' : 'edit');
  }
  private async changed(): Promise<void> {
    const close = this.mode === 'rate' && this.initialTarget.length > 0;
    this.onSaved(this.original === undefined ? this.code.trim().toUpperCase() : '');
    if (!this.alive) { return; }
    if (close) { this.onClose(); return; }
    this.revision++; this.profiles = currencyProfiles(); this.setMode('list'); this.keyword = '';
  }
  private editFromCard(profile: CurrencyProfile): void {
    if (this.working) { return; }
    const current = this.profiles.find((item: CurrencyProfile) => item.code === profile.code);
    if (current !== undefined) { this.edit(current); }
  }
  private async toggleSelection(profile: CurrencyProfile): Promise<void> {
    if (profile.code === 'CNY' || this.working) { return; }
    const current = this.profiles.find((item: CurrencyProfile) => item.code === profile.code);
    if (current === undefined) { return; }
    await this.toggle(current, !current.enabled);
  }
  private async toggle(profile: CurrencyProfile, enabled: boolean): Promise<void> {
    if (this.working || this.workspace === undefined) { return; }
    const version = (this.selectionVersions.get(profile.code) || 0) + 1;
    this.selectionVersions.set(profile.code, version);
    this.error = '';
    this.setSelection(profile.code, enabled);
    try {
      // RdbSession serializes writes. Do not lock other cards or replace their pending UI choices.
      await this.workspace.currencySettings.setEnabled(profile, enabled);
      this.onSaved();
    } catch (_) {
      if (this.alive && this.selectionVersions.get(profile.code) === version) {
        const saved = currencyProfiles().find((item: CurrencyProfile) => item.code === profile.code);
        this.setSelection(profile.code, saved?.enabled ?? profile.enabled);
        this.error = '启用状态保存失败，请重试；人民币需保持启用';
      }
    }
  }
  private setSelection(code: string, selected: boolean): void {
    this.profiles = this.profiles.map((item: CurrencyProfile): CurrencyProfile => ({ code: item.code, name: item.name,
      symbol: item.symbol, scale: item.scale, custom: item.custom, enabled: item.code === code ? selected : item.enabled }));
  }
  private isSelected(code: string): boolean {
    return this.profiles.find((item: CurrencyProfile) => item.code === code)?.enabled ?? false;
  }
  private profileName(code: string): string {
    return this.profiles.find((item: CurrencyProfile) => item.code === code)?.name || code;
  }

  private async save(): Promise<void> {
    if (this.working || this.workspace === undefined) { return; }
    const code = this.code.trim().toUpperCase();
    if (!/^[A-Z]{3}$/.test(code) || !this.name.trim() || !this.symbol.trim() || !/^[0-4]$/.test(this.minorDigits)) {
      this.error = '请填写三位大写字母代码、名称、符号，小数位为 0～4'; return;
    }
    if (this.original === undefined && this.profiles.some((item: CurrencyProfile) => item.code === code)) {
      this.error = '此币种代码已存在，请编辑已有币种'; return;
    }
    if (code !== this.baseCode && ((this.original === undefined || this.mode === 'rate') && !validManualRate(this.rate) ||
      this.rate.length > 0 && !validManualRate(this.rate))) { this.error = '请输入大于 0 的汇率，最多 12 位小数'; return; }
    const settings = currencySettings();
    if (this.mode !== 'rate') {
      settings.flags = settings.flags.filter((item: CurrencyFlagChoice) => item.code !== code);
      settings.flags.push({ code: code, region: this.region });
    }
    if (code !== this.baseCode && this.rate.length > 0) {
      settings.rates = settings.rates.filter((item: ManualCurrencyRate) =>
        !((item.from === this.baseCode && item.to === code) || (item.to === this.baseCode && item.from === code)));
      settings.rates.push({ from: this.baseCode, to: code, rate: this.rate, date: this.today() });
    }
    const profile: CurrencyProfile = { code: code, name: this.name.trim(), symbol: this.symbol.trim(), scale: Number(this.minorDigits),
      enabled: this.original?.enabled ?? true, custom: this.original?.custom ?? true };
    this.working = true; this.error = '';
    try { await this.workspace.currencySettings.save(profile, settings); await this.changed(); }
    catch (_) { if (this.alive) { this.error = '保存失败，请检查名称、符号长度和汇率后重试'; } }
    finally { if (this.alive) { this.working = false; } }
  }
  private canRestoreOnline(): boolean {
    return this.original !== undefined && this.code !== this.baseCode &&
      BUILTIN_CURRENCY_CODES.includes(this.baseCode) && BUILTIN_CURRENCY_CODES.includes(this.code);
  }
  private async resetRate(): Promise<void> {
    if (this.working || this.workspace === undefined || !this.canRestoreOnline()) { return; }
    const settings = currencySettings();
    settings.rates = settings.rates.filter((item: ManualCurrencyRate) =>
      !((item.from === this.baseCode && item.to === this.code) || (item.to === this.baseCode && item.from === this.code)));
    this.working = true;
    try { await this.workspace.currencySettings.save(undefined, settings); await this.changed(); }
    catch (_) { if (this.alive) { this.error = '恢复自动汇率失败，请重试'; } }
    finally { if (this.alive) { this.working = false; } }
  }
  private async remove(): Promise<void> {
    if (this.working || this.workspace === undefined || !this.original?.custom) { return; }
    const result = await this.getUIContext().getPromptAction().showDialog({ title: '删除币种', message: '仅未被账户或历史数据使用的自定义币种可以删除。',
      buttons: [{ text: '取消', color: '#808080' }, { text: '删除', color: '#D94838' }] });
    if (!this.alive || result.index !== 1) { return; }
    const settings = currencySettings();
    settings.rates = settings.rates.filter((item: ManualCurrencyRate) => item.from !== this.code && item.to !== this.code);
    settings.flags = settings.flags.filter((item: CurrencyFlagChoice) => item.code !== this.code);
    this.working = true;
    try { await this.workspace.currencySettings.save(undefined, settings, this.code); await this.changed(); }
    catch (_) { if (this.alive) { this.error = '删除失败；已被使用的币种请改为停用'; } }
    finally { if (this.alive) { this.working = false; } }
  }
  private profileKey(profile: CurrencyProfile): string {
    return profile.code;
  }
  private visibleProfiles(): CurrencyProfile[] {
    const keyword = this.keyword.trim().toLowerCase();
    const matches = this.profiles.filter((item: CurrencyProfile) => (item.code + ' ' + item.name).toLowerCase().includes(keyword));
    return matches.filter((item: CurrencyProfile) => item.custom).concat(matches.filter((item: CurrencyProfile) => !item.custom));
  }
  private flags(): RegionFlag[] {
    const keyword = this.keyword.trim().toLowerCase();
    return REGION_FLAGS.filter((item: RegionFlag) => (item.region + ' ' + item.name).toLowerCase().includes(keyword));
  }
  private showBack(): boolean {
    return this.mode !== 'list' && !(this.mode === 'rate' && this.initialTarget.length > 0);
  }
  private fieldBorder(field: string): ResourceColor {
    return this.focusedField === field ? $r('app.color.xq_brand') : $r('app.color.xq_exchange_form_border');
  }
  private chooseMinorDigits(): void {
    if (this.original !== undefined || this.working) { return; }
    this.getUIContext().showTextPickerDialog({ range: ['0','1','2','3','4'], selected: Number(this.minorDigits),
      selectedTextStyle: { color: $r('app.color.xq_font_emphasize') },
      acceptButtonStyle: { fontColor: $r('app.color.xq_font_emphasize') },
      cancelButtonStyle: { fontColor: $r('app.color.xq_font_secondary') },
      onAccept: (value: TextPickerResult) => { const index = typeof value.index === 'number' ? value.index : value.index[0]; this.minorDigits = index.toString(); } });
  }
  @Builder
  private fieldLabel(label: string, locked: boolean = false) {
    Row() {
      Text(label).fontSize('13fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
      Blank()
      if (locked) { Text('不可修改').fontSize('11fp').fontColor($r('app.color.xq_font_tertiary')) }
    }.width('100%')
  }
  @Builder
  private back() {
    if (this.showBack()) {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        Image($r('app.media.lucide_chevron_left1')).width(22).height(22).fillColor($r('app.color.xq_icon_primary'))
      }.width(40).height(40).padding(0).flexShrink(0).backgroundColor(Color.Transparent).accessibilityText('返回')
        .enabled(!this.working).onClick(() => { this.setMode(this.mode === 'flags' ? 'edit' : 'list'); this.keyword = ''; this.error = ''; })
    }
  }
  @Builder
  private management() {
    Search({ value: this.keyword, placeholder: '搜索币种名称或代码' }).height(40)
      .fontColor($r('app.color.xq_font_primary')).placeholderColor($r('app.color.xq_font_secondary'))
      .backgroundColor($r('app.color.xq_app_surface_keyboard')).onChange((value: string) => { this.keyword = value; })
    Button('＋ 新增币种').stateEffect(false).width('100%').height(44).backgroundColor($r('app.color.xq_exchange_currency_card_background'))
      .fontColor($r('app.color.xq_font_emphasize')).enabled(!this.working).onClick(() => { this.edit(undefined); })
    List({ space: 8 }) {
      ForEach(this.visibleProfiles(), (profile: CurrencyProfile) => {
        ListItem() {
          Row({ space: 8 }) {
            Row({ space: 8 }) {
              // Passive content; the outer card owns selection, including gaps and edge padding.
              Stack({ alignContent: Alignment.Center }) {
                Circle().width(20).height(20)
                  .fill(this.isSelected(profile.code) ? $r('app.color.xq_brand') : Color.Transparent)
                  .stroke(this.isSelected(profile.code) ? Color.Transparent : $r('app.color.xq_icon_secondary')).strokeWidth(1)
                if (this.isSelected(profile.code)) {
                  Image($r('app.media.lucide_check1')).width(14).height(14).fillColor(Color.White).draggable(false)
                }
              }.width(32).height(40).opacity(profile.code === 'CNY' ? 0.45 : 1).hitTestBehavior(HitTestMode.None)
              CurrencyFlagBadge({ currencyCode: profile.code, refreshToken: this.revision })
              Column({ space: 4 }) {
                Text(this.profileName(profile.code)).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).copyOption(CopyOptions.None)
                Text(profile.code).fontSize('11fp').fontColor($r('app.color.xq_font_secondary')).copyOption(CopyOptions.None)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start).hitTestBehavior(HitTestMode.None)
            }.layoutWeight(1).padding(12).constraintSize({ minHeight: 64 }).backgroundColor(Color.Transparent)
              .hitTestBehavior(HitTestMode.None)
            Button('编辑').stateEffect(false).fontSize('12fp').padding(8).backgroundColor(Color.Transparent).fontColor($r('app.color.xq_font_emphasize'))
              .enabled(!this.working).monopolizeEvents(true).onClick(() => { this.editFromCard(profile); })
          }.width('100%').padding({ right: 12 }).borderRadius(14).backgroundColor($r('app.color.xq_exchange_currency_card_background'))
            .hoverEffect(HoverEffect.None).accessibilityLevel('yes')
            .accessibilityText(this.profileName(profile.code) + (profile.code === 'CNY' ? '，固定开启' : this.isSelected(profile.code) ? '，已开启，点击取消' : '，未开启，点击开启'))
            .onClick(() => { this.toggleSelection(profile); })
        }
      }, (profile: CurrencyProfile) => this.profileKey(profile))
    }.width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
  }
  @Builder
  private editor() {
    Scroll() {
      Column({ space: 20 }) {
        if (this.mode === 'edit') {
          Column({ space: 8 }) {
            this.fieldLabel('币种代码', this.original !== undefined)
            if (this.original !== undefined) {
              Text(this.code).fontSize('16fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
                .height(48).padding({ left: 14, right: 14 })
                .backgroundColor($r('app.color.xq_exchange_form_readonly_background')).border({ width: 1, color: $r('app.color.xq_exchange_form_readonly_border') }).borderRadius(12)
            } else {
              TextInput({ text: this.code, placeholder: '输入三位字母，如 ABC' }).maxLength(3).fontSize('16fp').height(48)
                .fontColor($r('app.color.xq_font_primary')).placeholderColor($r('app.color.xq_font_tertiary'))
                .backgroundColor($r('app.color.xq_exchange_form_field_background')).caretColor($r('app.color.xq_brand'))
                .padding({ left: 14, right: 14 }).border({ width: 1, color: this.fieldBorder('code') }).borderRadius(12)
                .enabled(!this.working).onChange((value: string) => { this.code = value.toUpperCase(); })
                .onFocus(() => { this.focusedField = 'code'; }).onBlur(() => { this.focusedField = ''; }).id('currency-code')
            }
          }.width('100%')
          Column({ space: 8 }) {
            this.fieldLabel('货币名称')
            TextInput({ text: this.name, placeholder: '输入货币名称，如：美元' }).maxLength(40).fontSize('16fp').height(48)
              .fontColor($r('app.color.xq_font_primary')).placeholderColor($r('app.color.xq_font_tertiary'))
              .backgroundColor($r('app.color.xq_exchange_form_field_background')).caretColor($r('app.color.xq_brand'))
              .padding({ left: 14, right: 14 }).border({ width: 1, color: this.fieldBorder('name') }).borderRadius(12)
              .enabled(!this.working).onChange((value: string) => { this.name = value; })
              .onFocus(() => { this.focusedField = 'name'; }).onBlur(() => { this.focusedField = ''; }).id('currency-name')
          }.width('100%')
          Column({ space: 8 }) {
            this.fieldLabel('货币符号')
            TextInput({ text: this.symbol, placeholder: '输入符号，如：$、¥' }).maxLength(12).fontSize('16fp').height(48)
              .fontColor($r('app.color.xq_font_primary')).placeholderColor($r('app.color.xq_font_tertiary'))
              .backgroundColor($r('app.color.xq_exchange_form_field_background')).caretColor($r('app.color.xq_brand'))
              .padding({ left: 14, right: 14 }).border({ width: 1, color: this.fieldBorder('symbol') }).borderRadius(12)
              .enabled(!this.working).onChange((value: string) => { this.symbol = value; })
              .onFocus(() => { this.focusedField = 'symbol'; }).onBlur(() => { this.focusedField = ''; }).id('currency-symbol')
          }.width('100%')
          Column({ space: 8 }) {
            this.fieldLabel('小数位数', this.original !== undefined)
            if (this.original !== undefined) {
              Text(this.minorDigits + ' 位').fontSize('16fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
                .height(48).padding({ left: 14, right: 14 })
                .backgroundColor($r('app.color.xq_exchange_form_readonly_background')).border({ width: 1, color: $r('app.color.xq_exchange_form_readonly_border') }).borderRadius(12)
            } else {
              Button({ type: ButtonType.Normal, stateEffect: false }) {
                Row() {
                  Text(this.minorDigits + ' 位').fontSize('16fp').fontColor($r('app.color.xq_font_primary')).layoutWeight(1).textAlign(TextAlign.Start)
                  Image($r('app.media.lucide_chevron_down1')).width(18).height(18).fillColor($r('app.color.xq_icon_secondary'))
                }.width('100%')
              }.width('100%').height(48).padding({ left: 14, right: 14 })
                .backgroundColor($r('app.color.xq_exchange_form_field_background')).border({ width: 1, color: $r('app.color.xq_exchange_form_border') }).borderRadius(12)
                .enabled(!this.working).onClick(() => { this.chooseMinorDigits(); }).id('currency-scale-picker')
            }
          }.width('100%')
          Column({ space: 8 }) {
            this.fieldLabel('旗帜')
            Button({ type: ButtonType.Normal, stateEffect: false }) {
              Row({ space: 10 }) {
                if (regionFlag(this.region) !== undefined) {
                  Image(regionFlag(this.region) || $r('app.media.lucide_globe1')).width(32).height(24).objectFit(ImageFit.Contain).draggable(false)
                }
                Text(this.region ? this.region.toUpperCase() : '使用货币代码占位').fontSize('15fp').fontColor($r('app.color.xq_font_primary'))
                  .layoutWeight(1).textAlign(TextAlign.Start)
                Text('更换').fontSize('12fp').fontColor($r('app.color.xq_font_emphasize'))
                Image($r('app.media.lucide_chevron_right1')).width(18).height(18).fillColor($r('app.color.xq_icon_secondary'))
              }.width('100%')
            }.width('100%').height(52).padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.xq_exchange_form_field_background')).border({ width: 1, color: $r('app.color.xq_exchange_form_border') }).borderRadius(12)
              .enabled(!this.working).onClick(() => { this.keyword = ''; this.setMode('flags'); }).id('currency-flag-picker')
          }.width('100%')
        }
        if (this.code !== this.baseCode) {
          Column({ space: 8 }) {
            this.fieldLabel('兑换汇率')
            Text('1 ' + this.baseCode + ' 可兑换的 ' + (this.code || '目标币种') + ' 数量')
              .fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            ExchangeRateField({ value: $rate, disabled: this.working })
            Text('手动设置后保留此汇率，不被在线报价覆盖。').fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
          }.width('100%')
        }
        Button(this.working ? '保存中…' : this.mode === 'rate' ? '保存汇率' : '保存币种').stateEffect(false).width('100%').height(46)
          .backgroundColor($r('app.color.xq_brand')).fontColor(Color.White).enabled(!this.working).onClick(() => { this.save(); })
        if (this.canRestoreOnline()) {
          Button('恢复自动汇率').stateEffect(false).width('100%').height(40).backgroundColor(Color.Transparent).fontColor($r('app.color.xq_font_emphasize'))
            .enabled(!this.working).onClick(() => { this.resetRate(); })
        }
        if (this.mode === 'edit' && this.original?.custom) {
          Button('删除未使用的币种').stateEffect(false).width('100%').height(40).backgroundColor(Color.Transparent).fontColor($r('app.color.xq_warning'))
            .enabled(!this.working).onClick(() => { this.remove(); })
        }
      }.width('100%').padding(12).justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Start)
        .borderRadius(16).backgroundColor($r('app.color.xq_exchange_form_panel_background'))
    }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
  }
  @Builder
  private flagPicker() {
    Search({ value: this.keyword, placeholder: '搜索地区代码或英文名称，如 CN、China' }).height(40)
      .fontColor($r('app.color.xq_font_primary')).placeholderColor($r('app.color.xq_font_secondary'))
      .backgroundColor($r('app.color.xq_app_surface_keyboard')).onChange((value: string) => { this.keyword = value; })
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 12 }) {
        Text(this.code || 'ABC').fontSize('12fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_secondary'))
          .width(42).height(32).textAlign(TextAlign.Center).borderRadius(6).backgroundColor($r('app.color.xq_exchange_form_field_background'))
        Text('使用货币代码占位').fontSize('14fp').fontColor($r('app.color.xq_font_primary')).layoutWeight(1).textAlign(TextAlign.Start)
        if (!this.region) { Image($r('app.media.lucide_check1')).width(18).height(18).fillColor($r('app.color.xq_brand')) }
      }.width('100%')
    }.width('100%').height(52).padding({ left: 14, right: 14 })
      .backgroundColor($r('app.color.xq_exchange_form_field_background'))
      .border({ width: 1, color: !this.region ? $r('app.color.xq_brand') : $r('app.color.xq_exchange_form_border') }).borderRadius(12)
      .onClick(() => { this.region = ''; this.setMode('edit'); this.keyword = ''; }).id('currency-no-flag-choice')
    Grid() {
      ForEach(this.flags(), (flag: RegionFlag) => {
        GridItem() {
          Button({ type: ButtonType.Normal, stateEffect: false }) {
            Column({ space: 6 }) {
              Image(flag.flag).width(32).height(24).objectFit(ImageFit.Contain)
              Text(flag.region.toUpperCase()).fontSize('11fp').fontColor($r('app.color.xq_font_primary'))
            }.width('100%').height('100%').justifyContent(FlexAlign.Center)
          }.width('100%').height(72).backgroundColor($r('app.color.xq_exchange_currency_card_background'))
            .border({ width: 1, color: this.region === flag.region ? $r('app.color.xq_brand') : $r('app.color.xq_exchange_form_border') }).borderRadius(12)
            .accessibilityText(flag.name).onClick(() => { this.region = flag.region; this.setMode('edit'); this.keyword = ''; })
        }.height(72)
      }, (flag: RegionFlag) => flag.region)
    }.columnsTemplate(gridColumnsTemplate(this.flagColumns)).columnsGap(8).rowsGap(8).width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
      .onAreaChange((_old: Area, area: Area) => { const ui = this.getUIContext(); this.flagColumns = adaptiveColumns(Number(area.width),64,8,8,ui.fp2px(12)/ui.vp2px(12)); })
  }
  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        this.back()
        Text(this.title()).fontSize('20fp').fontWeight(FontWeight.Bold).fontColor($r('app.color.xq_font_primary')).layoutWeight(1)
      }.width('100%').constraintSize({ minHeight: 40 }).alignItems(VerticalAlign.Center).padding({ right: 48 })
      if (this.error) { Text(this.error).fontSize('12fp').fontColor($r('app.color.xq_warning')).width('100%') }
      if (this.mode === 'list') { this.management() }
      else if (this.mode === 'flags') { this.flagPicker() }
      else { this.editor() }
    }.width('100%').height('100%').padding({ left: 16, right: 16, top: 20, bottom: 16 })
      .justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Start)
  }
}
