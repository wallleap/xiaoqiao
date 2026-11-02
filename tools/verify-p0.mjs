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
const { CurrencyUnit } = load(base + '/core/money/CurrencyUnit.ets');
const { Money } = load(base + '/core/money/Money.ets');
const { ExchangeRate } = load(base + '/core/money/ExchangeRate.ets');
const { ExpenseRecord } = load(base + '/domain/model/ExpenseRecord.ets');
const { RecordExpense } = load(base + '/domain/services/RecordExpense.ets');
let count = 0;
async function test(name, run) { await run(); count++; console.log(`PASS ${name}`); }
const cny = new CurrencyUnit('CNY-v1', 'CNY', 2);
const usd = new CurrencyUnit('USD-v1', 'USD', 2);
for (const [code, scale, input, minor] of [['JPY',0,'123','123'],['CNY',2,'0.01','1'],['KWD',3,'12.345','12345'],['CLF',4,'0.0001','1']]) {
  await test(`currency scale ${scale}`, () => { const money = Money.parse(input, new CurrencyUnit(code,code,scale)); assert.equal(money.minor.toString(),minor); assert.equal(money.toDecimalString(),input); });
}
await test('precision rejected instead of truncated', () => { for (const text of ['1.001','1e3','NaN','1,000','+1','1.']) assert.throws(() => Money.parse(text,cny)); });
await test('negative arithmetic remains exact', () => assert.equal(Money.parse('0.10',cny).subtract(Money.parse('0.30',cny)).toDecimalString(),'-0.20'));
await test('currency definition version mismatch rejected', () => assert.throws(() => Money.parse('1',cny).add(Money.parse('1',new CurrencyUnit('CNY-v2','CNY',2)))));
await test('BigInt JSON round trip uses strings', () => { const m=Money.fromMinorText('900719925474099312345',cny); const data=JSON.parse(JSON.stringify(m.toData())); assert.equal(Money.fromData(data,cny).minor,m.minor); assert.throws(()=>m.toSafeMinorNumber()); });
await test('persistence safe integer boundary', () => { assert.equal(Money.fromMinorText('9007199254740991',cny).toSafeMinorNumber(),9007199254740991); assert.throws(()=>Money.fromMinorText('-9007199254740992',cny).toSafeMinorNumber()); });
await test('exchange rounds once HALF_UP, including negative ties', () => { const rate=new ExchangeRate(usd,cny,'0.5'); assert.equal(rate.convert(Money.parse('0.01',usd)).toDecimalString(),'0.01'); assert.equal(rate.convert(Money.parse('-0.01',usd)).toDecimalString(),'-0.01'); assert.equal(rate.convert(Money.parse('0.02',usd)).toDecimalString(),'0.01'); });
await test('exchange scale conversion and rate validation', () => { assert.equal(new ExchangeRate(usd,new CurrencyUnit('JPY','JPY',0),'150.123').convert(Money.parse('1.23',usd)).toDecimalString(),'185'); for(const rate of ['0','-1','1e2','NaN']) assert.throws(()=>new ExchangeRate(usd,cny,rate)); });
const command = () => ({id:'expense-1',bookId:'book-1',categoryId:'food',gross:Money.parse('30',cny),discount:Money.parse('2',cny),bookPaid:Money.parse('28',cny),accountId:'cash',accountPaid:Money.parse('28',cny),includeInAssets:true,includeInBudget:true,note:'午餐',occurredAtMs:1790830800000,localDate:'2026-10-01',timezone:'Asia/Shanghai',offsetMinutes:480});
await test('expense discount, independent flags, input snapshot', () => { const c=command(); c.includeInAssets=false; const r=new ExpenseRecord(c); c.note='changed'; assert.equal(r.paid.minor,2800n); assert.equal(r.command.note,'午餐'); assert.equal(r.command.includeInAssets,false); assert.equal(r.command.includeInBudget,true); });
await test('invalid expense never reaches repository', async () => { let writes=0; const service=new RecordExpense({saveExpense:async()=>{writes++}}); const c=command(); c.discount=Money.parse('31',cny); await assert.rejects(service.execute(c)); assert.equal(writes,0); });
await test('calendar day must match captured UTC offset', () => { const c=command(); c.localDate='2026-02-30'; assert.throws(()=>new ExpenseRecord(c),/INVALID_LOCAL_DATE/); });
await test('incomplete settlement and missing FX snapshot rejected', () => { const c=command(); c.accountPaid=undefined; assert.throws(()=>new ExpenseRecord(c)); const foreign=command(); foreign.accountPaid=Money.parse('28',usd); assert.throws(()=>new ExpenseRecord(foreign),/FX_SNAPSHOT_COMMAND_REQUIRED/); });
await test('repository failure propagates to caller', async () => { const service=new RecordExpense({saveExpense:async()=>{throw new Error('WRITE_FAILED')}}); await assert.rejects(service.execute(command()),/WRITE_FAILED/); });
const { SerialTaskQueue } = load(base + '/data/rdb/SerialTaskQueue.ets');
await test('queue holds later work until async task completes', async () => {
  const q = new SerialTaskQueue(); const events = []; let release;
  const gate = new Promise(resolve => { release = resolve; });
  const first = q.run(async () => { events.push('first-start'); await gate; events.push('first-end'); return 1; });
  const second = q.run(async () => { events.push('second'); return 2; });
  await Promise.resolve(); assert.deepEqual(events, ['first-start']); release();
  assert.deepEqual(await Promise.all([first, second]), [1,2]);
  assert.deepEqual(events, ['first-start','first-end','second']);
});
await test('queue propagates rejection and continues in FIFO order', async () => {
  const q = new SerialTaskQueue(); const events = [];
  const rejected = q.run(async () => { events.push('bad'); throw new Error('EXPECTED'); });
  const assertion = assert.rejects(rejected, /EXPECTED/);
  const next = q.run(async () => { events.push('good'); return 'saved'; });
  await assertion; assert.equal(await next, 'saved'); assert.deepEqual(events, ['bad','good']);
});
const { LedgerKind, displayAmount, filterEntries } = load(base + '/presentation/ledger/LedgerOverview.ets');
await test('ledger amount grouping preserves large integer precision', () => {
  assert.equal(displayAmount('9007199254740991'), '90,071,992,547,409.91');
  assert.equal(displayAmount('1'), '0.01');
});
await test('ledger filters intersect kind, search and account without changing source', () => {
  const rows = [
    {id:'a', title:'午餐', category:'餐饮', account:'微信', income:false},
    {id:'b', title:'工资', category:'工资', account:'银行卡', income:true},
    {id:'c', title:'地铁', category:'交通', account:'微信', income:false}
  ];
  assert.deepEqual(filterEntries(rows,LedgerKind.Income,'','').map(r=>r.id), ['b']);
  assert.deepEqual(filterEntries(rows,LedgerKind.All,' 地铁 ','微信').map(r=>r.id), ['c']);
  assert.equal(filterEntries(rows,LedgerKind.Income,'午餐','微信').length, 0);
  assert.equal(rows.length,3);
});
console.log(`${count} host checks passed. Native ArkTS/RDB/Decimal and UI require the separate device suite.`);
