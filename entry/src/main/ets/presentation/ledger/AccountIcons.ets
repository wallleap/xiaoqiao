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
    case 'type_fenfu': return $r('app.media.accounts_credit_card');
    case 'type_other_property': return $r('app.media.lucide_vault1');
    case 'type_other_credit': return $r('app.media.accounts_credit_card');
    case 'type_other_stored': return $r('app.media.accounts_recharge_card');
    case 'type_other_asset': return $r('app.media.accounts_zijin');
    case 'type_meituan_credit': return $r('app.media.accounts_meituan');
    case 'type_douyin_credit': return $r('app.media.accounts_douyin');
    case 'type_jd_jintiao': return $r('app.media.accounts_jd');
    case 'type_jd_baitiao': return $r('app.media.accounts_jd');
    case 'type_weilidai': return $r('app.media.accounts_webank');
    case 'type_mybank_loan': return $r('app.media.accounts_sme_loan');
    case 'type_unionpay': return $r('app.media.accounts_unionpay');
    case 'type_pdd_wallet': return $r('app.media.accounts_duoduo');
    case 'type_huawei_wallet': return $r('app.media.accounts_huawei');
    case 'type_qq_wallet': return $r('app.media.accounts_qq');
    case 'type_yuebao': return $r('app.media.accounts_yu_e_bao');
    case 'type_bus': return $r('app.media.accounts_bus_card');
    case 'type_campus': return $r('app.media.accounts_campus_card');
    case 'type_fuel': return $r('app.media.accounts_gas_card');
    case 'type_meal': return $r('app.media.accounts_food_card');
    case 'type_phone': return $r('app.media.accounts_recharge_card');
    case 'type_shopping': return $r('app.media.accounts_recharge_card');
    case 'type_membership': return $r('app.media.accounts_recharge_card');
    case 'type_etc': return $r('app.media.accounts_bus_card');
    case 'type_provident': return $r('app.media.accounts_gongjijin');
    case 'type_pension': return $r('app.media.accounts_yanglaojin');
    case 'type_medical': return $r('app.media.accounts_yibao');
    case 'type_stock': return $r('app.media.accounts_stock');
    case 'type_fund': return $r('app.media.accounts_fund');
    case 'type_bond': return $r('app.media.accounts_bond');
    case 'type_futures': return $r('app.media.accounts_future');
    case 'type_gold': return $r('app.media.accounts_gold');
    case 'type_investment': return $r('app.media.lucide_chart_pie1');
    case 'type_lingqiantong': return $r('app.media.accounts_mini_fund');
    case 'type_paypal': return $r('app.media.accounts_paypal');
    case 'type_ecny': return $r('app.media.accounts_e_cny');
    case 'cash': return $r('app.media.accounts_cash');
    case 'wechat_pay': return $r('app.media.accounts_wechat_pay');
    case 'alipay': return $r('app.media.accounts_alipay');
    case 'credit_card': return $r('app.media.accounts_credit_card');
    case 'huabei': return $r('app.media.accounts_huabei');
    case 'jiebei': return $r('app.media.accounts_jiebei');
    default: return $r('app.media.accounts_bank_card');
  }
}
