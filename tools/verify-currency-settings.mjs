/** Host tests run production money/settings/repository code against a temporary SQLite database. */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import readline from 'node:readline';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const base = path.resolve('entry/src/main/ets');
const cache = new Map(); let downloads = 0;
function load(file) {
  file = path.resolve(file); if (cache.has(file)) return cache.get(file).exports;
  const module = { exports: {} }; cache.set(file,module);
  const source = fs.readFileSync(file,'utf8');
  const code = ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
  vm.runInThisContext(`(function(require,module,exports,$r){${code}\n})`,{filename:file})(id => {
    if (id === '@kit.NetworkKit') return {http:{createHttp(){downloads++;throw Error('offline');}}};
    if (id === '@kit.ArkData') return {};
    if (id === '@kit.ArkUI') return {uiMaterial:{isImmersiveMaterialSupported:()=>true,ImmersiveStyle:{THICK:'thick'},ImmersiveMaterial:class{constructor(options){this.options=options;}}}};
    assert(id.startsWith('.'),id); return load(path.resolve(path.dirname(file),id+'.ets'));
  },module,module.exports,name=>name);
  return module.exports;
}
const currencies = load(base+'/core/money/Currencies.ets');
const config = load(base+'/core/money/CurrencySettings.ets');
const { OfficialExchangeRates: rates } = load(base+'/data/exchange/OfficialExchangeRates.ets');
const { RdbCurrencySettings } = load(base+'/data/rdb/RdbCurrencySettings.ets');
const { Money } = load(base+'/core/money/Money.ets');
const { ExchangeRate } = load(base+'/core/money/ExchangeRate.ets');
// Guard against ArkUI inherited-attribute collisions (e.g. scale/size/background).
const commonSource=ts.createSourceFile('common.d.ts',fs.readFileSync('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/component/common.d.ts','utf8'),ts.ScriptTarget.Latest,true);
const inherited=new Set();
for(const declaration of commonSource.statements){
  if((ts.isClassDeclaration(declaration)||ts.isInterfaceDeclaration(declaration)) && ['CommonMethod','CommonAttribute','BaseCustomComponent','CustomComponent'].includes(declaration.name?.text)){
    for(const member of declaration.members){if(member.name && (ts.isMethodDeclaration(member)||ts.isMethodSignature(member)||ts.isPropertyDeclaration(member)||ts.isPropertySignature(member))) inherited.add(member.name.getText(commonSource));}
  }
}
for(const component of ['ExchangeRatesPage','CurrencyManagerSheet','ExchangeRateField','CurrencyFlagBadge']){
  const source=fs.readFileSync(base+'/components/'+component+'.ets','utf8').replace('export struct','class');
  const tree=ts.createSourceFile(component+'.ts',source,ts.ScriptTarget.Latest,true);
  const cls=tree.statements.find(ts.isClassDeclaration);
  for(const member of cls.members){if(member.name && !['aboutToAppear','aboutToDisappear','build'].includes(member.name.getText(tree))) assert(!inherited.has(member.name.getText(tree)),component+': inherited attribute '+member.name.getText(tree));}
}
const quietMaterial=load(base+'/presentation/exchange/ExchangeSheetMaterial.ets').createExchangeSheetMaterial();
assert.equal(quietMaterial.options.interactive,false);assert.equal(quietMaterial.options.style,'thick');assert(!quietMaterial.options.lightEffect);
const profiles = config.currencyProfiles();
const original = config.currencySettings();
for (const flag of load(base+'/presentation/exchange/CurrencyFlags.ets').REGION_FLAGS) { config.validateCurrencySettings(profiles,{version:1,flags:[{code:'CNY',region:flag.region}],rates:[]}); }
const date = '2026-11-21';
const manual = (from,to,rate) => ({from,to,rate,date});
const custom = code => ({code,name:code,symbol:code,scale:2,enabled:true,custom:true});
config.installCurrencySettings([...profiles,custom('ABC'),custom('DEF')], {version:1,flags:[{code:'ABC',region:'cn'}],rates:[manual('USD','EUR','0.9'),manual('USD','ABC','3'),manual('EUR','DEF','4')]});
rates.days = [{date,rates:[{code:'EUR',rate:'1'},{code:'USD',rate:'1.1'},{code:'CNY',rate:'7.7'},{code:'JPY',rate:'165'}]}];
rates.fetchedAt = Date.now();
assert.equal((await rates.quote('USD','EUR',date)).rate,'0.9');
assert.equal((await rates.quote('EUR','USD',date)).rate,'1.111111111111');
assert.equal((await rates.quote('USD','EUR',date)).source,'manual');
assert.equal(downloads,0);
assert.equal((await rates.quote('ABC','DEF',date)).rate,'1.2');
assert.equal((await rates.quote('ABC','CNY',date)).rate,'2.333333333333');
assert.equal((await rates.quote('CNY','ABC',date)).rate,'0.428571428571');
assert.equal(config.configuredFlag('ABC'),'cn');
const unit = currencies.currencyUnit;
const historical = new ExchangeRate(unit('USD'),unit('CNY'),'7').convert(Money.parse('10',unit('USD')));
const changed = config.currencySettings(); changed.rates.push(manual('USD','CNY','8'));
config.installCurrencySettings(config.currencyProfiles(),changed);
assert.equal((await rates.quote('USD','CNY',date)).rate,'8');
assert.equal(historical.toDecimalString(),'70.00');
assert.equal(new ExchangeRate(unit('USD'),unit('CNY'),(await rates.quote('USD','CNY',date)).rate).convert(Money.parse('10',unit('USD'))).toDecimalString(),'80.00');
const disabled = config.currencyProfiles().map(p=>({...p,enabled:p.code!=='USD'}));
config.installCurrencySettings(disabled,changed);
assert(!config.enabledCurrencies().some(p=>p.code==='USD'));
assert(config.enabledCurrencies('USD').some(p=>p.code==='USD'));
assert.equal((await rates.quote('USD','CNY',date)).rate,'8');
for (const value of ['0','-1','1e3','NaN','0.0000000000001','12345678901234567']) assert(!config.validManualRate(value),value);
assert.throws(()=>config.validateCurrencySettings(disabled,{...changed,rates:[manual('USD','EUR','0')]}));
assert.throws(()=>config.validateCurrencySettings(disabled,{...changed,rates:[manual('USD','EUR','1'),manual('EUR','USD','1')]}));
config.installCurrencySettings([...disabled,custom('XYZ')],changed);
await assert.rejects(()=>rates.quote('XYZ','CNY',date),/FX_MANUAL_RATE_MISSING/);
// Restore automatic quote: removing the manual pair reveals the online rate.
config.installCurrencySettings(profiles,original);
assert.equal((await rates.quote('USD','EUR',date)).source,'ECB');
assert.equal((await rates.quote('USD','EUR',date)).rate,'0.909090909091');
// Fractions retain their exact numerator through paths, rounding only at the final quote.
const paths = config.manualRatePaths('ABC',[manual('USD','ABC','3'),manual('USD','EUR','0.9'),manual('EUR','DEF','4')]);
assert.equal(config.manualPathRate(paths.find(p=>p.code==='DEF')),'1.2');
console.log('PASS manual precedence, reciprocal/cross/custom rates, disabled selection/history, exact conversion and reset');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(),'xiaoqiao-fx-test-'));
const worker = spawn('python3',['-u','-c',`
import sqlite3,json,sys,os
root=sys.argv[1]
db=sqlite3.connect(os.path.join(root,'ledger.db'),isolation_level=None)
db.execute('PRAGMA foreign_keys=ON')
reader=None
for line in sys.stdin:
 try:
  c=json.loads(line)
  if c['op']=='schema': db.executescript(c['text']); result=None
  elif c['op']=='splitReads':
   db.execute('PRAGMA journal_mode=WAL'); reader=sqlite3.connect(os.path.join(root,'ledger.db'),isolation_level=None); result=None
  elif c['op']=='backup':
   other=sqlite3.connect(os.path.join(root,'backup.db')); db.backup(other); other.close(); result=None
  elif c['op']=='restore':
   other=sqlite3.connect(os.path.join(root,'backup.db')); other.backup(db); other.close(); result=None
  else:
   connection=reader if c['op']=='query' and reader is not None else db
   cur=connection.execute(c['sql'],c.get('args',[])); result=cur.fetchall() if c['op']=='query' else None
  print(json.dumps({'value':result}),flush=True)
 except Exception as e: print(json.dumps({'error':str(e)}),flush=True)
`,temporary],{stdio:['pipe','pipe','inherit']});
const lines = readline.createInterface({input:worker.stdout}); const pending=[];
lines.on('line',line=>{const next=pending.shift();const result=JSON.parse(line);result.error?next.reject(Error(result.error)):next.resolve(result.value);});
const rpc = request=>new Promise((resolve,reject)=>{pending.push({resolve,reject});worker.stdin.write(JSON.stringify(request)+'\n');});
const db = {
  async executeSql(sql,args=[]){await rpc({op:'exec',sql,args});},
  async insert(table,values){const keys=Object.keys(values);await this.executeSql(`INSERT INTO ${table}(${keys.join(',')}) VALUES(${keys.map(()=>'?').join(',')})`,Object.values(values));},
  async querySql(sql,args=[]){const rows=await rpc({op:'query',sql,args});let at=-1;return {rowCount:rows.length,goToNextRow(){return ++at<rows.length;},goToFirstRow(){at=0;return rows.length>0;},getString(i){return String(rows[at][i]);},getLong(i){return rows[at][i];},close(){}};}
};
let writeTail=Promise.resolve();
const session = {read:work=>work(db),write(work){const result=writeTail.then(async()=>{await db.executeSql('BEGIN');try{const result=await work(db);await db.executeSql('COMMIT');return result;}catch(error){await db.executeSql('ROLLBACK');throw error;}});writeTail=result.catch(()=>{});return result;}};
try {
  await rpc({op:'schema',text:fs.readFileSync('docs/database/schema-v1.sql','utf8')});
  for(const p of profiles) await db.insert('currencies',{id:p.code,code:p.code,name:p.name,symbol:p.symbol,minor_unit:p.scale,valid_from:'1999-01-01',source_version:'TEST',is_enabled:1});
  await rpc({op:'splitReads'});
  const repository = new RdbCurrencySettings(session); await repository.load();
  const saved = {version:1,flags:[{code:'ABC',region:'hk'}],rates:[manual('USD','ABC','3')]};
  await repository.save(custom('ABC'),saved);
  assert.equal(unit('ABC').scale,2);assert.equal(config.configuredFlag('ABC'),'hk');
  assert.equal((await rates.quote('ABC','USD',date)).rate,'0.333333333333');
  const {queryExchangeRates}=load(base+'/presentation/exchange/ExchangeRateQuery.ets');
  const displayed=await queryExchangeRates('USD',date,(from,to,day)=>rates.quote(from,to,day));
  assert.equal(displayed[0].code,'ABC');assert.equal(displayed[0].rate,'3');assert.equal(displayed[0].manual,true);
  // Recover the former 'committed but absent from runtime' case without modifying stored rows.
  config.installCurrencySettings(profiles,original);assert(!currencies.CURRENCIES.some(p=>p.code==='ABC'));
  await repository.load();assert(config.enabledCurrencies().some(p=>p.code==='ABC'));assert.equal(config.configuredFlag('ABC'),'hk');

  await rpc({op:'backup'});
  await repository.setEnabled(config.currencyProfiles().find(p=>p.code==='USD'),false);
  assert(!config.enabledCurrencies().some(p=>p.code==='USD'));
  // SQL failure rolls back both definition changes and JSON; no runtime publish.
  const before = JSON.stringify(config.currencyProfiles());
  await assert.rejects(()=>repository.save({...custom('ABC'),scale:3},saved));
  assert.equal(JSON.stringify(config.currencyProfiles()),before);
  await assert.rejects(()=>repository.save({...custom('ABC'),name:'changed'},{...saved,rates:[manual('USD','ABC','0')]}));
  assert.equal((await RdbCurrencySettings.read(db)).currencies.find(p=>p.code==='ABC').name,'ABC');
  // Real foreign keys protect used currencies, including archived/deleted accounts.
  await db.insert('accounts',{id:'a',name:'archived',kind:'asset',currency_id:'ABC',archived_at_ms:1,deleted_at_ms:2,created_at_ms:1,updated_at_ms:1});
  await assert.rejects(()=>repository.save(undefined,{version:1,flags:[],rates:[]},'ABC'),/FOREIGN KEY/);
  assert(config.currencyProfiles().some(p=>p.code==='ABC'));
  await repository.save(custom('DEF'),saved);
  await repository.save(undefined,saved,'DEF'); assert(!config.currencyProfiles().some(p=>p.code==='DEF'));
  await rpc({op:'restore'}); await repository.load();
  assert(config.enabledCurrencies().some(p=>p.code==='USD'));
  assert.equal(config.configuredFlag('ABC'),'hk');assert.equal((await rates.quote('USD','ABC',date)).rate,'3');
  // Old backups without the settings key restore defaults and remove custom definitions.
  await db.executeSql('DELETE FROM db_meta WHERE key=?',['currency_settings_v1']);
  await db.executeSql('DELETE FROM accounts'); await db.executeSql("DELETE FROM currencies WHERE id='ABC'");
  await repository.load(); assert(!currencies.CURRENCIES.some(p=>p.code==='ABC'));assert.equal(config.currencySettings().rates.length,0);
  // Execute production Sheet handlers against the same real repository.
  const sheetSource=fs.readFileSync(base+'/components/CurrencyManagerSheet.ets','utf8');
  const prefix=sheetSource.slice(sheetSource.indexOf('export struct'),sheetSource.indexOf('  @Builder')).replace('export struct','class')+'\n}';
  const tree=ts.createSourceFile('sheet.ts',prefix,ts.ScriptTarget.Latest,true);
  const cls=tree.statements.find(ts.isClassDeclaration);
  const methods=cls.members.filter(ts.isMethodDeclaration).map(m=>m.getText(tree)).join('\n');
  const flags=load(base+'/presentation/exchange/CurrencyFlags.ets');
  const scope={exports:{},...config,...currencies,...flags,$r:name=>name};
  vm.runInNewContext(ts.transpileModule('class Sheet {'+methods+'}\nexports.Sheet=Sheet;', {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,scope);
  const sheet=new scope.exports.Sheet();let notifications=0;const modes=[];let closes=0;const createdCodes=[];
  Object.assign(sheet,{workspace:{currencySettings:repository},baseCode:'CNY',initialTarget:'',working:false,revision:0,selectionVersions:new Map(),onSaved(code){notifications++;if(code)createdCodes.push(code);},onModeChanged(mode){modes.push(mode);},onClose(){closes++;}});
  let lastPicker;
  sheet.getUIContext=()=>({getPromptAction:()=>({showDialog:async()=>({index:1})}),showTextPickerDialog(options){lastPicker=options;}});
  sheet.aboutToAppear();sheet.edit(undefined);Object.assign(sheet,{code:'XYZ',name:'Test currency',symbol:'T',minorDigits:'2',region:'cn',rate:'4.5'});
  await sheet.save();assert.equal(sheet.error,'');assert.equal(sheet.mode,'list');assert.equal(notifications,1);assert.deepEqual(createdCodes,['XYZ']);assert.equal(sheet.visibleProfiles()[0].code,'XYZ');
  assert.equal((await rates.quote('CNY','XYZ',date)).rate,'4.5');
  sheet.edit(config.currencyProfiles().find(p=>p.code==='XYZ'),true);assert.equal(sheet.rate,'4.5');
  sheet.rate='0';await sheet.save();assert(sheet.error.includes('大于 0'));assert.equal((await rates.quote('CNY','XYZ',date)).rate,'4.5');
  sheet.rate='5';await sheet.save();assert.equal((await rates.quote('XYZ','CNY',date)).rate,'0.2');
  // A slow save for one card must not swallow the first tap on another card.
  const originalWorkspace=sheet.workspace;
  const staleProfile=sheet.profiles.find(p=>p.code==='XYZ');
  const usdProfile=sheet.profiles.find(p=>p.code==='USD');
  let finishWrite;let writeCount=0;
  const waiting=new Promise(resolve=>{finishWrite=resolve;});
  sheet.workspace={currencySettings:{async setEnabled(profile,enabled){writeCount++;await waiting;await repository.setEnabled(profile,enabled);}}};
  const firstTap=sheet.toggleSelection(staleProfile);
  assert.equal(sheet.isSelected('XYZ'),false);assert.equal(config.currencyProfiles().find(p=>p.code==='XYZ').enabled,true);
  const secondCardTap=sheet.toggleSelection(usdProfile);
  assert.equal(sheet.isSelected('XYZ'),false);assert.equal(sheet.isSelected('USD'),false);assert.equal(writeCount,2);
  assert.equal(sheet.profileKey(staleProfile),sheet.profileKey({...staleProfile,enabled:false}));
  finishWrite();await Promise.all([firstTap,secondCardTap]);sheet.workspace=originalWorkspace;
  assert.equal(sheet.isSelected('XYZ'),false);assert.equal(sheet.isSelected('USD'),false);
  assert.equal(config.currencyProfiles().find(p=>p.code==='XYZ').enabled,false);
  assert.equal(config.currencyProfiles().find(p=>p.code==='USD').enabled,false);
  sheet.editFromCard(staleProfile);assert.equal(sheet.original.enabled,false);sheet.setMode('list');
  await sheet.toggleSelection(staleProfile);assert.equal(sheet.isSelected('XYZ'),true);assert.equal(sheet.isSelected('USD'),false);
  // Repeated taps on the same card are queued, not silently dropped.
  let release;const slow=new Promise(resolve=>{release=resolve;});
  sheet.workspace={currencySettings:{async setEnabled(profile,enabled){await slow;await repository.setEnabled(profile,enabled);}}};
  const off=sheet.toggleSelection(staleProfile);const on=sheet.toggleSelection(staleProfile);
  assert.equal(sheet.isSelected('XYZ'),true);release();await Promise.all([off,on]);
  assert.equal(config.currencyProfiles().find(p=>p.code==='XYZ').enabled,true);sheet.workspace=originalWorkspace;
  // A failed save only rolls back its own card, preserving a successful change to another card.
  let failWrite;const failing=new Promise((_resolve,reject)=>{failWrite=reject;});
  sheet.workspace={currencySettings:{setEnabled(profile,enabled){return profile.code==='XYZ'?failing:repository.setEnabled(profile,enabled);}}};
  const failedTap=sheet.toggleSelection(staleProfile);assert.equal(sheet.isSelected('XYZ'),false);
  await sheet.toggleSelection(usdProfile);assert.equal(sheet.isSelected('USD'),true);
  failWrite(Error('disk failure'));await failedTap;
  assert.equal(sheet.isSelected('XYZ'),true);assert.equal(sheet.isSelected('USD'),true);
  assert.equal(config.currencyProfiles().find(p=>p.code==='XYZ').enabled,true);assert.equal(config.currencyProfiles().find(p=>p.code==='USD').enabled,true);
  assert(sheet.error.includes('保存失败'));sheet.workspace=originalWorkspace;sheet.error='';
  const otherRowKey=sheet.profileKey(config.currencyProfiles().find(p=>p.code==='JPY'));
  sheet.keyword='XYZ';sheet.mode='list';const toggleRevision=sheet.revision;const toggleModes=modes.length;
  await sheet.toggleSelection(config.currencyProfiles().find(p=>p.code==='XYZ'));
  assert.equal(sheet.keyword,'XYZ');assert.equal(sheet.revision,toggleRevision);assert.equal(modes.length,toggleModes);
  assert.equal(sheet.profileKey(config.currencyProfiles().find(p=>p.code==='JPY')),otherRowKey);
  assert(!config.enabledCurrencies().some(p=>p.code==='XYZ'));
  await sheet.toggleSelection(config.currencyProfiles().find(p=>p.code==='XYZ'));
  assert(config.enabledCurrencies().some(p=>p.code==='XYZ'));
  const noticesBefore=notifications;
  await sheet.toggleSelection(config.currencyProfiles().find(p=>p.code==='CNY'));
  assert.equal(notifications,noticesBefore);assert(config.enabledCurrencies().some(p=>p.code==='CNY'));
  const ui=fs.readFileSync(base+'/components/CurrencyManagerSheet.ets','utf8');
  assert(ui.includes('.align(Alignment.TopStart)'));
  assert.equal((ui.match(/edgeEffect\(EdgeEffect.Spring, \{ alwaysEnabled: true \}\)/g)||[]).length,3);
  assert(!ui.includes('EdgeEffect.None'));
  assert(ui.includes('Button({ type: ButtonType.Normal, stateEffect: false })'));
  assert(ui.includes("Button('编辑').stateEffect(false)"));
  const quotePage=fs.readFileSync(base+'/components/ExchangeRatesPage.ets','utf8');
  const baseSheet=quotePage.slice(quotePage.indexOf('private baseCurrencySheet()'),quotePage.indexOf('private baseSelector()'));
  assert(baseSheet.includes('.edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })'));
  assert(baseSheet.includes('stateEffect: false'));
  assert(baseSheet.includes('scrollForward: NestedScrollMode.SELF_ONLY'));
  assert(quotePage.includes('detents: [height], dragBar: false'));
  assert(quotePage.includes("this.managerMode === 'rate' ? '55%'"));
  const sheetRoot=quotePage.slice(quotePage.indexOf('private sheetContent()'),quotePage.indexOf('private baseCurrencySheet()'));
  assert(!sheetRoot.includes('Scroll()'));
  assert(!ui.includes('.focusable(true)'));
  assert(ui.includes(".borderRadius(16).backgroundColor($r('app.color.xq_exchange_form_panel_background'))"));
  assert(ui.includes('this.toggleSelection(profile)'));
  const management=ui.slice(ui.indexOf('private management()'),ui.indexOf('private editor()'));
  assert(!management.includes('Checkbox('));
  assert(!management.includes('Button({'));
  assert.equal((management.match(/this.toggleSelection\(profile\)/g)||[]).length,1);
  assert(management.includes('.monopolizeEvents(true).onClick(() => { this.editFromCard(profile); })'));
  assert(!ui.includes('stopPropagation'));
  assert(inherited.has('monopolizeEvents'));
  assert(management.indexOf('.onClick(() => { this.toggleSelection(profile); })') > management.indexOf("padding({ right: 12 }).borderRadius(14)"));
  const editProfile=config.currencyProfiles().find(p=>p.code==='USD');
  const noticesBeforeEdit=notifications;
  sheet.editFromCard(editProfile);
  assert.equal(sheet.mode,'edit');assert.equal(notifications,noticesBeforeEdit);
  assert.equal(config.currencyProfiles().find(p=>p.code==='USD').enabled,editProfile.enabled);
  assert.equal((ui.match(/scrollForward: NestedScrollMode.SELF_ONLY/g)||[]).length,3);
  assert.equal((ui.match(/scrollBackward: NestedScrollMode.SELF_ONLY/g)||[]).length,3);
  const flagPicker=ui.slice(ui.indexOf('private flagPicker()'),ui.indexOf('  build()'));
  assert(flagPicker.includes(".id('currency-no-flag-choice')"));
  assert(flagPicker.includes("Text('使用货币代码占位')"));
  assert(flagPicker.includes("backgroundColor($r('app.color.xq_exchange_form_field_background'))"));
  const editor=ui.slice(ui.indexOf('private editor()'),ui.indexOf('private flagPicker()'));
  for(const field of ['币种代码','货币名称','货币符号','小数位数','旗帜','兑换汇率']) assert(editor.includes("this.fieldLabel('"+field+"'"));
  assert(editor.includes('lucide_chevron_down1'));assert(editor.includes('lucide_chevron_right1'));
  assert(ui.includes("Text('不可修改')"));
  const rateField=fs.readFileSync(base+'/components/ExchangeRateField.ets','utf8');
  assert(rateField.includes('this.fieldFocused'));assert(rateField.includes("placeholder: '点击输入汇率'"));assert(rateField.includes('.borderRadius(12)'));
  sheet.mode='rate';sheet.initialTarget='USD';assert.equal(sheet.showBack(),false);
  sheet.initialTarget='';assert.equal(sheet.showBack(),true);
  sheet.mode='list';assert.equal(sheet.showBack(),false);
  sheet.mode='flags';assert.equal(sheet.showBack(),true);
  sheet.focusedField='name';assert.equal(sheet.fieldBorder('name'),'app.color.xq_brand');assert.equal(sheet.fieldBorder('symbol'),'app.color.xq_exchange_form_border');
  sheet.original=editProfile;lastPicker=undefined;sheet.chooseMinorDigits();assert.equal(lastPicker,undefined);
  sheet.edit(undefined);sheet.chooseMinorDigits();assert(lastPicker);assert.equal(lastPicker.range.length,5);
  lastPicker.onAccept({index:4});assert.equal(sheet.minorDigits,'4');
  assert(ui.includes('Text(this.profileName(profile.code))'));
  assert(management.includes('.fill(this.isSelected(profile.code)'));
  assert(!management.includes('profile.enabled'));
  assert(!management.includes('.enabled(!this.working).hoverEffect'));assert(!ui.includes("Text(profile.name + ':'"));
  await sheet.toggle(config.currencyProfiles().find(p=>p.code==='XYZ'),false);
  assert(!config.enabledCurrencies().some(p=>p.code==='XYZ'));assert.equal((await rates.quote('XYZ','CNY',date)).rate,'0.2');
  sheet.initialTarget='XYZ';sheet.edit(config.currencyProfiles().find(p=>p.code==='XYZ'),true);sheet.rate='6';await sheet.save();assert.equal(closes,1);assert.equal(sheet.mode,'rate');sheet.initialTarget='';
  sheet.edit(config.currencyProfiles().find(p=>p.code==='XYZ'),true);assert.equal(sheet.canRestoreOnline(),false);await sheet.resetRate();
  assert.equal((await rates.quote('CNY','XYZ',date)).rate,'6');
  sheet.baseCode='XYZ';sheet.edit(config.currencyProfiles().find(p=>p.code==='USD'),true);assert.equal(sheet.canRestoreOnline(),false);
  sheet.baseCode='CNY';sheet.edit(config.currencyProfiles().find(p=>p.code==='CNY'),true);assert.equal(sheet.canRestoreOnline(),false);
  sheet.edit(config.currencyProfiles().find(p=>p.code==='USD'),true);assert.equal(sheet.canRestoreOnline(),true);
  sheet.rate='0.2';await sheet.save();assert.equal((await rates.quote('CNY','USD',date)).source,'manual');
  sheet.edit(config.currencyProfiles().find(p=>p.code==='USD'),true);await sheet.resetRate();
  assert.equal((await rates.quote('CNY','USD',date)).source,'ECB');
  sheet.edit(config.currencyProfiles().find(p=>p.code==='XYZ'));await sheet.remove();assert(!currencies.CURRENCIES.some(p=>p.code==='XYZ'));
  sheet.aboutToDisappear();
  console.log('PASS production Sheet handlers: create/edit/invalid rate/single-tap feedback/multi-card preservation/repeated taps/stable row identity/isolated rollback/CNY guard/reset/delete');
  console.log('PASS production repository with separate SQLite reader/writer: new currency published after commit, quote/list visibility, stale runtime reload, rollback, FK guards and backup/restore');
} finally {worker.stdin.end();await new Promise(resolve=>worker.on('exit',resolve));fs.rmSync(temporary,{recursive:true,force:true});}
