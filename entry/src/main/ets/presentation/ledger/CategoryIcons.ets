/** Stable semantic keys stored in SQLite; resource handles stay in the presentation layer. */
export interface CategoryIconOption {
  key: string;
  label: string;
}

export const CATEGORY_ICON_OPTIONS: CategoryIconOption[] = [
  { key: 'food', label: '餐饮' },
  { key: 'transport', label: '交通' },
  { key: 'clothes', label: '服饰' },
  { key: 'car', label: '汽车' },
  { key: 'fun', label: '娱乐' },
  { key: 'care', label: '个护' },
  { key: 'home', label: '生活' },
  { key: 'study', label: '学习' },
  { key: 'health', label: '健康' },
  { key: 'gift', label: '礼物' },
  { key: 'charity', label: '公益' },
  { key: 'insurance', label: '保险' },
  { key: 'salary', label: '工资' },
  { key: 'bonus', label: '奖金' },
  { key: 'sidejob', label: '兼职' },
  { key: 'investment', label: '理财' },
  { key: 'other', label: '其他' }
];

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
