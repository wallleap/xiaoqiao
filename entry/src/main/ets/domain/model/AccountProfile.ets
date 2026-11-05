import { Money } from '../../core/money/Money';
import { CurrencyUnit } from '../../core/money/CurrencyUnit';

export interface AccountStyle {
  key: string;
  name: string;
  brand: string;
  color: string;
}
export const ACCOUNT_STYLES: AccountStyle[] = [
  { key: 'cash', name: '现金', brand: 'cash', color: '#D49A38' },
  { key: 'wechat_pay', name: '微信', brand: 'wechat', color: '#07B75A' },
  { key: 'alipay', name: '支付宝', brand: 'alipay', color: '#1677FF' },
  { key: 'bank_card', name: '银行卡', brand: 'bank', color: '#5378B8' },
  { key: 'icbk', name: '工商银行', brand: 'icbc', color: '#C8282B' },
  { key: 'bkch', name: '中国银行', brand: 'boc', color: '#A82433' },
  { key: 'ccbc', name: '建设银行', brand: 'ccb', color: '#1665AE' },
  { key: 'aboc', name: '农业银行', brand: 'abc', color: '#008779' },
  { key: 'cmb', name: '招商银行', brand: 'cmb', color: '#C62335' },
  { key: 'credit_card', name: '信用卡', brand: 'credit', color: '#7358B5' },
  { key: 'huabei', name: '花呗', brand: 'huabei', color: '#328CDA' },
  { key: 'jiebei', name: '借呗', brand: 'jiebei', color: '#239EB0' }
];

export interface AccountCommand {
  id: string;
  name: string;
  kind: string;
  styleKey: string;
  includeInNetAssets: boolean;
  opening: Money;
}
export interface AccountProfile {
  id: string;
  name: string;
  kind: string;
  currencyId: string;
  brand: string;
  iconKey: string;
  iconVariant: string;
  brandColor: string;
  includeInNetAssets: boolean;
  revision: number;
  archived: boolean;
  balanceMinor: string;
}
export interface AccountOverview {
  accounts: AccountProfile[];
  assetsMinor: string;
  liabilitiesMinor: string;
  netMinor: string;
}

export class AccountDraft {
  readonly command: AccountCommand;
  readonly style: AccountStyle;
  constructor(command: AccountCommand) {
    const style = ACCOUNT_STYLES.find((item: AccountStyle) => item.key === command.styleKey);
    if (command.id.trim().length === 0 || command.name.trim().length === 0 || command.name.trim().length > 40 ||
      (command.kind !== 'asset' && command.kind !== 'liability') || style === undefined) { throw new Error('INVALID_ACCOUNT'); }
    if (!command.opening.currency.matches(new CurrencyUnit('CNY', 'CNY', 2)) ||
      (command.kind === 'asset' && command.opening.minor < BigInt(0)) ||
      (command.kind === 'liability' && command.opening.minor > BigInt(0))) { throw new Error('INVALID_OPENING_BALANCE'); }
    command.opening.toSafeMinorNumber();
    this.style = style;
    this.command = { id: command.id, name: command.name.trim(), kind: command.kind, styleKey: command.styleKey,
      includeInNetAssets: command.includeInNetAssets, opening: command.opening };
  }
}

export function requireAccountRevision(revision: number): void {
  if (!Number.isSafeInteger(revision) || revision < 1 || revision >= Number.MAX_SAFE_INTEGER) { throw new Error('INVALID_EXPECTED_REVISION'); }
}
