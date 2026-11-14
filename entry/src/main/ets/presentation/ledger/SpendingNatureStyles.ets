import { isCustomNatureColor } from '../../domain/model/SpendingNature';

export function spendingNatureBackground(key: string): ResourceColor {
  if (isCustomNatureColor(key)) { return '#22' + key.substring(1).toUpperCase(); }
  switch (key) {
    case 'survival': return $r('app.color.xq_nature_survival_bg');
    case 'experience': return $r('app.color.xq_nature_experience_bg');
    case 'growth': return $r('app.color.xq_nature_growth_bg');
    case 'emergency': return $r('app.color.xq_nature_emergency_bg');
    case 'calm': return $r('app.color.xq_nature_calm_bg');
    case 'creative': return $r('app.color.xq_nature_creative_bg');
    case 'social': return $r('app.color.xq_nature_social_bg');
    default: return $r('app.color.xq_nature_neutral_bg');
  }
}

export function spendingNatureText(key: string): ResourceColor {
  if (isCustomNatureColor(key)) {
    const rgb = parseInt(key.substring(1), 16);
    const red = (rgb >>> 16) & 255; const green = (rgb >>> 8) & 255; const blue = rgb & 255;
    // Keep very light selections readable on their pale chip background.
    if (red * 0.299 + green * 0.587 + blue * 0.114 > 160) {
      return '#' + [red, green, blue].map((value: number) => Math.round(value * 0.55).toString(16).padStart(2, '0')).join('');
    }
    return key;
  }
  switch (key) {
    case 'survival': return $r('app.color.xq_nature_survival_text');
    case 'experience': return $r('app.color.xq_nature_experience_text');
    case 'growth': return $r('app.color.xq_nature_growth_text');
    case 'emergency': return $r('app.color.xq_nature_emergency_text');
    case 'calm': return $r('app.color.xq_nature_calm_text');
    case 'creative': return $r('app.color.xq_nature_creative_text');
    case 'social': return $r('app.color.xq_nature_social_text');
    default: return $r('app.color.xq_nature_neutral_text');
  }
}
