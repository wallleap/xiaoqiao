import { LedgerBackupPackage } from '../backup/LedgerBackupPackage';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { LocalBackupPreview } from '../rdb/LocalLedgerBackup';
import { DAV_MAX_BYTES, DavConfig, DavFile, WebDavClient } from './WebDavClient';

export class WebDavBackup {
  private readonly context: common.Context;
  private readonly backup: LedgerBackupPackage;
  private readonly client: WebDavClient;
  constructor(context: common.Context, backup: LedgerBackupPackage, config: DavConfig, client?: WebDavClient) {
    this.context = context; this.backup = backup; this.client = client || new WebDavClient(config);
  }
  async list(): Promise<DavFile[]> { return this.client.list(); }
  async upload(): Promise<void> {
    const name = 'xiaoqiao-' + new Date().toISOString().replace(/[:.]/g, '-') + '-' + util.generateRandomUUID() + '.xqbackup';
    const path = this.context.cacheDir + '/' + name;
    try {
      await this.backup.exportTo(path);
      const file = await fs.open(path, fs.OpenMode.READ_ONLY);
      let data: ArrayBuffer;
      try {
        const bytes = (await fs.stat(file.fd)).size;
        if (bytes <= 0 || bytes > DAV_MAX_BYTES) { throw new Error('DAV_SIZE'); }
        data = new ArrayBuffer(bytes);
        if (await fs.read(file.fd, data) !== bytes) { throw new Error('DAV_READ'); }
      } finally { await fs.close(file); }
      await this.client.upload(name, data);
    } finally { if (await fs.access(path)) { await fs.unlink(path); } }
  }
  async prepare(file: DavFile): Promise<LocalBackupPreview> {
    const path = this.context.cacheDir + '/xiaoqiao-dav-download-' + util.generateRandomUUID() + '.xqbackup';
    try {
      const data = await this.client.download(file);
      const output = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      try {
        if (await fs.write(output.fd, data) !== data.byteLength) { throw new Error('DAV_WRITE'); }
        await fs.fsync(output.fd);
      } finally { await fs.close(output); }
      return await this.backup.prepare(path);
    } finally { if (await fs.access(path)) { await fs.unlink(path); } }
  }
}
