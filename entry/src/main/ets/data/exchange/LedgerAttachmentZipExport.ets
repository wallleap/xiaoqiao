import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { LedgerAttachmentDraft } from '../../domain/model/LedgerAttachment';
import { LedgerSnapshot } from '../../domain/model/LedgerSnapshot';
import { BackupFileInfo, BackupFiles } from '../backup/BackupFiles';
import { BackupZip } from '../backup/BackupZip';

interface AttachmentZipEntry {
  entryId: string;
  attachments: LedgerAttachmentDraft[];
}

interface AttachmentZipManifest {
  format: string;
  version: number;
  createdAt: string;
  bookId: string;
  bookName: string;
  csvPath: string;
  entries: AttachmentZipEntry[];
}

export class LedgerAttachmentZipExport {
  static async exportTo(uri: string, snapshot: LedgerSnapshot, csv: string,
    resourceRoot: string, context: common.Context): Promise<void> {
    const directory = context.cacheDir + '/xiaoqiao-attachment-zip-' + util.generateRandomUUID();
    const archive = directory + '.zip';
    try {
      await BackupFiles.mkdir(directory + '/docProps');
      await BackupFiles.mkdir(directory + '/xl/media');
      await BackupFiles.writeText(directory + '/docProps/xiaoqiao-entries.csv', csv);
      const entries: AttachmentZipEntry[] = [];
      const unique: Map<string, LedgerAttachmentDraft> = new Map();
      for (const entry of snapshot.entries) {
        const attachments = entry.attachments || [];
        if (attachments.length === 0) { continue; }
        entries.push({ entryId: entry.id, attachments: attachments });
        for (const attachment of attachments) {
          unique.set(attachment.sha256, attachment);
        }
      }
      for (const attachment of unique.values()) {
        const source = resourceRoot + '/' + attachment.relativePath;
        const info = await BackupFiles.info(source, attachment.relativePath);
        if (info.sha256 !== attachment.sha256 || info.bytes !== attachment.bytes) {
          throw new Error('ATTACHMENT_RESOURCE_MISMATCH');
        }
        const extension = attachment.relativePath.split('.').pop() || '';
        await BackupFiles.copy(source, directory + '/xl/media/' + attachment.sha256 + '.' + extension);
      }
      const manifest: AttachmentZipManifest = { format: 'xiaoqiao-attachment-export', version: 1,
        createdAt: new Date().toISOString(), bookId: snapshot.bookId, bookName: snapshot.bookName,
        csvPath: 'docProps/xiaoqiao-entries.csv', entries: entries };
      await BackupFiles.writeText(directory + '/docProps/attachments.json', JSON.stringify(manifest));
      const paths: string[] = ['docProps/xiaoqiao-entries.csv', 'docProps/attachments.json'];
      for (const attachment of unique.values()) {
        const extension = attachment.relativePath.split('.').pop() || '';
        paths.push('xl/media/' + attachment.sha256 + '.' + extension);
      }
      const infos: BackupFileInfo[] = [];
      for (const path of paths) { infos.push(await BackupFiles.info(directory + '/' + path, path)); }
      await BackupZip.encodeOffice(directory, archive, infos);
      await BackupFiles.copy(archive, uri);
    } finally {
      await BackupFiles.remove(directory);
      await BackupFiles.remove(archive);
    }
  }
}
