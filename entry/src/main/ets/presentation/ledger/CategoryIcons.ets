/** Stable semantic keys stored in SQLite; resource handles stay in the presentation layer. */
export function categoryIcon(key: string): Resource {
  switch (key) {
    case 'salary': return $r('app.media.colorful_icon_0280');
    case 'bonus': return $r('app.media.colorful_icon_0088');
    case 'sidejob': return $r('app.media.colorful_icon_0161');
    case 'investment': return $r('app.media.colorful_icon_0126');
    case 'food': return $r('app.media.colorful_icon_0287');
    case 'transport': return $r('app.media.colorful_icon_0224');
    case 'clothes': return $r('app.media.colorful_icon_0207');
    case 'car': return $r('app.media.colorful_icon_0222');
    case 'fun': return $r('app.media.colorful_icon_0235');
    case 'care': return $r('app.media.colorful_icon_0071');
    case 'home': return $r('app.media.colorful_icon_0161');
    case 'study': return $r('app.media.colorful_icon_0280');
    case 'health': return $r('app.media.colorful_icon_0073');
    case 'gift': return $r('app.media.colorful_icon_0088');
    case 'charity': return $r('app.media.colorful_icon_0104');
    case 'insurance': return $r('app.media.colorful_icon_0126');
    default: return $r('app.media.colorful_icon_0205');
  }
}
