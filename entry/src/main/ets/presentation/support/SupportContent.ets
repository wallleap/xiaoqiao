export type SupportPageKind = 'help' | 'feedback' | 'about';
export interface HelpQuestion { id: string; question: string; answer: string; }
export interface FeedbackDraft { title: string; detail: string; contact: string; version: string; }
export const FEEDBACK_EMAIL: string = 'vonnelu@163.com';

export const HELP_QUESTIONS: HelpQuestion[] = [
  { id: 'local', question: '不登录可以正常记账吗？', answer: '可以。日常记账、账本、账户、预算和本地备份可在未登录时使用。华为账号用于连接云备份，不会替代本机账本。' },
  { id: 'books', question: '怎样创建或切换账本？', answer: '在“我的 → 账本管理”创建和管理账本；点击账目页顶部的账本名称可切换账本。已归档账本可在账本管理中展开查看和恢复使用。' },
  { id: 'period', question: '账本币种和月起始日怎么设置？', answer: '在账本管理中新建或编辑账本。默认币种为 CNY、月起始日为每月 1 日。已有流水、预算或预付款后，账本币种会锁定。月份按周期开始的月份命名，不足起始日的月份取月末。' },
  { id: 'rates', question: '如何设置外币和手动汇率？', answer: '进入“我的 → 汇率转换”，可管理币种并按当前基准设置手动汇率。手动值优先，不被在线报价覆盖；新账目按当前规则折算，已保存账目的历史折算金额保持原样。' },
  { id: 'prepaid', question: '预付款为什么没有立即计入支出？', answer: '预付款付款先保留为预付余额，核销时再计入支出；是否计入预算和净资产取决于对应设置。剩余款可在预付款项目中退款。撤销最后一条有效流水时会提示同时删除空项目。' },
  { id: 'backup', question: '怎样备份或恢复账本？', answer: '进入“我的 → 备份与恢复”，选择本地备份、WebDAV 或华为云备份。恢复前请核对预览内容；恢复会替换当前数据，不会自动合并多个设备的账目。' },
  { id: 'import', question: '怎样导入或导出账目？', answer: '进入“我的 → 导入与导出”，按页面提示选择文件、检查映射和导入预览，确认后再导入。导出可用于保存或整理账目，不会修改原账目。' },
  { id: 'colors', question: '怎样修改深色模式和收支颜色？', answer: '在“我的 → 设置 → 外观”调整深色模式和收支转账颜色。支出和收入的红、绿色互斥，黑色可共用；颜色会持久保存，并随完整备份恢复。' }
];

export function supportTitle(kind: SupportPageKind): string {
  return kind === 'help' ? '帮助中心' : kind === 'feedback' ? '意见反馈' : '关于我们';
}
export function searchHelp(query: string): HelpQuestion[] {
  const text = query.trim().toLowerCase();
  return HELP_QUESTIONS.filter((item: HelpQuestion) => !text || (item.question + item.answer).toLowerCase().includes(text));
}
export function feedbackText(draft: FeedbackDraft): string {
  const title = draft.title.trim().replace(/[\r\n]+/g,' ');
  const detail = draft.detail.trim();
  const contact = draft.contact.trim();
  if (!title || !detail) { throw new Error('FEEDBACK_REQUIRED'); }
  if (title.length > 80 || detail.length > 2000 || contact.length > 100) { throw new Error('FEEDBACK_TOO_LONG'); }
  return '小巧记账 · 意见反馈\n\n主题：' + title + '\n\n反馈内容：\n' + detail +
    (contact ? '\n\n联系方式：' + contact : '') + '\n\n应用版本：' + draft.version;
}
export function feedbackMailUri(draft: FeedbackDraft): string {
  const body = feedbackText(draft);
  const subject = '[小巧记账] ' + draft.title.trim().replace(/[\r\n]+/g,' ');
  return 'mailto:' + FEEDBACK_EMAIL + '?subject=' + encodeURIComponent(subject) + '&body=' + encodeURIComponent(body);
}
