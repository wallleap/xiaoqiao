import { ExpenseCommand, ExpenseRecord } from '../model/ExpenseRecord';
import { LedgerRepository } from '../ports/LedgerRepository';

export class RecordExpense {
  private readonly repository: LedgerRepository;

  constructor(repository: LedgerRepository) {
    this.repository = repository;
  }

  async execute(command: ExpenseCommand): Promise<ExpenseRecord> {
    const record = new ExpenseRecord(command);
    await this.repository.saveExpense(record);
    return record;
  }
}
