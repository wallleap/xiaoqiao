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
const { UpdateExpense } = load(base + '/domain/services/UpdateExpense.ets');
await test('expense edit validates revision and amount before repository writes', async () => {
  let writes=0;
  const update=new UpdateExpense({updateExpense:async()=>{writes++;}});
  for (const revision of [0,-1,1.5,NaN,Number.MAX_SAFE_INTEGER]) await assert.rejects(update.execute(command(),revision),/INVALID_EXPECTED_REVISION/);
  const invalid=command(); invalid.discount=Money.parse('31',cny);
  await assert.rejects(update.execute(invalid,1));
  assert.equal(writes,0);
});
await test('expense edit passes the same identity and expected revision without creating a record', async () => {
  let captured;
  const update=new UpdateExpense({updateExpense:async(record,revision)=>{captured={id:record.command.id,minor:record.paid.minor,revision};}});
  await update.execute(command(),7);
  assert.deepEqual(captured,{id:'expense-1',minor:2800n,revision:7});
});
await test('expense edit conflicts propagate instead of being reported as success', async () => {
  const update=new UpdateExpense({updateExpense:async()=>{throw new Error('TRANSACTION_CHANGED');}});
  await assert.rejects(update.execute(command(),1),/TRANSACTION_CHANGED/);
});
const { IncomeRecord } = load(base + '/domain/model/IncomeRecord.ets');
const { IncomeService } = load(base + '/domain/services/IncomeService.ets');
const incomeCommand = () => { const c=command(); return {id:'income-1',bookId:c.bookId,categoryId:'salary',amount:Money.parse('120.30',cny),bookAmount:Money.parse('120.30',cny),accountId:'cash',accountAmount:Money.parse('120.30',cny),includeInAssets:true,note:'工资',occurredAtMs:c.occurredAtMs,localDate:c.localDate,timezone:c.timezone,offsetMinutes:c.offsetMinutes}; };
await test('income has no discount or expense budget and snapshots its command', () => {
  const c=incomeCommand(); const r=new IncomeRecord(c); c.note='changed';
  assert.equal(r.settlement.paid.minor,12030n); assert.equal(r.settlement.command.discount.minor,0n);
  assert.equal(r.settlement.command.includeInBudget,false); assert.equal(r.settlement.command.note,'工资');
});
await test('invalid income amount and settlement never reach persistence', async () => {
  let writes=0; const service=new IncomeService({saveIncome:async()=>writes++,updateIncome:async()=>writes++});
  for (const amount of ['0','-1']) { const c=incomeCommand(); c.amount=Money.parse(amount,cny); await assert.rejects(service.save(c)); }
  const c=incomeCommand(); c.accountAmount=Money.parse('1',cny); await assert.rejects(service.save(c));
  const foreign=incomeCommand(); foreign.bookAmount=Money.parse('120.30',usd); await assert.rejects(service.save(foreign));
  await assert.rejects(service.update(incomeCommand(),0),/INVALID_EXPECTED_REVISION/); assert.equal(writes,0);
});
await test('income routes save and same-id update separately and propagates conflicts', async () => {
  const calls=[]; const service=new IncomeService({saveIncome:async r=>calls.push(['save',r.settlement.command.id]),updateIncome:async(r,v)=>{calls.push(['edit',r.settlement.command.id,v]); throw new Error('TRANSACTION_CHANGED');}});
  await service.save(incomeCommand()); await assert.rejects(service.update(incomeCommand(),3),/TRANSACTION_CHANGED/);
  assert.deepEqual(calls,[['save','income-1'],['edit','income-1',3]]);
});
const { AccountDraft, requireAccountRevision } = load(base + '/domain/model/AccountProfile.ets');
const accountCommand = () => ({id:'account-1',name:'  微信零钱  ',kind:'asset',styleKey:'wechat_pay',includeInNetAssets:true,opening:Money.parse('100.20',new CurrencyUnit('CNY','CNY',2))});
await test('account opening is exact and brand metadata comes from the approved catalog', () => {
  const c=accountCommand(); const draft=new AccountDraft(c); c.name='changed';
  assert.equal(draft.command.name,'微信零钱'); assert.equal(draft.command.opening.minor,10020n);
  assert.equal(draft.style.brand,'wechat'); assert.equal(draft.style.color,'#07B75A');
});
await test('liability opening is negative; invalid account metadata, signs and currencies reject', () => {
  const c=accountCommand(); c.kind='liability'; assert.throws(()=>new AccountDraft(c));
  c.opening=Money.parse('-20',new CurrencyUnit('CNY','CNY',2)); assert.equal(new AccountDraft(c).command.opening.minor,-2000n);
  for (const change of [{name:''},{name:'x'.repeat(41)},{kind:'unknown'},{styleKey:'../arbitrary.svg'},{opening:Money.parse('1',usd)}]) assert.throws(()=>new AccountDraft({...accountCommand(),...change}));
  assert.throws(()=>new AccountDraft({...accountCommand(),opening:Money.fromMinorText('9007199254740992',new CurrencyUnit('CNY','CNY',2))}));
  for (const v of [0,-1,1.5,NaN,Number.MAX_SAFE_INTEGER]) assert.throws(()=>requireAccountRevision(v));
});
const { AccountCalibration } = load(base + '/domain/model/AccountCalibration.ets');
const calibrationCommand = () => { const c=new CurrencyUnit('CNY','CNY',2); return {id:'adjustment',accountId:'asset',expectedRevision:1,before:Money.parse('110',c),after:Money.parse('80.25',c),reason:'  核对余额  '}; };
await test('calibration snapshots expected balance, trims reason, and computes exact signed delta', () => {
  const c=calibrationCommand(); const r=new AccountCalibration(c); c.reason='changed'; c.after=c.before;
  assert.equal(r.delta.minor,-2975n); assert.equal(r.command.before.minor,11000n); assert.equal(r.command.after.minor,8025n); assert.equal(r.command.reason,'核对余额');
  const debt=calibrationCommand(); debt.before=Money.parse('-50',debt.before.currency); debt.after=Money.parse('5.25',debt.before.currency);
  assert.equal(new AccountCalibration(debt).delta.minor,5525n);
  assert.equal(new AccountCalibration({...calibrationCommand(),reason:'  '}).command.reason,'手动校准余额');
});
await test('calibration rejects unchanged balance, wrong currency, invalid identity and revision', () => {
  const c=calibrationCommand();
  for (const change of [{id:''},{accountId:''},{expectedRevision:0},{expectedRevision:NaN},{expectedRevision:Number.MAX_SAFE_INTEGER},{reason:'x'.repeat(201)},{after:c.before},{after:Money.parse('1',usd)}]) assert.throws(()=>new AccountCalibration({...c,...change}));
});
await test('calibration checks before, after and difference against persistence limits', () => {
  const c=calibrationCommand(); const currency=c.before.currency;
  for(const change of [{before:Money.fromMinorText('9007199254740992',currency)},{after:Money.fromMinorText('-9007199254740992',currency)},{before:Money.fromMinorText('-9007199254740991',currency),after:Money.fromMinorText('9007199254740991',currency)}]) assert.throws(()=>new AccountCalibration({...c,...change}),/PERSISTED_AMOUNT_OUT_OF_RANGE/);
  assert.equal(new AccountCalibration({...c,before:Money.fromMinorText('9007199254740991',currency),after:Money.fromMinorText('9007199254740990',currency)}).delta.minor,-1n);
});
const { TransferRecord } = load(base + '/domain/model/TransferRecord.ets');
const { TransferService } = load(base + '/domain/services/TransferService.ets');
const transferCommand = () => { const c=incomeCommand(); return {id:'transfer-1',bookId:c.bookId,fromAccountId:'a',toAccountId:'b',amount:Money.parse('10.25',new CurrencyUnit('CNY','CNY',2)),includeInAssets:true,note:'调拨',occurredAtMs:c.occurredAtMs,localDate:c.localDate,timezone:c.timezone,offsetMinutes:c.offsetMinutes}; };
await test('transfer snapshots exact positive CNY money and two distinct accounts', () => {
  const c=transferCommand(); const r=new TransferRecord(c); c.note='changed';
  assert.equal(r.command.amount.minor,1025n); assert.equal(r.command.note,'调拨');
  for (const values of [{fromAccountId:''},{toAccountId:'a'},{amount:Money.parse('0',new CurrencyUnit('CNY','CNY',2))},{amount:Money.parse('-1',new CurrencyUnit('CNY','CNY',2))},{amount:Money.parse('1',usd)},{localDate:'2026-02-30'}]) assert.throws(()=>new TransferRecord({...transferCommand(),...values}));
});
await test('invalid transfer or revision never writes; update keeps the same identity', async () => {
  const calls=[]; const service=new TransferService({saveTransfer:async r=>calls.push(['save',r.command.id]),updateTransfer:async(r,v)=>calls.push(['edit',r.command.id,v])});
  await assert.rejects(service.save({...transferCommand(),toAccountId:'a'})); await assert.rejects(service.update(transferCommand(),0)); assert.equal(calls.length,0);
  await service.save(transferCommand()); await service.update(transferCommand(),3);
  assert.deepEqual(calls,[['save','transfer-1'],['edit','transfer-1',3]]);
  await assert.rejects(new TransferService({saveTransfer:async()=>{throw new Error('PAIR_FAILED');}}).save(transferCommand()),/PAIR_FAILED/);
});
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
const { LedgerKind, displayAmount, filterEntries, dailyTotals, isToday } = load(base + '/presentation/ledger/LedgerOverview.ets');
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
const { ExpenseAmountInput } = load(base + '/presentation/ledger/ExpenseAmountInput.ets');
await test('expense keyboard evaluates exact decimal addition/subtraction and rejects incomplete input', () => {
  assert.equal(ExpenseAmountInput.evaluate('0.10+0.20−0.05', cny).toDecimalString(), '0.25');
  assert.equal(ExpenseAmountInput.evaluate('12+3−2', cny).toDecimalString(), '13.00');
  assert.throws(() => ExpenseAmountInput.evaluate('12+', cny), /INCOMPLETE/);
  assert.throws(() => ExpenseAmountInput.evaluate('90071992547409.92', cny), /OUT_OF_RANGE/);
  assert.equal(ExpenseAmountInput.append('1.23', '4'), '1.23');
  assert.equal(ExpenseAmountInput.append('12+', '−'), '12−');
  assert.equal(ExpenseAmountInput.append('0', '.'), '0.');
  assert.equal(ExpenseAmountInput.append('12', '⌫'), '1');
});
await test('discount input limits each operand and evaluated result to nine integer digits', () => {
  assert.equal(ExpenseAmountInput.appendDiscount('123456789', '0', 2), '123456789');
  assert.equal(ExpenseAmountInput.appendDiscount('123456789', '.', 2), '123456789.');
  assert.equal(ExpenseAmountInput.appendDiscount('123456789.12', '3', 2), '123456789.12');
  assert.equal(ExpenseAmountInput.appendDiscount('123456789+', '1', 2), '123456789+1');
  assert.equal(ExpenseAmountInput.appendDiscount('123456789', '⌫', 2), '12345678');
  assert.equal(ExpenseAmountInput.evaluateDiscount('999999999.99', cny).toDecimalString(), '999999999.99');
  assert.equal(ExpenseAmountInput.evaluateDiscount('0.10+0.20−0.05', cny).toDecimalString(), '0.25');
  assert.throws(() => ExpenseAmountInput.evaluateDiscount('1000000000', cny), /DISCOUNT_OUT_OF_RANGE/);
  assert.throws(() => ExpenseAmountInput.evaluateDiscount('999999999.99+0.01', cny), /DISCOUNT_OUT_OF_RANGE/);
  assert.throws(() => ExpenseAmountInput.evaluateDiscount('1−2', cny), /DISCOUNT_OUT_OF_RANGE/);
  assert.throws(() => ExpenseAmountInput.evaluateDiscount('1+', cny), /INCOMPLETE/);
});
await test('paid input preflight rejects overflow without blocking pending operators or deletion', () => {
  assert.equal(ExpenseAmountInput.appendChecked('1', '0', '+', cny, false), '1+');
  assert.equal(ExpenseAmountInput.appendChecked('1+', '0', '2', cny, false), '1+2');
  assert.equal(ExpenseAmountInput.paidAmount('1+', '0', cny, true).toDecimalString(), '1.00');
  assert.throws(() => ExpenseAmountInput.paidAmount('1+', '0', cny), /INCOMPLETE/);
  assert.throws(() => ExpenseAmountInput.appendChecked('90071992547409.9', '0', '2', cny, false), /OUT_OF_RANGE/);
  assert.throws(() => ExpenseAmountInput.appendChecked('13', '999999999+', '1', cny, true), /OUT_OF_RANGE/);
  assert.equal(ExpenseAmountInput.appendChecked('13', '999999999+', '⌫', cny, true), '999999999');
  assert.equal(ExpenseAmountInput.appendChecked('1+', '0', '1', cny, true), '1');
  assert.throws(() => ExpenseAmountInput.paidAmount('0−90071992547409.91', '1', cny), /OUT_OF_RANGE/);
  assert.equal(ExpenseAmountInput.paidAmount('12+3−2', '5+2−5', cny).toDecimalString(), '11.00');
});
const { MonthlyBudget, DEFAULT_MONTHLY_BUDGET_MINOR } = load(base + '/domain/model/MonthlyBudget.ets');
await test('standalone amount drafts enforce precision, nonnegative results and exact bounds', () => {
  assert.equal(ExpenseAmountInput.nonnegative('0.10+0.20−0.05', cny).toDecimalString(), '0.25');
  assert.equal(ExpenseAmountInput.nonnegative('0', cny).toDecimalString(), '0.00');
  assert.equal(ExpenseAmountInput.appendNonnegative('1.23', '4', cny), '1.23');
  assert.equal(ExpenseAmountInput.appendNonnegative('1', '−', cny), '1−');
  assert.throws(() => ExpenseAmountInput.nonnegative('1−', cny), /INCOMPLETE/);
  assert.throws(() => ExpenseAmountInput.appendNonnegative('1−', '2', cny), /NEGATIVE_AMOUNT/);
  assert.throws(() => ExpenseAmountInput.appendNonnegative('90071992547409.9', '2', cny), /OUT_OF_RANGE/);
  assert.equal(ExpenseAmountInput.appendNonnegative('1−', '⌫', cny), '1');
});
await test('monthly budget defaults, exact usage, overrun and zero allowance', () => {
  assert.equal(DEFAULT_MONTHLY_BUDGET_MINOR, '250000');
  assert.deepEqual(MonthlyBudget.period('2026-12'), {start:'2026-12-01', endExclusive:'2027-01-01'});
  assert.throws(() => MonthlyBudget.period('2026-13'), /INVALID_MONTH/);
  assert.throws(() => MonthlyBudget.parse('-1',cny), /NEGATIVE_BUDGET/);
  assert.throws(() => MonthlyBudget.parse('1.001',cny), /PRECISION/);
  assert.equal(MonthlyBudget.progress('250000','1100').remainingMinor,'248900');
  assert.equal(MonthlyBudget.progress('300000','248600').percentText,'82.9%');
  assert.equal(MonthlyBudget.progress('100','200').ringValue,100);
  assert.equal(MonthlyBudget.progress('100','200').remainingMinor,'-100');
  assert.equal(MonthlyBudget.progress('0','0').percentText,'—');
  assert.equal(MonthlyBudget.parse('0',cny).minor.toString(),'0');
});

