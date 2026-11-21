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
class Predicates{constructor(table){this.table=table;this.where=[];this.args=[];}equalTo(k,v){this.where.push(k+'=?');this.args.push(v);return this;}}
function load(file){file=path.resolve(file);if(cache.has(file))return cache.get(file).exports;const m={exports:{}};cache.set(file,m);const code=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText;vm.runInThisContext(`(function(require,module,exports){${code}\n})`,{filename:file})(id=>id.startsWith('.')?load(path.resolve(path.dirname(file),id+'.ets')):id==='@kit.ArkTS'?{util:{generateRandomUUID:()=>crypto.randomUUID()}}:id==='@kit.ArkData'?{relationalStore:{RdbPredicates:Predicates}}:{},m,m.exports);return m.exports;}
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'xq-book-delete-'));
const fixture=spawnSync('python3',['-c',`
import sys,sqlite3
sys.path.insert(0,sys.argv[1]+'/docs/database')
from verify_book_deletion import BookDeletionTests
f=BookDeletionTests();f.setUp();f.expense('a',amount=500);f.expense('b',book='b2',amount=200)
f.db.execute("UPDATE books SET archived_at_ms=3 WHERE id='b1'")
f.db.execute("INSERT INTO book_deletion_files VALUES('images/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png')")
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
const db={async querySql(sql,args=[]){const rows=await rpc({op:'query',sql,args});let at=-1;return{rowCount:rows.length,columnCount:rows[0]?.length||0,goToFirstRow(){at=0;return rows.length>0;},goToNextRow(){return ++at<rows.length;},getString(i){return String(rows[at][i]);},getLong(i){return Number(rows[at][i]);},isColumnNull(i){return rows[at][i]===null;},close(){}};},async executeSql(sql,args=[]){await rpc({op:'exec',sql,args});},async insert(table,values){const keys=Object.keys(values);await this.executeSql(`INSERT INTO ${table}(${keys}) VALUES(${keys.map(()=>'?')})`,Object.values(values));},async delete(p){return rpc({op:'exec',sql:`DELETE FROM ${p.table} WHERE ${p.where.join(' AND ')}`,args:p.args});}};
let tail=Promise.resolve();const session={read(fn){const result=tail.then(()=>fn(db));tail=result.catch(()=>{});return result;},write(fn){const result=tail.then(async()=>{await db.executeSql('BEGIN');try{const result=await fn(db);await db.executeSql('COMMIT');return result;}catch(e){await db.executeSql('ROLLBACK');throw e;}});tail=result.catch(()=>{});return result;}};
try{
 const {RdbBookDeletion}=load(base+'/data/rdb/RdbBookDeletion.ets');
 const schema=load(base+'/data/rdb/BookDeletionSchema.ets');assert.equal(schema.BOOK_DELETION_SCHEMA_SHA256,crypto.createHash('sha256').update(fs.readFileSync(root+'/docs/database/schema-v12-book-deletion.sql')).digest('hex'));
 let failRemove=true;const removed=[];
 const resources={async remove(kind,file){if(failRemove)throw Error('file busy');removed.push({kind,file});}};
 const service=new RdbBookDeletion(session,resources);
 await assert.rejects(service.execute('b2',1),/BOOK_DELETE_UNAVAILABLE/);
 await assert.rejects(service.execute('b1',2),/BOOK_DELETE_UNAVAILABLE/);
 assert.equal((await db.querySql("SELECT id FROM books WHERE id='b1'")).rowCount,1);
 assert.equal((await db.querySql('SELECT * FROM book_deletion_context')).rowCount,0);
 const before=await rpc({op:'query',sql:'SELECT account_id,balance_minor FROM v_account_balances ORDER BY account_id'});
 const result=await service.execute('b1',1);assert.equal(result.cleanupPending,true);assert.equal('backupUri' in result,false);
 assert.equal(fs.readdirSync(temp).some(name=>name.endsWith('.xqbackup')),false);
 assert.deepEqual(await rpc({op:'query',sql:'SELECT account_id,balance_minor FROM v_account_balances ORDER BY account_id'}),before);
 assert.equal((await db.querySql("SELECT id FROM books WHERE id='b1'")).rowCount,0);assert.equal((await db.querySql("SELECT id FROM transactions WHERE book_id='b1'")).rowCount,0);
 assert.equal((await db.querySql("SELECT id FROM transactions WHERE book_id='b2'")).rowCount,1);
 failRemove=false;assert.equal(await service.cleanup(),false);assert.deepEqual(removed,[{kind:'images',file:'images/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png'}]);
 assert.equal((await db.querySql('SELECT * FROM book_deletion_files')).rowCount,0);
 // Real UI handler: cancellation and direct confirmed deletion without a file picker.
 const source=fs.readFileSync(base+'/pages/Index.ets','utf8'),tree=ts.createSourceFile('index.ts',source.replace('struct Index','class Index'),ts.ScriptTarget.Latest,true),cls=tree.statements.find(ts.isClassDeclaration);
 const method=cls.members.find(m=>ts.isMethodDeclaration(m)&&m.name.getText(tree)==='deleteBook').getText(tree);
 let answer=0,calls=0,dialogs=0;
 const context={exports:{},$r:x=>x};
 vm.runInNewContext(ts.transpileModule('class Page{'+method+'}exports.Page=Page;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,context);
 const p=new context.exports.Page();Object.assign(p,{workspace:{deleteArchivedBook:async(...args)=>{calls++;assert.deepEqual(args,['archived',1]);return{cleanupPending:false};},books:async()=>[]},getUIContext:()=>({getHostContext:()=>({}),getPromptAction:()=>({showDialog:async()=>{dialogs++;return{index:answer};}})}),todayText:()=> '2026-11-21',loadLedger:async()=>{},notify:()=>{}});
 await p.deleteBook({id:'active',archived:false});assert.equal(dialogs,0);
 await p.deleteBook({id:'archived',revision:1,archived:true});assert.equal(calls,0);assert.equal(p.bookBusy,false);
 answer=1;await p.deleteBook({id:'archived',revision:1,archived:true});assert.equal(calls,1);assert.equal(p.bookBusy,false);
 assert(!method.includes('picker'));assert(!method.includes('备份后删除'));
 console.log('PASS production delete repository: no-backup direct deletion, revision guard, physical removal, exact balances, cleanup retry and UI archived/cancel gating (host only)');
}finally{worker.stdin.end();await new Promise(resolve=>worker.on('exit',resolve));fs.rmSync(temp,{recursive:true,force:true});}
