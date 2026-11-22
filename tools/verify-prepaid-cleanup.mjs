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
 const {currencyUnit}=load(base+'/core/money/Currencies.ets'),{Money}=load(base+'/core/money/Money.ets');
 // Execute the production V12 -> V13 candidate upgrade on the isolated reader/writer database.
 const migrationSchemas=['Review','Transfer','SpendingNature','BudgetNature','Recovery','NatureColor','Multicurrency','Prepaid','AccountDetails','BookCover','BookSettings','BookDeletion'];
 const migrationMarkers=['schema_checksum','transfer_schema_checksum','spending_nature_schema_checksum','budget_nature_schema_checksum','recovery_schema_checksum','nature_color_schema_checksum','multicurrency_schema_checksum','prepaid_schema_checksum','account_details_schema_checksum','book_cover_schema_checksum','book_settings_schema_checksum','book_deletion_schema_checksum'];
 await db.executeSql('DELETE FROM schema_migrations');
 for(let i=0;i<migrationSchemas.length;i++){const schema=load(base+'/data/rdb/'+migrationSchemas[i]+'Schema.ets'),hash=Object.entries(schema).find(([key])=>key.endsWith('_SCHEMA_SHA256'))[1];await db.insert('schema_migrations',{version:i+1,checksum:hash,applied_at_ms:1});await db.executeSql('INSERT OR REPLACE INTO db_meta(key,value) VALUES(?,?)',[migrationMarkers[i],hash]);}
 const oldTransactions=await rpc({op:'query',sql:'SELECT * FROM transactions ORDER BY id'});
 load(base+'/data/rdb/RdbSession.ets').RdbSession.forStore=()=>session;
 await load(base+'/data/rdb/CategoryDeletionMigration.ets').CategoryDeletionMigration.upgradeCandidate(db);
 assert.deepEqual(await rpc({op:'query',sql:'SELECT * FROM transactions ORDER BY id'}),oldTransactions);

 const beforeMigration=await rpc({op:'query',sql:'SELECT * FROM transactions ORDER BY id'});
 const {PrepaidCleanupMigration}=load(base+'/data/rdb/PrepaidCleanupMigration.ets');
 await PrepaidCleanupMigration.upgradeCandidate(db);assert.equal(await PrepaidCleanupMigration.status(db),14);
 assert.deepEqual(await rpc({op:'query',sql:'SELECT * FROM transactions ORDER BY id'}),beforeMigration);
 const {RdbPrepaidRepository}=load(base+'/data/rdb/RdbPrepaidRepository.ets');const repo=new RdbPrepaidRepository(db);
 const balances=()=>rpc({op:'query',sql:'SELECT * FROM v_account_balances ORDER BY account_id'});
 const money=s=>Money.parse(s,currencyUnit('CNY'));
 const payment=(id,project,kind='fund',revision=1)=>({id,bookId:'b1',projectId:project,expectedRevision:revision,kind,amount:money('10'),accountId:kind==='consume'?'':'cash',cash:kind==='consume'?undefined:money('10'),cashBook:kind==='consume'?undefined:money('10'),rateSource:'manual',rateDate:'2026-11-20',bookRate:'1',cashRate:'1',categoryId:'b1expense',incomeCategoryId:'b1income',spendingNatureId:'',includeInBudget:true,occurredAtMs:Date.parse('2026-11-20T12:00:00Z'),localDate:'2026-11-20',offsetMinutes:0,note:'',attachments:[],entryContext:{categoryId:'b1expense',categoryName:'餐饮',spendingNatureId:'',includeInBudget:true,grossMinor:'1000',discountMinor:'0',addressText:'',tagIds:[],tagNames:[]}});
 const create=async id=>repo.create({id,bookId:'b1',name:'项目'+id,currencyId:'CNY',merchant:'',note:'',expiryDate:'',includeInNetAssets:true},payment(id+'fund',id));
 const baseline=await balances();await create('p');let detail=await repo.detail('b1','p');
 await assert.rejects(repo.undo('b1','p','pfund',detail.project.revision),/PREPAID_EMPTY_CONFIRMATION_REQUIRED/);
 assert.equal((await repo.detail('b1','p')).events.length,1);
 assert.equal(await repo.undo('b1','p','pfund',detail.project.revision,true),true);
 assert.deepEqual(await balances(),baseline);await assert.rejects(repo.detail('b1','p'),/PREPAID_CHANGED/);
 // Ordinary undo keeps the project, then the final confirmed undo removes the entire inactive chain.
 await create('chain');detail=await repo.detail('b1','chain');
 await repo.save(payment('chainconsume','chain','consume',detail.project.revision));
 detail=await repo.detail('b1','chain');const linked=detail.events.at(-1).transactionId;assert(linked);
 assert.equal(await repo.undo('b1','chain','chainconsume',detail.project.revision),false);
 detail=await repo.detail('b1','chain');assert.equal(detail.events.length,1);
 assert.equal(await repo.undo('b1','chain','chainfund',detail.project.revision,true),true);
 assert.equal((await db.querySql('SELECT id FROM transactions WHERE id=?',[linked])).rowCount,0);
 assert.deepEqual(await balances(),baseline);
 // A draft appearing after the confirmation prevents cleanup and rolls the undo back atomically.
 await create('draft');detail=await repo.detail('b1','draft');const funded=await balances();
 await db.insert('prepaid_events',{id:'unfinished',project_id:'draft',sequence_no:2,kind:'fund',amount_minor:1,book_minor:1,account_id:'cash',account_currency_id:'CNY',cash_minor:1,cash_book_minor:1,local_date:'2026-11-20',occurred_at_ms:1,offset_minutes:0,created_at_ms:1});
 await assert.rejects(repo.undo('b1','draft','draftfund',detail.project.revision,true),/PREPAID_NOT_EMPTY/);
 assert.deepEqual(await balances(),funded);assert.equal((await repo.detail('b1','draft')).events.length,1);
 // Legacy empty project is explicitly deletable, but stale revisions and populated projects are blocked.
 await create('legacy');detail=await repo.detail('b1','legacy');
 await assert.rejects(repo.deleteEmpty('b1','legacy',detail.project.revision),/PREPAID_NOT_EMPTY/);
 await db.executeSql("UPDATE prepaid_events SET deleted_at_ms=2 WHERE project_id='legacy'");
 await assert.rejects(repo.deleteEmpty('b1','legacy',99),/PREPAID_CHANGED/);
 const emptyBalance=await balances();await repo.deleteEmpty('b1','legacy',detail.project.revision);assert.deepEqual(await balances(),emptyBalance);
 assert.equal((await db.querySql("SELECT id FROM prepaid_projects WHERE id='legacy'")).rowCount,0);
 assert.equal((await db.querySql('PRAGMA foreign_key_check')).rowCount,0);
 assert.equal(await PrepaidCleanupMigration.status(db),14);
 // Actual UI handler: cancel is a no-op; final versus ordinary confirmation text and API authorization differ.
 const src=fs.readFileSync(base+'/components/PrepaidPage.ets','utf8');const tree=ts.createSourceFile('page.ts',src.replace('export struct','class'),ts.ScriptTarget.Latest,true);
 const cls=tree.statements.find(ts.isClassDeclaration);const method=n=>cls.members.find(m=>ts.isMethodDeclaration(m)&&m.name.getText(tree)===n).getText(tree);
 const ctx={exports:{},$r:x=>x};vm.runInNewContext(ts.transpileModule('class Page{'+method('undo')+method('deleteEmptyProject')+'}exports.Page=Page;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
 let answer=0,dialog,calls=0,deleted=0,emptyCalls=0;
 const page=new ctx.exports.Page();Object.assign(page,{active:true,working:false,loading:false,detail:{project:{id:'ui',name:'游戏',revision:3,currencyId:'CNY'},events:[{id:'ufund',kind:'fund',amountMinor:'100'}]},setWorking(v){this.working=v;},label:()=> '预付',money:()=> '1.00',errorText:e=>e.message,projectDeleted:async()=>{deleted++;},reload:async()=>{},onChanged:async()=>{},getUIContext:()=>({getPromptAction:()=>({showDialog:async d=>{dialog=d;return {index:answer};}})}),workspace:{undoPrepaid:async(id,event,revision,confirmed)=>{calls++;assert.equal(confirmed,page.detail.events.length===1);return confirmed;},deleteEmptyPrepaid:async()=>{emptyCalls++;}}});
 await page.undo();assert.equal(calls,0);assert.equal(page.working,false);assert(dialog.message.includes('最后一条有效流水'));assert(dialog.message.includes('同时删除'));assert.equal(dialog.buttons[1].text,'撤销并删除项目');
 answer=1;await page.undo();assert.equal(calls,1);assert.equal(deleted,1);
 page.detail.events.unshift({id:'older'});await page.undo();assert.equal(calls,2);assert.equal(deleted,1);assert.equal(dialog.title,'撤销最近一条流水？');
 page.detail.events=[];answer=0;await page.deleteEmptyProject();assert.equal(emptyCalls,0);answer=1;await page.deleteEmptyProject();assert.equal(emptyCalls,1);assert.equal(deleted,2);
 console.log('PASS V14 production migration, separate-reader/writer final undo cleanup, draft race rollback, explicit empty deletion, exact balances, category reference cleanup and UI confirmation/cancel paths (host only)');
}finally{worker.stdin.end();await new Promise(resolve=>worker.on('exit',resolve));fs.rmSync(temp,{recursive:true,force:true});}
