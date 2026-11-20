/** Account purpose is independent of brand artwork and asset/liability arithmetic. */
export interface AccountTypeDefinition { key: string; name: string; group: string; kind: string; styleKey: string; color: string; }
export const ACCOUNT_TYPE_GROUPS: string[] = ['funds', 'stored', 'credit', 'other'];
export const ACCOUNT_TYPE_GROUP_NAMES: string[] = ['资金账户', '充值账户', '信用账户', '其他账户'];
export const ACCOUNT_TYPES: AccountTypeDefinition[] = [
  { key: 'cash', name: '现金', group: 'funds', kind: 'asset', styleKey: 'cash', color: '#AD2728' },
  { key: 'debit_card', name: '储蓄卡', group: 'funds', kind: 'asset', styleKey: 'bank_card', color: '#398C42' },
  { key: 'wechat', name: '微信零钱', group: 'funds', kind: 'asset', styleKey: 'wechat_pay', color: '#50AC70' },
  { key: 'lingqiantong', name: '零钱通', group: 'funds', kind: 'asset', styleKey: 'type_lingqiantong', color: '#E5B63D' },
  { key: 'alipay', name: '支付宝余额', group: 'funds', kind: 'asset', styleKey: 'alipay', color: '#3978F0' },
  { key: 'yuebao', name: '余额宝', group: 'funds', kind: 'asset', styleKey: 'type_yuebao', color: '#EF503B' },
  { key: 'unionpay', name: '云闪付', group: 'funds', kind: 'asset', styleKey: 'type_unionpay', color: '#EF403B' },
  { key: 'qq_wallet', name: 'QQ 钱包', group: 'funds', kind: 'asset', styleKey: 'type_qq_wallet', color: '#E8AD3D' },
  { key: 'ecny', name: '数字人民币', group: 'funds', kind: 'asset', styleKey: 'type_ecny', color: '#B52D31' },
  { key: 'huawei_wallet', name: '华为钱包', group: 'funds', kind: 'asset', styleKey: 'type_huawei_wallet', color: '#D95762' },
  { key: 'pdd_wallet', name: '多多钱包', group: 'funds', kind: 'asset', styleKey: 'type_pdd_wallet', color: '#D82726' },
  { key: 'paypal', name: 'PayPal', group: 'funds', kind: 'asset', styleKey: 'type_paypal', color: '#172C83' },
  { key: 'provident', name: '公积金', group: 'funds', kind: 'asset', styleKey: 'type_provident', color: '#AD3343' },
  { key: 'pension', name: '养老金', group: 'funds', kind: 'asset', styleKey: 'type_pension', color: '#C99A36' },
  { key: 'medical', name: '医保', group: 'funds', kind: 'asset', styleKey: 'type_medical', color: '#EF443D' },
  { key: 'other_asset', name: '其他资金', group: 'funds', kind: 'asset', styleKey: 'type_other_asset', color: '#315F96' },
  { key: 'bus', name: '公交卡', group: 'stored', kind: 'asset', styleKey: 'type_bus', color: '#285CBB' },
  { key: 'campus', name: '校园卡', group: 'stored', kind: 'asset', styleKey: 'type_campus', color: '#B41B70' },
  { key: 'fuel', name: '加油卡', group: 'stored', kind: 'asset', styleKey: 'type_fuel', color: '#AC4242' },
  { key: 'meal', name: '饭卡', group: 'stored', kind: 'asset', styleKey: 'type_meal', color: '#EBC968' },
  { key: 'phone', name: '话费账户', group: 'stored', kind: 'asset', styleKey: 'type_phone', color: '#4B7FE1' },
  { key: 'shopping', name: '购物卡', group: 'stored', kind: 'asset', styleKey: 'type_shopping', color: '#DA8A3D' },
  { key: 'membership', name: '会员储值卡', group: 'stored', kind: 'asset', styleKey: 'type_membership', color: '#4B7FE1' },
  { key: 'etc', name: 'ETC', group: 'stored', kind: 'asset', styleKey: 'type_etc', color: '#2D478C' },
  { key: 'other_stored', name: '其他充值', group: 'stored', kind: 'asset', styleKey: 'type_other_stored', color: '#202D76' },
  { key: 'credit_card', name: '信用卡', group: 'credit', kind: 'liability', styleKey: 'credit_card', color: '#23283C' },
  { key: 'mybank_loan', name: '网商贷', group: 'credit', kind: 'liability', styleKey: 'type_mybank_loan', color: '#3877F0' },
  { key: 'huabei', name: '花呗', group: 'credit', kind: 'liability', styleKey: 'huabei', color: '#328CDA' },
  { key: 'jiebei', name: '借呗', group: 'credit', kind: 'liability', styleKey: 'jiebei', color: '#239EB0' },
  { key: 'fenfu', name: '微信分付', group: 'credit', kind: 'liability', styleKey: 'type_fenfu', color: '#3EAC73' },
  { key: 'weilidai', name: '微粒贷', group: 'credit', kind: 'liability', styleKey: 'type_weilidai', color: '#3468A7' },
  { key: 'jd_baitiao', name: '京东白条', group: 'credit', kind: 'liability', styleKey: 'type_jd_baitiao', color: '#C53735' },
  { key: 'jd_jintiao', name: '京东金条', group: 'credit', kind: 'liability', styleKey: 'type_jd_jintiao', color: '#CDB34E' },
  { key: 'douyin_credit', name: '抖音月付', group: 'credit', kind: 'liability', styleKey: 'type_douyin_credit', color: '#5BC9CD' },
  { key: 'meituan_credit', name: '美团月付', group: 'credit', kind: 'liability', styleKey: 'type_meituan_credit', color: '#E9BC36' },
  { key: 'other_credit', name: '其他信用', group: 'credit', kind: 'liability', styleKey: 'type_other_credit', color: '#203F79' },
  { key: 'stock', name: '股票', group: 'other', kind: 'asset', styleKey: 'type_stock', color: '#DA312C' },
  { key: 'fund', name: '基金', group: 'other', kind: 'asset', styleKey: 'type_fund', color: '#E3C345' },
  { key: 'bond', name: '债券', group: 'other', kind: 'asset', styleKey: 'type_bond', color: '#C5502D' },
  { key: 'futures', name: '期货', group: 'other', kind: 'asset', styleKey: 'type_futures', color: '#333ED2' },
  { key: 'gold', name: '黄金', group: 'other', kind: 'asset', styleKey: 'type_gold', color: '#E8C23C' },
  { key: 'investment', name: '其他投资', group: 'other', kind: 'asset', styleKey: 'type_investment', color: '#8B7B77' },
  { key: 'other_property', name: '其他资产', group: 'other', kind: 'asset', styleKey: 'type_other_property', color: '#74551F' },
 ];
export function accountType(key: string): AccountTypeDefinition | undefined {
  return ACCOUNT_TYPES.find((item: AccountTypeDefinition) => item.key === key);
}
export function isBankAccountType(key: string): boolean { return key === 'debit_card' || key === 'credit_card'; }
