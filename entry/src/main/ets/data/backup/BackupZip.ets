import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BackupFiles, BackupFileInfo, PACKAGE_MAX_BYTES } from './BackupFiles';

export interface ZipFile { path: string; data: ArrayBuffer; }
/** Version 1 uses standard ZIP STORE entries. Photos and icons are already compressed.
 * Strict headers eliminate ZIP64, descriptors, symlinks and decompression bombs before writing any extracted file.
 */
export class BackupZip {
  static validPath(path: string): boolean {
    return path === 'manifest.json' || path === 'ledger.db' || /^assets\/(images|icons)\/[a-f0-9]{64}\.(png|jpg|webp|svg)$/.test(path);
  }
  static validOfficePath(path: string): boolean {
    return path.length > 0 && path.length <= 240 && !path.startsWith('/') && !path.includes('..') &&
      !path.includes('\\') && (path === '[Content_Types].xml' || path.startsWith('_rels/') ||
      path.startsWith('xl/') || path.startsWith('docProps/'));
  }
  static decode(data: ArrayBuffer): ZipFile[] { return BackupZip.decodeInternal(data, false); }
  static decodeOffice(data: ArrayBuffer): ZipFile[] { return BackupZip.decodeInternal(data, true); }
  private static decodeInternal(data: ArrayBuffer, office: boolean): ZipFile[] {
    if (data.byteLength < 22 || data.byteLength > PACKAGE_MAX_BYTES) { throw new Error('PACKAGE_SIZE'); }
    const view = new DataView(data); const bytes = new Uint8Array(data); const end = data.byteLength - 22;
    if (view.getUint32(end, true) !== 0x06054b50 || view.getUint16(end + 20, true) !== 0 ||
      view.getUint16(end + 4, true) !== 0 || view.getUint16(end + 6, true) !== 0) { throw new Error('PACKAGE_ZIP'); }
    const count = view.getUint16(end + 10, true);
    const central = view.getUint32(end + 16, true); const centralSize = view.getUint32(end + 12, true);
    if (count < 2 || count > 2048 || count !== view.getUint16(end + 8, true) || central + centralSize !== end) { throw new Error('PACKAGE_ZIP'); }
    const files: ZipFile[] = []; const paths: Set<string> = new Set();
    let cursor = central, localEnd = 0;
    const decoder = util.TextDecoder.create('utf-8', { fatal: true });
    for (let i = 0; i < count; i++) {
      if (cursor + 46 > end || view.getUint32(cursor, true) !== 0x02014b50) { throw new Error('PACKAGE_ZIP'); }
      const flags = view.getUint16(cursor + 8, true), method = view.getUint16(cursor + 10, true);
      const crc = view.getUint32(cursor + 16, true), size = view.getUint32(cursor + 24, true);
      const length = view.getUint16(cursor + 28, true), extra = view.getUint16(cursor + 30, true), comment = view.getUint16(cursor + 32, true);
      const local = view.getUint32(cursor + 42, true), mode = (view.getUint32(cursor + 38, true) >>> 16) & 0xf000;
      if (flags !== 0x800 || method !== 0 || size !== view.getUint32(cursor + 20, true) || size === 0 ||
        cursor + 46 + length + extra + comment > end || extra !== 0 || comment !== 0 ||
        view.getUint16(cursor + 34, true) !== 0 || (mode !== 0 && mode !== 0x8000) || local !== localEnd || local + 30 > central) { throw new Error('PACKAGE_ZIP'); }
      const path = decoder.decodeToString(bytes.slice(cursor + 46, cursor + 46 + length));
      if (!(office ? BackupZip.validOfficePath(path) : BackupZip.validPath(path)) || paths.has(path) ||
        view.getUint32(local, true) !== 0x04034b50 ||
        view.getUint16(local + 6, true) !== flags || view.getUint16(local + 8, true) !== method ||
        view.getUint32(local + 14, true) !== crc || view.getUint32(local + 18, true) !== size ||
        view.getUint32(local + 22, true) !== size || view.getUint16(local + 26, true) !== length || view.getUint16(local + 28, true) !== 0) { throw new Error('PACKAGE_ZIP'); }
      const start = local + 30 + length;
      if (start + size > central || decoder.decodeToString(bytes.slice(local + 30, start)) !== path) { throw new Error('PACKAGE_ZIP'); }
      const content = data.slice(start, start + size);
      if (BackupFiles.crc32(new Uint8Array(content)) !== crc) { throw new Error('PACKAGE_CRC'); }
      files.push({ path: path, data: content }); paths.add(path); localEnd = start + size;
      cursor += 46 + length;
    }
    if (cursor !== end || localEnd !== central) { throw new Error('PACKAGE_ZIP'); }
    if (!office && (!paths.has('manifest.json') || !paths.has('ledger.db'))) { throw new Error('PACKAGE_ZIP'); }
    return files;
  }
  static async encode(directory: string, target: string, files: BackupFileInfo[]): Promise<void> {
    await BackupZip.encodeInternal(directory, target, files, false);
  }
  static async encodeOffice(directory: string, target: string, files: BackupFileInfo[]): Promise<void> {
    await BackupZip.encodeInternal(directory, target, files, true);
  }
  private static async encodeInternal(directory: string, target: string, files: BackupFileInfo[], office: boolean): Promise<void> {
    const output = await fs.open(target, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    const offsets: number[] = []; let offset = 0;
    try {
      for (const file of files) {
        if (!(office ? BackupZip.validOfficePath(file.path) : BackupZip.validPath(file.path))) { throw new Error('PACKAGE_PATH'); }
        const name = new util.TextEncoder().encodeInto(file.path);
        const header = new ArrayBuffer(30 + name.length); const view = new DataView(header);
        view.setUint32(0, 0x04034b50, true); view.setUint16(4, 20, true); view.setUint16(6, 0x800, true); view.setUint16(12, 33, true);
        view.setUint32(14, file.crc32, true); view.setUint32(18, file.bytes, true); view.setUint32(22, file.bytes, true); view.setUint16(26, name.length, true);
        new Uint8Array(header, 30).set(name); offsets.push(offset);
        await BackupFiles.writeAll(output.fd, header);
        const data = await BackupFiles.read(directory + '/' + file.path);
        if (data.byteLength !== file.bytes || BackupFiles.crc32(new Uint8Array(data)) !== file.crc32) { throw new Error('PACKAGE_CHANGED'); }
        await BackupFiles.writeAll(output.fd, data); offset += header.byteLength + data.byteLength;
        if (offset > PACKAGE_MAX_BYTES) { throw new Error('PACKAGE_SIZE'); }
      }
      const centralStart = offset;
      for (let i = 0; i < files.length; i++) {
        const file = files[i], name = new util.TextEncoder().encodeInto(file.path);
        const header = new ArrayBuffer(46 + name.length); const view = new DataView(header);
        view.setUint32(0, 0x02014b50, true); view.setUint16(4, 0x314, true); view.setUint16(6, 20, true); view.setUint16(8, 0x800, true); view.setUint16(14, 33, true);
        view.setUint32(16, file.crc32, true); view.setUint32(20, file.bytes, true); view.setUint32(24, file.bytes, true);
        view.setUint16(28, name.length, true); view.setUint32(38, 0x81a40000, true); view.setUint32(42, offsets[i], true);
        new Uint8Array(header, 46).set(name); await BackupFiles.writeAll(output.fd, header); offset += header.byteLength;
      }
      const end = new ArrayBuffer(22); const view = new DataView(end);
      view.setUint32(0, 0x06054b50, true); view.setUint16(8, files.length, true); view.setUint16(10, files.length, true);
      view.setUint32(12, offset - centralStart, true); view.setUint32(16, centralStart, true);
      if (offset + 22 > PACKAGE_MAX_BYTES || files.length > 2048) { throw new Error('PACKAGE_SIZE'); }
      await BackupFiles.writeAll(output.fd, end); await fs.fsync(output.fd);
    } finally { await fs.close(output); }
  }
}
