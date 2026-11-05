import { ExpenseRecord } from '../model/ExpenseRecord';

export interface ExpenseUpdateRepository {
  updateExpense(record: ExpenseRecord, expectedRevision: number): Promise<void>;
}
