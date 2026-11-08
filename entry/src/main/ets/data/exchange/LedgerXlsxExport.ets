import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { LedgerSnapshot, SavedLedgerEntry } from '../../domain/model/LedgerSnapshot';
import { BackupFileInfo, BackupFiles } from '../backup/BackupFiles';
import { BackupZip } from '../backup/BackupZip';
import { LEDGER_CSV_HEADERS } from './LedgerCsvExport';
import { CurrencyUnit } from '../../core/money/CurrencyUnit';
import { Money } from '../../core/money/Money';

function xml(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}

function decimal(minor: string): string {
  return Money.fromMinorText(minor || '0', new CurrencyUnit('CNY', 'CNY', 2)).toDecimalString();
}

function time(entry: SavedLedgerEntry): string {
  const local = new Date(entry.occurredAtMs + entry.offsetMinutes * 60000);
  return String(local.getUTCHours()).padStart(2, '0') + ':' + String(local.getUTCMinutes()).padStart(2, '0');
}

function values(entry: SavedLedgerEntry): string[] {
  return [entry.date, time(entry), entry.transfer ? '转账' : entry.income ? '收入' : '支出', entry.category,
    entry.account, entry.toAccount || '', entry.note, 'CNY', decimal(entry.grossMinor), decimal(entry.discountMinor),
    decimal(entry.minor), decimal(entry.transferFeeMinor || '0'), decimal(entry.transferCouponMinor || '0'),
    (entry.tagNames || []).join('|'), entry.id];
}

function cell(value: string, column: number, row: number): string {
  const reference = String.fromCharCode(65 + column) + row;
  if (column >= 8 && column <= 12) { return `<c r="${reference}"><v>${xml(value)}</v></c>`; }
  return `<c r="${reference}" t="inlineStr"><is><t>${xml(value)}</t></is></c>`;
}

export function ledgerWorksheetXml(snapshot: LedgerSnapshot): string {
  const rows: string[] = [];
  rows.push('<row r="1">' + LEDGER_CSV_HEADERS.map((value: string, index: number) =>
    `<c r="${String.fromCharCode(65 + index)}1" t="inlineStr" s="1"><is><t>${xml(value)}</t></is></c>`).join('') + '</row>');
  snapshot.entries.forEach((entry: SavedLedgerEntry, rowIndex: number) => {
    rows.push(`<row r="${rowIndex + 2}">` + values(entry).map((value: string, column: number) =>
      cell(value, column, rowIndex + 2)).join('') + '</row>');
  });
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
    `<dimension ref="A1:O${snapshot.entries.length + 1}"/>` +
    '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>' +
    '<cols><col min="1" max="15" width="18" customWidth="1"/><col min="7" max="7" width="32" customWidth="1"/></cols>' +
    '<sheetData>' + rows.join('') + '</sheetData></worksheet>';
}

const CONTENT_TYPES = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
  '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
  '<Default Extension="xml" ContentType="application/xml"/>' +
  '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
  '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
  '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
  '</Types>';
const ROOT_RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
  '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
  '</Relationships>';
const WORKBOOK = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' +
  'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
  '<sheets><sheet name="账目" sheetId="1" r:id="rId1"/></sheets></workbook>';
const WORKBOOK_RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
  '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
  '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' +
  '</Relationships>';
const STYLES = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
  '<fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="11"/><name val="Arial"/></font></fonts>' +
  '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>' +
  '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
  '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
  '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
  '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>' +
  '</styleSheet>';

export class LedgerXlsxExport {
  static async exportTo(uri: string, snapshot: LedgerSnapshot, context: common.Context): Promise<void> {
    const directory = context.cacheDir + '/xiaoqiao-xlsx-' + util.generateRandomUUID();
    const archive = directory + '.xlsx';
    try {
      await BackupFiles.mkdir(directory + '/_rels');
      await BackupFiles.mkdir(directory + '/xl/_rels');
      await BackupFiles.mkdir(directory + '/xl/worksheets');
      const files: string[] = ['[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml',
        'xl/_rels/workbook.xml.rels', 'xl/styles.xml', 'xl/worksheets/sheet1.xml'];
      await BackupFiles.writeText(directory + '/[Content_Types].xml', CONTENT_TYPES);
      await BackupFiles.writeText(directory + '/_rels/.rels', ROOT_RELS);
      await BackupFiles.writeText(directory + '/xl/workbook.xml', WORKBOOK);
      await BackupFiles.writeText(directory + '/xl/_rels/workbook.xml.rels', WORKBOOK_RELS);
      await BackupFiles.writeText(directory + '/xl/styles.xml', STYLES);
      await BackupFiles.writeText(directory + '/xl/worksheets/sheet1.xml', ledgerWorksheetXml(snapshot));
      const infos: BackupFileInfo[] = [];
      for (const path of files) { infos.push(await BackupFiles.info(directory + '/' + path, path)); }
      await BackupZip.encodeOffice(directory, archive, infos);
      await BackupFiles.copy(archive, uri);
    } finally {
      await BackupFiles.remove(directory);
      await BackupFiles.remove(archive);
    }
  }
}