await test('daily totals use visible date groups and exact integer amounts', () => {
  const entries = [
    {date:'2026-11-03',income:true,minor:'900719925474099312345'},
    {date:'2026-11-03',income:false,minor:'1'},
    {date:'2026-11-03',income:false,minor:'2'},
    {date:'2026-11-02',income:false,minor:'1000'}
  ];
  const result = dailyTotals(entries, '2026-11-03');
  assert.equal(result.incomeMinor, '900719925474099312345');
  assert.equal(result.expenseMinor, '3');
  assert.equal(dailyTotals(entries.filter(e => e.income), '2026-11-03').expenseMinor, '0');
  assert.equal(dailyTotals([], '2026-11-03').incomeMinor, '0');
});
await test('transfers are visible in all, match both accounts, and never enter income/expense filters or daily totals', () => {
  const transfer={id:'t',title:'转账',category:'转账',account:'微信',toAccount:'银行卡',date:'2026-11-03',income:false,transfer:true,minor:'12345'};
  assert.equal(filterEntries([transfer],LedgerKind.All,'','').length,1);
  assert.equal(filterEntries([transfer],LedgerKind.Expense,'','').length,0);
  assert.equal(filterEntries([transfer],LedgerKind.Income,'','').length,0);
  assert.equal(filterEntries([transfer],LedgerKind.All,'银行','银行卡').length,1);
  assert.equal(filterEntries([transfer],LedgerKind.All,'','微信').length,1);
  assert.deepEqual(dailyTotals([transfer],transfer.date),{incomeMinor:'0',expenseMinor:'0'});
});
await test('today label compares the complete local calendar date', () => {
  const now = new Date(2026,10,3,0,1);
  assert.equal(isToday('2026-11-03', now), true);
  assert.equal(isToday('2025-11-03', now), false);
  assert.equal(isToday('2026-11-02', now), false);
});
await test('repayment binds fee and coupon to one transfer with exact outgoing and independent budget flag', () => {
  const c=transferCommand(); const currency=c.amount.currency;
  const r=new TransferRecord({...c, amount:Money.parse('100',currency), purpose:'credit_repayment',fee:Money.parse('2',currency),coupon:Money.parse('5',currency),feeInBudget:false});
  assert.equal(r.outgoing.minor,9700n); assert.equal(r.command.amount.minor,10000n);
  assert.equal(r.feeInExpense,true); assert.equal(r.feeInBudget,false);
  const covered=new TransferRecord({...c,purpose:'loan_repayment',coupon:c.amount}); assert.equal(covered.outgoing.minor,0n);
  for(const change of [{purpose:'unknown'},{fee:Money.parse('-1',currency)},{coupon:Money.parse('11',currency)},{coupon:Money.parse('1',currency)},{fee:Money.parse('1',usd)}]) assert.throws(()=>new TransferRecord({...c,...change}));
});
await test('embedded transfer fee participates in expense filter and daily totals, never principal or coupon', () => {
  const entry={id:'repayment',title:'还款',category:'信用卡还款',account:'银行',toAccount:'信用卡',date:'2026-11-03',income:false,transfer:true,minor:'9700',expenseMinor:'200',transferCouponMinor:'500'};
  assert.equal(filterEntries([entry],LedgerKind.Expense,'','').length,1);
  assert.equal(filterEntries([entry],LedgerKind.Income,'','').length,0);
  assert.deepEqual(dailyTotals([entry],entry.date),{incomeMinor:'0',expenseMinor:'200'});
});
console.log(`${count} host checks passed. Native ArkTS/RDB/Decimal and UI require the separate device suite.`);
