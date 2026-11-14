import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';
import { LedgerSnapshot, SavedLedgerEntry } from '../../domain/model/LedgerSnapshot';
import { transferPurposeLabel } from '../../domain/model/TransferRecord';

export interface LedgerExportColumn { key: string; label: string; }

export const LEDGER_EXPORT_COLUMNS: LedgerExportColumn[] = [
  { key: 'date', label: '日期' }, { key: 'time', label: '时间' }, { key: 'kind', label: '类型' },
  { key: 'category', label: '收支分类' }, { key: 'account', label: '账户' }, { key: 'toAccount', label: '转入账户' },
  { key: 'note', label: '备注' }, { key: 'merchant', label: '商户' }, { key: 'address', label: '地址' },
  { key: 'includeInBudget', label: '计入预算' }, { key: 'spendingNature', label: '预算分类' },
  { key: 'spendingNatureColor', label: '预算分类颜色' },
  { key: 'originalEntryId', label: '关联支出ID' }, { key: 'reimbursementPending', label: '待报销' },
  { key: 'latitude', label: '纬度' }, { key: 'longitude', label: '经度' },
  { key: 'currency', label: '币种' }, { key: 'gross', label: '原金额' },
  { key: 'discount', label: '优惠' }, { key: 'paid', label: '实付金额' }, { key: 'fee', label: '转账手续费' },
  { key: 'coupon', label: '转账优惠' }, { key: 'transferPurpose', label: '转账用途' },
  { key: 'feeBudget', label: '手续费计入预算' }, { key: 'tags', label: '标签' },
  { key: 'attachments', label: '附件数' }, { key: 'id', label: '账目ID' }
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
    case 'kind': return entry.recoveryKind === 'refund' ? '退款' : entry.recoveryKind === 'reimbursement' ? '报销' : entry.transfer ? '转账' : entry.income ? '收入' : '支出';
    case 'category': return entry.category;
    case 'account': return entry.account;
    case 'toAccount': return entry.toAccount || '';
    case 'note': return entry.note;
    case 'merchant': return entry.merchant || '';
    case 'address': return entry.address || '';
    case 'latitude': return entry.location === undefined ? '' : (entry.location.latitudeE6 / 1000000).toFixed(6);
    case 'longitude': return entry.location === undefined ? '' : (entry.location.longitudeE6 / 1000000).toFixed(6);
    case 'includeInBudget': return !entry.income && !entry.transfer && !entry.recoveryKind ? (entry.includeInBudget ? '是' : '否') : '';
    case 'spendingNature': return entry.spendingNatureName || '';
    case 'spendingNatureColor': return entry.spendingNatureColor || '';
    case 'originalEntryId': return entry.originalEntryId || '';
    case 'reimbursementPending': return !entry.income && !entry.transfer && !entry.recoveryKind ? (entry.reimbursementPending ? '是' : '否') : '';
    case 'currency': return 'CNY';
    case 'gross': return decimal(entry.recoveryKind ? (-BigInt(entry.minor)).toString() : entry.grossMinor);
    case 'discount': return decimal(entry.discountMinor);
    case 'paid': return decimal(entry.recoveryKind ? (-BigInt(entry.minor)).toString() : entry.minor);
    case 'fee': return decimal(entry.transferFeeMinor || '0');
    case 'coupon': return decimal(entry.transferCouponMinor || '0');
    case 'transferPurpose': return entry.transfer ? transferPurposeLabel(entry.transferPurpose || 'transfer') : '';
    case 'feeBudget': return entry.transfer ? (entry.feeInBudget === false ? '否' : '是') : '';
    case 'tags': return (entry.tagNames || []).join('|');
    case 'attachments': return String((entry.attachments || []).length);
    case 'id': return entry.id;
    default: return '';
  }
}

export function filterLedgerEntries(entries: SavedLedgerEntry[], kind: string = 'all',
  accountName: string = ''): SavedLedgerEntry[] {
  return entries.filter((entry: SavedLedgerEntry) => {
    if (kind === 'income' && (entry.transfer || !entry.income)) { return false; }
    if (kind === 'expense' && (entry.transfer || entry.income)) { return false; }
    if (accountName.length > 0 && entry.account !== accountName &&
      (!entry.transfer || entry.toAccount !== accountName)) { return false; }
    return true;
  });
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
