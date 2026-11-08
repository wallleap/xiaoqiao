export interface ImageCompressionPreset {
  key: string;
  label: string;
  maxEdge: number;
  quality: number;
}

export const IMAGE_COMPRESSION_PRESETS: ImageCompressionPreset[] = [
  { key: 'original', label: '原图', maxEdge: 0, quality: 100 },
  { key: 'sharp', label: '清晰 · 长边 2560', maxEdge: 2560, quality: 90 },
  { key: 'standard', label: '标准 · 长边 2048', maxEdge: 2048, quality: 82 },
  { key: 'compact', label: '省空间 · 长边 1600', maxEdge: 1600, quality: 70 }
];

export function imageCompressionPreset(key: string): ImageCompressionPreset {
  return IMAGE_COMPRESSION_PRESETS.find((preset: ImageCompressionPreset) => preset.key === key) ||
    IMAGE_COMPRESSION_PRESETS[2];
}
