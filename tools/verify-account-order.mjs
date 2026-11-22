/** Production account-order SQL against isolated in-memory SQLite; never touches a device database. */
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import readline from 'node:readline';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
function methods(file, names) {
  const source = fs.readFileSync(file, 'utf8').replace(/(?:export )?struct /, 'class ');
  const tree = ts.createSourceFile('source.ts', source, ts.ScriptTarget.Latest, true);
  const cls = tree.statements.find(ts.isClassDeclaration);
  return names.map(name => cls.members.find(m => ts.isMethodDeclaration(m) && m.name.getText(tree) === name).getText(tree)).join('\n');
}
function execute(source, globals = {}) {
  const ctx = { exports: {}, ...globals };
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
  return ctx.exports;
}
const worker = spawn('python3', ['-u', '-c', `
import sqlite3,json,sys
c=sqlite3.connect(':memory:',isolation_level=None)
for line in sys.stdin:
 try:
  p=json.loads(line);r=c.execute(p['sql'],p.get('args',[]));v=r.fetchall() if p['op']=='query' else r.rowcount
  print(json.dumps({'value':v}),flush=True)
 except Exception as e:print(json.dumps({'error':str(e)}),flush=True)
`]);
const pending = [];
readline.createInterface({ input: worker.stdout }).on('line', line => { const p = pending.shift(), r = JSON.parse(line); r.error ? p.reject(Error(r.error)) : p.resolve(r.value); });
const sql = (text, args = [], query = false) => new Promise((resolve, reject) => { pending.push({ resolve, reject }); worker.stdin.write(JSON.stringify({ sql: text, args, op: query ? 'query' : 'exec' }) + '\n'); });
class Predicates {
  constructor(table) { this.table = table; this.where = []; this.args = []; }
  equalTo(k, v) { this.where.push(k + '=?'); this.args.push(v); return this; }
  isNull(k) { this.where.push(k + ' IS NULL'); return this; }
}
let failUpdate = 0, updates = 0;
const db = {
  async querySql(text, args = []) { const rows = await sql(text, args, true); let index = -1; return { goToNextRow: () => ++index < rows.length, getString: i => String(rows[index][i]), getLong: i => Number(rows[index][i]), close() {} }; },
  async update(values, p) { if (++updates === failUpdate) throw Error('IO_ERROR'); const keys = Object.keys(values); return sql(`UPDATE ${p.table} SET ${keys.map(k => k + '=?')} WHERE ${p.where.join(' AND ')}`, [...Object.values(values), ...p.args]); }
};
let tail = Promise.resolve();
const session = { write(fn) { const work = tail.then(async () => { await sql('BEGIN'); try { const result = await fn(db); await sql('COMMIT'); return result; } catch (e) { await sql('ROLLBACK'); throw e; } }); tail = work.catch(() => {}); return work; } };
try {
  await sql('CREATE TABLE accounts(id TEXT PRIMARY KEY,revision INTEGER,sort_order INTEGER,updated_at_ms INTEGER,archived_at_ms INTEGER,deleted_at_ms INTEGER,balance_minor INTEGER)');
  for (const [id, archived, deleted, balance] of [['a', null, null, 123], ['b', null, null, -456], ['c', null, null, 789], ['archived', 9, null, 99], ['deleted', null, 9, 88]]) {
    await sql('INSERT INTO accounts VALUES(?,1,7,1,?,?,?)', [id, archived, deleted, balance]);
  }
  const { Repo } = execute('class Repo {' + methods('entry/src/main/ets/data/rdb/RdbAccountRepository.ets', ['reorder']) + '}exports.Repo=Repo;', { relationalStore: { RdbPredicates: Predicates } });
  const repo = new Repo(); repo.session = session;
  const initial = await sql('SELECT * FROM accounts ORDER BY id', [], true);
  const order = ['c', 'a', 'b'].map(id => ({ id, revision: 1 }));
  for (const invalid of [[], [order[0], order[0]], [{ id: 'a', revision: 0 }], [{ id: ' ', revision: 1 }], [{ id: 'a', revision: Number.MAX_SAFE_INTEGER }], [{ id: 'a', revision: 1.1 }]]) await assert.rejects(repo.reorder(invalid), /INVALID_ACCOUNT_ORDER/);
  for (const invalid of [order.slice(1), [...order, { id: 'archived', revision: 1 }], order.map(x => ({ ...x, revision: 2 })), order.map(x => x.id === 'c' ? { id: 'missing', revision: 1 } : x)]) await assert.rejects(repo.reorder(invalid), /ACCOUNT_CHANGED/);
  assert.deepEqual(await sql('SELECT * FROM accounts ORDER BY id', [], true), initial);
  failUpdate = 2; updates = 0; await assert.rejects(repo.reorder(order), /IO_ERROR/);
  assert.deepEqual(await sql('SELECT * FROM accounts ORDER BY id', [], true), initial, 'partial write must roll back');
  failUpdate = 0; updates = 0; await repo.reorder(order);
  assert.deepEqual(await sql('SELECT id,sort_order,revision FROM accounts WHERE archived_at_ms IS NULL AND deleted_at_ms IS NULL ORDER BY sort_order,id', [], true), [['c',0,2],['a',1,2],['b',2,2]]);
  assert.deepEqual(await sql("SELECT * FROM accounts WHERE id IN ('archived','deleted') ORDER BY id", [], true), initial.filter(r => ['archived','deleted'].includes(r[0])));
  assert.deepEqual(await sql('SELECT id,balance_minor FROM accounts ORDER BY id', [], true), initial.map(r => [r[0],r[6]]));
  await assert.rejects(repo.reorder(order), /ACCOUNT_CHANGED/);
  const current = order.map(x => ({ ...x, revision: 2 }));
  const concurrent = await Promise.allSettled([repo.reorder(current), repo.reorder(current.slice().reverse())]);
  assert.equal(concurrent.filter(x => x.status === 'fulfilled').length, 1);
  assert.equal(concurrent.filter(x => x.status === 'rejected').length, 1);
  console.log('PASS account-order validation/membership/revisions; SQLite rollback on partial failure; balances and archived/deleted rows unchanged; concurrent stale save rejected.');
} finally { worker.stdin.end(); }

