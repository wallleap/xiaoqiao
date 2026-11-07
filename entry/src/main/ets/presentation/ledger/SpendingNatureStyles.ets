export function spendingNatureBackground(key: string): Resource {
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

export function spendingNatureText(key: string): Resource {
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
