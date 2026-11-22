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
const appValues=new Map();globalThis.AppStorage={setOrCreate:(key,value)=>appValues.set(key,value)};globalThis.$r=name=>({id:name});
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
  elif c['op']=='restore':
   x=sqlite3.connect(c['path']);x.backup(w);x.close();value=None
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
 const {TransactionColors:C,DEFAULT_TRANSACTION_COLORS:D}=load(base+'/presentation/ledger/TransactionColors.ets');
 const {RdbTransactionColors:R}=load(base+'/data/rdb/RdbTransactionColors.ets');
 assert.equal(C.selected('expense',D),'orange');assert.equal(C.selected('income',D),'green');assert.equal(C.selected('transfer',D),'black');
 assert.deepEqual(C.options('expense').map(x=>x.id),['red','orange','green','black']);
 assert.deepEqual(C.options('income').map(x=>x.id),['red','green','black']);assert.deepEqual(C.options('transfer').map(x=>x.id),['blue','black']);
 // Validate every selectable pair; only shared red and shared green are illegal, black is explicitly exempt.
 let combinations=0;
 for(const expense of C.options('expense'))for(const income of C.options('income'))for(const transfer of C.options('transfer')){
  const json=JSON.stringify({version:1,expense:expense.id,income:income.id,transfer:transfer.id});
  if(expense.id===income.id&&expense.id!=='black'){assert.throws(()=>C.parse(json),/TRANSACTION_COLORS_INVALID/);continue;}
  assert.equal(C.parse(json).expense,expense.id);combinations++;
  for(const option of C.options('expense'))assert.equal(C.disabled('expense',option.id,json),option.id===income.id&&option.id!=='black');
  for(const option of C.options('income'))assert.equal(C.disabled('income',option.id,json),option.id===expense.id&&option.id!=='black');
  for(const option of C.options('transfer'))assert.equal(C.disabled('transfer',option.id,json),false);
 }
 assert.equal(combinations,20);
 let json=C.change(D,'expense','red');assert(C.disabled('income','red',json));
 json=C.change(json,'expense','black');json=C.change(json,'income','black');assert(!C.disabled('expense','black',json));
 assert.equal(C.shade(0xCA3439,0xFFFFFF,0),'#CA3439');assert.equal(C.shade(0x000000,0xFFFFFF,5),'#999999');
 assert.equal(C.shade(0xFFFFFF,0x000000,5),'#666666');assert.equal(C.shade(0x000000,0xFFFFFF,999),'#999999');
 assert.equal(C.color('expense',json).id,'app.color.xq_font_primary');assert.equal(C.onDark('expense',json).id,'app.color.xq_transaction_black_on_dark');
 for(const invalid of ['null','[]','{}','bad',JSON.stringify({version:2,expense:'orange',income:'green',transfer:'black'}),JSON.stringify({version:1,expense:'blue',income:'green',transfer:'black'})])assert.throws(()=>C.parse(invalid));
 // Real existing db_meta persistence and whole SQLite backup/restore, including legacy absence.
 assert.equal(await R.read(db),D);await R.load(session);assert.equal(C.selected('expense',appValues.get('transactionColorSelection')),'orange');
 const custom=C.change(C.change(D,'expense','red'),'transfer','blue');await R.save(session,custom);
 assert.equal(await R.read(db),custom);assert.equal(appValues.get('transactionColorSelection'),custom);
 await rpc({op:'backup',path:temp+'/colors.db'});
 await R.save(session,D);await rpc({op:'restore',path:temp+'/colors.db'});await R.load(session);
 assert.equal(appValues.get('transactionColorSelection'),custom);
 const original=db.executeSql;db.executeSql=async()=>{throw Error('disk full');};
 await assert.rejects(R.save(session,D),/disk full/);assert.equal(appValues.get('transactionColorSelection'),custom);db.executeSql=original;
 assert.equal(await R.read(db),custom);
 await db.executeSql("DELETE FROM db_meta WHERE key='transaction_colors_v1'");await R.load(session);assert.equal(appValues.get('transactionColorSelection'),D);
 await db.executeSql("INSERT INTO db_meta(key,value) VALUES('transaction_colors_v1',?)",[JSON.stringify({version:1,expense:'red',income:'red',transfer:'black'})]);await assert.rejects(R.read(db),/TRANSACTION_COLORS_INVALID/);
 // Palette resources exist in both themes and dark-budget variants remain visible.
 const light=JSON.parse(fs.readFileSync(root+'/entry/src/main/resources/base/element/color.json')).color;
 const dark=JSON.parse(fs.readFileSync(root+'/entry/src/main/resources/dark/element/color.json')).color;
 for(const mode of ['base','dark']){
  const old=JSON.parse(spawnSync('git',['show','HEAD:entry/src/main/resources/'+mode+'/element/color.json'],{encoding:'utf8'}).stdout).color;
  const current=mode==='base'?light:dark;for(const name of ['xq_brand','xq_app_income','xq_font_emphasize'])assert.equal(current.find(x=>x.name===name).value,old.find(x=>x.name===name).value);
 }

 for(const id of ['red','orange','green','blue'])for(const palette of [light,dark])assert(palette.some(c=>c.name==='xq_transaction_'+id));
 assert(light.some(c=>c.name==='xq_transaction_black_on_dark'&&c.value!=='#FF000000'));
 // Execute actual color-page choice handler; a blocked option never reaches saving.
 const colorSource=fs.readFileSync(base+'/components/TransactionColorsPage.ets','utf8');
 const colorTree=ts.createSourceFile('colors.ts',colorSource.replace('export struct','class'),ts.ScriptTarget.Latest,true),colorClass=colorTree.statements.find(ts.isClassDeclaration);
 const choose=colorClass.members.find(m=>ts.isMethodDeclaration(m)&&m.name.getText(colorTree)==='choose').getText(colorTree);
 const colorContext={exports:{},TransactionColors:C};vm.runInNewContext(ts.transpileModule('class Page{'+choose+'}exports.Page=Page;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,colorContext);
 let saves=0;const colorPage=new colorContext.exports.Page();Object.assign(colorPage,{selection:D,save:json=>{saves++;colorPage.selection=json;}});
 colorPage.choose('expense','green');assert.equal(saves,0);colorPage.choose('expense','red');assert.equal(saves,1);colorPage.choose('income','red');assert.equal(saves,1);
 colorPage.choose('expense','black');colorPage.choose('income','black');assert.equal(saves,3);assert.equal(C.selected('income',colorPage.selection),'black');
 // Execute actual settings-level back handler: child closes first; saving prevents navigation.
 const settings=fs.readFileSync(base+'/components/SettingsPage.ets','utf8'),tree=ts.createSourceFile('settings.ts',settings.replace('export struct','class'),ts.ScriptTarget.Latest,true),cls=tree.statements.find(ts.isClassDeclaration);
 const handler=cls.members.find(m=>ts.isMethodDeclaration(m)&&m.name.getText(tree)==='navigateBack').getText(tree);
 const ctx={exports:{}};vm.runInNewContext(ts.transpileModule('class Settings{'+handler+'}exports.Settings=Settings;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
 const page=new ctx.exports.Settings();page.showColors=true;page.colorSaving=true;assert.equal(page.navigateBack(),true);assert.equal(page.showColors,true);page.colorSaving=false;assert.equal(page.navigateBack(),true);assert.equal(page.showColors,false);assert.equal(page.navigateBack(),false);
 const index=fs.readFileSync(base+'/pages/Index.ets','utf8');assert(index.includes('if (!this.settingsBackHandler())'));assert(index.includes('await this.workspace.loadTransactionColors()'));
 assert(fs.readFileSync(base+'/data/rdb/LocalLedgerBackup.ets','utf8').includes('await RdbTransactionColors.read(db)'));
 console.log('PASS 20 legal color combinations; red/green mutual exclusion and black exception; invalid settings; real db_meta save/failure; complete SQLite backup restore and old-backup defaults; theme resources; nested/system back guards (host only)');
}finally{worker.stdin.end();await new Promise(resolve=>worker.on('exit',resolve));fs.rmSync(temp,{recursive:true,force:true});}
