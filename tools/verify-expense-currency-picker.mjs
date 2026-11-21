/** Host tests of production amount policy and extracted editor event handlers; no native UI runtime. */
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
  file = path.resolve(file);
  if (cache.has(file)) return cache.get(file).exports;
  const module = { exports: {} }; cache.set(file, module);
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  vm.runInThisContext(`(function(require,module,exports){${code}\n})`, { filename: file })(id => { assert(id.startsWith('.')); return load(path.resolve(path.dirname(file), id + '.ets')); }, module, module.exports);
  return module.exports;
}
const { prepareCurrencySwitch } = load(base + '/presentation/ledger/CurrencySwitchDraft.ets');
const { currencyUnit } = load(base + '/core/money/Currencies.ets');
const { enabledCurrencies, currencyProfiles, currencySettings, installCurrencySettings } = load(base + '/core/money/CurrencySettings.ets');
const draft = { amount: '12.30+2.00', discount: '0.30', fee: '1.00', coupon: '0' };
assert.equal(prepareCurrencySwitch(draft, currencyUnit('USD'), 'expense').amount, '12.3+2');
assert.equal(draft.amount, '12.30+2.00');
assert.throws(() => prepareCurrencySwitch(draft, currencyUnit('JPY'), 'expense'), /金额/);
assert.equal(prepareCurrencySwitch({ ...draft, amount: '12.00', discount: '0.00' }, currencyUnit('JPY'), 'expense').amount, '12');
for (const amount of ['12+', '-1', '0−1', '9007199254740992', '1'.repeat(65)]) {
  assert.throws(() => prepareCurrencySwitch({ ...draft, amount }, currencyUnit('USD'), 'expense'));
}
for (const [field, label] of [['discount', '优惠'], ['fee', '手续费'], ['coupon', '抵扣金额']]) {
  assert.throws(() => prepareCurrencySwitch({ amount: '12', discount: '0', fee: '0', coupon: '0', [field]: '0.1' }, currencyUnit('JPY'), field === 'discount' ? 'expense' : 'transfer'), new RegExp(label));
}
assert.equal(prepareCurrencySwitch({ ...draft, amount: '0', discount: 'invalid' }, currencyUnit('JPY'), 'income').amount, '0');
const profiles = currencyProfiles(), settings = currencySettings();
installCurrencySettings([...profiles.map(p => ({ ...p, enabled: p.code !== 'EUR' })), { code: 'ABC', name: '自定义币', symbol: 'A', scale: 4, enabled: true, custom: true }], settings);
assert.equal(prepareCurrencySwitch({ ...draft, amount: '1.2345' }, currencyUnit('ABC'), 'expense').amount, '1.2345');
const source = fs.readFileSync(base + '/components/ExpenseEditor.ets', 'utf8');
const tree = ts.createSourceFile('editor.ts', source.replace('export struct', 'class'), ts.ScriptTarget.Latest, true);
const cls = tree.statements.find(s => ts.isClassDeclaration(s) && s.name.text === 'ExpenseEditor');
const names = ['applyCurrency', 'currencyChoices', 'selectCurrency', 'focusAmount', 'currencySheetOptions', 'prepareSaveRates', 'save'];
const methods = names.map(name => cls.members.find(m => ts.isMethodDeclaration(m) && m.name.getText(tree) === name).getText(tree)).join('\n');
const code = ts.transpileModule('class Editor {' + methods + '}\nexports.Editor=Editor;', { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
const service = { quote: async (from, to, date) => ({ from, to, rate: from === to ? '1' : '7.2', date, source: from === to ? 'same_currency' : 'manual' }) };
const { ExpenseAmountInput } = load(base + '/presentation/ledger/ExpenseAmountInput.ets');
const context = { OfficialExchangeRates: service, ExpenseAmountInput, ExpenseErrorField: { Amount: 'amount', Category: 'category', Save: 'save' }, exports: {}, prepareCurrencySwitch, currencyUnit, enabledCurrencies, $r: x => x, SheetKeyboardAvoidMode: { TRANSLATE_AND_RESIZE: 'resize' } };
vm.runInNewContext(code, context);
function editor(extra = {}) {
  const page = new context.exports.Editor();
  Object.assign(page, { active: true, saving: false, currencyCode: 'CNY', expression: '12.34', discount: '0.04', transferFee: '1.01', transferCoupon: '0.01',
    bookRate: '7', settlementRate: '8', actualSettlement: '99', quoteDate: '2026-11-20', quoteSource: 'ECB', quoteVersion: 1,
    showCurrencyPicker: true, currencySearch: '', currencyError: '', accountId: 'cny', toAccountId: 'recipient',
    accounts: [{ id: 'cny', currencyId: 'CNY' }, { id: 'usd', currencyId: 'USD' }], ...extra });
  return page;
}
let p = editor(); const original = JSON.stringify(p); p.applyCurrency('CNY');
assert.equal(JSON.stringify(p), original.replace('"showCurrencyPicker":true', '"showCurrencyPicker":false'));
p = editor(); p.applyCurrency('USD');
assert.equal(p.currencyCode, 'USD'); assert.equal(p.expression, '12.34'); assert.equal(p.discount, '0.04');
assert.equal(p.transferFee, '1.01'); assert.equal(p.transferCoupon, '0.01');
for (const key of ['bookRate', 'settlementRate', 'actualSettlement', 'quoteDate']) assert.equal(p[key], '');
assert.equal(p.quoteSource, 'manual'); assert.equal(p.quoteVersion, 2); assert.equal(p.showCurrencyPicker, false);
p = editor(); p.applyCurrency('JPY'); assert.equal(p.currencyCode, 'CNY'); assert.equal(p.bookRate, '7'); assert.equal(p.showCurrencyPicker, true); assert.match(p.currencyError, /0 位小数/);
for (const accountId of ['cny', 'usd']) {
  p = editor({ isTransfer: true, accountId }); p.applyCurrency('USD');
  assert.equal(p.accountId, accountId === 'usd' ? 'usd' : ''); assert.equal(p.toAccountId, 'recipient');
}
for (const guard of [{ active: false }, { saving: true }, { editingEntry: {} }, { quoteBusy: true }]) {
  p = editor(guard); p.applyCurrency('USD'); assert.equal(p.currencyCode, 'CNY');
}
p = editor(); p.applyCurrency('EUR'); assert.equal(p.currencyCode, 'CNY');
p.currencySearch = '美元'; assert.equal(p.currencyChoices()[0].code, 'USD');
p.currencySearch = ' abc '; assert.equal(p.currencyChoices()[0].name, '自定义币');
p.currencySearch = ''; assert(!p.currencyChoices().some(x => x.code === 'EUR'));
p = editor({ showCurrencyPicker: false, keyboardVisible: true });
let stopped = 0, cleared = 0, focused = 0;
p.amountController = { stopEditing() { stopped++; } };
p.getUIContext = () => ({ getFocusController: () => ({ clearFocus() { cleared++; }, requestFocus() { focused++; } }) });
let release; p.loadCurrencyMaterial = () => new Promise(resolve => { release = resolve; });
const opening = p.selectCurrency(); assert.equal(stopped, 1); assert.equal(cleared, 1); assert.equal(p.keyboardVisible, false);
p.focusAmount(); assert.equal(focused, 0); await p.selectCurrency(); assert.equal(stopped, 1);
release(); await opening; assert.equal(p.showCurrencyPicker, true); p.focusAmount(); assert.equal(focused, 0);
p.showCurrencyPicker = false; p.focusAmount(); assert.equal(focused, 1);
p.preparingCurrencyMaterial = undefined; const closing = p.selectCurrency(); p.active = false; release(); await closing;
assert.equal(p.showCurrencyPicker, false); assert.equal(p.openingCurrencyPicker, false);
assert.equal(p.currencySheetOptions().height, '75%');
const picker = source.slice(source.indexOf('private currencyPicker()'), source.indexOf('private async prepareSaveRates()'));
assert.match(picker, /edgeEffect\(EdgeEffect.Spring, \{ alwaysEnabled: true \}\)/);
assert.match(picker, /stateEffect: false/); assert.match(picker, /currency\.code\)\.onClick/);
assert.match(source, /this\.currencySheetMaterial = factory\.createExchangeSheetMaterial\(\)/);
assert(!source.includes('stopPropagation'));

// New records fetch shared manual/online rates only when saving; editing preserves the saved snapshot.
p = editor(); p.currencyCode = 'USD'; p.settlementCode = () => 'EUR'; p.fxDate = () => '2026-11-21';
await p.prepareSaveRates(); assert.equal(p.bookRate, '7.2'); assert.equal(p.settlementRate, '7.2'); assert.equal(p.quoteSource, 'manual'); assert.equal(p.quoteBusy, false);
let quoteCalls = 0;
service.quote = async () => { quoteCalls++; throw new Error('offline'); };
p.editingEntry = {}; await p.prepareSaveRates(); assert.equal(quoteCalls, 0); assert.equal(p.bookRate, '7.2');
p.editingEntry = undefined; await assert.rejects(p.prepareSaveRates(), /FX_SAVE_UNAVAILABLE/); assert.equal(p.quoteBusy, false);
p = editor(); p.settlementCode = () => 'CNY'; p.fxDate = () => '2026-11-21';
quoteCalls = 0; await p.prepareSaveRates(); assert.equal(quoteCalls, 0);
let resolveQuote;
service.quote = (from, to, date) => new Promise(resolve => { resolveQuote = () => resolve({ from, to, rate: '7.2', date, source: 'manual' }); });
p = editor({ currencyCode: 'USD' }); p.settlementCode = () => 'USD'; p.fxDate = () => '2026-11-21';
const pendingRate = p.prepareSaveRates(); p.active = false; resolveQuote();
await new Promise(resolve => setImmediate(resolve)); resolveQuote();
await assert.rejects(pendingRate, /FX_SAVE_UNAVAILABLE/); assert.equal(p.bookRate, '7');
// Execute production save: lookup failure never writes, releases saving state, and gives an actionable error.
service.quote = async () => { throw new Error('offline'); };
p = editor({ currencyCode: 'USD', selectedId: 'food', selectedNatureId: '', selectedTagIds: [], note: '', merchantName: '', addressText: '' });
p.amountCurrency = () => currencyUnit(p.currencyCode); p.effectiveDiscount = () => p.discount;
p.prepaidMode = () => false; p.settlementCode = () => 'USD'; p.fxDate = () => '2026-11-21';
let writes = 0; const savingEvents = [];
p.workspace = { saveExpense: async () => { writes++; } };
p.onSavingChange = value => savingEvents.push(value); p.showError = (_field, message) => { p.errorText = message; };
await p.save(); assert.equal(writes, 0); assert.equal(p.saving, false); assert.deepEqual(savingEvents, [true, false]); assert.match(p.errorText, /尚未保存/);
// Successful save uses the global quote and retains the entered foreign amount.
service.quote = async (from, to, date) => ({ from, to, rate: from === to ? '1' : '7.2', date, source: from === to ? 'same_currency' : 'manual' });
const { ExchangeRate } = load(base + '/core/money/ExchangeRate.ets');
p.converted = (amount, code, rate) => amount.currency.code === code ? amount : new ExchangeRate(amount.currency, currencyUnit(code), rate).convert(amount);
p.fxQuote = rate => ({ rate, source: p.quoteSource }); p.settlementAmount = amount => amount;
p.attachmentDrafts = () => []; p.localDate = () => '2026-11-21'; p.onSaved = () => {};
p.workspace.saveExpense = async command => { writes++; assert.equal(command.gross.toDecimalString(), '12.34'); assert.equal(command.bookPaid.toDecimalString(), '88.56'); assert.equal(command.bookFx.source, 'manual'); };
await p.save(); assert.equal(writes, 1); assert.equal(p.saved, true); assert.equal(p.saving, false);
const fxCard = source.slice(source.indexOf('private fxCard()'), source.indexOf('private prepaidMode()'));
assert(!/TextInput|MoneyAmountField|获取参考汇率|bookAmountText|实际到账/.test(fxCard));

installCurrencySettings(profiles, settings);
console.log('PASS: currency list selection, amount/precision policy, FX invalidation, accounts, focus, automatic save quotes and failure-before-write (host only)');
