import { fileIo as fs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export const PACKAGE_MAX_BYTES: number = 32 * 1024 * 1024;
export interface BackupFileInfo { path: string; bytes: number; sha256: string; crc32: number; }

export class BackupFiles {
  static async mkdir(path: string): Promise<void> {
    if (!await fs.access(path)) {
      try { await fs.mkdir(path, true); } catch (error) { if (!await fs.access(path)) { throw error as Error; } }
    }
    const stat = await fs.lstat(path);
    if (!stat.isDirectory() || stat.isSymbolicLink()) { throw new Error('PACKAGE_DIRECTORY'); }
  }
  static async remove(path: string): Promise<void> {
    if (!await fs.access(path)) { return; }
    const stat = await fs.lstat(path);
    if (stat.isDirectory() && !stat.isSymbolicLink()) { await fs.rmdir(path); } else { await fs.unlink(path); }
  }
  static async copy(source: string, destination: string): Promise<void> {
    const input = await fs.open(source, fs.OpenMode.READ_ONLY);
    try {
      const size = (await fs.stat(input.fd)).size;
      if (size <= 0 || size > PACKAGE_MAX_BYTES) { throw new Error('PACKAGE_SIZE'); }
      const output = await fs.open(destination, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      try { await fs.copyFile(input.fd, output.fd); await fs.fsync(output.fd);
        if ((await fs.stat(output.fd)).size !== size) { throw new Error('PACKAGE_COPY'); }
      } finally { await fs.close(output); }
    } finally { await fs.close(input); }
  }
  static async read(path: string, limit: number = PACKAGE_MAX_BYTES): Promise<ArrayBuffer> {
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const stat = await fs.stat(file.fd);
      if (!stat.isFile() || stat.size <= 0 || stat.size > limit) { throw new Error('PACKAGE_SIZE'); }
      const data = new ArrayBuffer(stat.size);
      let offset = 0;
      while (offset < stat.size) {
        const chunk = new ArrayBuffer(Math.min(65536, stat.size - offset));
        const count = await fs.read(file.fd, chunk);
        if (count <= 0) { throw new Error('PACKAGE_READ'); }
        new Uint8Array(data, offset, count).set(new Uint8Array(chunk, 0, count)); offset += count;
      }
      return data;
    } finally { await fs.close(file); }
  }
  static async write(path: string, data: ArrayBuffer): Promise<void> {
    const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    try { await BackupFiles.writeAll(file.fd, data); await fs.fsync(file.fd); } finally { await fs.close(file); }
  }
  static async writeAll(fd: number, data: ArrayBuffer): Promise<void> {
    let offset = 0;
    while (offset < data.byteLength) {
      const count = await fs.write(fd, data.slice(offset, Math.min(offset + 65536, data.byteLength)));
      if (count <= 0) { throw new Error('PACKAGE_WRITE'); } offset += count;
    }
  }
  static async text(path: string): Promise<string> {
    return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(await BackupFiles.read(path, 1024 * 1024)));
  }
  static async writeText(path: string, value: string): Promise<void> {
    await BackupFiles.write(path, new util.TextEncoder().encodeInto(value).buffer as ArrayBuffer);
  }
  static crc32(data: Uint8Array): number {
    let crc = 0xffffffff;
    for (let i = 0; i < data.length; i++) {
      crc ^= data[i];
      for (let bit = 0; bit < 8; bit++) { crc = (crc >>> 1) ^ ((crc & 1) === 1 ? 0xedb88320 : 0); }
    }
    return (crc ^ 0xffffffff) >>> 0;
  }
  static async info(path: string, relative: string): Promise<BackupFileInfo> {
    const data = new Uint8Array(await BackupFiles.read(path));
    const md = cryptoFramework.createMd('SHA256'); await md.update({ data: data });
    const digest = (await md.digest()).data;
    const hash = Array.from(digest).map((value: number) => value.toString(16).padStart(2, '0')).join('');
    return { path: relative, bytes: data.length, sha256: hash, crc32: BackupFiles.crc32(data) };
  }
}
