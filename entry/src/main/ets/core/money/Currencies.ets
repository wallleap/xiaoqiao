import { CurrencyUnit } from './CurrencyUnit';

export interface CurrencyDefinition { code: string; name: string; symbol: string; scale: number; }

/** Explicit minor units: ISO currency precision is never inferred from a rate or symbol. */
export const CURRENCIES: CurrencyDefinition[] = [
  { code: 'CNY', name: '人民币', symbol: '¥', scale: 2 },
  { code: 'USD', name: '美元', symbol: '$', scale: 2 },
  { code: 'EUR', name: '欧元', symbol: '€', scale: 2 },
  { code: 'HKD', name: '港币', symbol: 'HK$', scale: 2 },
  { code: 'JPY', name: '日元', symbol: 'JP¥', scale: 0 },
  { code: 'GBP', name: '英镑', symbol: '£', scale: 2 },
  { code: 'AUD', name: '澳元', symbol: 'A$', scale: 2 },
  { code: 'CAD', name: '加拿大元', symbol: 'C$', scale: 2 },
  { code: 'SGD', name: '新加坡元', symbol: 'S$', scale: 2 },
  { code: 'KRW', name: '韩元', symbol: '₩', scale: 0 },
  { code: 'CHF', name: '瑞士法郎', symbol: 'CHF', scale: 2 },
  { code: 'THB', name: '泰铢', symbol: '฿', scale: 2 },
  { code: 'NZD', name: '新西兰元', symbol: 'NZ$', scale: 2 },
  { code: 'MYR', name: '马来西亚林吉特', symbol: 'RM', scale: 2 },
  { code: 'IDR', name: '印度尼西亚卢比', symbol: 'Rp', scale: 2 },
  { code: 'INR', name: '印度卢比', symbol: '₹', scale: 2 },
  { code: 'PHP', name: '菲律宾比索', symbol: '₱', scale: 2 },
  { code: 'BRL', name: '巴西雷亚尔', symbol: 'R$', scale: 2 },
  { code: 'CZK', name: '捷克克朗', symbol: 'Kč', scale: 2 },
  { code: 'DKK', name: '丹麦克朗', symbol: 'DKK', scale: 2 },
  { code: 'HUF', name: '匈牙利福林', symbol: 'Ft', scale: 2 },
  { code: 'ILS', name: '以色列新谢克尔', symbol: '₪', scale: 2 },
  { code: 'ISK', name: '冰岛克朗', symbol: 'ISK', scale: 0 },
  { code: 'MXN', name: '墨西哥比索', symbol: 'MX$', scale: 2 },
  { code: 'NOK', name: '挪威克朗', symbol: 'NOK', scale: 2 },
  { code: 'PLN', name: '波兰兹罗提', symbol: 'zł', scale: 2 },
  { code: 'RON', name: '罗马尼亚列伊', symbol: 'lei', scale: 2 },
  { code: 'SEK', name: '瑞典克朗', symbol: 'SEK', scale: 2 },
  { code: 'TRY', name: '土耳其里拉', symbol: '₺', scale: 2 },
  { code: 'ZAR', name: '南非兰特', symbol: 'R', scale: 2 }
];

export function currencyDefinition(code: string): CurrencyDefinition {
  const value = CURRENCIES.find((item: CurrencyDefinition) => item.code === code);
  if (value === undefined) { throw new Error('UNSUPPORTED_CURRENCY'); }
  return value;
}

export function currencyUnit(code: string): CurrencyUnit {
  const value = currencyDefinition(code);
  return new CurrencyUnit(value.code, value.code, value.scale);
}

/** Round a positive rational to a finite quote with HALF_UP; never divide through Number. */
export function crossRate(targetPerEuro: string, sourcePerEuro: string): string {
  const parse = (text: string): bigint[] => {
    if (!/^\d{1,16}(\.\d{1,12})?$/.test(text)) { throw new Error('INVALID_EXCHANGE_RATE'); }
    const parts = text.split('.');
    const digits = parts[1] || '';
    const value = BigInt(parts[0] + digits);
    if (value <= BigInt(0)) { throw new Error('INVALID_EXCHANGE_RATE'); }
    return [value, BigInt(10) ** BigInt(digits.length)];
  };
  const target = parse(targetPerEuro); const source = parse(sourcePerEuro);
  const numerator = target[0] * source[1] * BigInt('1000000000000');
  const denominator = source[0] * target[1];
  let rounded = numerator / denominator;
  if (numerator % denominator * BigInt(2) >= denominator) { rounded += BigInt(1); }
  if (rounded <= BigInt(0)) { throw new Error('INVALID_EXCHANGE_RATE'); }
  const digits = rounded.toString().padStart(13, '0');
  return (digits.substring(0, digits.length - 12) + '.' + digits.substring(digits.length - 12)).replace(/0+$/, '').replace(/\.$/, '');
}
