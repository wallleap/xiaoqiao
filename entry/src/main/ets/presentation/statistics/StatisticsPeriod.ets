import { StatisticsBucketUnit } from '../../domain/model/LedgerStatistics';

export type StatisticsRange = 'week' | 'month' | 'year' | 'custom';

export interface StatisticsDateRange {
  startDate: string;
  endDateExclusive: string;
  bucketUnit: StatisticsBucketUnit;
}

function pad(value: number): string {
  return String(value).padStart(2, '0');
}

export function localDate(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function parseLocalDate(value: string): Date {
  const parts = value.split('-');
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0, 0);
}

function startOfMonth(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), 1, 12, 0, 0, 0);
}

export function currentRange(range: StatisticsRange, now: Date = new Date(),
  customStart: string = '', customEnd: string = ''): StatisticsDateRange {
  if (range === 'week') {
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 12, 0, 0, 0);
    const weekday = (start.getDay() + 6) % 7;
    start.setDate(start.getDate() - weekday);
    const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 7, 12, 0, 0, 0);
    return { startDate: localDate(start), endDateExclusive: localDate(end), bucketUnit: 'day' };
  }
  if (range === 'month') {
    const start = startOfMonth(now);
    const end = new Date(start.getFullYear(), start.getMonth() + 1, 1, 12, 0, 0, 0);
    return { startDate: localDate(start), endDateExclusive: localDate(end), bucketUnit: 'day' };
  }
  if (range === 'year') {
    return { startDate: `${now.getFullYear()}-01-01`, endDateExclusive: `${now.getFullYear() + 1}-01-01`,
      bucketUnit: 'month' };
  }
  const first = parseLocalDate(customStart);
  const last = parseLocalDate(customEnd);
  const start = first <= last ? first : last;
  const endInclusive = first <= last ? last : first;
  const end = new Date(endInclusive.getFullYear(), endInclusive.getMonth(), endInclusive.getDate() + 1, 12, 0, 0, 0);
  const days = Math.round((end.getTime() - start.getTime()) / 86400000);
  return { startDate: localDate(start), endDateExclusive: localDate(end), bucketUnit: days > 62 ? 'month' : 'day' };
}

export function shiftedRange(range: StatisticsRange, current: StatisticsDateRange, direction: number): StatisticsDateRange {
  if (range === 'custom' || direction === 0) { return current; }
  const start = parseLocalDate(current.startDate);
  const end = parseLocalDate(current.endDateExclusive);
  if (range === 'week') {
    start.setDate(start.getDate() + direction * 7);
    end.setDate(end.getDate() + direction * 7);
  } else if (range === 'month') {
    start.setMonth(start.getMonth() + direction);
    end.setMonth(end.getMonth() + direction);
  } else {
    start.setFullYear(start.getFullYear() + direction);
    end.setFullYear(end.getFullYear() + direction);
  }
  return { startDate: localDate(start), endDateExclusive: localDate(end), bucketUnit: current.bucketUnit };
}

export function rangeTitle(range: StatisticsRange, value: StatisticsDateRange): string {
  if (range === 'week') { return `${value.startDate.substring(5)} — ${lastInclusive(value).substring(5)}`; }
  if (range === 'month') { return value.startDate.substring(0, 7).replace('-', '年') + '月'; }
  if (range === 'year') { return value.startDate.substring(0, 4) + '年'; }
  return `${value.startDate.substring(5)} — ${lastInclusive(value).substring(5)}`;
}

function lastInclusive(value: StatisticsDateRange): string {
  const end = parseLocalDate(value.endDateExclusive);
  end.setDate(end.getDate() - 1);
  return localDate(end);
}
