/** Host execution of pure ArkTS-compatible code; does not emulate HarmonyOS APIs. */
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
const compiler = process.env.P0_TYPESCRIPT_PATH ?? '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js';
const ts = require(compiler);
const cache = new Map();
function load(path) {
  path = resolve(path);
  if (cache.has(path)) return cache.get(path).exports;
  const module = { exports: {} }; cache.set(path, module);
  const source = readFileSync(path, 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }, reportDiagnostics: true });
  const errors = (output.diagnostics ?? []).filter(d => d.category === ts.DiagnosticCategory.Error);
  assert.equal(errors.length, 0, ts.formatDiagnosticsWithColorAndContext(errors, { getCurrentDirectory: () => root, getCanonicalFileName: f => f, getNewLine: () => '\n' }));
  vm.runInThisContext(`(function(require,module,exports){${output.outputText}\n})`, { filename: path })((id) => {
    assert.ok(id.startsWith('.'), `Native/external import forbidden in host suite: ${id}`);
    return load(resolve(dirname(path), id + '.ets'));
  }, module, module.exports);
  return module.exports;
}
const base = resolve(root, 'entry/src/main/ets');
const { Money } = load(base + '/core/money/Money.ets');
const { currencyUnit } = load(base + '/core/money/Currencies.ets');
const { AccountDraft, ACCOUNT_STYLES } = load(base + '/domain/model/AccountProfile.ets');
const { ACCOUNT_TYPES } = load(base + '/domain/model/AccountTypes.ets');
const command = (values={}) => ({ id:'test-account', name:'工资卡', kind:'asset', styleKey:'cash',
  includeInNetAssets:true, opening:Money.parse('0',currencyUnit('CNY')), ...values });
for (const type of ACCOUNT_TYPES) {
  assert.ok(ACCOUNT_STYLES.some(s => s.key === type.styleKey), type.key);
  const draft = new AccountDraft(command({accountType:type.key, kind:type.kind, styleKey:type.styleKey}));
  assert.equal(draft.command.accountType,type.key);
}
const input=command({accountType:'debit_card',issuerKey:'icbk',cardTail:'1234',note:'  工资卡  '});
const saved=new AccountDraft(input); input.note='changed';
assert.equal(saved.command.note,'工资卡');assert.equal(saved.command.cardTail,'1234');
for (const cardTail of ['1','12345','12a4','１２３４']) assert.throws(()=>new AccountDraft(command({accountType:'debit_card',cardTail})));
assert.throws(()=>new AccountDraft(command({accountType:'cash',cardTail:'1234'})));
assert.throws(()=>new AccountDraft(command({accountType:'cash',issuerKey:'icbk'})));
assert.throws(()=>new AccountDraft(command({accountType:'debit_card',issuerKey:'not-a-bank'})));
assert.throws(()=>new AccountDraft(command({accountType:'debit_card',issuerKey:'icbk_color'})));
assert.throws(()=>new AccountDraft(command({accountType:'huabei'})));
assert.throws(()=>new AccountDraft(command({note:'a'.repeat(501)})));
assert.equal(new AccountDraft(command()).command.accountType,'other_asset');
assert.equal(new AccountDraft(command({kind:'liability'})).command.accountType,'other_credit');
assert.equal(new AccountDraft(command({accountType:'debit_card',issuerKey:'other_bank'})).command.issuerKey,'other_bank');
const { BANK_ACCOUNT_STYLES }=load(base+'/domain/model/BankAccountStyles.ets');
const banks=BANK_ACCOUNT_STYLES.filter(b=>b.variant==='monochrome'&&!b.historical);
assert.equal(banks.length,146);
assert.ok(banks.every(b=>/^[A-Z]$/.test(b.indexLetter)));
assert.equal(banks.find(b=>b.name==='厦门银行').indexLetter,'X');
assert.equal(banks.find(b=>b.name==='重庆银行').indexLetter,'C');
console.log(`PASS ${ACCOUNT_TYPES.length} account types, metadata validation/snapshots, legacy commands, ${banks.length} indexed banks`);

