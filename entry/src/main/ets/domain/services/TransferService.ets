import { TransferCommand, TransferRecord } from '../model/TransferRecord';
import { TransferRepository } from '../ports/TransferRepository';

export class TransferService {
  private readonly repository: TransferRepository;
  constructor(repository: TransferRepository) { this.repository = repository; }
  async save(command: TransferCommand): Promise<void> { await this.repository.saveTransfer(new TransferRecord(command)); }
  async update(command: TransferCommand, revision: number): Promise<void> {
    if (!Number.isSafeInteger(revision) || revision < 1 || revision >= Number.MAX_SAFE_INTEGER) { throw new Error('INVALID_EXPECTED_REVISION'); }
    await this.repository.updateTransfer(new TransferRecord(command), revision);
  }
}
