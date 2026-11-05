import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';
import { requireAccountRevision } from './AccountProfile';

export interface AccountCalibrationCommand {
  id: string;
  accountId: string;
  expectedRevision: number;
  before: Money;
  after: Money;
  reason: string;
}

/** Expected balance is captured by the preview, never silently recomputed during a write. */
export class AccountCalibration {
  readonly command: AccountCalibrationCommand;
  readonly delta: Money;
  constructor(command: AccountCalibrationCommand) {
    requireAccountRevision(command.expectedRevision);
    const currency = new CurrencyUnit('CNY', 'CNY', 2);
    if (!command.id.trim() || !command.accountId.trim() || command.reason.trim().length > 200) { throw new Error('INVALID_CALIBRATION'); }
    if (!command.before.currency.matches(currency) || !command.after.currency.matches(currency)) { throw new Error('UNSUPPORTED_ACCOUNT_CURRENCY'); }
    this.delta = command.after.subtract(command.before);
    command.before.toSafeMinorNumber(); command.after.toSafeMinorNumber(); this.delta.toSafeMinorNumber();
    if (this.delta.minor === BigInt(0)) { throw new Error('BALANCE_UNCHANGED'); }
    this.command = { id: command.id, accountId: command.accountId, expectedRevision: command.expectedRevision,
      before: command.before, after: command.after, reason: command.reason.trim() || '手动校准余额' };
  }
}

export interface AccountAdjustment {
  id: string;
  kind: string;
  beforeMinor: string;
  afterMinor: string;
  deltaMinor: string;
  reason: string;
  occurredAtMs: number;
}
export interface AdjustmentCursor { occurredAtMs: number; id: string; }
export interface AdjustmentPage { items: AccountAdjustment[]; next?: AdjustmentCursor; }