// The type chooser defaults to white glyphs; colorful logos remain optional.
globalThis.$r=(id)=>id;
const { accountIcon }=load(base+'/presentation/ledger/AccountIcons.ets');
for (const type of ACCOUNT_TYPES) {
  const style=ACCOUNT_STYLES.find(s=>s.key===type.styleKey);
  assert.notEqual(style.variant,'color',type.key);
  const changedGlyphs = { meituan_credit: 'accounts_meituan', other_property: 'lucide_vault1', investment: 'lucide_chart_pie1' };
  if (changedGlyphs[type.key]) {
    assert.equal(accountIcon(style.key),'app.media.'+changedGlyphs[type.key],type.key);
  } else {
    assert.ok(!accountIcon(style.key).includes('lucide_'),type.key);
  }
}
for (const [key,resource] of [['lingqiantong','mini_fund'],['yuebao','yu_e_bao'],['bus','bus_card'],['campus','campus_card'],['fuel','gas_card'],['meal','food_card'],['stock','stock'],['futures','future']]) {
  assert.equal(accountIcon(ACCOUNT_TYPES.find(t=>t.key===key).styleKey),'app.media.accounts_'+resource);
}
console.log('PASS 43 default types avoid color variants; monthly payment, other assets and investments have distinct glyphs');

const { matchImportedAccount }=load(base+'/domain/model/ImportedAccountMatch.ets');
for (const type of ACCOUNT_TYPES) assert.equal(matchImportedAccount(type.name).accountType,type.key,type.name);
for (const [name,type,kind] of [
  ['微信零钱','wechat','asset'],['支付宝余额','alipay','asset'],['微信-零钱通','lingqiantong','asset'],
  ['支付宝余额宝','yuebao','asset'],['支付宝花呗','huabei','liability'],['借呗','jiebei','liability'],
  ['网商贷','mybank_loan','liability'],['微信分付','fenfu','liability'],['微粒贷','weilidai','liability'],
  ['京东白条','jd_baitiao','liability'],['京东金条','jd_jintiao','liability'],['抖音月付','douyin_credit','liability'],
  ['美团月付','meituan_credit','liability'],['校园卡','campus','asset'],['公积金账户','provident','asset'],
  ['会员储值卡','membership','asset'],['证券账户','stock','asset'],['现金','cash','asset'],
  ['贷款待还','other_credit','liability'],['未识别账户','other_asset','asset'],['支付宝/微信','other_asset','asset'],
  ['花呗/借呗','other_credit','liability'],['招商银行/中国银行','other_asset','asset']]) {
  const matched=matchImportedAccount(name);assert.equal(matched.accountType,type,name);assert.equal(matched.kind,kind,name);
  new AccountDraft(command({name,accountType:matched.accountType,kind:matched.kind,styleKey:matched.style.key,
    issuerKey:matched.issuerKey,cardTail:matched.cardTail}));
}
for (const [name,issuer,type,tail] of [
  ['招商银行信用卡（1234）','cmb','credit_card','1234'],['招行借记卡 尾号 5678','cmb','debit_card','5678'],
  ['中国工商银行储蓄卡','icbk','debit_card',''],['工行信用卡','icbk','credit_card',''],
  ['CCB 储蓄卡','ccbc','debit_card',''],['中行信用卡 ****9012','bkch','credit_card','9012'],
  ['招商银行12345678','cmb','debit_card',''],['信用卡(123)','other_bank','credit_card',''],
  ['信用卡 尾号12345','other_bank','credit_card','']]) {
  const matched=matchImportedAccount(name);assert.equal(matched.issuerKey,issuer,name);assert.equal(matched.accountType,type,name);assert.equal(matched.cardTail,tail,name);
}
for (const name of ['邮储储蓄卡','交行信用卡','浦发信用卡']) assert.notEqual(matchImportedAccount(name).issuerKey,'other_bank',name);
console.log('PASS import product/platform precedence, bank aliases, unambiguous tails and conservative fallback');

const { preferredBankStyle }=load(base+'/domain/model/BankAccountStyles.ets');
for (const bank of BANK_ACCOUNT_STYLES.filter(b=>b.variant==='monochrome')) {
  const chosen=preferredBankStyle(bank.key);
  assert.ok(chosen,bank.name);
  assert.equal(chosen.variant,bank.preferredVariant,bank.name);
  assert.equal(preferredBankStyle(bank.key+'_color').key,chosen.key,bank.name);
  new AccountDraft(command({accountType:'debit_card',styleKey:chosen.key,issuerKey:bank.key}));
}
assert.equal(preferredBankStyle('icbk').variant,'monochrome');
assert.equal(preferredBankStyle('other_bank'),undefined);
const minsheng=matchImportedAccount('民生银行信用卡（1234）');
assert.equal(minsheng.style.variant,'color');
assert.ok(!minsheng.issuerKey.endsWith('_color'));
assert.equal(minsheng.cardTail,'1234');
assert.equal(matchImportedAccount('工行储蓄卡').style.variant,'monochrome');
console.log('PASS per-bank appearance defaults, canonical issuer keys and import parity');

