import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';
import { LedgerSnapshot, SavedLedgerEntry } from '../../domain/model/LedgerSnapshot';

export const LEDGER_CSV_HEADERS: string[] = [
  '日期', '时间', '类型', '收支分类', '账户', '转入账户', '备注', '币种',
  '原金额', '优惠', '实付金额', '转账手续费', '转账优惠', '标签', '账目ID'
];

function csvCell(value: string): string {
  return '"' + value.replace(/"/g, '""') + '"';
}

function decimal(minor: string): string {
  return Money.fromMinorText(minor || '0', new CurrencyUnit('CNY', 'CNY', 2)).toDecimalString();
}

function time(entry: SavedLedgerEntry): string {
  const local = new Date(entry.occurredAtMs + entry.offsetMinutes * 60000);
  return String(local.getUTCHours()).padStart(2, '0') + ':' + String(local.getUTCMinutes()).padStart(2, '0');
}

function row(entry: SavedLedgerEntry): string[] {
  return [
    entry.date,
    time(entry),
    entry.transfer ? '转账' : entry.income ? '收入' : '支出',
    entry.category,
    entry.account,
    entry.toAccount || '',
    entry.note,
    'CNY',
    decimal(entry.grossMinor),
    decimal(entry.discountMinor),
    decimal(entry.minor),
    decimal(entry.transferFeeMinor || '0'),
    decimal(entry.transferCouponMinor || '0'),
    (entry.tagNames || []).join('|'),
    entry.id
  ];
}

/** RFC 4180-style UTF-8 CSV with BOM for spreadsheet and Excel compatibility. */
export function exportLedgerCsv(snapshot: LedgerSnapshot): string {
  const lines: string[] = [LEDGER_CSV_HEADERS.map(csvCell).join(',')];
  for (const entry of snapshot.entries) {
    lines.push(row(entry).map(csvCell).join(','));
  }
  return '\uFEFF' + lines.join('\r\n') + '\r\n';
}
