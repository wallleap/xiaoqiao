/** Production cycle, currency, repository and snapshot checks; temporary host SQLite only. */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import readline from 'node:readline';
import { createRequire } from 'node:module';
import crypto from 'node:crypto';
const require = createRequire(import.meta.url);
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const root = path.resolve(import.meta.dirname, '..'), base = root + '/entry/src/main/ets';
const cache = new Map();
function load(file) {
 file = path.resolve(file); if (cache.has(file)) return cache.get(file).exports;
 const module = { exports: {} }; cache.set(file, module);
 const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
 vm.runInThisContext(`(function(require,module,exports){${code}\n})`,{filename:file})(id=>id.startsWith('.')?load(path.resolve(path.dirname(file),id+'.ets')):id==='@kit.ArkTS'?{util:{generateRandomUUID:()=>crypto.randomUUID()}}:id==='@kit.ArkData'?{relationalStore:{RdbPredicates:Predicates}}:{},module,module.exports);
 return module.exports;
}
const generated = load(base+'/data/rdb/BookSettingsSchema.ets');
assert.equal(generated.BOOK_SETTINGS_SCHEMA_SHA256, crypto.createHash('sha256').update(fs.readFileSync(root+'/docs/database/schema-v11-book-settings.sql')).digest('hex'));
const { MonthlyBudget } = load(base+'/domain/model/MonthlyBudget.ets');
const { currentRange, shiftedRange } = load(base+'/presentation/statistics/StatisticsPeriod.ets');
const { currencyUnit } = load(base+'/core/money/Currencies.ets');
const { Money } = load(base+'/core/money/Money.ets');
const { ValidatedLedgerBook } = load(base+'/domain/model/LedgerBook.ets');
assert.equal(new ValidatedLedgerBook({id:'b',name:'Default'}).draft.currencyId,'CNY');
assert.equal(new ValidatedLedgerBook({id:'b',name:'Default'}).draft.monthStartDay,1);
for (const day of [0,32,1.5]) assert.throws(()=>MonthlyBudget.period('2026-11',day));
assert.equal(MonthlyBudget.period('2024-02',31).start,'2024-02-29');
assert.equal(MonthlyBudget.period('2026-02',31).start,'2026-02-28');
assert.equal(MonthlyBudget.monthForDate('2026-11-24',25),'2026-10');
assert.equal(MonthlyBudget.monthForDate('2026-11-25',25),'2026-11');
assert.equal(MonthlyBudget.monthForDate('2026-12-24',25),'2026-11');
for(let day=1;day<=31;day++) for(let month=1;month<=12;month++) {
 const key='2024-'+String(month).padStart(2,'0'), p=MonthlyBudget.period(key,day);
 assert.equal(MonthlyBudget.monthForDate(p.start,day),key);
 const next=month===12?'2025-01':'2024-'+String(month+1).padStart(2,'0');
 assert.equal(p.endExclusive,MonthlyBudget.period(next,day).start);
}
const feb=currentRange('month',new Date(2024,1,29,12),'','',31);
assert.equal(feb.startDate,'2024-02-29');assert.equal(shiftedRange('month',feb,1,31).startDate,'2024-03-31');
const { billCalendarDays,trimBillDecimal,compactBillAmount }=load(base+'/presentation/ledger/BillCalendar.ets');
const cells=billCalendarDays('2026-11',25).filter(c=>c.inMonth);
assert.equal(cells.length,30);assert.equal(cells[0].date,'2026-11-25');assert.equal(cells.at(-1).date,'2026-12-24');
assert.equal(trimBillDecimal('123','JPY'),'123');assert.equal(trimBillDecimal('1234','USD'),'12.34');
assert.equal(compactBillAmount('100000',0,'JPY'),'10万');
// Execute page navigation handlers: management is routed, selection remains a Sheet, and busy saves block return.
const indexSource=fs.readFileSync(base+'/pages/Index.ets','utf8');
const indexTree=ts.createSourceFile('index.ts',indexSource.replace('struct Index','class Index'),ts.ScriptTarget.Latest,true);
const indexClass=indexTree.statements.find(ts.isClassDeclaration);
const indexMethods=['openBookSheet','beginCreateBook','beginEditBook','backFromBookManagement','prepareBookSelectionMaterial','loadBookSelectionMaterial','selectionSheetOptions'].map(name=>indexClass.members.find(m=>ts.isMethodDeclaration(m)&&m.name.getText(indexTree)===name).getText(indexTree)).join('\n');
const indexContext={exports:{},SheetSize:{LARGE:'large'},SheetKeyboardAvoidMode:{TRANSLATE_AND_RESIZE:'resize',TRANSLATE_AND_SCROLL:'scroll'},$r:name=>name};
vm.runInNewContext(ts.transpileModule('class Page{'+indexMethods+'}exports.Page=Page;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,indexContext);
const index=new indexContext.exports.Page();let reloads=0;
Object.assign(index,{workspace:{books:async()=>[]},bookScroller:{scrollTo(){}},getUIContext:()=>({getFocusController:()=>({clearFocus(){}})}),loadLedger:()=>{reloads++;},notify(){}});
await index.openBookSheet(true);assert.equal(index.showBookManagement,true);assert.equal(index.showSelection,false);
index.beginCreateBook();assert.equal(index.bookEditing,true);assert.equal(index.bookCurrencyId,'CNY');
index.bookBusy=true;index.backFromBookManagement();assert.equal(index.bookEditing,true);
index.bookBusy=false;index.backFromBookManagement();assert.equal(index.bookEditing,false);assert.equal(index.showBookManagement,true);
index.backFromBookManagement();assert.equal(index.showBookManagement,false);assert.equal(reloads,1);
await index.openBookSheet(false);assert.equal(index.showSelection,true);assert.equal(index.showBookManagement,false);
index.beginEditBook({id:'b',name:'book',currencyId:'USD',monthStartDay:25});assert.equal(index.showSelection,false);assert.equal(index.showBookManagement,true);assert.equal(index.bookMonthStartDay,25);
const pageBuilder=indexSource.slice(indexSource.indexOf('private bookManagementPage()'),indexSource.indexOf('private bookSheet()'));
assert.match(pageBuilder,/HdsNavigation\(\) \{\s*Scroll\(this.bookScroller\)/);
assert.match(pageBuilder,/enableComponentSafeArea: true/);assert.match(pageBuilder,/bindToScrollable\(\[this.bookScroller\]\)/);
const categoryPage=fs.readFileSync(base+'/components/CategoryManagementPage.ets','utf8');
function titleStyle(text){const start=text.indexOf('style:',text.indexOf('.titleBar(')),begin=text.indexOf('{',start);let level=0;for(let i=begin;i<text.length;i++){if(text[i]==='{')level++;else if(text[i]==='}'&&--level===0)return text.slice(begin,i+1).replace(/\s+/g,'');}throw Error('Missing title style');}
assert.equal(titleStyle(pageBuilder),titleStyle(categoryPage));
for(const api of ['ignoreLayoutSafeArea','expandSafeArea']){const expression=new RegExp('\\.'+api+'\\([^\\n]+');assert.equal(pageBuilder.match(expression)[0].split('.id(')[0],categoryPage.match(expression)[0]);}
assert(!/backgroundStyle|maskExtraHeight|blurRadius|dynamicHideTitleBar/.test(pageBuilder));
assert.match(indexSource,/this.bookManagement \? \$r\('app.color.xq_app_surface_card'\) : \$r\('app.color.xq_exchange_currency_card_background'\)/);
index.selectionKind=0;index.bookEditing=false;index.books=[{id:'b'}];index.bookManagement=false;
let bookOptions=index.selectionSheetOptions();assert.equal(bookOptions.height,340);assert.equal(bookOptions.backgroundColor,'app.color.xq_app_surface_page');
index.materialReady=true;index.filterMaterials={menu:{interactive:true}};index.bookSelectionMaterial={interactive:false};
bookOptions=index.selectionSheetOptions();assert.equal(bookOptions.systemMaterial,index.bookSelectionMaterial);assert.equal(bookOptions.height,340);
index.selectionKind=1;assert.equal(index.selectionSheetOptions().systemMaterial,index.filterMaterials.menu);
const bookSheetBuilder=indexSource.slice(indexSource.indexOf('private bookSheet()'),indexSource.indexOf('private filterSheet()'));
assert.match(bookSheetBuilder,/padding\(\{ left: 16, right: 16, top: 20, bottom: 16 \}\)/);assert.match(bookSheetBuilder,/minHeight: 40/);assert.match(bookSheetBuilder,/right: 48/);
assert.match(bookSheetBuilder,/NestedScrollMode.SELF_ONLY/);
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'xq-book-settings-'));
const fixture=spawnSync('python3',['-c',`
import sys,sqlite3
sys.path.insert(0,sys.argv[1]+'/docs/database')
from verify_book_settings import BookSettingsTests
f=BookSettingsTests();f.setUp();f.migrate()
from verify_account_details import statements
f.db.execute('BEGIN')
for schema in ['BookDeletionSchema.ets','CategoryDeletionSchema.ets']:
 for sql in statements(schema):f.db.execute(sql)
f.db.execute('COMMIT')
f.db.execute("UPDATE books SET base_currency_id='USD',month_start_day=25 WHERE id='b2'")
for i,date in enumerate(['2026-11-24','2026-11-25','2026-12-24','2026-12-25']):
 f.helper.tx(id='t'+str(i),book_id='b2',category_id='b2expense',currency_id='USD',book_currency_id='USD',gross_minor=100*(i+1),paid_minor=100*(i+1),book_minor=100*(i+1),include_in_assets=0,occurred_local_date=date)
 f.db.execute("UPDATE transactions SET posting_state='posted' WHERE id=?",('t'+str(i),))
f.db.execute("INSERT INTO db_meta(key,value) VALUES('active_book_id','b2')")
db=sqlite3.connect(sys.argv[2]);f.db.backup(db);db.close();f.doCleanups()
`,root,temp+'/ledger.db'],{encoding:'utf8'});assert.equal(fixture.status,0,fixture.stderr);
const worker=spawn('python3',['-u','-c',`
import sqlite3,sys,json
w=sqlite3.connect(sys.argv[1],isolation_level=None);w.execute('PRAGMA foreign_keys=ON');w.execute('PRAGMA journal_mode=WAL')
r=sqlite3.connect(sys.argv[1],isolation_level=None)
for line in sys.stdin:
 try:
  c=json.loads(line);cur=(r if c['op']=='query' else w).execute(c['sql'],c.get('args',[]));print(json.dumps({'value':cur.fetchall() if c['op']=='query' else None}),flush=True)
 except Exception as e:print(json.dumps({'error':str(e)}),flush=True)
`,temp+'/ledger.db'],{stdio:['pipe','pipe','inherit']});
const pending=[];readline.createInterface({input:worker.stdout}).on('line',line=>{const next=pending.shift(),r=JSON.parse(line);r.error?next.reject(Error(r.error)):next.resolve(r.value);});
const rpc=c=>new Promise((resolve,reject)=>{pending.push({resolve,reject});worker.stdin.write(JSON.stringify(c)+'\n');});
class Predicates {constructor(table){this.table=table;this.where=[];this.args=[];} equalTo(k,v){this.where.push(k+'=?');this.args.push(v);return this;}isNull(k){this.where.push(k+' IS NULL');return this;}}
const db={
 async querySql(sql,args=[]){const rows=await rpc({op:'query',sql,args});let at=-1;return{rowCount:rows.length,goToFirstRow(){at=0;return rows.length>0;},goToNextRow(){return ++at<rows.length;},getString(i){return rows[at][i]===null?'':String(rows[at][i]);},getLong(i){return Number(rows[at][i]);},isColumnNull(i){return rows[at][i]===null;},close(){}};},
 async executeSql(sql,args=[]){await rpc({op:'exec',sql,args});},
 async insert(table,values){const keys=Object.keys(values).filter(k=>values[k]!==undefined);await this.executeSql(`INSERT INTO ${table}(${keys}) VALUES(${keys.map(()=>'?')})`,keys.map(k=>values[k]));},
 async update(values,pred){const keys=Object.keys(values);await this.executeSql(`UPDATE ${pred.table} SET ${keys.map(k=>k+'=?')} WHERE ${pred.where.join(' AND ')}`,[...Object.values(values),...pred.args]);return(await this.querySql('SELECT changes()')).getLong(0);}
};
// changes() must be read on writer, unlike normal separate query connection.
db.update=async(values,pred)=>{const keys=Object.keys(values);await db.executeSql(`UPDATE ${pred.table} SET ${keys.map(k=>k+'=?')} WHERE ${pred.where.join(' AND ')}`,[...Object.values(values),...pred.args]);return 1;};
const session={read:fn=>fn(db),async write(fn){await db.executeSql('BEGIN');try{const value=await fn(db);await db.executeSql('COMMIT');return value;}catch(e){await db.executeSql('ROLLBACK');throw e;}}};
try {
 const source=fs.readFileSync(base+'/data/rdb/LedgerWorkspace.ets','utf8');
 const tree=ts.createSourceFile('workspace.ts',source,ts.ScriptTarget.Latest,true),cls=tree.statements.find(ts.isClassDeclaration);
 const names=['snapshot','readBookSettings','books','createBook','updateBook','activeBookFromMeta','saveActiveBook','setMonthlyBudget','setBudgetNatureAmount'];
 const methods=names.map(n=>cls.members.find(m=>ts.isMethodDeclaration(m)&&m.name.getText(tree)===n).getText(tree)).join('\n');
 const context={exports:{},currencyUnit,Money,MonthlyBudget,ValidatedLedgerBook,DEFAULT_BOOK_ID:'b1',DEFAULT_MONTHLY_BUDGET_MINOR:'250000',LEDGER_USAGE_ROWS_SQL:load(base+'/data/rdb/LedgerUsageQuery.ets').LEDGER_USAGE_ROWS_SQL,
  RdbFxSnapshots:{read:async()=>undefined},prepaidEntryContext:()=>undefined,util:{generateRandomUUID:()=>crypto.randomUUID()},relationalStore:{RdbPredicates:Predicates}};
 vm.runInNewContext(ts.transpileModule('class LedgerWorkspace {static ACTIVE_BOOK_KEY="active_book_id";'+methods+'}\nexports.Workspace=LedgerWorkspace;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,context);
 const workspace=new context.exports.Workspace();workspace.session=session;workspace.activeBookId='b2';workspace.currency=currencyUnit('CNY');
 let result=await workspace.snapshot('2026-11');
 assert.equal(result.currencyId,'USD');assert.equal(result.periodStart,'2026-11-25');assert.equal(result.periodEndExclusive,'2026-12-25');
 assert.equal(result.entries.length,2);assert.equal(result.expenseMinor,'500');assert.equal(result.budgetUsedMinor,'500');assert.equal(result.budgetTotalMinor,'250000');
 const {RdbStatisticsRepository}=load(base+'/data/rdb/RdbStatisticsRepository.ets');const statistics=new RdbStatisticsRepository(db);
 const totals=await statistics.snapshot('b2',result.periodStart,result.periodEndExclusive,'expense','day',25);assert.equal(totals.totalMinor,'500');
 const annual=await statistics.snapshot('b2','2026-01-25','2027-01-25','expense','month',25);assert.equal(annual.buckets.length,12);assert.equal(annual.buckets.find(x=>x.key==='2026-11').amountMinor,'500');
 await workspace.setMonthlyBudget('2026-11','42.50');result=await workspace.snapshot('2026-11');assert.equal(result.budgetTotalMinor,'4250');
 await db.executeSql("UPDATE books SET month_start_day=1 WHERE id='b2'");result=await workspace.snapshot('2026-11');assert.equal(result.entries.length,2);assert.equal(result.expenseMinor,'300');assert.equal(result.budgetTotalMinor,'250000');
 assert.equal((await db.querySql("SELECT total_minor FROM budgets WHERE period_start_date='2026-11-25'")).rowCount,1);
 await workspace.createBook('日元','jpy',{coverPalette:'butter',coverIcon:'lucide_notebook_text1',currencyId:'JPY',monthStartDay:31});
 result=await workspace.snapshot('2024-02');assert.equal(result.currencyId,'JPY');assert.equal(result.periodStart,'2024-02-29');assert.equal(result.budgetTotalMinor,'2500');
 await workspace.updateBook('jpy','日元改名',1,{coverPalette:'butter',coverIcon:'lucide_notebook_text1',currencyId:'USD',monthStartDay:15});
 result=await workspace.snapshot('2026-11');assert.equal(result.currencyId,'USD');assert.equal(result.monthStartDay,15);
 await workspace.setMonthlyBudget('2026-11','10');await assert.rejects(workspace.updateBook('jpy','locked',2,{coverPalette:'butter',coverIcon:'lucide_notebook_text1',currencyId:'CNY',monthStartDay:1}),/book currency is in use/);
 const {RdbPrepaidRepository}=load(base+'/data/rdb/RdbPrepaidRepository.ets');
 await db.insert('prepaid_projects',{id:'usd-prepaid',book_id:'b2',name:'USD prepaid',currency_id:'USD',created_at_ms:1,updated_at_ms:1});
 const initial={project:{id:'usd-prepaid',bookId:'b2',name:'USD prepaid',merchant:'',currencyId:'USD',revision:1,fundedMinor:'0',remainingMinor:'0',remainingBookMinor:'0'},events:[]};
 const payment={id:'fund-usd',projectId:'usd-prepaid',bookId:'b2',expectedRevision:1,kind:'fund',amount:Money.parse('10',currencyUnit('USD')),accountId:'usd',cash:Money.parse('10',currencyUnit('USD')),cashBook:Money.parse('10',currencyUnit('USD')),rateSource:'manual',rateDate:'2026-11-25',bookRate:'1',cashRate:'1',categoryId:'b2expense',incomeCategoryId:'b2income',spendingNatureId:'',includeInBudget:true,occurredAtMs:Date.parse('2026-11-25T12:00:00Z'),localDate:'2026-11-25',offsetMinutes:0,note:''};
 await session.write(()=>RdbPrepaidRepository.saveIn(db,payment,initial));
 const detail=await RdbPrepaidRepository.detailIn(db,'b2','usd-prepaid');
 assert.equal(detail.project.bookCurrencyId,'USD'); assert.equal(detail.project.remainingBookMinor,'1000');
 await session.write(()=>RdbPrepaidRepository.saveIn(db,{...payment,id:'consume-usd',expectedRevision:detail.project.revision,kind:'consume',amount:Money.parse('3',currencyUnit('USD')),cash:undefined,cashBook:undefined},detail));
 const tx=await db.querySql("SELECT currency_id,book_currency_id,paid_minor,book_minor FROM transactions WHERE note LIKE '预付款核销%' AND book_id='b2'");assert(tx.goToFirstRow());assert.equal(tx.getString(0),'USD');assert.equal(tx.getString(1),'USD');assert.equal(tx.getLong(2),300);
 const {parseFxEntry}=load(base+'/domain/model/FxEntrySnapshot.ets');
 assert.equal(parseFxEntry(JSON.stringify({currencyId:'USD',paidMinor:'100',grossMinor:'100',discountMinor:'0',bookMinor:'100',bookCurrencyId:'USD',accountCurrencyId:'USD',accountMinor:'100'})).bookCurrencyId,'USD');
 console.log('PASS 372 cycle boundaries, leap/short months, cycle calendar, JPY precision, production snapshot/statistics/CRUD/budgets, USD prepaid consumption and FX snapshots with separate SQLite reader/writer');
} finally {worker.stdin.end();await new Promise(resolve=>worker.on('exit',resolve));fs.rmSync(temp,{recursive:true,force:true});}
