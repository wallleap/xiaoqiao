/** Execute budget render/load/save methods without assuming a component getter is installed by ArkUI. */
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const base = path.resolve(import.meta.dirname, '../entry/src/main/ets');
const cache = new Map();
function load(file) {
 file=path.resolve(file);if(cache.has(file))return cache.get(file).exports;
 const module={exports:{}};cache.set(file,module);
 const code=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
 vm.runInThisContext(`(function(require,module,exports){${code}\n})`,{filename:file})(id=>load(path.resolve(path.dirname(file),id+'.ets')),module,module.exports);
 return module.exports;
}
const {currencyUnit,currencyDefinition}=load(base+'/core/money/Currencies.ets');
const {CurrencyUnit}=load(base+'/core/money/CurrencyUnit.ets');
const {Money}=load(base+'/core/money/Money.ets');
const {ExpenseAmountInput}=load(base+'/presentation/ledger/ExpenseAmountInput.ets');
const source=fs.readFileSync(process.env.XQ_BUDGET_TEST_SOURCE || base+'/components/BudgetPage.ets','utf8');
const tree=ts.createSourceFile('budget.ts',source.replace('export struct','class'),ts.ScriptTarget.Latest,true);
const cls=tree.statements.find(ts.isClassDeclaration);
const names=['amountCurrency','symbol','amount','load','validTotal','validNature','sumAllocated','unallocated','editNature','saveTotal','saveNature'];
const methods=cls.members.filter(m=>ts.isMethodDeclaration(m)&&names.includes(m.name.getText(tree))).map(m=>m.getText(tree)).join('\n');
const overview=ts.createSourceFile('overview.ts',fs.readFileSync(base+'/presentation/ledger/LedgerOverview.ets','utf8'),ts.ScriptTarget.Latest,true);
const format=overview.statements.find(m=>ts.isFunctionDeclaration(m)&&m.name?.text==='displayAmount').getText(overview).replace('export ','');
const context={exports:{},currencyUnit,currencyDefinition,CurrencyUnit,Money,ExpenseAmountInput};
vm.runInNewContext(ts.transpileModule(format+'\nclass Page{'+methods+'}\nexports.Page=Page;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,context);
function page(extra={}){return Object.assign(new context.exports.Page(),{totalInput:'0',natureInput:'0',loading:true,busy:false,monthKey:'2026-11',error:'',...extra});}
// Same symbol() and amount() invoked on the first render at the reported crash site.
let p=page();assert.equal(p.symbol(),'¥');assert.equal(p.amount('0'),'0.00');assert.equal(p.validTotal(),true);
p=page({workspace:{}});assert.equal(p.symbol(),'¥');assert.equal(p.amount('123'),'1.23');
p=page({workspace:{bookCurrency:currencyUnit('JPY')},totalInput:'12.3'});assert.equal(p.symbol(),currencyDefinition('JPY').symbol);assert.equal(p.amount('123'),'123');assert.equal(p.validTotal(),false);
p.totalInput='12';assert.equal(p.validTotal(),true);p.natureInput='0.1';assert.equal(p.validNature(),false);
p=page({snapshot:{currencyId:'USD',budgetTotalMinor:'10000',budgetNatureLines:[{amountMinor:'2500'}]},workspace:{bookCurrency:currencyUnit('JPY')}});
assert.equal(p.symbol(),'$');assert.equal(p.amount(p.sumAllocated().toString()),'25.00');assert.equal(p.unallocated(),'7500');
let saved;let closed=0;let stopped=0;
p=page({workspace:{bookCurrency:currencyUnit('JPY'),snapshot:async()=>({currencyId:'JPY',budgetTotalMinor:'2500',budgetNatureLines:[]}),setMonthlyBudget:async(month,amount)=>{saved={month,amount};}},onClose:()=>closed++,totalController:{stopEditing(){stopped++;}}});
assert.equal(p.symbol(),currencyDefinition('JPY').symbol);await p.load();assert.equal(p.totalInput,'2500');assert.equal(p.loading,false);
p.totalInput='3000';await p.saveTotal();assert.deepEqual(saved,{month:'2026-11',amount:'3000'});assert.equal(closed,1);assert.equal(stopped,1);assert.equal(p.busy,false);
p=page({workspace:{bookCurrency:currencyUnit('USD'),snapshot:async()=>{throw Error('read failed');}}});await p.load();assert.match(p.error,/预算暂时无法读取/);assert.equal(p.symbol(),'$');assert.equal(p.amount('0'),'0.00');assert.equal(p.loading,false);
p=page();await p.load();assert.equal(p.loading,false);assert.equal(p.symbol(),'¥');
assert(!/this\.currency\b|private get currency/.test(source));
assert.match(source,/fieldId: 'ledger-budget-input', currency: this\.amountCurrency\(\)/);
assert.match(source,/fieldId: 'budget-nature-input', currency: this\.amountCurrency\(\)/);
console.log('PASS budget first-render symbol/amount, missing workspace/metadata, snapshot currency, JPY precision, load/save and read failure (host methods only)');
