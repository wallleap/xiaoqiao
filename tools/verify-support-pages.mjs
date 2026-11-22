/** Host-only production logic tests. Never launches mail, accesses clipboard, or touches device data. */
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
function execute(source, globals = {}) {
  const context = { exports: {}, ...globals };
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  vm.runInNewContext(code, context);
  return context.exports;
}
const model = execute(fs.readFileSync('entry/src/main/ets/presentation/support/SupportContent.ets', 'utf8'));
assert.equal(model.FEEDBACK_EMAIL, 'vonnelu@163.com');
assert.equal(model.supportTitle('help'), '帮助中心');
assert.equal(model.searchHelp('  CNY ').length, 1);
assert.equal(model.searchHelp('不存在的关键词').length, 0);
assert.equal(model.searchHelp(' ').length, model.HELP_QUESTIONS.length);
const draft = { title: '问题 & 建议\r\n副本', detail: '中文\n金额=1&bcc=bad@example.com?#', contact: '', version: '1.2 (12)' };
const uri = new URL(model.feedbackMailUri(draft));
assert.equal(uri.pathname, model.FEEDBACK_EMAIL);
assert.equal(uri.searchParams.size, 2);
assert.equal(uri.searchParams.get('subject'), '[小巧记账] 问题 & 建议 副本');
assert(uri.searchParams.get('body').includes(draft.detail));
assert(!uri.searchParams.get('body').includes('联系方式：'));
assert(model.feedbackText({ ...draft, contact: 'test@example.com' }).includes('联系方式：test@example.com'));
for (const invalid of [{ title: ' ' }, { detail: '' }, { title: 'a'.repeat(81) }, { detail: 'a'.repeat(2001) }, { contact: 'a'.repeat(101) }]) {
  assert.throws(() => model.feedbackMailUri({ ...draft, ...invalid }));
}
const source = fs.readFileSync('entry/src/main/ets/components/SupportPage.ets', 'utf8');
const methods = source.slice(source.indexOf('  aboutToAppear()'), source.indexOf('  private statusBarColor()'));
let starts = [], copied = [], dialogIndex = 0, dialogFails = false, failMail = false, failCopy = false, failVersion = false;
const { Page } = execute('class Page {' + methods + '}\nexports.Page=Page;', { ...model, $r: value => value,
  bundleManager: { BundleFlag: { GET_BUNDLE_INFO_DEFAULT: 0 }, getBundleInfoForSelf: async () => { if (failVersion) throw Error(); return { versionName: '2.3', versionCode: 123 }; } },
  pasteboard: { MIMETYPE_TEXT_PLAIN: 'text/plain', createData: (type, text) => ({ type, text }), getSystemPasteboard: () => ({ setData: async data => { if (failCopy) throw Error(); copied.push(data); } }) }
});
let closed = 0;
const page = new Page();
Object.assign(page, { active: true, kind: 'feedback', titleText: draft.title, detailText: draft.detail, contactText: '', version: draft.version,
  working: false, confirming: false, versionLoading: false, expanded: [], onClose: () => closed++, onRegisterBack: handler => { page.back = handler; },
  getUIContext: () => ({ getFocusController: () => ({ clearFocus() {} }),
    getHostContext: () => ({ startAbility: async want => { starts.push(want); if (failMail) throw Error(); } }),
    getPromptAction: () => ({ showDialog: async () => { if (dialogFails) throw Error(); return { index: dialogIndex }; } }) }) });
await page.openMail();
assert.equal(starts.length, 1); assert.equal(starts[0].uri, model.feedbackMailUri(draft));
assert(page.message.includes('确认发送')); assert.equal(page.working, false);
assert.equal(page.detailText, draft.detail);
failMail = true; await page.openMail(); assert(page.error); assert(page.message.includes(model.FEEDBACK_EMAIL)); assert.equal(page.detailText, draft.detail);
await page.copyFeedback(); assert(copied[0].text.includes('收件人：' + model.FEEDBACK_EMAIL)); assert.equal(page.working, false);
failCopy = true; await page.copyFeedback(); assert(page.error); assert.equal(page.detailText, draft.detail);
page.titleText = ''; await page.openMail(); assert(page.titleError); assert.equal(starts.length, 2);
page.titleText = draft.title;
await page.closePage(); assert.equal(closed, 0); assert.equal(page.confirming, false);
dialogFails = true; await page.closePage(); assert.equal(closed, 0); dialogFails = false;
dialogIndex = 1; await page.closePage(); assert.equal(closed, 1);
page.working = true; await page.closePage(); await page.openMail(); assert.equal(closed, 1); assert.equal(starts.length, 2); page.working = false;
page.kind = 'help'; await page.closePage(); assert.equal(closed, 2);
await page.loadVersion(); assert.equal(page.version, '2.3 (123)'); assert.equal(page.versionLoading, false);
failVersion = true; await page.loadVersion(); assert.equal(page.version, '暂不可用'); assert(page.versionError); assert.equal(page.versionLoading, false);
page.aboutToAppear(); assert.equal(page.back(), true); page.aboutToDisappear(); assert.equal(page.back(), false);
console.log('PASS FAQ search; encoded mail recipient/subject/body; validation; mail and copy failures preserve draft; discard/cancel/back; version success/failure.');
