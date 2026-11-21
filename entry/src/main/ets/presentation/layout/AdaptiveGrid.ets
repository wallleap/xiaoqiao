// Width is the measured content area in vp, after the surrounding card/sheet padding.
// Grow tiles with the effective fp/vp ratio instead of squeezing enlarged labels.
export function adaptiveColumns(width: number, minimumWidth: number, gap: number,
  maximumColumns: number, fontScale: number): number {
  const scale = Number.isFinite(fontScale) ? Math.max(1, fontScale) : 1;
  if (!Number.isFinite(width) || width <= 0) { return 1; }
  return Math.max(1, Math.min(maximumColumns, Math.floor((width + gap + 0.000001) / (minimumWidth * scale + gap))));
}

export function gridColumnsTemplate(columns: number): string {
  const tracks: string[] = [];
  for (let index = 0; index < columns; index++) { tracks.push('1fr'); }
  return tracks.join(' ');
}
