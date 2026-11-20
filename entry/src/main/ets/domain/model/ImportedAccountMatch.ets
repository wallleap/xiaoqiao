import { BANK_ACCOUNT_STYLES, BankAccountStyle, preferredBankStyle } from './BankAccountStyles';
import { ACCOUNT_STYLES, AccountStyle } from './AccountProfile';
import { ACCOUNT_TYPES, AccountTypeDefinition } from './AccountTypes';

interface AccountNameRule { type: string; pattern: RegExp; }
interface BankNameRule { key: string; pattern: RegExp; }
export interface ImportedAccountMatch {
  accountType: string;
  kind: string;
  style: AccountStyle;
  issuerKey: string;
  cardTail: string;
}

const CREDIT_RULES: AccountNameRule[] = [
  { type: 'huabei', pattern: /花呗|\bhuabei\b/i },
  { type: 'jiebei', pattern: /借呗|\bjiebei\b/i },
  { type: 'mybank_loan', pattern: /网商贷/ },
  { type: 'fenfu', pattern: /分付/ },
  { type: 'weilidai', pattern: /微粒贷/ },
  { type: 'jd_baitiao', pattern: /京东白条|白条/ },
  { type: 'jd_jintiao', pattern: /京东金条|金条/ },
  { type: 'douyin_credit', pattern: /抖音月付/ },
  { type: 'meituan_credit', pattern: /美团月付/ }
];
const ASSET_RULES: AccountNameRule[] = [
  { type: 'lingqiantong', pattern: /零钱通/ },
  { type: 'yuebao', pattern: /余额宝/ },
  { type: 'wechat', pattern: /微信|\bwechat\b|\bweixin\b/i },
  { type: 'alipay', pattern: /支付宝|\balipay\b/i },
  { type: 'unionpay', pattern: /云闪付/ },
  { type: 'qq_wallet', pattern: /QQ\s*钱包/i },
  { type: 'ecny', pattern: /数字人民币/ },
  { type: 'huawei_wallet', pattern: /华为钱包/ },
  { type: 'pdd_wallet', pattern: /多多钱包/ },
  { type: 'paypal', pattern: /\bpaypal\b/i },
  { type: 'provident', pattern: /公积金/ },
  { type: 'pension', pattern: /养老金|养老账户/ },
  { type: 'medical', pattern: /医保/ },
  { type: 'bus', pattern: /公交卡|交通卡/ },
  { type: 'campus', pattern: /校园卡/ },
  { type: 'fuel', pattern: /加油卡|油卡/ },
  { type: 'meal', pattern: /饭卡|餐卡/ },
  { type: 'phone', pattern: /话费/ },
  { type: 'shopping', pattern: /购物卡|礼品卡/ },
  { type: 'membership', pattern: /储值卡|会员卡/ },
  { type: 'etc', pattern: /\betc\b/i },
  { type: 'other_stored', pattern: /充值卡|充值账户/ },
  { type: 'stock', pattern: /股票|证券/ },
  { type: 'fund', pattern: /基金/ },
  { type: 'bond', pattern: /债券|国债/ },
  { type: 'futures', pattern: /期货/ },
  { type: 'gold', pattern: /黄金/ }
];
const BANK_ALIASES: BankNameRule[] = [
  { key: 'icbk', pattern: /工行/ }, { key: 'bkch', pattern: /中行/ },
  { key: 'ccbc', pattern: /建行/ }, { key: 'aboc', pattern: /农行/ },
  { key: 'cmb', pattern: /招行/ },
  { key: 'bank_be3f0313e6049e7a', pattern: /交行/ },
  { key: 'bank_697f11d169df03a4', pattern: /邮储|邮政储蓄/ },
  { key: 'bank_f992e61b2440eb9f', pattern: /浦发/ },
  { key: 'bank_5d085ba3787c37d7', pattern: /平安/ },
  { key: 'bank_f5f4efccb216cf52', pattern: /兴业/ },
  { key: 'bank_dd14c4de90f711ad', pattern: /民生/ },
  { key: 'bank_2c94c71d0e1e5cf4', pattern: /光大/ },
  { key: 'bank_acaaf4fe223ff584', pattern: /广发/ },
  { key: 'bank_0b4239b04615dee8', pattern: /中信/ },
  { key: 'bank_a347afb643e9dda2', pattern: /华夏/ },
  { key: 'bank_0b35a3df2f0658ed', pattern: /浙商/ }
];

