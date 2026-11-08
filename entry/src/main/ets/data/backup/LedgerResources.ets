import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BackupFileInfo, BackupFiles } from './BackupFiles';
import { BackupZip } from './BackupZip';

export interface StoredLedgerResource { relativePath: string; sha256: string; bytes: number; mimeType: string; }
export class LedgerResources {
  readonly root: string;
  private readonly context: common.Context;
  constructor(context: common.Context, name: string) {
    if (!/^[a-zA-Z0-9_-]+\.db$/.test(name)) { throw new Error('RESOURCE_DATABASE_NAME'); }
    this.context = context; this.root = context.filesDir + '/ledger_assets/' + name.slice(0, -3);
  }
  static safe(path: string): boolean { return BackupZip.validPath('assets/' + path) && path !== 'ledger.db' && path !== 'manifest.json'; }
  private static format(data: Uint8Array): string {
    if (data.length >= 8 && [137,80,78,71,13,10,26,10].every((value: number, index: number) => data[index] === value)) { return 'png'; }
    if (data.length >= 3 && data[0] === 255 && data[1] === 216 && data[2] === 255) { return 'jpg'; }
    if (data.length >= 12 && String.fromCharCode(...Array.from(data.slice(0, 4))) === 'RIFF' &&
      String.fromCharCode(...Array.from(data.slice(8, 12))) === 'WEBP') { return 'webp'; }
    if (data.length <= 1024 * 1024) {
      const text = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(data);
      if (/<svg\b/i.test(text) && !/<!DOCTYPE|<!ENTITY|<\s*(script|foreignObject)\b|\bon\w+\s*=|@import|url\s*\(/i.test(text) &&
        !/\b(?:href|src)\s*=\s*["'](?!#)/i.test(text)) { return 'svg'; }
    }
    throw new Error('RESOURCE_FORMAT');
  }
  static async validate(path: string, file: string): Promise<void> {
    if (!LedgerResources.safe(path) || (await fs.lstat(file)).isSymbolicLink()) { throw new Error('RESOURCE_PATH'); }
    const data = new Uint8Array(await BackupFiles.read(file));
    if (LedgerResources.format(data) !== path.split('.').pop()) { throw new Error('RESOURCE_FORMAT'); }
  }
  async remove(kind: string, relativePath: string): Promise<void> {
    if ((kind !== 'images' && kind !== 'icons') || !relativePath.startsWith(kind + '/') ||
      !LedgerResources.safe(relativePath)) { throw new Error('RESOURCE_PATH'); }
    const path = this.root + '/' + relativePath;
    if (await fs.access(path)) { await fs.unlink(path); }
  }
  async put(kind: string, source: string): Promise<StoredLedgerResource> {
    if (kind !== 'images' && kind !== 'icons') { throw new Error('RESOURCE_KIND'); }
    const data = await BackupFiles.read(source);
    const extension = LedgerResources.format(new Uint8Array(data));
    if (kind === 'images' && extension === 'svg') { throw new Error('RESOURCE_FORMAT'); }
    const temporary = this.context.cacheDir + '/xiaoqiao-resource-' + util.generateRandomUUID();
    try {
      await BackupFiles.write(temporary, data);
      const info = await BackupFiles.info(temporary, '');
      const relative = kind + '/' + info.sha256 + '.' + extension;
      await BackupFiles.mkdir(this.root + '/' + kind);
      const destination = this.root + '/' + relative;
      if (!await fs.access(destination)) { await fs.rename(temporary, destination); }
      else {
        await LedgerResources.validate(relative, destination);
        if ((await BackupFiles.info(destination, relative)).sha256 !== info.sha256) { throw new Error('RESOURCE_HASH'); }
      }
      return { relativePath: relative, sha256: info.sha256, bytes: info.bytes,
        mimeType: extension === 'svg' ? 'image/svg+xml' : extension === 'jpg' ? 'image/jpeg' : 'image/' + extension };
    } finally { await BackupFiles.remove(temporary); }
  }
  static async catalog(root: string): Promise<BackupFileInfo[]> {
    const result: BackupFileInfo[] = [];
    if (!await fs.access(root)) { return result; }
    if ((await fs.lstat(root)).isSymbolicLink()) { throw new Error('RESOURCE_PATH'); }
    const kinds = await fs.listFile(root);
    for (const kind of kinds) {
      if ((kind !== 'images' && kind !== 'icons') || !(await fs.lstat(root + '/' + kind)).isDirectory() ||
        (await fs.lstat(root + '/' + kind)).isSymbolicLink()) { throw new Error('RESOURCE_PATH'); }
      for (const name of await fs.listFile(root + '/' + kind)) {
        const relative = kind + '/' + name;
        await LedgerResources.validate(relative, root + '/' + relative);
        const info = await BackupFiles.info(root + '/' + relative, 'assets/' + relative);
        if (name.split('.')[0] !== info.sha256) { throw new Error('RESOURCE_HASH'); }
        result.push(info);
        if (result.length > 2046) { throw new Error('PACKAGE_SIZE'); }
      }
    }
    return result;
  }
}
