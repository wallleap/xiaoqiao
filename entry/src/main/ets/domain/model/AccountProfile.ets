import { BANK_ACCOUNT_STYLES } from './BankAccountStyles';
import { FINANCE_ACCOUNT_STYLES } from './FinanceAccountStyles';
import { ACCOUNT_TYPES, AccountTypeDefinition, accountType, isBankAccountType } from './AccountTypes';
import { Money } from '../../core/money/Money';
import { currencyUnit } from '../../core/money/Currencies';

export interface AccountStyle {
  key: string;
  name: string;
  brand: string;
  color: string;
  variant?: string;
  historical?: boolean;
  searchText?: string;
}
export const ACCOUNT_STYLES: AccountStyle[] = [
  { key: 'cash', name: '现金', brand: 'cash', color: '#D49A38' },
  ...FINANCE_ACCOUNT_STYLES,
  { key: 'bank_card', name: '银行卡', brand: 'bank', color: '#5378B8' },
  { key: 'credit_card', name: '信用卡', brand: 'credit', color: '#7358B5' },
  ...BANK_ACCOUNT_STYLES,
  ...ACCOUNT_TYPES.filter((item: AccountTypeDefinition) => item.styleKey.startsWith('type_')).map((item: AccountTypeDefinition): AccountStyle => {
    return { key: item.styleKey, name: item.name, brand: item.key, color: item.color };
  })
];

export interface AccountCommand {
  accountType?: string;
  issuerKey?: string;
  cardTail?: string;
  note?: string;
  id: string;
  name: string;
  kind: string;
  styleKey: string;
  includeInNetAssets: boolean;
  opening: Money;
}
export interface AccountProfile {
  accountType?: string;
  issuerKey?: string;
  cardTail?: string;
  note?: string;
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
/** Expected versions make an account-order save atomic against concurrent edits. */
export interface AccountOrderItem { id: string; revision: number; }

export interface AccountOverview {
  accounts: AccountProfile[];
  assetsMinor: string;
  liabilitiesMinor: string;
  netMinor: string;
  prepaidMinor?: string;
  valuationMissing?: string[];
  valuationDate?: string;
}

export class AccountDraft {
  readonly command: AccountCommand;
  readonly style: AccountStyle;
  constructor(command: AccountCommand) {
    const style = ACCOUNT_STYLES.find((item: AccountStyle) => item.key === command.styleKey);
    if (command.id.trim().length === 0 || command.name.trim().length === 0 || command.name.trim().length > 40 ||
      (command.kind !== 'asset' && command.kind !== 'liability') || style === undefined) { throw new Error('INVALID_ACCOUNT'); }
    if (!command.opening.currency.matches(currencyUnit(command.opening.currency.code)) ||
      (command.kind === 'asset' && command.opening.minor < BigInt(0)) ||
      (command.kind === 'liability' && command.opening.minor > BigInt(0))) { throw new Error('INVALID_OPENING_BALANCE'); }
    command.opening.toSafeMinorNumber();
    const typeKey = command.accountType || (command.kind === 'liability' ? 'other_credit' : 'other_asset');
    const type = accountType(typeKey);
    const issuerKey = command.issuerKey || '';
    const cardTail = (command.cardTail || '').trim();
    const note = (command.note || '').trim();
    if (type === undefined || type.kind !== command.kind || note.length > 500 ||
      (cardTail !== '' && !/^[0-9]{4}$/.test(cardTail)) ||
      (!isBankAccountType(typeKey) && (issuerKey !== '' || cardTail !== '')) ||
      (issuerKey !== '' && issuerKey !== 'other_bank' && !BANK_ACCOUNT_STYLES.some((item: AccountStyle) => item.key === issuerKey && item.variant === 'monochrome'))) {
      throw new Error('INVALID_ACCOUNT_DETAILS');
    }
    this.style = style;
    this.command = { id: command.id, name: command.name.trim(), kind: command.kind, styleKey: command.styleKey,
      includeInNetAssets: command.includeInNetAssets, opening: command.opening,
      accountType: typeKey, issuerKey: issuerKey, cardTail: cardTail, note: note };
  }
}

export function requireAccountRevision(revision: number): void {
  if (!Number.isSafeInteger(revision) || revision < 1 || revision >= Number.MAX_SAFE_INTEGER) { throw new Error('INVALID_EXPECTED_REVISION'); }
}
