import { authentication } from '@kit.AccountKit';
import { common } from '@kit.AbilityKit';
import { cloudSync, fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { BackupFiles, PACKAGE_MAX_BYTES } from '../backup/BackupFiles';
import { LedgerBackupPackage } from '../backup/LedgerBackupPackage';
import { LocalBackupPreview } from '../rdb/LocalLedgerBackup';

export interface CloudBackupRecord { name: string; bytes: number; createdAt: number; }

export interface HuaweiAccountProfile { nickName: string; avatarUri: string; }

/** Client-side connection only: never persist authorization codes, tokens or client secrets. */
export class HuaweiAccountConnection {
  private static openID: string = '';
  private static accountProfile: HuaweiAccountProfile = { nickName: '', avatarUri: '' };
  static connect(openID: string): void {
    if (!openID) { throw new Error('HUAWEI_ACCOUNT_REQUIRED'); }
    if (HuaweiAccountConnection.openID !== openID) { HuaweiAccountConnection.accountProfile = { nickName: '', avatarUri: '' }; }
    HuaweiAccountConnection.openID = openID;
  }
  static disconnect(): void {
    HuaweiAccountConnection.openID = '';
    HuaweiAccountConnection.accountProfile = { nickName: '', avatarUri: '' };
  }
  static profile(): HuaweiAccountProfile { return HuaweiAccountConnection.accountProfile; }

  static async loadProfile(context: common.Context, forceAuthorization: boolean): Promise<HuaweiAccountProfile> {
    const id = await HuaweiAccountConnection.current();
    const request = new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest();
    request.scopes = ['openid', 'profile']; request.forceAuthorization = forceAuthorization;
    request.state = util.generateRandomUUID();
    const response = await new authentication.AuthenticationController(context).executeRequest(request) as authentication.AuthorizationWithHuaweiIDResponse;
    const credential = response.data;
    if (credential === undefined || response.state !== request.state || credential.openID !== id || await HuaweiAccountConnection.current() !== id) {
      throw new Error('HUAWEI_ACCOUNT_CHANGED');
    }
    const uri = credential.avatarUri || '';
    HuaweiAccountConnection.accountProfile = { nickName: (credential.nickName || '').trim().substring(0, 20),
      avatarUri: /^https:\/\//i.test(uri) ? uri : '' };
    return HuaweiAccountConnection.accountProfile;
  }
  static async current(): Promise<string> {
    const id = HuaweiAccountConnection.openID;
    if (!id) { throw new Error('HUAWEI_ACCOUNT_REQUIRED'); }
    const result = await new authentication.HuaweiIDProvider().getHuaweiIDState({ idType: authentication.IdType.OPEN_ID, idValue: id });
    if (result.state !== authentication.State.AUTHORIZED || HuaweiAccountConnection.openID !== id) {
      HuaweiAccountConnection.disconnect(); throw new Error('HUAWEI_ACCOUNT_CHANGED');
    }
    return id;
  }
}

/** Own immutable backup files only. The live SQLite database stays outside the cloud filesystem. */
export class HuaweiCloudBackup {
  private readonly context: common.Context;
  private readonly root: string = '/data/storage/el2/cloud';
  private sync: cloudSync.FileSync | undefined = undefined;
  private listener: ((progress: cloudSync.SyncProgress) => void) | undefined = undefined;
  constructor(context: common.Context) { this.context = context; }

  static available(): boolean {
    return deviceInfo.sdkApiVersion >= 21 && canIUse('SystemCapability.FileManagement.DistributedFileService.CloudSync.Core');
  }

  private async directory(): Promise<string> {
    if (!HuaweiCloudBackup.available()) { throw new Error('CLOUD_UNSUPPORTED'); }
    const id = await HuaweiAccountConnection.current();
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: new util.TextEncoder().encodeInto(id) });
    const digest = (await md.digest()).data;
    const scope = Array.from(digest).map((value: number) => value.toString(16).padStart(2, '0')).join('');
    // Keep separate account namespaces even while system account changes are propagating.
    return this.root + '/xiaoqiao-backups/' + scope;
  }

  async observe(callback: (progress: cloudSync.SyncProgress) => void): Promise<void> {
    await HuaweiAccountConnection.current();
    if (!HuaweiCloudBackup.available()) { throw new Error('CLOUD_UNSUPPORTED'); }
    this.close(); this.sync = new cloudSync.FileSync(); this.listener = callback;
    this.sync.on('progress', callback);
  }

  close(): void {
    try { if (this.sync !== undefined && this.listener !== undefined) { this.sync.off('progress', this.listener); } }
    catch (_) { /* The platform may have already torn down the account's sync session. */ }
    finally { this.listener = undefined; this.sync = undefined; }
  }

  async requestSync(): Promise<void> {
    await HuaweiAccountConnection.current();
    if (this.sync === undefined) { throw new Error('CLOUD_NOT_READY'); }
    // Resolving start means accepted, not that any particular backup has reached the server.
    await this.sync.start();
  }

  async lastSyncTime(): Promise<number> { return this.sync === undefined ? 0 : this.sync.getLastSyncTime(); }

  async list(): Promise<CloudBackupRecord[]> {
    const directory = await this.directory();
    if (!await fs.access(directory)) { return []; }
    const names = await fs.listFile(directory);
    const records: CloudBackupRecord[] = [];
    for (const name of names) {
      if (!/^backup-\d{13}-[0-9a-f-]{36}\.xqbackup$/.test(name)) { continue; }
      const stat = await fs.lstat(directory + '/' + name);
      if (stat.isFile() && !stat.isSymbolicLink() && stat.size > 0 && stat.size <= PACKAGE_MAX_BYTES) {
        records.push({ name: name, bytes: stat.size, createdAt: Number(name.substring(7, 20)) });
      }
    }
    await HuaweiAccountConnection.current();
    return records.sort((left: CloudBackupRecord, right: CloudBackupRecord) => right.createdAt - left.createdAt);
  }

  async create(backup: LedgerBackupPackage): Promise<void> {
    const account = await HuaweiAccountConnection.current();
    const local = this.context.cacheDir + '/cloud-backup-' + util.generateRandomUUID() + '.xqbackup';
    let partial = '';
    try {
      await backup.exportTo(local);
      const directory = await this.directory();
      if (await HuaweiAccountConnection.current() !== account) { throw new Error('HUAWEI_ACCOUNT_CHANGED'); }
      if (!await fs.access(this.root)) { throw new Error('CLOUD_NOT_READY'); }
      await BackupFiles.mkdir(directory);
      const name = 'backup-' + Date.now().toString() + '-' + util.generateRandomUUID().toLowerCase() + '.xqbackup';
      partial = directory + '/' + name + '.partial';
      await BackupFiles.copy(local, partial);
      if (await HuaweiAccountConnection.current() !== account) { throw new Error('HUAWEI_ACCOUNT_CHANGED'); }
      await fs.rename(partial, directory + '/' + name); partial = '';
    } finally {
      await BackupFiles.remove(local);
      if (partial.length > 0) { await BackupFiles.remove(partial); }
    }
  }

  private async cache(path: string): Promise<void> {
    const cache = new cloudSync.CloudFileCache(); const uri = fileUri.getUriFromPath(path);
    let timer: number = -1;
    let callback: ((progress: cloudSync.DownloadProgress) => void) | undefined = undefined;
    try {
      await new Promise<void>((resolve, reject) => {
        callback = (progress: cloudSync.DownloadProgress): void => {
          if (progress.uri !== uri) { return; }
          if (progress.state === cloudSync.State.COMPLETED) { resolve(); }
          else if (progress.state === cloudSync.State.FAILED || progress.state === cloudSync.State.STOPPED) { reject(new Error('CLOUD_DOWNLOAD_FAILED')); }
        };
        cache.on('progress', callback);
        timer = setTimeout(() => { reject(new Error('CLOUD_DOWNLOAD_TIMEOUT')); }, 120000);
        cache.start(uri).catch(() => { reject(new Error('CLOUD_DOWNLOAD_FAILED')); });
      });
    } finally {
      clearTimeout(timer);
      if (callback !== undefined) { cache.off('progress', callback); }
      try { await cache.stop(uri); } catch (_) { /* Already completed or unavailable. */ }
    }
  }

  async prepare(backup: LedgerBackupPackage, record: CloudBackupRecord): Promise<LocalBackupPreview> {
    const account = await HuaweiAccountConnection.current();
    if (!/^backup-\d{13}-[0-9a-f-]{36}\.xqbackup$/.test(record.name)) { throw new Error('CLOUD_BACKUP_NAME'); }
    const directory = await this.directory(); const path = directory + '/' + record.name;
    const local = this.context.cacheDir + '/cloud-restore-' + util.generateRandomUUID() + '.xqbackup';
    try {
      const before = await fs.lstat(path);
      if (!before.isFile() || before.isSymbolicLink() || before.size <= 0 || before.size > PACKAGE_MAX_BYTES) { throw new Error('PACKAGE_SIZE'); }
      await this.cache(path);
      const stat = await fs.lstat(path);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size <= 0 || stat.size > PACKAGE_MAX_BYTES) { throw new Error('PACKAGE_SIZE'); }
      await BackupFiles.copy(path, local);
      if (await HuaweiAccountConnection.current() !== account) { throw new Error('HUAWEI_ACCOUNT_CHANGED'); }
      return await backup.prepare(local);
    } finally { await BackupFiles.remove(local); }
  }
}
