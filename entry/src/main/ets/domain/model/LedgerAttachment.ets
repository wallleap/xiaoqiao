export interface LedgerAttachmentDraft {
  relativePath: string;
  sha256: string;
  bytes: number;
  mimeType: string;
}

export interface LedgerAttachment extends LedgerAttachmentDraft {
  id: string;
  filePath: string;
}

export function validateAttachmentDrafts(attachments?: LedgerAttachmentDraft[]): LedgerAttachmentDraft[] | undefined {
  if (attachments === undefined) { return undefined; }
  if (attachments.length > 9) { throw new Error('INVALID_ATTACHMENT_COUNT'); }
  const result: LedgerAttachmentDraft[] = [];
  const hashes: Set<string> = new Set();
  for (const attachment of attachments) {
    if (!/^images\/[a-f0-9]{64}\.(png|jpg|webp)$/.test(attachment.relativePath) ||
      !/^[a-f0-9]{64}$/.test(attachment.sha256) ||
      attachment.relativePath.split('/')[1].split('.')[0] !== attachment.sha256 ||
      !Number.isSafeInteger(attachment.bytes) || attachment.bytes <= 0 ||
      !['image/png', 'image/jpeg', 'image/webp'].includes(attachment.mimeType) ||
      hashes.has(attachment.sha256)) {
      throw new Error('INVALID_ATTACHMENT');
    }
    hashes.add(attachment.sha256);
    result.push({ relativePath: attachment.relativePath, sha256: attachment.sha256,
      bytes: attachment.bytes, mimeType: attachment.mimeType });
  }
  return result;
}
