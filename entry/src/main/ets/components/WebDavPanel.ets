import { LedgerBackupPackage } from '../data/backup/LedgerBackupPackage';
import { common } from '@kit.AbilityKit';
import { LocalBackupPreview } from '../data/rdb/LocalLedgerBackup';
import { DavCredentials } from '../data/webdav/DavCredentials';
import { DavConfig, DavFile, davMessage, normalizedDav } from '../data/webdav/WebDavClient';
import { WebDavBackup } from '../data/webdav/WebDavBackup';

@Component
export struct WebDavPanel {
  getBackup: () => LedgerBackupPackage | undefined = () => undefined;
  @Prop canOperate: boolean = false;
  onBusy: (busy: boolean) => void = () => {};
  onPreview: (preview: LocalBackupPreview | undefined) => void = () => {};
  @State private endpoint: string = '';
  @State private username: string = '';
  @State private password: string = '';
  @State private files: DavFile[] = [];
  @State private message: string = '';
  @State private error: boolean = false;
  @State private loading: boolean = true;
  @State private saved: boolean = false;
  private readonly credentials: DavCredentials = new DavCredentials();

  aboutToAppear(): void { this.load(); }
  private async load(): Promise<void> {
    try {
      const value = await this.credentials.load();
      if (value !== undefined) {
        this.endpoint = value.endpoint; this.username = value.username; this.password = value.password; this.saved = true;
      }
    } catch (_) { this.message = '无法读取连接信息，请重新填写并保存。'; this.error = true; }
    finally { this.loading = false; }
  }
  private changed(): void { this.files = []; this.message = ''; }
  private config(): DavConfig { return normalizedDav({ endpoint: this.endpoint, username: this.username, password: this.password }); }
  private async run(action: string, file?: DavFile): Promise<void> {
    const local = this.getBackup();
    if (!this.canOperate || this.loading || local === undefined) { return; }
    this.onBusy(true); this.loading = true; this.message = ''; this.error = false;
    try {
      if (action === 'forget') {
        await this.credentials.remove(); this.endpoint = ''; this.username = ''; this.password = ''; this.files = []; this.saved = false;
        this.message = '连接信息已移除'; return;
      }
      const config = this.config();
      if (action === 'save') {
        await this.credentials.save(config); this.endpoint = config.endpoint; this.saved = true; this.files = [];
        this.message = '连接信息已保存'; return;
      }
      const service = new WebDavBackup(this.getUIContext().getHostContext() as common.Context, local, config);
      if (action === 'list') {
        this.files = await service.list(); this.message = this.files.length === 0 ? '连接成功，文件夹中暂无小巧记账备份' : `连接成功，找到 ${this.files.length} 份备份`;
      } else if (action === 'upload') {
        await service.upload(); this.message = '备份已上传'; this.files = [];
      } else if (file !== undefined) {
        this.onPreview(undefined); await local.discard();
        this.onPreview(await service.prepare(file)); this.message = '备份检查通过，请在下方确认恢复';
      }
    } catch (error) { this.error = true; this.message = davMessage(error as Error); }
    finally { this.loading = false; this.onBusy(false); }
  }

  @Builder
  private action(label: string, key: string) {
    Button(label).fontSize('14fp').constraintSize({ minHeight: 40 }).layoutWeight(1)
      .fontColor($r('app.color.xq_font_emphasize')).backgroundColor($r('app.color.xq_app_surface_page'))
      .enabled(this.canOperate && !this.loading).id('dav-' + key).onClick(() => { this.run(key); })
  }
  build() {
    Column({ space: 12 }) {
      Text('WebDAV 备份').fontSize('20fp').fontWeight(FontWeight.Bold).fontColor($r('app.color.xq_font_primary'))
      Text('备份存到此地址下的 xiaoqiao 文件夹，不存在时自动创建。文件未加密，请使用自己的可信服务器。')
        .fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
      TextInput({ placeholder: 'HTTPS 父目录地址', text: this.endpoint }).maxLength(2048).type(InputType.URL)
        .enabled(this.canOperate && !this.loading).id('dav-endpoint').onChange((value: string) => { this.endpoint = value; this.changed(); })
      TextInput({ placeholder: '用户名', text: this.username }).maxLength(512)
        .enabled(this.canOperate && !this.loading).id('dav-username').onChange((value: string) => { this.username = value; this.changed(); })
      TextInput({ placeholder: '密码 / 应用密码', text: this.password }).maxLength(4096).type(InputType.Password)
        .enabled(this.canOperate && !this.loading).id('dav-password').onChange((value: string) => { this.password = value; this.changed(); })
      Row({ space: 8 }) { this.action('保存连接', 'save'); this.action('测试并读取备份', 'list'); }.width('100%')
      Button('上传当前账本备份').width('100%').constraintSize({ minHeight: 44 }).fontSize('16fp')
        .backgroundColor($r('app.color.xq_brand')).fontColor(Color.White).enabled(this.canOperate && !this.loading)
        .id('dav-upload').onClick(() => { this.run('upload'); })
      if (this.saved) {
        Button('移除连接信息').fontSize('14fp').backgroundColor(Color.Transparent).fontColor($r('app.color.xq_font_secondary'))
          .enabled(this.canOperate && !this.loading).id('dav-forget').onClick(() => { this.run('forget'); })
      }
      ForEach(this.files, (file: DavFile) => {
        Button() {
          Column({ space: 4 }) {
            Text(file.name).fontSize('14fp').fontColor($r('app.color.xq_font_primary')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${(file.bytes / 1024).toFixed(1)} KiB · 点击下载并预览`).fontSize('12fp').fontColor($r('app.color.xq_font_secondary'))
          }.alignItems(HorizontalAlign.Start).width('100%')
        }.type(ButtonType.Normal).width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.xq_app_surface_page'))
          .enabled(this.canOperate && !this.loading).onClick(() => { this.run('download', file); })
      }, (file: DavFile) => file.href)
      if (this.loading) { LoadingProgress().width(24).height(24).color($r('app.color.xq_brand')) }
      if (this.message.length > 0) {
        Text(this.message).fontSize('14fp').fontColor(this.error ? $r('app.color.xq_warning') : $r('app.color.xq_font_secondary')).id('dav-feedback')
      }
    }.width('100%').padding(16).borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card')).alignItems(HorizontalAlign.Start)
  }
}
