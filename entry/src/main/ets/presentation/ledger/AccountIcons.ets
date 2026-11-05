export function accountIcon(key: string): Resource {
  switch (key) {
    case 'cash': return $r('app.media.accounts_cash');
    case 'wechat_pay': return $r('app.media.accounts_wechat_pay');
    case 'alipay': return $r('app.media.accounts_alipay');
    case 'icbk': return $r('app.media.accounts_icbk');
    case 'bkch': return $r('app.media.accounts_bkch');
    case 'ccbc': return $r('app.media.accounts_ccbc');
    case 'aboc': return $r('app.media.accounts_aboc');
    case 'cmb': return $r('app.media.accounts_cmb');
    case 'credit_card': return $r('app.media.accounts_credit_card');
    case 'huabei': return $r('app.media.accounts_huabei');
    case 'jiebei': return $r('app.media.accounts_jiebei');
    default: return $r('app.media.accounts_bank_card');
  }
}
