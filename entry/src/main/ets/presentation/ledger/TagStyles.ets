export function tagTextColor(key: string): ResourceColor {
  switch (key) {
    case 'brand': return $r('app.color.xq_font_emphasize');
    case 'income': return $r('app.color.xq_app_income');
    case 'warning': return $r('app.color.xq_warning');
    case 'alert': return $r('app.color.xq_alert');
    default: return $r('app.color.xq_font_primary');
  }
}

export function tagBackground(key: string): ResourceColor {
  switch (key) {
    case 'brand': return $r('app.color.xq_comp_emphasize_tertiary');
    case 'income': return $r('app.color.xq_app_confirm_background');
    case 'warning': return $r('app.color.xq_app_warning_background');
    case 'alert': return $r('app.color.xq_app_alert_background');
    default: return $r('app.color.xq_app_surface_page');
  }
}
