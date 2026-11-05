import { IncomeRecord } from '../model/IncomeRecord';

export interface IncomeRepository {
  saveIncome(record: IncomeRecord): Promise<void>;
  updateIncome(record: IncomeRecord, expectedRevision: number): Promise<void>;
}
