import { LedgerBackupPackage } from '../data/backup/LedgerBackupPackage';
import { WebDavPanel } from './WebDavPanel';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, DividerShowType, ScrollEffectType } from '@kit.UIDesignKit';
import { LocalBackupPreview } from '../data/rdb/LocalLedgerBackup';

@Component
export struct LocalBackupPage {
  getBackup: () => LedgerBackupPackage | undefined = () => undefined;
  @Prop @Watch('readyChanged') ready: boolean = false;
  @State private busy: boolean = false;
  @State private previous: boolean = false;
  @State private preview: LocalBackupPreview | undefined = undefined;
  @State private progress: string = '';
  @State private message: string = '';
  @State private error: boolean = false;
  @State private recoveryRequired: boolean = false;
  onBusy: (busy: boolean) => void = () => {};
  onRestored: () => Promise<boolean> = async () => true;
  onRecoveryRequired: () => void = () => {};
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.refreshPrevious(); }
  private readyChanged(): void { if (this.ready) { this.refreshPrevious(); } }

  private async refreshPrevious(): Promise<void> {
    try { this.previous = await this.getBackup()?.hasPrevious() || false; }
    catch (_) { this.previous = false; }
  }

  private setBusy(busy: boolean, progress: string = ''): void {
    this.busy = busy;
    this.progress = progress;
    this.onBusy(busy);
  }

  private feedback(message: string, error: boolean = false): void {
    this.message = message;
    this.error = error;
  }

  private filePicker(): picker.DocumentViewPicker {
    return new picker.DocumentViewPicker(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  private async save(previous: boolean): Promise<void> {
    const backup = this.getBackup();
    if (!this.ready || this.busy || this.recoveryRequired || backup === undefined) { return; }
    this.setBusy(true);
    this.feedback('');
    try {
      const options = new picker.DocumentSaveOptions();
      const date = new Date().toISOString().slice(0, 10);
      options.newFileNames = [`小巧记账-${previous ? '恢复前副本' : '本地备份'}-${date}.xqbackup`];
      const destinations = await this.filePicker().save(options);
      if (destinations.length === 0) { return; }
      this.progress = '正在保存备份…';
      await backup.exportTo(destinations[0], previous);
      this.feedback(previous ? '恢复前副本已保存' : '本地备份已保存');
    } catch (_) { this.feedback('未能保存完整备份，请检查存储空间后重试。', true); }
    finally { this.setBusy(false); }
  }

  private async choose(): Promise<void> {
    const backup = this.getBackup();
    if (!this.ready || this.busy || this.recoveryRequired || backup === undefined) { return; }
    this.setBusy(true);
    this.feedback('');
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['小巧记账备份|.xqbackup'];
      const sources = await this.filePicker().select(options);
      if (sources.length === 0) { return; }
      this.preview = undefined;
      this.progress = '正在检查备份…';
      this.preview = await backup.prepare(sources[0]);
    } catch (_) { this.feedback('无法读取这份备份。请选择完整且与当前账本版本兼容的备份文件。', true); }
    finally { this.setBusy(false); }
  }

  private async discard(): Promise<void> {
    this.preview = undefined;
    try { await this.getBackup()?.discard(); } catch (_) { /* Staging will be overwritten on the next selection. */ }
  }

  private async confirm(): Promise<void> {
    const backup = this.getBackup();
    if (!this.ready || this.busy || this.recoveryRequired || backup === undefined || this.preview === undefined) { return; }
    this.setBusy(true);
    this.feedback('');
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '用这份备份替换当前账本？',
        message: '当前账本将被备份中的数据替换。应用会先保留恢复前副本。',
        buttons: [{ text: '取消', color: $r('app.color.xq_font_primary') },
          { text: '替换并恢复', color: $r('app.color.xq_warning') }]
      }).catch(() => undefined);
      if (result?.index !== 1) { return; }
      this.progress = '正在恢复账本…';
      this.preview = undefined;
      try { await backup.restore(); }
      catch (error) {
        const code = (error as Error).message;
        this.recoveryRequired = code === 'BACKUP_RECOVERY_REQUIRED';
        if (this.recoveryRequired) { this.onRecoveryRequired(); }
        this.feedback(this.recoveryRequired ? '恢复中断。恢复前副本已保留，请退出应用并重新打开以恢复原账本。' :
          code === 'BACKUP_RESTORE_ROLLED_BACK' ? '恢复未完成，已还原原账本。' : '未能开始恢复，请重新选择备份。', true);
        await this.refreshPrevious();
        return;
      }
      const refreshed = await this.onRestored();
      await this.refreshPrevious();
      this.feedback(refreshed ? '账本已恢复' : '账本已恢复，部分页面读取失败，请返回重试。', !refreshed);
    } finally { this.setBusy(false); }
  }

  private statusBarColor(): string {
    const host = this.getUIContext().getHostContext();
    return host === undefined ? '#E5000000' : '#' + (host.resourceManager.getColorSync($r('app.color.xq_font_primary').id) >>> 0).toString(16).padStart(8, '0');
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Column({ space: 12 }) {
            Text('本地备份与恢复').fontSize('20fp').fontWeight(FontWeight.Bold).fontColor($r('app.color.xq_font_primary'))
            Text('将账本、图片和自定义图标一起备份，或从备份包恢复。').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
            Button('保存本地备份').width('100%').constraintSize({ minHeight: 44 }).fontSize('16fp')
              .backgroundColor($r('app.color.xq_brand')).fontColor(Color.White)
              .enabled(this.ready && !this.busy && !this.recoveryRequired)
              .id('local-backup-save').onClick(() => { this.save(false); })
            Button('选择备份文件').width('100%').constraintSize({ minHeight: 44 }).fontSize('16fp')
              .backgroundColor($r('app.color.xq_app_surface_page')).fontColor($r('app.color.xq_font_primary'))
              .enabled(this.ready && !this.busy && !this.recoveryRequired)
              .id('local-backup-select').onClick(() => { this.choose(); })
            if (this.previous) {
              Button('导出恢复前副本').width('100%').constraintSize({ minHeight: 44 }).fontSize('16fp')
                .backgroundColor(Color.Transparent).fontColor($r('app.color.xq_font_emphasize'))
                .enabled(this.ready && !this.busy && !this.recoveryRequired)
                .id('local-backup-previous').onClick(() => { this.save(true); })
            }
          }.width('100%').padding(16).borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
            .alignItems(HorizontalAlign.Start)
          WebDavPanel({ getBackup: this.getBackup, canOperate: this.ready && !this.busy && !this.recoveryRequired,
            onBusy: (value: boolean) => { this.setBusy(value); },
            onPreview: (value: LocalBackupPreview | undefined) => { this.preview = value; }
          })
          if (this.preview !== undefined) {
            Column({ space: 12 }) {
              Text('恢复预览').fontSize('18fp').fontWeight(FontWeight.Bold).fontColor($r('app.color.xq_font_primary'))
              Text(`${this.preview.books} 个账本 · ${this.preview.entries} 笔账目 · ${this.preview.accounts} 个账户 · ${this.preview.resources || 0} 个资源`)
                .fontSize('14fp').fontColor($r('app.color.xq_font_secondary')).id('local-backup-preview')
              Text('恢复会替换当前账本。').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
              Button('继续恢复').width('100%').constraintSize({ minHeight: 44 }).fontSize('16fp')
                .backgroundColor($r('app.color.xq_brand')).fontColor(Color.White)
                .enabled(this.ready && !this.busy).id('local-backup-restore').onClick(() => { this.confirm(); })
              Button('取消预览').width('100%').constraintSize({ minHeight: 44 }).fontSize('16fp')
                .backgroundColor(Color.Transparent).fontColor($r('app.color.xq_font_secondary'))
                .enabled(!this.busy).id('local-backup-discard').onClick(() => { this.discard(); })
            }.width('100%').padding(16).borderRadius(20).backgroundColor($r('app.color.xq_app_surface_card'))
              .alignItems(HorizontalAlign.Start)
          }
          if (this.progress.length > 0) {
            Row({ space: 8 }) {
              LoadingProgress().width(20).height(20).color($r('app.color.xq_brand'))
              Text(this.progress).fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
            }.width('100%').padding(12)
          }
          if (this.message.length > 0) {
            Text(this.message).width('100%').padding(12).fontSize('14fp')
              .fontColor(this.error ? $r('app.color.xq_warning') : $r('app.color.xq_font_primary')).id('local-backup-feedback')
          }
          if (!this.ready) {
            Text('请先在账目页完成账本读取或升级。').fontSize('14fp').fontColor($r('app.color.xq_font_secondary'))
          }
        }.width('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16, top: 12, bottom: 128 })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off).clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.mode(NavigationMode.Stack).titleMode(HdsNavigationTitleMode.MINI).hideBackButton(true)
      .titleBar({ enableComponentSafeArea: true, avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '设置' }, divider: { showType: DividerShowType.OFF } },
        style: {
          originalStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') } } },
          scrollEffectStyle: { contentStyle: { titleStyle: { mainTitleColor: $r('app.color.xq_font_primary') } } },
          systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } } })
      .systemBarStyle({ statusBarContentColor: this.statusBarColor() }, { statusBarContentColor: this.statusBarColor() })
      .bindToScrollable([this.scroller]).backgroundColor($r('app.color.xq_app_surface_page'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]).id('local-backup-page')
  }
}
