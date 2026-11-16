import { FxConversion } from '../../core/money/FxConversion';
export type RecoveryKind = 'refund' | 'reimbursement';

export interface ExpenseRecovery {
  id: string;
  transactionId: string;
  kind: RecoveryKind;
  amountMinor: string;
  currencyId?: string;
  bookMinor?: string;
  accountMinor?: string;
  accountCurrencyId?: string;
  accountFx?: FxConversion;
  accountId: string;
  accountName: string;
  localDate: string;
  occurredAtMs: number;
  offsetMinutes: number;
  note: string;
  revision: number;
  balanceMode: string;
}

export interface RecoveryCommand {
  id: string;
  transactionId: string;
  bookId: string;
  kind: RecoveryKind;
  amountMinor: string;
  currencyId?: string;
  bookMinor?: string;
  accountMinor?: string;
  accountCurrencyId?: string;
  accountFx?: FxConversion;
  accountId: string;
  occurredAtMs: number;
  localDate: string;
  offsetMinutes: number;
  note: string;
  expectedRevision?: number;
}

export function recoveryError(error: Error): string {
  const code = error.message || '';
  if (code.includes('RECOVERY_EXCEEDS_PAID')) { return '报销与退款合计不能超过原支出实付金额'; }
  if (code.includes('EXPENSE_HAS_RECOVERIES')) { return '请先删除关联的报销和退款记录，再删除原支出'; }
  if (code.includes('ACCOUNT_UNAVAILABLE')) { return '到账账户不可用，请重新选择'; }
  if (code.includes('RECOVERY_SOURCE')) { return '找不到可关联的支出，请同时导入原支出或核对关联支出ID'; }
  if (code.includes('RECOVERY_CHANGED') || code.includes('TRANSACTION_CHANGED')) { return '记录已变化，请重新打开后操作'; }
  if (code.includes('INVALID_RECOVERY')) { return '请填写有效的正数金额、到账日期和时间'; }
  return '操作未完成，请重新读取账目后检查，避免重复录入';
}
