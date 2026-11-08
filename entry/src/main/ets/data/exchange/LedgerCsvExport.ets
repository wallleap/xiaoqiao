import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';
import { LedgerSnapshot, SavedLedgerEntry } from '../../domain/model/LedgerSnapshot';

export interface LedgerExportColumn { key: string; label: string; }

export const LEDGER_EXPORT_COLUMNS: LedgerExportColumn[] = [
  { key: 'date', label: '日期' }, { key: 'time', label: '时间' }, { key: 'kind', label: '类型' },
  { key: 'category', label: '收支分类' }, { key: 'account', label: '账户' }, { key: 'toAccount', label: '转入账户' },
  { key: 'note', label: '备注' }, { key: 'currency', label: '币种' }, { key: 'gross', label: '原金额' },
  { key: 'discount', label: '优惠' }, { key: 'paid', label: '实付金额' }, { key: 'fee', label: '转账手续费' },
  { key: 'coupon', label: '转账优惠' }, { key: 'tags', label: '标签' }, { key: 'id', label: '账目ID' }
];
export const LEDGER_CSV_HEADERS: string[] = LEDGER_EXPORT_COLUMNS.map((column) => column.label);

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

export function ledgerExportValue(entry: SavedLedgerEntry, key: string): string {
  switch (key) {
    case 'date': return entry.date;
    case 'time': return time(entry);
    case 'kind': return entry.transfer ? '转账' : entry.income ? '收入' : '支出';
    case 'category': return entry.category;
    case 'account': return entry.account;
    case 'toAccount': return entry.toAccount || '';
    case 'note': return entry.note;
    case 'currency': return 'CNY';
    case 'gross': return decimal(entry.grossMinor);
    case 'discount': return decimal(entry.discountMinor);
    case 'paid': return decimal(entry.minor);
    case 'fee': return decimal(entry.transferFeeMinor || '0');
    case 'coupon': return decimal(entry.transferCouponMinor || '0');
    case 'tags': return (entry.tagNames || []).join('|');
    case 'id': return entry.id;
    default: return '';
  }
}

/** RFC 4180-style UTF-8 CSV with BOM for spreadsheet and Excel compatibility. */
export function exportLedgerCsv(snapshot: LedgerSnapshot,
  selectedKeys: string[] = LEDGER_EXPORT_COLUMNS.map((column) => column.key)): string {
  const selected = LEDGER_EXPORT_COLUMNS.filter((column) => selectedKeys.includes(column.key));
  if (selected.length === 0) { throw new Error('EXPORT_NO_FIELDS'); }
  const lines: string[] = [selected.map((column) => csvCell(column.label)).join(',')];
  for (const entry of snapshot.entries) {
    lines.push(selected.map((column) => csvCell(ledgerExportValue(entry, column.key))).join(','));
  }
  return '\uFEFF' + lines.join('\r\n') + '\r\n';
}
