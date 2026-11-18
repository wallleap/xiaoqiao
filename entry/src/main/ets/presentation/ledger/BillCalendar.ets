import { i18n } from '@kit.LocalizationKit';

export interface BillCalendarDay {
  date: string;
  day: number;
  inMonth: boolean;
  secondary: string;
  festival: boolean;
}

export function billDateKey(date: Date): string {
  return date.getFullYear().toString() + '-' + (date.getMonth() + 1).toString().padStart(2, '0') + '-' + date.getDate().toString().padStart(2, '0');
}

/** Festival labels only: these rules do not claim statutory leave or adjusted workdays. */
function gregorianFestival(date: Date): string {
  const key = (date.getMonth() + 1).toString() + '-' + date.getDate().toString();
  const labels: Map<string, string> = new Map([
    ['1-1', '元旦'], ['2-14', '情人节'], ['3-8', '妇女节'], ['5-1', '劳动节'],
    ['5-4', '青年节'], ['6-1', '儿童节'], ['9-10', '教师节'], ['10-1', '国庆节'], ['12-25', '圣诞节']
  ]);
  return labels.get(key) || '';
}

function lunarLabel(date: Date): string[] {
  const solar = gregorianFestival(date);
  try {
    const calendar = i18n.getCalendar('zh-Hans-CN', 'chinese');
    calendar.setTime(date);
    const month = calendar.get('month') + 1;
    const day = calendar.get('date');
    const leap = calendar.get('is_leap_month') === 1;
    if (solar) { return [solar, 'festival']; }
    if (!leap) {
      const festivals: Map<string, string> = new Map([
        ['1-1', '春节'], ['1-15', '元宵节'], ['5-5', '端午节'], ['7-7', '七夕'],
        ['8-15', '中秋节'], ['9-9', '重阳节'], ['12-8', '腊八节']
      ]);
      const festival = festivals.get(month.toString() + '-' + day.toString());
      if (festival) { return [festival, 'festival']; }
      if (month === 12 && day >= 29) {
        const tomorrow = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1, 12);
        calendar.setTime(tomorrow);
        if (calendar.get('month') === 0 && calendar.get('date') === 1) { return ['除夕', 'festival']; }
      }
    }
    const months = ['正月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '冬月', '腊月'];
    if (day === 1) { return [(leap ? '闰' : '') + (months[month - 1] || ''), 'lunar']; }
    const digits = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];
    const text = day === 10 ? '初十' : day === 20 ? '二十' : day === 30 ? '三十' :
      (day < 10 ? '初' : day < 20 ? '十' : '廿') + (digits[(day - 1) % 10] || '');
    return [text, 'lunar'];
  } catch (_) { return solar ? [solar, 'festival'] : ['', 'lunar']; }
}

/** Monday-first complete weeks, including muted adjoining-month dates. Local noon avoids DST boundaries. */
export function billCalendarDays(monthKey: string): BillCalendarDay[] {
  const parts = monthKey.split('-');
  const year = Number(parts[0]); const month = Number(parts[1]) - 1;
  if (!Number.isInteger(year) || !Number.isInteger(month) || month < 0 || month > 11) { return []; }
  const first = new Date(year, month, 1, 12);
  const offset = (first.getDay() + 6) % 7;
  const days = new Date(year, month + 1, 0, 12).getDate();
  const count = Math.max(35, Math.ceil((offset + days) / 7) * 7);
  const result: BillCalendarDay[] = [];
  for (let index = 0; index < count; index++) {
    const date = new Date(year, month, index - offset + 1, 12);
    const inMonth = date.getMonth() === month;
    const label = inMonth ? lunarLabel(date) : ['', ''];
    result.push({ date: billDateKey(date), day: date.getDate(), inMonth: inMonth, secondary: label[0], festival: label[1] === 'festival' });
  }
  return result;
}

export function trimBillDecimal(minor: string): string {
  const negative = minor.startsWith('-');
  const absolute = negative ? -BigInt(minor) : BigInt(minor);
  const decimal = (absolute / BigInt(100)).toString() + '.' + (absolute % BigInt(100)).toString().padStart(2, '0');
  return (negative ? '−' : '') + decimal.replace(/\.00$/, '').replace(/(\.\d)0$/, '$1');
}

/** Truncates compact labels only; exact minor-unit totals remain available below the calendar. */
export function compactBillAmount(minor: string, digits: number = 2): string {
  const value = BigInt(minor); const absolute = value < BigInt(0) ? -value : value;
  if (absolute < BigInt(100000)) { return trimBillDecimal(minor); }
  const divisor = absolute >= BigInt('10000000000') ? BigInt('10000000000') : BigInt(1000000);
  const scale = BigInt(10) ** BigInt(digits);
  const scaled = absolute * scale / divisor;
  const whole = (scaled / scale).toString();
  const fraction = digits > 0 ? (scaled % scale).toString().padStart(digits, '0').replace(/0+$/, '') : '';
  return (value < BigInt(0) ? '−' : '') + whole + (fraction ? '.' + fraction : '') + (divisor === BigInt(1000000) ? '万' : '亿');
}
