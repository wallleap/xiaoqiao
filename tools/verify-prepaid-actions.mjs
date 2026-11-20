import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const source = fs.readFileSync(new URL('../entry/src/main/ets/components/PrepaidPage.ets', import.meta.url), 'utf8');
const prefix = source.slice(source.indexOf('export struct'), source.indexOf('  @Builder')).replace('export struct', 'class') + '\n}';
const tree = ts.createSourceFile('page.ts', prefix, ts.ScriptTarget.Latest, true);
const cls = tree.statements.find(ts.isClassDeclaration);
function method(name) {
  const member = cls.members.find(x => ts.isMethodDeclaration(x) && x.name.getText(tree) === name);
  assert(member, name);
  return member.getText(tree);
}
const code = ts.transpileModule('class Actions {' + method('openInitialAction') + method('openForm') + '}\nexports.Actions=Actions;', { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
const context = { exports: {}, util: { generateRandomUUID: () => 'new-event' }, prepaidToday: () => '2026-11-20' };
vm.runInNewContext(code, context);
function fixture(remaining = '100') {
  const page = new context.exports.Actions();
  Object.assign(page, { initialProjectId: 'p', initialAction: 'consume', active: true, loading: false, working: false, error: '', accounts: [], categories: [], incomeCategories: [], spendingNatures: [], detail: { project: { id: 'p', remainingMinor: remaining, revision: 7, currencyId: 'CNY' }, events: [] }, showForm: false, resetRates() {}, onInitialActionHandled() { this.handled = true; }, async reload() { assert(this.handled); } });
  return page;
}
for (const action of ['consume', 'refund', 'fund', 'edit']) {
  const page = fixture(); page.initialAction = action;
  await page.openInitialAction(); assert.equal(page.action, action); assert.equal(page.formRevision, 7); assert.equal(page.showForm, true);
}
for (const action of ['consume', 'refund']) {
  const page = fixture('0'); page.initialAction = action;
  await page.openInitialAction(); assert.equal(page.showForm, false); assert(page.message.includes('余额'));
}
for (const failure of ['read-error', 'closed', 'wrong-project']) {
  const page = fixture(); page.reload = async () => { if (failure === 'read-error') page.error = 'failed'; if (failure === 'closed') page.active = false; if (failure === 'wrong-project') page.detail.project.id = 'other'; };
  await page.openInitialAction(); assert.equal(page.showForm, false);
}
for (const action of ['view', '', 'create', 'invalid']) { const page = fixture(); page.initialAction = action; await page.openInitialAction(); assert.equal(page.showForm, false); }
console.log('PASS 预付款入口：最新版本表单、核销退款零余额拦截、读取失败/页面关闭/项目不符拦截、查看流水及一次性操作回调');
