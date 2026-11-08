import { util } from '@kit.ArkTS';
import { BackupFiles } from '../backup/BackupFiles';
import { BackupZip, ZipFile } from '../backup/BackupZip';
import { CsvTable } from './LedgerCsvImport';

export interface XlsxSheetInfo {
  name: string;
  path: string;
}

function decode(data: ArrayBuffer): string {
  return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(data));
}

function text(value: string): string {
  return value.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&apos;/g, '\'').replace(/&amp;/g, '&');
}

function sharedStrings(files: ZipFile[]): string[] {
  const file = files.find((item: ZipFile) => item.path === 'xl/sharedStrings.xml');
  if (file === undefined) { return []; }
  const values: string[] = [];
  const xml = decode(file.data);
  const regex = /<si\b[^>]*>([\s\S]*?)<\/si>/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(xml)) !== null) {
    const parts: string[] = [];
    const textRegex = /<t\b[^>]*>([\s\S]*?)<\/t>/g;
    let part: RegExpExecArray | null;
    while ((part = textRegex.exec(match[1])) !== null) { parts.push(text(part[1])); }
    values.push(parts.join(''));
  }
  return values;
}

function columnIndex(reference: string): number {
  const letters = reference.replace(/[0-9]/g, '');
  let value = 0;
  for (const char of letters) { value = value * 26 + char.charCodeAt(0) - 64; }
  return value - 1;
}

function worksheet(files: ZipFile[], shared: string[], sheetPath: string = ''): string[][] {
  const file = files.find((item: ZipFile) => item.path === (sheetPath || 'xl/worksheets/sheet1.xml')) ||
    files.find((item: ZipFile) => item.path.startsWith('xl/worksheets/') && item.path.endsWith('.xml'));
  if (file === undefined) { throw new Error('XLSX_WORKSHEET_MISSING'); }
  const xml = decode(file.data);
  const rows: string[][] = [];
  const rowRegex = /<row\b[^>]*>([\s\S]*?)<\/row>/g;
  let rowMatch: RegExpExecArray | null;
  while ((rowMatch = rowRegex.exec(xml)) !== null) {
    const values: string[] = [];
    const cellRegex = /<c\b([^>]*)>([\s\S]*?)<\/c>/g;
    let cellMatch: RegExpExecArray | null;
    while ((cellMatch = cellRegex.exec(rowMatch[1])) !== null) {
      const attrs = cellMatch[1];
      const body = cellMatch[2];
      const ref = /\br="([A-Z]+)[0-9]+"/.exec(attrs);
      if (ref === null) { continue; }
      const index = columnIndex(ref[1]);
      const kind = /\bt="([^"]+)"/.exec(attrs)?.[1] || '';
      let value = '';
      if (kind === 'inlineStr') {
        const parts: string[] = [];
        const textRegex = /<t\b[^>]*>([\s\S]*?)<\/t>/g;
        let part: RegExpExecArray | null;
        while ((part = textRegex.exec(body)) !== null) { parts.push(text(part[1])); }
        value = parts.join('');
      } else {
        const raw = /<v>([\s\S]*?)<\/v>/.exec(body)?.[1] || '';
        value = kind === 's' ? shared[Number(raw)] || '' : text(raw);
      }
      while (values.length < index) { values.push(''); }
      values[index] = value;
    }
    rows.push(values);
  }
  while (rows.length > 0 && rows[rows.length - 1].every((value: string) => value.trim().length === 0)) { rows.pop(); }
  if (rows.length === 0) { throw new Error('XLSX_EMPTY'); }
  return rows;
}

function sheetInfo(files: ZipFile[]): XlsxSheetInfo[] {
  const workbook = files.find((item: ZipFile) => item.path === 'xl/workbook.xml');
  const rels = files.find((item: ZipFile) => item.path === 'xl/_rels/workbook.xml.rels');
  if (workbook === undefined || rels === undefined) { return []; }
  const relMap: Map<string, string> = new Map();
  const relXml = decode(rels.data);
  const relRegex = /<Relationship\b([^>]*)\/?>/g;
  let rel: RegExpExecArray | null;
  while ((rel = relRegex.exec(relXml)) !== null) {
    const id = /\bId="([^"]+)"/.exec(rel[1])?.[1] || '';
    let target = /\bTarget="([^"]+)"/.exec(rel[1])?.[1] || '';
    if (id.length === 0 || target.length === 0 || !target.includes('worksheets/')) { continue; }
    if (!target.startsWith('/')) { target = 'xl/' + target; } else { target = target.substring(1); }
    relMap.set(id, target.replace('/worksheets/', '/worksheets/'));
  }
  const values: XlsxSheetInfo[] = [];
  const workbookXml = decode(workbook.data);
  const sheetRegex = /<sheet\b([^>]*)\/?>/g;
  let sheet: RegExpExecArray | null;
  while ((sheet = sheetRegex.exec(workbookXml)) !== null) {
    const name = /\bname="([^"]+)"/.exec(sheet[1])?.[1] || '';
    const id = /\br:id="([^"]+)"/.exec(sheet[1])?.[1] || '';
    const path = relMap.get(id) || '';
    if (name.length > 0 && path.length > 0) { values.push({ name: text(name), path: path }); }
  }
  return values;
}

export async function listXlsxSheets(uri: string): Promise<XlsxSheetInfo[]> {
  const files = BackupZip.decodeOffice(await BackupFiles.read(uri));
  return sheetInfo(files);
}

export async function readXlsxTable(uri: string, sheetPath: string = ''): Promise<CsvTable> {
  const files = BackupZip.decodeOffice(await BackupFiles.read(uri));
  const rows = worksheet(files, sharedStrings(files), sheetPath);
  return { headers: rows[0].map((value: string) => value.trim()), rows: rows.slice(1), delimiter: ',' };
}