// Exercise the production snapshot with a minimal read-only native-store fixture.
const nativeSource=readFileSync(base+'/data/rdb/RdbAccountRepository.ets','utf8');
const nativeOutput=ts.transpileModule(nativeSource,{compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText;
const nativeModule={exports:{}};
vm.runInThisContext(`(function(require,module,exports){${nativeOutput}\n})`)((id)=>{
  if(id==='./RdbSession')return {RdbSession:{forStore:store=>({read:work=>work(store)})}};
  if(id==='@kit.ArkData')return {relationalStore:{}};
  if(id==='@kit.ArkTS')return {util:{}};
  assert.ok(id.startsWith('.'));
  return load(resolve(base+'/data/rdb',id+'.ets'));
},nativeModule,nativeModule.exports);
const fixtureAccounts=[['active','asset','CNY',true,false,10000],['archived','asset','CNY',true,true,7000],
  ['debt','liability','CNY',true,false,-2000],['old-debt','liability','CNY',true,true,-3000],
  ['excluded','asset','CNY',false,false,4000],['usd','asset','USD',true,false,5000],['old-eur','asset','EUR',true,true,6000]];
function resultRows(rows){let i=-1;return {rowCount:rows.length,goToNextRow:()=>++i<rows.length,getString:c=>String(rows[i][c]),
  getLong:c=>Number(rows[i][c]),isColumnNull:c=>rows[i][c]===null,close:()=>{}};}
const fixtureStore={querySql:async sql=>sql.includes('FROM accounts WHERE')?
  resultRows(fixtureAccounts.map(([id,kind,currency,include,archived])=>[id,id,kind,currency,'cash','cash','monochrome','#D49A38',include?1:0,1,archived?1:null,kind==='asset'?'other_asset':'other_credit','','',''])):
  resultRows(fixtureAccounts.map(([id,kind,currency,include,archived,balance])=>[id,String(balance)]))};
const repository=new nativeModule.exports.RdbAccountRepository(fixtureStore);
const overview=await repository.snapshot();assert.equal(overview.assetsMinor,'10000');assert.equal(overview.liabilitiesMinor,'2000');assert.equal(overview.netMinor,'8000');
assert.equal(overview.accounts.find(a=>a.id==='archived').balanceMinor,'7000');
assert.equal(overview.accounts.find(a=>a.id==='old-debt').balanceMinor,'-3000');
// Execute the actual workspace valuation method with a rate spy, without loading native app services.
const workspaceText=readFileSync(base+'/data/rdb/LedgerWorkspace.ets','utf8');
const workspaceAst=ts.createSourceFile('workspace.ts',workspaceText,ts.ScriptTarget.Latest,true);
const workspaceClass=workspaceAst.statements.find(n=>ts.isClassDeclaration(n)&&n.name?.text==='LedgerWorkspace');
const method=workspaceClass.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(workspaceAst)==='accountOverview');
const methodText=method.getText(workspaceAst).replace('async accountOverview','async function accountOverview');
const methodJS=ts.transpileModule(methodText,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
const requested=[];
const { ExchangeRate: TestExchangeRate }=load(base+'/core/money/ExchangeRate.ets');
const evaluate=vm.runInThisContext(`(function(RdbPrepaidRepository,OfficialExchangeRates,ExchangeRate,Money,currencyUnit){${methodJS};return accountOverview;})`);
const valueOverview=evaluate({projects:async()=>[{includeInNetAssets:true,remainingBookMinor:'3300'}]},
  {quote:async(code,to,date)=>{requested.push(code);if(code!=='USD')throw Error('Unexpected rate lookup');return {rate:'7',date};}},TestExchangeRate,Money,currencyUnit);
const valued=await valueOverview.call({accountRepository:repository,session:{read:work=>work({})},currency:currencyUnit('CNY')});
assert.deepEqual(requested,['USD']);assert.deepEqual(valued.valuationMissing,[]);
assert.equal(valued.assetsMinor,'48300');assert.equal(valued.liabilitiesMinor,'2000');assert.equal(valued.netMinor,'46300');
assert.equal(valued.prepaidMinor,'3300');
console.log('PASS production CNY snapshot and FX valuation exclude archived accounts, preserve balances and retain prepayments');
fixtureAccounts.find(a=>a[0]==='archived')[4]=false;
fixtureAccounts.find(a=>a[0]==='old-debt')[4]=false;
const restoredOverview=await repository.snapshot();
assert.equal(restoredOverview.assetsMinor,'17000');assert.equal(restoredOverview.liabilitiesMinor,'5000');assert.equal(restoredOverview.netMinor,'12000');
console.log('PASS restored accounts re-enter overview with unchanged stored balances');
