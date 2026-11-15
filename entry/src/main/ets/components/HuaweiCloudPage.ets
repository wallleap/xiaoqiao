import { common } from '@kit.AbilityKit';
import { LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { cloudSync } from '@kit.CoreFileKit';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { LedgerBackupPackage } from '../data/backup/LedgerBackupPackage';
import { LocalBackupPreview } from '../data/rdb/LocalLedgerBackup';
import { CloudBackupRecord, HuaweiAccountConnection, HuaweiCloudBackup } from '../data/cloud/HuaweiCloudBackup';

@Component
export struct HuaweiCloudPage {
  getBackup: () => LedgerBackupPackage | undefined = () => undefined;
  @Prop ready: boolean = false;
  onBusy: (busy: boolean) => void = () => {};
  onClose: () => void = () => {};
  onRestored: () => Promise<boolean> = async () => true;
  onRecoveryRequired: () => void = () => {};
  @State private connected: boolean = false;
  @State private busy: boolean = false;
  @State private records: CloudBackupRecord[] = [];
  @State private message: string = '';
  @State private error: boolean = false;
  @State private syncStatus: string = '尚未请求同步';
  @State private lastSync: number = 0;
  @State private preview: LocalBackupPreview | undefined = undefined;
  @State private recoveryRequired: boolean = false;
  private previewAccount: string = '';
  private service: HuaweiCloudBackup | undefined = undefined;
  private active: boolean = false;
  private readonly scroller: Scroller = new Scroller();
  private readonly loginController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController();
  private readonly loginParams: loginComponentManager.LoginWithHuaweiIDButtonParams = {
    style: loginComponentManager.Style.BUTTON_BLACK, loginType: loginComponentManager.LoginType.ID,
    supportDarkMode: true, textAndIconStyle: true, borderRadius: 22
  };

  aboutToAppear(): void {
    this.active = true;
    const host = this.getUIContext().getHostContext();
    if (host !== undefined) { this.service = new HuaweiCloudBackup(host); }
    this.loginController.onClickLoginWithHuaweiIDButton((err: BusinessError, credential: loginComponentManager.HuaweiIDCredential) => {
      if (!this.active || this.busy) { return; }
      if (err) { this.failure(err); return; }
      try { HuaweiAccountConnection.connect(credential.openID); this.connect(true); }
      catch (_) { this.message = '未能确认华为账号，请重新登录'; this.error = true; }
    });
    this.resumeConnection();
  }

  aboutToDisappear(): void {
    this.active = false; this.service?.close();
    if (!this.busy) { this.getBackup()?.discard().catch(() => {}); }
  }

  private setBusy(value: boolean): void { this.busy = value; this.onBusy(value); }
  private async resumeConnection(): Promise<void> {
    try { await HuaweiAccountConnection.current(); await this.connect(); }
    catch (_) { this.connected = false; }
  }

  private async connect(requestProfile: boolean = false): Promise<void> {
    this.setBusy(true); this.message = ''; this.error = false;
    try {
      if (this.service === undefined) { throw new Error('CLOUD_NOT_READY'); }
      await HuaweiAccountConnection.current(); this.connected = true;
      const host = this.getUIContext().getHostContext();
      if (host !== undefined) {
        try { await HuaweiAccountConnection.loadProfile(host, requestProfile); }
        catch (_) { /* Avatar/nickname consent is optional and must not undo account connection. */ }
      }
      if (!HuaweiCloudBackup.available()) { this.syncStatus = '当前设备暂不支持云文件同步'; return; }
      await this.service?.observe((progress: cloudSync.SyncProgress) => { this.syncProgress(progress); });
      this.lastSync = await this.service?.lastSyncTime() || 0;
      this.records = await this.service?.list() || [];
      this.message = '已连接华为账号；备份前请在系统云空间中开启本应用同步';
    } catch (error) { this.failure(error as Error); }
    finally { this.setBusy(false); }
  }

  private async authorizeProfile(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (host === undefined || this.busy || !this.connected) { return; }
    this.setBusy(true);
    try {
      await HuaweiAccountConnection.loadProfile(host, true);
      this.message = '头像昵称已更新，返回“我的”页即可查看'; this.error = false;
    } catch (_) { this.message = '暂未取得头像昵称，仍可正常使用云备份'; this.error = false; }
    finally { this.setBusy(false); }
  }

  private failure(error: Error | BusinessError): void {
    const code = (error as BusinessError).code;
    const message = error.message;
    this.error = true;
    if (message === 'HUAWEI_ACCOUNT_CHANGED' || message === 'HUAWEI_ACCOUNT_REQUIRED' || code === 1001502001) {
      this.connected = false; this.records = []; this.preview = undefined; this.previewAccount = '';
      this.service?.close();
      this.message = '华为账号已退出或发生变化，请重新连接后操作';
    } else if (code === 1001502012 || code === 1005300001) { this.message = '已取消登录'; this.error = false; }
    else if (code === 1001500001 || code === 1001502003) { this.message = '应用身份校验未通过，暂时无法登录华为账号'; }
    else if (message === 'CLOUD_UNSUPPORTED') { this.message = '当前设备暂不支持云文件同步，请使用本地备份或 WebDAV'; }
    else if (code === 22400001 || message === 'CLOUD_NOT_READY') { this.message = '云空间尚未就绪，请登录系统华为账号并开启本应用同步'; }
    else if (code === 22400002 || code === 1001502005) { this.message = '网络不可用，请连接网络后重试'; }
    else if (code === 22400003) { this.message = '电量过低，请充电后重试同步'; }
    else if (message === 'PACKAGE_SIZE') { this.message = '完整备份包上限为 32 MiB，请检查备份大小'; }
    else if (message === 'CLOUD_DOWNLOAD_TIMEOUT' || message === 'CLOUD_DOWNLOAD_FAILED') { this.message = '备份下载未完成，请检查网络和云空间后重试'; }
    else { this.message = '操作未完成，请检查网络、云空间开关和剩余空间后重试'; }
  }

  private async syncProgress(progress: cloudSync.SyncProgress): Promise<void> {
    if (!this.active) { return; }
    try { await HuaweiAccountConnection.current(); } catch (error) { if (this.active) { this.failure(error as Error); } return; }
    if (!this.active) { return; }
    if (progress.state === cloudSync.SyncState.COMPLETED) {
      this.syncStatus = '云空间同步已完成';
      this.lastSync = await this.service?.lastSyncTime().catch(() => 0) || 0;
    } else if (progress.error === cloudSync.ErrorType.CLOUD_STORAGE_FULL) { this.syncStatus = '云空间不足，同步已暂停'; }
    else if (progress.error === cloudSync.ErrorType.NETWORK_UNAVAILABLE || progress.error === cloudSync.ErrorType.WIFI_UNAVAILABLE) {
      this.syncStatus = '网络不可用，同步已暂停';
    } else if (progress.state === cloudSync.SyncState.UPLOAD_FAILED || progress.state === cloudSync.SyncState.DOWNLOAD_FAILED) {
      this.syncStatus = '同步未完成，请稍后重试';
    } else if (progress.state === cloudSync.SyncState.STOPPED) { this.syncStatus = '同步已暂停'; }
    else { this.syncStatus = '正在与云空间同步…'; }
  }

  private async refresh(): Promise<void> {
    if (this.busy || !this.connected || this.service === undefined) { return; }
    this.setBusy(true); this.message = ''; this.error = false;
    try {
      this.records = await this.service.list();
      await this.service.requestSync(); this.syncStatus = '已请求同步，等待系统完成';
    } catch (error) { this.failure(error as Error); }
    finally { this.setBusy(false); }
  }

  private async createBackup(): Promise<void> {
    const backup = this.getBackup();
    if (!this.ready || this.busy || !this.connected || this.recoveryRequired || backup === undefined || this.service === undefined) { return; }
    this.setBusy(true); this.message = ''; this.error = false;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({ title: '备份到华为云空间？',
        message: '将完整账本、账户、分类、备注和图片附件写入当前华为账号的云空间，备份包未另设密码。请确认设备当前登录的是你的账号。',
        buttons: [{ text: '取消', color: $r('app.color.xq_font_primary') }, { text: '开始备份', color: $r('app.color.xq_font_emphasize') }]
      }).catch(() => undefined);
      if (result?.index !== 1) { return; }
      this.message = '正在生成完整备份…';
      await this.service.create(backup);
      this.records = await this.service.list();
      this.message = '备份已写入云目录，等待系统同步；可稍后查看同步状态';
      await this.service.requestSync(); this.syncStatus = '已请求同步，等待系统完成';
    } catch (error) { this.failure(error as Error); }
    finally { this.setBusy(false); }
  }

  private async choose(record: CloudBackupRecord): Promise<void> {
    const backup = this.getBackup();
    if (!this.ready || this.busy || this.recoveryRequired || backup === undefined || this.service === undefined) { return; }
    this.setBusy(true); this.message = '正在下载并校验备份…'; this.error = false; this.preview = undefined;
    try {
      this.previewAccount = await HuaweiAccountConnection.current();
      const preview = await this.service.prepare(backup, record);
      if (await HuaweiAccountConnection.current() !== this.previewAccount) { throw new Error('HUAWEI_ACCOUNT_CHANGED'); }
      this.preview = preview; this.message = '';
    } catch (error) { this.previewAccount = ''; this.failure(error as Error); }
    finally { this.setBusy(false); }
  }

  private async discard(): Promise<void> {
    if (this.busy) { return; }
    this.setBusy(true); this.preview = undefined; this.previewAccount = '';
    try { await this.getBackup()?.discard(); } finally { this.setBusy(false); }
  }

  private async restore(): Promise<void> {
    const backup = this.getBackup();
    if (!this.ready || this.busy || this.recoveryRequired || this.preview === undefined || backup === undefined) { return; }
    this.setBusy(true); this.error = false;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({ title: '用云备份替换当前账本？',
        message: '当前本地数据将被替换，应用会保留恢复前副本。多台设备的账目不会自动合并。',
        buttons: [{ text: '取消', color: $r('app.color.xq_font_primary') }, { text: '替换并恢复', color: $r('app.color.xq_warning') }]
      }).catch(() => undefined);
      if (result?.index !== 1) { return; }
      if (await HuaweiAccountConnection.current() !== this.previewAccount) { throw new Error('HUAWEI_ACCOUNT_CHANGED'); }
      this.preview = undefined; this.previewAccount = ''; this.message = '正在恢复账本…';
      await backup.restore();
      const refreshed = await this.onRestored(); this.message = refreshed ? '账本已恢复' : '账本已恢复，请返回重试页面读取';
    } catch (error) {
      const code = (error as Error).message;
      if (code === 'BACKUP_RECOVERY_REQUIRED') {
        this.recoveryRequired = true; this.message = '恢复中断，恢复前副本已保留，请退出并重新打开应用'; this.error = true; this.onRecoveryRequired();
      } else if (code === 'BACKUP_RESTORE_ROLLED_BACK') { this.message = '恢复未完成，已还原原账本'; this.error = true; }
      else { this.failure(error as Error); }
    } finally { this.setBusy(false); }
  }

  private async openCloudSettings(): Promise<void> {
    try {
      await (this.getUIContext().getHostContext() as common.UIAbilityContext).startAbility({ uri: 'hicloud://cloudDrive/getInfo?path=MainActivity' });
    } catch (_) { this.message = '请前往系统设置 → 华为账号 → 云空间，开启本应用同步'; this.error = false; }
  }

  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' :
      '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }

  private date(value: number): string {
    if (value <= 0) { return '暂无记录'; }
    const date = new Date(value < 1000000000000 ? value * 1000 : value);
    return `${date.getFullYear()}/${String(date.getMonth() + 1).padStart(2, '0')}/${String(date.getDate()).padStart(2, '0')} ` +
      `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Column({ space: 12 }) {
            Text(this.connected ? '已连接华为账号' : '连接华为账号').fontSize('18fp').fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.xq_font_primary')).width('100%')
            Text('使用当前设备的华为账号管理云备份。登录不会自动上传账本，不获取手机号。').fontSize('12fp')
              .fontColor($r('app.color.xq_font_secondary')).width('100%')
            if (!this.connected && canIUse('SystemCapability.AuthenticationServices.HuaweiID.UIComponent')) {
              LoginWithHuaweiIDButton({ params: this.loginParams, controller: this.loginController }).width('100%').height(44).enabled(!this.busy)
            } else if (!this.connected) {
              Text('当前设备暂不支持华为账号登录').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
            } else {
              Button('更新头像昵称').fontSize('14fp').fontColor($r('app.color.xq_font_emphasize')).backgroundColor(Color.Transparent)
                .enabled(!this.busy).onClick(() => { this.authorizeProfile(); })
              Button('断开应用内连接').fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).backgroundColor(Color.Transparent)
                .enabled(!this.busy && this.preview === undefined).onClick(() => {
                  HuaweiAccountConnection.disconnect(); this.service?.close(); this.connected = false; this.records = []; this.lastSync = 0;
                  this.syncStatus = '已断开应用内连接'; this.message = '系统云空间开关不受此操作影响，已写入云目录的文件仍可能继续同步'; this.error = false;
                })
            }
          }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
          Column({ space: 12 }) {
            Text('云空间备份').fontSize('18fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary')).width('100%')
            Text(this.syncStatus).fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).width('100%')
            Text('最近系统同步：' + this.date(this.lastSync)).fontSize('12fp').fontColor($r('app.color.xq_font_tertiary')).width('100%')
            Button('前往云空间设置').height(40).width('100%').fontSize('14fp')
              .fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_page'))
              .enabled(!this.busy).onClick(() => { this.openCloudSettings(); })
            Button(this.busy ? '处理中…' : '立即备份').height(44).width('100%').fontSize('14fp').fontColor(Color.White)
              .backgroundColor($r('app.color.xq_brand')).enabled(this.ready && this.connected && !this.busy && !this.recoveryRequired && this.preview === undefined && HuaweiCloudBackup.available())
              .onClick(() => { this.createBackup(); })
          }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
          Row() {
            Text('备份记录').fontSize('18fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary'))
            Blank()
            Button('刷新').fontSize('14fp').fontColor($r('app.color.xq_font_emphasize')).backgroundColor(Color.Transparent)
              .enabled(this.connected && !this.busy && HuaweiCloudBackup.available()).onClick(() => { this.refresh(); })
          }.width('100%')
          Text('记录来自云目录；文件写入成功不代表已上传完成，请结合系统同步状态查看。').fontSize('12fp')
            .fontColor($r('app.color.xq_font_secondary')).width('100%')
          if (this.records.length === 0) {
            Text(this.connected ? '暂无备份记录，开启同步后可刷新查看' : '连接华为账号后查看备份').fontSize('14fp')
              .fontColor($r('app.color.xq_font_secondary')).width('100%').padding({ top: 12, bottom: 12 })
          }
          ForEach(this.records, (record: CloudBackupRecord) => {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text(this.date(record.createdAt)).fontSize('16fp').fontColor($r('app.color.xq_font_primary'))
                Text((record.bytes / 1024 / 1024).toFixed(2) + ' MiB').fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button('查看并恢复').fontSize('12fp').fontColor($r('app.color.xq_font_emphasize'))
                .backgroundColor($r('app.color.xq_app_surface_page')).enabled(this.ready && !this.busy && !this.recoveryRequired)
                .onClick(() => { this.choose(record); })
            }.width('100%').padding(16).borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
          }, (record: CloudBackupRecord) => record.name)
          if (this.preview !== undefined) {
            Column({ space: 12 }) {
              Text('恢复预览').fontSize('18fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.xq_font_primary')).width('100%')
              Text(`${this.preview.books} 个账本 · ${this.preview.entries} 笔账目 · ${this.preview.accounts} 个账户`).fontSize('14fp')
                .fontColor($r('app.color.xq_font_secondary')).width('100%')
              Row({ space: 12 }) {
                Button('取消').layoutWeight(1).height(44).enabled(!this.busy).onClick(() => { this.discard(); })
                  .fontColor($r('app.color.xq_font_primary')).backgroundColor($r('app.color.xq_app_surface_page'))
                Button('恢复账本').layoutWeight(1).height(44).enabled(this.ready && !this.busy && !this.recoveryRequired)
                  .fontColor(Color.White).backgroundColor($r('app.color.xq_brand')).onClick(() => { this.restore(); })
              }.width('100%')
            }.padding(16).width('100%').borderRadius(16).backgroundColor($r('app.color.xq_app_surface_card'))
          }
          if (this.message.length > 0) { Text(this.message).fontSize('14fp').fontColor(this.error ? $r('app.color.xq_warning') : $r('app.color.xq_font_secondary')).width('100%') }
          Text('云备份包含完整账本和附件，不会自动合并多设备账目。应用不保存登录令牌；重新启动后需要再次连接。').fontSize('12fp')
            .fontColor($r('app.color.xq_font_tertiary')).width('100%')
        }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({ enableComponentSafeArea: true, content: { title: { mainTitle: '华为账号与云备份' }, divider: { showType: DividerShowType.OFF },
        backIcon: { action: () => { if (!this.busy) { this.onClose(); } } } }, style: {
        originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
        scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') }, backIconStyle: { iconColor: $r('app.color.xq_icon_primary') } } },
        systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
