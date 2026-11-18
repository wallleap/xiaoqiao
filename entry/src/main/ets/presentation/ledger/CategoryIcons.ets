import { COLORFUL_CATEGORY_ICONS, ColorfulCategoryIcon, LEGACY_COLORFUL_ICON_KEYS } from './ColorfulCategoryIcons';

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

/** Resolve legacy semantic keys without rewriting existing category records. */
function semanticCategoryIconKey(key: string): string {
  switch (key) {
    case 'salary': return 'colorful_icon_0280';
    case 'bonus': return 'colorful_icon_0088';
    case 'sidejob': return 'colorful_icon_0161';
    case 'investment': return 'colorful_icon_0126';
    case 'food': return 'colorful_icon_0287';
    case 'transport': return 'colorful_icon_0224';
    case 'clothes': return 'colorful_icon_0207';
    case 'car': return 'colorful_icon_0222';
    case 'fun': return 'colorful_icon_0235';
    case 'care': return 'colorful_icon_0071';
    case 'home': return 'colorful_icon_0161';
    case 'study': return 'colorful_icon_0280';
    case 'health': return 'colorful_icon_0073';
    case 'gift': return 'colorful_icon_0088';
    case 'charity': return 'colorful_icon_0104';
    case 'insurance': return 'colorful_icon_0126';
    case 'other': return 'colorful_icon_0205';
    default: return key;
  }
}

export function categoryIconKey(key: string, income: boolean = false): string {
  if (income && key === 'other') { return 'icon00373'; }
  const legacyKey = semanticCategoryIconKey(key);
  return LEGACY_COLORFUL_ICON_KEYS[legacyKey] || legacyKey;
}

export function categoryIcon(key: string, income: boolean = false): Resource {
  const resolvedKey = categoryIconKey(key, income);
  return COLORFUL_CATEGORY_ICONS.find((option: ColorfulCategoryIcon) => option.key === resolvedKey)?.resource ||
    $r('app.media.colorful_icon00204');
}