function ruleMatches(name: string, rules: AccountNameRule[]): string[] {
  const keys: string[] = [];
  for (const rule of rules) { if (rule.pattern.test(name) && !keys.includes(rule.type)) { keys.push(rule.type); } }
  return keys;
}

function matchingBanks(name: string): BankAccountStyle[] {
  const matched: BankAccountStyle[] = [];
  for (const bank of BANK_ACCOUNT_STYLES) {
    if (bank.variant !== 'monochrome' || bank.historical) { continue; }
    const alias = BANK_ALIASES.find((item: BankNameRule) => item.key === bank.key);
    const sourceName = (bank.searchText || '').split(' ')[0];
    const abbreviation = (bank.searchText || '').split(' ').slice(1).join(' ').trim();
    const english = /^[a-z0-9]+$/i.test(abbreviation) &&
      new RegExp('(^|[^a-z])' + abbreviation + '(?=$|[^a-z])', 'i').test(name);
    if (name.includes(bank.name) || (sourceName.length > 0 && name.includes(sourceName)) ||
      alias?.pattern.test(name) === true || english) { matched.push(bank); }
  }
  return matched;
}

function result(typeKey: string, bank: BankAccountStyle | undefined = undefined, tail: string = ''): ImportedAccountMatch {
  const type = ACCOUNT_TYPES.find((item: AccountTypeDefinition) => item.key === typeKey);
  if (type === undefined) { throw new Error('INVALID_IMPORTED_ACCOUNT_TYPE'); }
  const style = bank === undefined ? ACCOUNT_STYLES.find((item: AccountStyle) => item.key === type.styleKey) : (preferredBankStyle(bank.key) || bank);
  if (style === undefined) { throw new Error('INVALID_IMPORTED_ACCOUNT_STYLE'); }
  const card = typeKey === 'debit_card' || typeKey === 'credit_card';
  return { accountType: typeKey, kind: type.kind, style: style,
    issuerKey: card ? (bank?.key || 'other_bank') : '', cardTail: card ? tail : '' };
}

/** Match only newly created import accounts; never rename or reclassify an existing account. */
export function matchImportedAccount(rawName: string): ImportedAccountMatch {
  const name = rawName.trim();
  const exact = ACCOUNT_TYPES.find((item: AccountTypeDefinition) => item.name.toLowerCase() === name.toLowerCase());
  if (exact !== undefined) { return result(exact.key); }
  const credit = ruleMatches(name, CREDIT_RULES);
  if (credit.length > 0) { return result(credit.length === 1 ? credit[0] : 'other_credit'); }
  const banks = matchingBanks(name);
  const bank = banks.length === 1 ? banks[0] : undefined;
  // Only explicit masked/labelled/parenthesized tails; do not infer from arbitrary numbers.
  const tail = name.match(/(?:尾号\s*[:：]?\s*|\*+\s*)([0-9]{4})(?![0-9])|[（(]\s*([0-9]{4})\s*[）)]/);
  const cardTail = tail === null ? '' : (tail[1] || tail[2] || '');
  if (/信用卡|贷记卡/.test(name)) { return result('credit_card', bank, cardTail); }
  if (/贷款|待还|借款|欠款|消费贷|网贷|负债|信用账户/.test(name)) { return result('other_credit'); }
  if (/储蓄卡|借记卡/.test(name) || bank !== undefined) { return result('debit_card', bank, cardTail); }
  // Subproducts take priority over platform names such as 支付宝余额宝 and 微信零钱通.
  const specific = ASSET_RULES.filter((item: AccountNameRule) => item.type !== 'wechat' && item.type !== 'alipay');
  const assets = ruleMatches(name, specific);
  if (assets.length > 0) { return result(assets.length === 1 ? assets[0] : 'other_asset'); }
  const platform = ruleMatches(name, ASSET_RULES.filter((item: AccountNameRule) => item.type === 'wechat' || item.type === 'alipay'));
  if (platform.length === 1) { return result(platform[0]); }
  if (/^(现金|现金账户|cash)$/i.test(name)) { return result('cash'); }
  return result('other_asset');
}
