import { IncomeCommand, IncomeRecord } from '../model/IncomeRecord';
import { IncomeRepository } from '../ports/IncomeRepository';

export class IncomeService {
  private readonly repository: IncomeRepository;
  constructor(repository: IncomeRepository) { this.repository = repository; }
  async save(command: IncomeCommand): Promise<void> {
    await this.repository.saveIncome(new IncomeRecord(command));
  }
  async update(command: IncomeCommand, expectedRevision: number): Promise<void> {
    if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 1 || expectedRevision >= Number.MAX_SAFE_INTEGER) {
      throw new Error('INVALID_EXPECTED_REVISION');
    }
    await this.repository.updateIncome(new IncomeRecord(command), expectedRevision);
  }
}
