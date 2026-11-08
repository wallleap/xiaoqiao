import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { LedgerAttachmentDraft } from '../../domain/model/LedgerAttachment';

export interface StoredAttachmentRecord {
  id: string;
  relativePath: string;
  sha256: string;
  bytes: number;
  mimeType: string;
}

export class RdbAttachmentLinks {
  static async replace(db: relationalStore.RdbStore, transactionId: string,
    attachments: LedgerAttachmentDraft[] | undefined): Promise<void> {
    if (attachments === undefined) { return; }
    await db.delete(new relationalStore.RdbPredicates('transaction_attachments').equalTo('transaction_id', transactionId));
    let order = 0;
    for (const attachment of attachments) {
      let id = '';
      const existing = await db.querySql("SELECT id,relative_path,mime_type,byte_size FROM attachments " +
        'WHERE content_sha256=? AND deleted_at_ms IS NULL', [attachment.sha256]);
      try {
        if (existing.goToFirstRow()) {
          id = existing.getString(0);
          if (existing.getString(1) !== attachment.relativePath ||
            existing.getString(2) !== attachment.mimeType || existing.getLong(3) !== attachment.bytes) {
            throw new Error('ATTACHMENT_METADATA_MISMATCH');
          }
        }
      } finally { existing.close(); }
      if (id.length === 0) {
        id = util.generateRandomUUID();
        await db.insert('attachments', { id: id, content_sha256: attachment.sha256,
          relative_path: attachment.relativePath, mime_type: attachment.mimeType,
          byte_size: attachment.bytes, state: 'ready', created_at_ms: Date.now() });
      }
      await db.insert('transaction_attachments', { transaction_id: transactionId, attachment_id: id,
        sort_order: order });
      order++;
    }
  }

  static async load(db: relationalStore.RdbStore, transactionId: string): Promise<StoredAttachmentRecord[]> {
    const values: StoredAttachmentRecord[] = [];
    const rows = await db.querySql('SELECT a.id,a.relative_path,a.content_sha256,a.byte_size,a.mime_type ' +
      'FROM transaction_attachments t JOIN attachments a ON a.id=t.attachment_id ' +
      'WHERE t.transaction_id=? AND a.deleted_at_ms IS NULL ORDER BY t.sort_order', [transactionId]);
    try {
      while (rows.goToNextRow()) {
        values.push({ id: rows.getString(0), relativePath: rows.getString(1), sha256: rows.getString(2),
          bytes: rows.getLong(3), mimeType: rows.getString(4) });
      }
    } finally { rows.close(); }
    return values;
  }
}
