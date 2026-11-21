/** Production deletion orchestration against separate SQLite reader/writer; no device or native package/filesystem runtime. */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import readline from 'node:readline';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const root=path.resolve(import.meta.dirname,'..'),base=root+'/entry/src/main/ets',cache=new Map();
class Predicates{constructor(table){this.table=table;this.where=[];this.args=[];}equalTo(k,v){this.where.push(k+'=?');this.args.push(v);return this;}isNull(k){this.where.push(k+' IS NULL');return this;}}
function load(file){file=path.resolve(file);if(cache.has(file))return cache.get(file).exports;const m={exports:{}};cache.set(file,m);const code=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText;vm.runInThisContext(`(function(require,module,exports){${code}\n})`,{filename:file})(id=>id.startsWith('.')?load(path.resolve(path.dirname(file),id+'.ets')):id==='@kit.ArkTS'?{util:{generateRandomUUID:()=>crypto.randomUUID()}}:id==='@kit.ArkData'?{relationalStore:{RdbPredicates:Predicates}}:{},m,m.exports);return m.exports;}
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'xq-book-delete-'));
const fixture=spawnSync('python3',['-c',`
import sys,sqlite3
sys.path.insert(0,sys.argv[1]+'/docs/database')
from verify_category_deletion import CategoryDeletionTests
f=CategoryDeletionTests();f.setUp();f.old.expense('a',amount=500);f.old.expense('b',book='b2',amount=200)
f.db.execute("UPDATE transactions SET posting_state='draft' WHERE id='a'")
f.db.execute("UPDATE transactions SET occurred_at_ms=1795132800000 WHERE id='a'")
f.db.execute("UPDATE account_movements SET occurred_at_ms=1795132800000 WHERE transaction_id='a'")
f.db.execute("UPDATE transactions SET posting_state='posted' WHERE id='a'")
f.db.execute("UPDATE categories SET name='餐饮',icon_key='food' WHERE id='b1expense'")
f.db.execute("INSERT OR REPLACE INTO db_meta(key,value) VALUES('active_book_id','b1')")
x=sqlite3.connect(sys.argv[2]);f.db.backup(x);x.close();f.doCleanups()
`,root,temp+'/ledger.db'],{encoding:'utf8'});assert.equal(fixture.status,0,fixture.stderr);
const worker=spawn('python3',['-u','-c',`
import sqlite3,json,sys
w=sqlite3.connect(sys.argv[1],isolation_level=None);w.execute('PRAGMA foreign_keys=ON');w.execute('PRAGMA journal_mode=WAL');r=sqlite3.connect(sys.argv[1],isolation_level=None)
for line in sys.stdin:
 try:
  c=json.loads(line)
  if c['op']=='backup':
   x=sqlite3.connect(c['path']);w.backup(x);x.close();value=None
  else:
   cur=(r if c['op']=='query' else w).execute(c['sql'],c.get('args',[]));value=cur.fetchall() if c['op']=='query' else cur.rowcount
  print(json.dumps({'value':value}),flush=True)
 except Exception as e:print(json.dumps({'error':str(e)}),flush=True)
`,temp+'/ledger.db'],{stdio:['pipe','pipe','inherit']});
const pending=[];readline.createInterface({input:worker.stdout}).on('line',line=>{const n=pending.shift(),v=JSON.parse(line);v.error?n.reject(Error(v.error)):n.resolve(v.value);});
const rpc=value=>new Promise((resolve,reject)=>{pending.push({resolve,reject});worker.stdin.write(JSON.stringify(value)+'\n');});
const db={async querySql(sql,args=[]){const rows=await rpc({op:'query',sql,args});let at=-1;return{rowCount:rows.length,columnCount:rows[0]?.length||0,goToFirstRow(){at=0;return rows.length>0;},goToNextRow(){return ++at<rows.length;},getString(i){return rows[at][i]===null?'':String(rows[at][i]);},getLong(i){return Number(rows[at][i]);},isColumnNull(i){return rows[at][i]===null;},close(){}};},async executeSql(sql,args=[]){await rpc({op:'exec',sql,args});},async insert(table,values){const keys=Object.keys(values);await this.executeSql(`INSERT INTO ${table}(${keys}) VALUES(${keys.map(()=>'?')})`,Object.values(values));},async update(values,p){const keys=Object.keys(values);return rpc({op:'exec',sql:`UPDATE ${p.table} SET ${keys.map(k=>k+'=?')} WHERE ${p.where.join(' AND ')}`,args:[...Object.values(values),...p.args]});},async delete(p){return rpc({op:'exec',sql:`DELETE FROM ${p.table} WHERE ${p.where.join(' AND ')}`,args:p.args});}};
let tail=Promise.resolve();const session={read(fn){const result=tail.then(()=>fn(db));tail=result.catch(()=>{});return result;},write(fn){const result=tail.then(async()=>{await db.executeSql('BEGIN');try{const result=await fn(db);await db.executeSql('COMMIT');return result;}catch(e){await db.executeSql('ROLLBACK');throw e;}});tail=result.catch(()=>{});return result;}};
try {
 const {currencyUnit}=load(base+'/core/money/Currencies.ets'),{Money}=load(base+'/core/money/Money.ets'),{MonthlyBudget}=load(base+'/domain/model/MonthlyBudget.ets');
 const {RdbFxSnapshots}=load(base+'/data/rdb/RdbFxSnapshots.ets'),{RdbStatisticsRepository}=load(base+'/data/rdb/RdbStatisticsRepository.ets'),{RdbLedgerSearch}=load(base+'/data/rdb/RdbLedgerSearch.ets');
 // Execute the production V12 -> V13 candidate upgrade on the isolated reader/writer database.
 const migrationSchemas=['Review','Transfer','SpendingNature','BudgetNature','Recovery','NatureColor','Multicurrency','Prepaid','AccountDetails','BookCover','BookSettings','BookDeletion'];
 const migrationMarkers=['schema_checksum','transfer_schema_checksum','spending_nature_schema_checksum','budget_nature_schema_checksum','recovery_schema_checksum','nature_color_schema_checksum','multicurrency_schema_checksum','prepaid_schema_checksum','account_details_schema_checksum','book_cover_schema_checksum','book_settings_schema_checksum','book_deletion_schema_checksum'];
 await db.executeSql('DELETE FROM schema_migrations');
 for(let i=0;i<migrationSchemas.length;i++){const schema=load(base+'/data/rdb/'+migrationSchemas[i]+'Schema.ets'),hash=Object.entries(schema).find(([key])=>key.endsWith('_SCHEMA_SHA256'))[1];await db.insert('schema_migrations',{version:i+1,checksum:hash,applied_at_ms:1});await db.executeSql('INSERT OR REPLACE INTO db_meta(key,value) VALUES(?,?)',[migrationMarkers[i],hash]);}
 const oldTransactions=await rpc({op:'query',sql:'SELECT * FROM transactions ORDER BY id'});
 load(base+'/data/rdb/RdbSession.ets').RdbSession.forStore=()=>session;
 await load(base+'/data/rdb/CategoryDeletionMigration.ets').CategoryDeletionMigration.upgradeCandidate(db);
 assert.deepEqual(await rpc({op:'query',sql:'SELECT * FROM transactions ORDER BY id'}),oldTransactions);
 const source=fs.readFileSync(base+'/data/rdb/LedgerWorkspace.ets','utf8'),tree=ts.createSourceFile('workspace.ts',source,ts.ScriptTarget.Latest,true),cls=tree.statements.find(ts.isClassDeclaration);
 const methods=['snapshot','readBookSettings','categories','entryDetail','deleteCategory','categoryPrepaidReferences','activeBookFromMeta'].map(n=>cls.members.find(m=>ts.isMethodDeclaration(m)&&m.name.getText(tree)===n).getText(tree)).join('\n');
 const context={exports:{},currencyUnit,Money,MonthlyBudget,RdbFxSnapshots,RdbRecoveryRepository:load(base+'/data/rdb/RdbRecoveryRepository.ets').RdbRecoveryRepository,RdbAttachmentLinks:load(base+'/data/rdb/RdbAttachmentLinks.ets').RdbAttachmentLinks,DEFAULT_BOOK_ID:'b1',DEFAULT_MONTHLY_BUDGET_MINOR:'250000',relationalStore:{RdbPredicates:Predicates},prepaidEntryContext:()=>undefined};
 vm.runInNewContext(ts.transpileModule('class LedgerWorkspace {static ACTIVE_BOOK_KEY="active_book_id";'+methods+'}exports.Workspace=LedgerWorkspace;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,context);
 const workspace=new context.exports.Workspace();Object.assign(workspace,{session,activeBookId:'b1',currency:currencyUnit('CNY')});
 const stat=new RdbStatisticsRepository(db);
 const before={snapshot:await workspace.snapshot('2026-11'),detail:await workspace.entryDetail('a'),stats:await stat.snapshot('b1','2026-11-01','2026-12-01','expense','day'),search:await RdbLedgerSearch.search(db,'b1','餐饮')};
 const {exportLedgerCsv}=load(base+'/data/exchange/LedgerCsvExport.ets');const csvBefore=exportLedgerCsv(before.snapshot);
 const balances=await rpc({op:'query',sql:'SELECT * FROM v_account_balances ORDER BY account_id'});
 await assert.rejects(workspace.deleteCategory('b1expense',9),/CATEGORY_CHANGED/);
 await workspace.deleteCategory('b1expense',1);
 assert.equal((await db.querySql("SELECT id FROM categories WHERE id='b1expense'")).rowCount,0);
 assert.deepEqual(await rpc({op:'query',sql:'SELECT * FROM v_account_balances ORDER BY account_id'}),balances);
 assert.deepEqual(JSON.parse(JSON.stringify(await workspace.snapshot('2026-11'))),JSON.parse(JSON.stringify({...before.snapshot,categories:before.snapshot.categories.filter(c=>c.id!=='b1expense')})));
 assert.equal(exportLedgerCsv(await workspace.snapshot('2026-11')),csvBefore);
 assert.deepEqual(await workspace.entryDetail('a'),before.detail);
 assert.deepEqual(await stat.snapshot('b1','2026-11-01','2026-12-01','expense','day'),before.stats);
 assert.deepEqual(await RdbLedgerSearch.search(db,'b1','餐饮'),before.search);
 assert.equal((await workspace.categories()).some(c=>c.id==='b1expense'),false);
 await assert.rejects(workspace.deleteCategory('spare',1),/LAST_ACTIVE_CATEGORY/);
 // Exercise actual repository and validated command, preserving the deleted category when editing history.
 const {RdbLedgerRepository}=load(base+'/data/rdb/RdbLedgerRepository.ets'),{ExpenseRecord}=load(base+'/domain/model/ExpenseRecord.ets');
 const repo=Object.create(RdbLedgerRepository.prototype);repo.session=session;
 const amount=Money.fromMinorText('500',currencyUnit('CNY')),zero=Money.fromMinorText('0',currencyUnit('CNY'));
 const cmd={id:'a',bookId:'b1',categoryId:'b1expense',gross:amount,discount:zero,bookPaid:amount,accountId:'cash',accountPaid:amount,includeInAssets:true,includeInBudget:false,note:'编辑后',occurredAtMs:before.detail.occurredAtMs,localDate:before.detail.localDate,timezone:before.detail.timezone,offsetMinutes:before.detail.offsetMinutes};
 await repo.updateExpense(new ExpenseRecord(cmd),1);
 assert.equal((await workspace.entryDetail('a')).categoryName,'餐饮');assert.equal((await workspace.entryDetail('a')).note,'编辑后');
 await repo.updateExpense(new ExpenseRecord({...cmd,categoryId:'spare'}),2);
 assert.equal((await workspace.entryDetail('a')).categoryId,'spare');
 await assert.rejects(repo.updateExpense(new ExpenseRecord(cmd),3),/CATEGORY_UNAVAILABLE/);
 assert.deepEqual(await rpc({op:'query',sql:'SELECT * FROM v_account_balances ORDER BY account_id'}),balances);
 // Install genuine migration markers and execute the production version-chain validation.
 const schemas=['Review','Transfer','SpendingNature','BudgetNature','Recovery','NatureColor','Multicurrency','Prepaid','AccountDetails','BookCover','BookSettings','BookDeletion','CategoryDeletion'];
 const markers=['schema_checksum','transfer_schema_checksum','spending_nature_schema_checksum','budget_nature_schema_checksum','recovery_schema_checksum','nature_color_schema_checksum','multicurrency_schema_checksum','prepaid_schema_checksum','account_details_schema_checksum','book_cover_schema_checksum','book_settings_schema_checksum','book_deletion_schema_checksum','category_deletion_schema_checksum'];
 await db.executeSql('DELETE FROM schema_migrations');
 for(let i=0;i<schemas.length;i++){const schema=load(base+'/data/rdb/'+schemas[i]+'Schema.ets'),hash=Object.entries(schema).find(([key])=>key.endsWith('_SCHEMA_SHA256'))[1];await db.insert('schema_migrations',{version:i+1,checksum:hash,applied_at_ms:1});await db.executeSql('INSERT OR REPLACE INTO db_meta(key,value) VALUES(?,?)',[markers[i],hash]);}
 const {CategoryDeletionMigration}=load(base+'/data/rdb/CategoryDeletionMigration.ets');assert.equal(await CategoryDeletionMigration.status(db),13);
 const checksum=load(base+'/data/rdb/CategoryDeletionSchema.ets').CATEGORY_DELETION_SCHEMA_SHA256;assert.equal(checksum,crypto.createHash('sha256').update(fs.readFileSync(root+'/docs/database/schema-v13-category-deletion.sql')).digest('hex'));
 // Historical resource icons must remain in complete-backup resource enumeration.
 const iconPath='icons/'+ 'a'.repeat(64)+'.svg';
 await db.insert('categories',{id:'resource-category',book_id:'b1',kind:'expense',name:'资源分类',name_key:'资源分类',icon_key:'resource:'+iconPath,created_at_ms:1,updated_at_ms:1});
 await repo.saveExpense(new ExpenseRecord({...cmd,id:'resource-tx',categoryId:'resource-category',accountId:undefined,accountPaid:undefined,includeInAssets:false}));
 await workspace.deleteCategory('resource-category',1);
 const {LocalLedgerBackup}=load(base+'/data/rdb/LocalLedgerBackup.ets');
 assert((await LocalLedgerBackup.resources(db)).some(ref=>ref.path===iconPath));
 for(const c of load(base+'/core/money/Currencies.ets').BUILTIN_CURRENCIES){await db.executeSql('INSERT OR IGNORE INTO currencies(id,code,name,symbol,minor_unit,valid_from,source_version) VALUES(?,?,?,?,?,?,?)',[c.code,c.code,c.name,c.symbol,c.scale,'2026-01-01','host-fixture']);}
 await LocalLedgerBackup.check(db);
 // Prepaid blocker is a stable app error, before any native DELETE/RAISE error can lose its text.
 await db.insert('categories',{id:'blocked-category',book_id:'b1',kind:'expense',name:'预付分类',name_key:'预付分类',created_at_ms:1,updated_at_ms:1});
 await db.insert('prepaid_projects',{id:'blocked-project',book_id:'b1',name:'预付项目',currency_id:'CNY',created_at_ms:1,updated_at_ms:1});
 await db.insert('prepaid_events',{id:'blocked-event',project_id:'blocked-project',sequence_no:1,kind:'fund',amount_minor:100,book_minor:100,account_id:'cash',account_currency_id:'CNY',cash_minor:100,cash_book_minor:100,quote_json:JSON.stringify({entry:{categoryId:'blocked-category'}}),local_date:'2026-11-20',occurred_at_ms:1,offset_minutes:0,created_at_ms:1});
 const nativeDelete=db.delete;let nativeDeletes=0;db.delete=(...args)=>{nativeDeletes++;return nativeDelete(...args);};
 await assert.rejects(workspace.deleteCategory('blocked-category',1),/^Error: CATEGORY_HAS_PREPAID$/);assert.equal(nativeDeletes,0);db.delete=nativeDelete;
 assert.equal((await db.querySql("SELECT id FROM categories WHERE id='blocked-category'")).rowCount,1);
 // Read-only blocker lookup uses exactly the deletion predicate and groups duplicate matches per project.
 let references=await workspace.categoryPrepaidReferences('blocked-category');
 assert.equal(references.length,1);assert.equal(references[0].projectId,'blocked-project');
 assert.equal(references[0].projectName,'预付项目');assert.equal(references[0].eventCount,1);
 await db.executeSql("UPDATE prepaid_events SET kind='refund',quote_json=?,transaction_id='a' WHERE id='blocked-event'",[JSON.stringify({entry:{categoryId:'spare'}})]);
 references=await workspace.categoryPrepaidReferences('spare');
 assert.equal(references.length,1);assert.equal(references[0].eventCount,1);
 await db.executeSql("UPDATE prepaid_events SET quote_json='{}' WHERE id='blocked-event'");
 assert.equal((await workspace.categoryPrepaidReferences('spare'))[0].eventCount,1);
 assert.equal((await workspace.categoryPrepaidReferences('blocked-category')).length,0);
 await db.executeSql("UPDATE prepaid_events SET kind='fund',quote_json=?,transaction_id=NULL WHERE id='blocked-event'",[JSON.stringify({entry:{categoryId:'blocked-category'}})]);
 await db.executeSql("UPDATE prepaid_events SET deleted_at_ms=2 WHERE id='blocked-event'");
 assert.equal((await workspace.categoryPrepaidReferences('blocked-category'))[0].eventCount,1);
 // Actual page confirmation handler: cancel, confirmed deletion, and mapped blocking error.
 const pageSource=fs.readFileSync(base+'/components/CategoryManagementPage.ets','utf8');
 const pageTree=ts.createSourceFile('page.ts',pageSource.replace('export struct','class'),ts.ScriptTarget.Latest,true),pageClass=pageTree.statements.find(ts.isClassDeclaration);
 const handler=pageClass.members.find(m=>ts.isMethodDeclaration(m)&&m.name.getText(pageTree)==='remove').getText(pageTree);
 const uiContext={exports:{},$r:x=>x};vm.runInNewContext(ts.transpileModule('class Page{'+handler+'}exports.Page=Page;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,uiContext);
 let answer=0,calls=0,fail=false;const page=new uiContext.exports.Page();
 Object.assign(page,{interactionLocked:()=>false,workspace:{async deleteCategory(id,revision){calls++;assert.equal(id,'cat');assert.equal(revision,4);if(fail)throw Error('CATEGORY_HAS_BUDGET');},async categories(){return[];}},getUIContext:()=>({getPromptAction:()=>({showDialog:async()=>({index:answer})})})});
 page.remove({id:'cat',revision:4,name:'分类'});await new Promise(resolve=>setImmediate(resolve));assert.equal(calls,0);assert.equal(page.busy,false);
 answer=1;page.remove({id:'cat',revision:4,name:'分类'});await new Promise(resolve=>setImmediate(resolve));assert.equal(calls,1);assert.equal(page.busy,false);
 fail=true;page.remove({id:'cat',revision:4,name:'分类'});await new Promise(resolve=>setImmediate(resolve));assert(page.error.includes('预算'));assert.equal(page.busy,false);
 page.workspace.categoryPrepaidReferences=async()=>[{projectId:'blocked-project',projectName:'预付项目',eventCount:1}];page.workspace.deleteCategory=async()=>{throw Error('CATEGORY_HAS_PREPAID');};page.remove({id:'cat',revision:4,name:'分类'});await new Promise(resolve=>setImmediate(resolve));assert(page.error.includes('预付款项目或核销记录'));assert(!page.error.includes('删除未确认'));assert.equal(page.prepaidReferences[0].projectId,'blocked-project');assert.equal(page.busy,false);
 page.workspace.categoryPrepaidReferences=async()=>{throw Error('read failed');};page.remove({id:'cat',revision:4,name:'分类'});await new Promise(resolve=>setImmediate(resolve));assert(page.error.includes('关联项目读取失败'));assert.equal(page.busy,false);
 // Returning from a reference detail closes to the caller; ordinary prepaid details keep list navigation.
 const prepaidSource=fs.readFileSync(base+'/components/PrepaidPage.ets','utf8');
 const prepaidTree=ts.createSourceFile('prepaid.ts',prepaidSource.replace('export struct','class'),ts.ScriptTarget.Latest,true);
 const prepaidClass=prepaidTree.statements.find(ts.isClassDeclaration);
 const closeHandler=prepaidClass.members.find(m=>ts.isMethodDeclaration(m)&&m.name.getText(prepaidTree)==='closePage').getText(prepaidTree);
 const backContext={exports:{}};vm.runInNewContext(ts.transpileModule('class Page{'+closeHandler+'}exports.Page=Page;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,backContext);
 let closed=0;const detailPage=new backContext.exports.Page();Object.assign(detailPage,{detail:{project:{}},returnToCaller:true,onClose:()=>closed++});
 detailPage.closePage();assert.equal(closed,1);
 detailPage.returnToCaller=false;detailPage.closePage();assert.equal(closed,1);assert.equal(detailPage.detail,undefined);
 detailPage.closePage();assert.equal(closed,2);
 const indexSource=fs.readFileSync(base+'/pages/Index.ets','utf8');
 const categoryRoute=indexSource.slice(indexSource.indexOf('private categoryManagementPage()'),indexSource.indexOf('private tagManagementPage()'));
 assert(categoryRoute.includes('onOpenPrepaid:'));assert(categoryRoute.includes('Visibility.Hidden'));assert(categoryRoute.includes('this.prepaidPage()'));
 assert(pageSource.includes("id('category-prepaid-' + reference.projectId)"));
 const refresh=pageSource.slice(pageSource.indexOf("Button('刷新分类'"),pageSource.indexOf("id('category-refresh')"));assert(refresh.includes('ButtonType.Capsule'));assert(refresh.includes('xq_brand'));assert(refresh.includes('xq_font_on_primary'));
 assert(!pageSource.includes('category-toggle-archive'));assert(pageSource.includes('category-delete-'));
 console.log('PASS production category delete: exact balances, unchanged snapshot/detail/search/statistics/CSV, no new picker option, history edit/reclassify, revision/last-category guards V13 backup validation/resource icons, UI confirmation and status chain (separate SQLite reader/writer, host only)');
}finally{worker.stdin.end();await new Promise(resolve=>worker.on('exit',resolve));fs.rmSync(temp,{recursive:true,force:true});}
