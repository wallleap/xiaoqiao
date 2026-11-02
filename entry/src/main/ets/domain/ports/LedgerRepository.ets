import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';
import { ExpenseRecord } from '../model/ExpenseRecord';

/** Each write either commits the complete record or rejects without partial effects. */
export interface LedgerRepository {
  saveExpense(record: ExpenseRecord): Promise<void>;
  readBalance(accountId: string, currency: CurrencyUnit): Promise<Money>;
}