const { Page } = execute('class Page {' + methods('entry/src/main/ets/components/AccountSortPage.ets', ['aboutToAppear','aboutToDisappear','dirty','move','closePage','save']) + '}exports.Page=Page;', { $r: x => x });
const page = new Page(); let closed = 0, saved = 0, calls = 0, answer = 0, fail = false;
Object.assign(page, { accounts: [{ id:'a',revision:1,archived:false },{ id:'b',revision:1,archived:false },{ id:'old',revision:1,archived:true }],
  saving:false,dragging:false,confirming:false,onRegisterBack: cb => { page.back = cb; },onClose: () => closed++,onSaved: () => saved++,
  getUIContext: () => ({ getPromptAction: () => ({ showDialog: async () => ({ index:answer }) }) }),
  workspace: { reorderAccounts: async order => { calls++; assert.deepEqual(Array.from(order,x=>x.id),['b','a']); if (fail) throw Error(); } } });
page.aboutToAppear(); assert.equal(page.rows.length,2); assert(!page.dirty());
page.move(-1,1); page.move(0,3); assert(!page.dirty());
page.move(0,1); assert(page.dirty()); assert.equal(page.accounts[0].id,'a');
await page.closePage(); assert.equal(closed,0); assert.equal(page.confirming,false);
answer=1; await page.closePage(); assert.equal(closed,1);
fail=true; await page.save(); assert.equal(saved,0); assert.equal(page.saving,false); assert(page.error); assert(page.dirty());
fail=false; await page.save(); assert.equal(saved,1); assert.equal(calls,2);
page.dragging=true; await page.save(); await page.closePage(); assert.equal(calls,2); assert.equal(closed,1);
page.aboutToDisappear(); assert.equal(page.back(),false);
console.log('PASS production sort-page local move; dirty/discard handling; drag guard; save failure retains order; success callback and system back registration.');

let menuOptions, menuTarget, menuOpened = 0, menuClosed = 0, sorts = 0, menuFails = false;
class Content { constructor(_ui, _builder, params) { this.params = params; this.disposed = 0; } dispose() { this.disposed++; } }
const { MenuPage } = execute('class MenuPage {' + methods('entry/src/main/ets/components/AccountsPage.ets', ['aboutToAppear','aboutToDisappear','closeMore','openMore']) + '}exports.MenuPage=MenuPage;', {
  ComponentContent: Content, wrapBuilder: x => x, accountMoreMenu() {}, Placement: { BottomRight: 1 }
});
const menuPage = new MenuPage();
Object.assign(menuPage, { loading:false,error:'',overview:{accounts:[]},onSort:()=>sorts++,getUIContext:()=>({getPromptAction:()=>({
  openMenu:async(_content,target,options)=>{menuOpened++;menuOptions=options;menuTarget=target;if(menuFails)throw Error();},
  closeMenu:async()=>{menuClosed++;menuOptions.onDidDisappear();}
})}) });
menuPage.aboutToAppear(); await menuPage.openMore();
const first = menuPage.menuContent; assert.equal(menuTarget.id,'accounts-more');
await menuPage.openMore(); assert.equal(menuOpened,1);
first.params.onSort(); await new Promise(resolve=>setImmediate(resolve));
assert.equal(sorts,1);assert.equal(menuClosed,1);assert.equal(first.disposed,1);
await menuPage.openMore();const second=menuPage.menuContent;menuOptions.onDidDisappear();assert.equal(second.disposed,1);assert.equal(menuPage.menuContent,undefined);
menuFails=true;await menuPage.openMore();assert(menuPage.menuError);assert.equal(menuPage.menuContent,undefined);
menuFails=false;await menuPage.openMore();const last=menuPage.menuContent;menuPage.aboutToDisappear();await new Promise(resolve=>setImmediate(resolve));assert.equal(last.disposed,1);
console.log('PASS production anchored menu open/re-entry guard; sort action; dismissal/disposal; open failure and leave-page cleanup.');
const { Root } = execute('class Root {' + methods('entry/src/main/ets/pages/Index.ets', ['onBackPress']) + '}exports.Root=Root;');
const root = new Root(); let handled = 0;
Object.assign(root, { showAccountSort:true, accountSortBackHandler:()=>{handled++;return true;} });
assert.equal(root.onBackPress(),true);assert.equal(handled,1);assert.equal(root.showAccountSort,true);
root.accountSortBackHandler=()=>false;assert.equal(root.onBackPress(),true);assert.equal(root.showAccountSort,false);
console.log('PASS root system back delegates to account sorting and does not exit the app.');

// Regression: MenuItem.startIcon does not inherit text color for monochrome SVGs.
const menuSource = fs.readFileSync('entry/src/main/ets/components/AccountsPage.ets','utf8');
const menuBuilder = menuSource.slice(menuSource.indexOf('function accountMoreMenu('),menuSource.indexOf('@Component'));
assert(!menuBuilder.includes('startIcon:'));
assert(menuBuilder.includes(".fillColor($r('app.color.xq_icon_primary'))"));
assert(menuBuilder.includes(".fontColor($r('app.color.xq_font_primary'))"));
console.log('PASS sort menu monochrome icon explicitly uses adaptive theme color.');
