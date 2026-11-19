import { bankAccountIcon } from './BankAccountIcons';
import { financeAccountIcon } from './FinanceAccountIcons';

export function accountIcon(key: string, variant: string = ''): Resource {
  const financeKey = variant === 'color' && !key.endsWith('_color') ? key + '_color' : key;
  const financeIcon = financeAccountIcon(financeKey);
  if (financeIcon !== undefined) { return financeIcon; }
  // Older backups may pair an unsuffixed bank key with icon_variant=color.
  const colored = variant === 'color' ? bankAccountIcon(key.endsWith('_color') ? key : key + '_color') : undefined;
  if (colored !== undefined) { return colored; }
  const bankIcon = bankAccountIcon(key);
  if (bankIcon !== undefined) { return bankIcon; }
  switch (key) {
    case 'cash': return $r('app.media.accounts_cash');
    case 'wechat_pay': return $r('app.media.accounts_wechat_pay');
    case 'alipay': return $r('app.media.accounts_alipay');
    case 'credit_card': return $r('app.media.accounts_credit_card');
    case 'huabei': return $r('app.media.accounts_huabei');
    case 'jiebei': return $r('app.media.accounts_jiebei');
    default: return $r('app.media.accounts_bank_card');
  }
}
