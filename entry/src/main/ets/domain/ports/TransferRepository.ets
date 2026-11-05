import { TransferRecord } from '../model/TransferRecord';

export interface TransferRepository {
  saveTransfer(record: TransferRecord): Promise<void>;
  updateTransfer(record: TransferRecord, revision: number): Promise<void>;
}
