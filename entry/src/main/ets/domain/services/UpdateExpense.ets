import { ExpenseCommand, ExpenseRecord } from '../model/ExpenseRecord';
import { ExpenseUpdateRepository } from '../ports/ExpenseUpdateRepository';

export class UpdateExpense {
  private readonly repository: ExpenseUpdateRepository;

  constructor(repository: ExpenseUpdateRepository) { this.repository = repository; }

  async execute(command: ExpenseCommand, expectedRevision: number): Promise<void> {
    if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 1 || expectedRevision >= Number.MAX_SAFE_INTEGER) {
      throw new Error('INVALID_EXPECTED_REVISION');
    }
    const record = new ExpenseRecord(command);
    await this.repository.updateExpense(record, expectedRevision);
  }
}
