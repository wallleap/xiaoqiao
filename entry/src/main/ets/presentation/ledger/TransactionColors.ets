export type TransactionColorKind = 'expense' | 'income' | 'transfer';
export interface TransactionColorSelection { version: number; expense: string; income: string; transfer: string; }
export interface TransactionColorOption { id: string; name: string; }
export const DEFAULT_TRANSACTION_COLORS: string = '{"version":1,"expense":"orange","income":"green","transfer":"black"}';
export const TRANSACTION_COLOR_STORAGE: string = 'transactionColorSelection';

/** Business colors are separate from brand/action colors. Black follows the readable theme foreground. */
export class TransactionColors {
  static options(kind: TransactionColorKind): TransactionColorOption[] {
    if (kind === 'transfer') { return [{ id: 'blue', name: '蓝色' }, { id: 'black', name: '黑色' }]; }
    if (kind === 'income') { return [{ id: 'red', name: '红色' }, { id: 'green', name: '绿色' }, { id: 'black', name: '黑色' }]; }
    return [{ id: 'red', name: '红色' }, { id: 'orange', name: '橙色' }, { id: 'green', name: '绿色' }, { id: 'black', name: '黑色' }];
  }
  static parse(json: string): TransactionColorSelection {
    const value = JSON.parse(json) as TransactionColorSelection;
    if (value === null || value.version !== 1 ||
      !TransactionColors.options('expense').some((item: TransactionColorOption) => item.id === value.expense) ||
      !TransactionColors.options('income').some((item: TransactionColorOption) => item.id === value.income) ||
      !TransactionColors.options('transfer').some((item: TransactionColorOption) => item.id === value.transfer) ||
      (value.expense === value.income && value.expense !== 'black')) { throw new Error('TRANSACTION_COLORS_INVALID'); }
    return { version: 1, expense: value.expense, income: value.income, transfer: value.transfer };
  }
  static selected(kind: TransactionColorKind, json: string): string {
    const value = TransactionColors.parse(json);
    return kind === 'expense' ? value.expense : kind === 'income' ? value.income : value.transfer;
  }
  static disabled(kind: TransactionColorKind, id: string, json: string): boolean {
    if (kind === 'transfer' || id === 'black' || id === 'orange') { return false; }
    const value = TransactionColors.parse(json);
    return (kind === 'expense' ? value.income : value.expense) === id;
  }
  static change(json: string, kind: TransactionColorKind, id: string): string {
    const value = TransactionColors.parse(json);
    if (kind === 'expense') { value.expense = id; }
    else if (kind === 'income') { value.income = id; }
    else { value.transfer = id; }
    return JSON.stringify(TransactionColors.parse(JSON.stringify(value)));
  }
  static swatch(id: string): Resource {
    switch (id) {
      case 'red': return $r('app.color.xq_transaction_red');
      case 'orange': return $r('app.color.xq_transaction_orange');
      case 'green': return $r('app.color.xq_transaction_green');
      case 'blue': return $r('app.color.xq_transaction_blue');
      default: return $r('app.color.xq_font_primary');
    }
  }
  static color(kind: TransactionColorKind, json: string): Resource { return TransactionColors.swatch(TransactionColors.selected(kind, json)); }
  /** The budget summary has a dark surface even in light mode. */
  static onDark(kind: TransactionColorKind, json: string): Resource {
    switch (TransactionColors.selected(kind,json)) {
      case 'red': return $r('app.color.xq_transaction_red_on_dark');
      case 'orange': return $r('app.color.xq_transaction_orange_on_dark');
      case 'green': return $r('app.color.xq_transaction_green_on_dark');
      case 'blue': return $r('app.color.xq_transaction_blue_on_dark');
      default: return $r('app.color.xq_transaction_black_on_dark');
    }
  }
  static shade(color: number, surface: number, index: number): string {
    const weight = Math.min(0.60, Math.max(0,index) * 0.12);
    let hex = '#';
    for (const shift of [16,8,0]) {
      const channel = Math.round(((color >>> shift) & 255) * (1-weight) + ((surface >>> shift) & 255) * weight);
      hex += channel.toString(16).padStart(2,'0');
    }
    return hex.toUpperCase();
  }
  static publish(json: string): void {
    AppStorage.setOrCreate<string>(TRANSACTION_COLOR_STORAGE, JSON.stringify(TransactionColors.parse(json)));
  }
}
