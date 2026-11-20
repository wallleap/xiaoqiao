/** A missing result must never look like an already computed zero. */
export function summaryValue(value: string, hasValue: boolean, loading: boolean, error: string): string {
  return hasValue ? value : error.length > 0 && !loading ? '读取失败' : '计算中…';
}
export function summaryStatus(hasValue: boolean, loading: boolean, error: string): string {
  if (!hasValue) { return ''; }
  return loading ? '更新中' : error.length > 0 ? '更新失败' : '';
}
