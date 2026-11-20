/** Production summary UI-state and async refresh checks; no native runtime/device access. */
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
function execute(source) {
  const context = { exports: {} };
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  vm.runInNewContext(code, context);
  return context.exports;
}
const { summaryValue, summaryStatus } = execute(fs.readFileSync('entry/src/main/ets/presentation/profile/PersonalSummaryState.ets', 'utf8'));
for (const value of ['1', '0', '0.00']) {
  assert.equal(summaryValue(value, false, true, ''), '计算中…');
  assert.equal(summaryValue(value, false, false, '失败'), '读取失败');
  assert.equal(summaryValue(value, true, true, ''), value);
  assert.equal(summaryValue(value, true, false, '失败'), value);
}
assert.equal(summaryStatus(true, true, ''), '更新中');
assert.equal(summaryStatus(true, false, '失败'), '更新失败');
assert.equal(summaryStatus(true, false, ''), '');
const source = fs.readFileSync('entry/src/main/ets/pages/Index.ets', 'utf8');
const from = source.indexOf('  private async refreshUsage('), to = source.indexOf('  private async refreshAfterDeletion(', from);
const { Refresh } = execute('class Refresh {' + source.slice(from, to) + '}\nexports.Refresh=Refresh;');
const page = new Refresh();
Object.assign(page, { usage: undefined, usageLoading: false, usageError: '', accountOverviewLoading: false, accountError: '', personalNetMinor: '', personalNetError: '' });
let resolveUsage;
const usage = page.refreshUsage({ usageSummary: () => new Promise(resolve => { resolveUsage = resolve; }) });
assert.equal(page.usageLoading, true); assert.equal(page.usage, undefined);
resolveUsage({ firstEntryDate: '2025-11-09', entryCount: '1825' }); await usage;
assert.equal(page.usageLoading, false); assert.equal(page.usage.entryCount, '1825');
await page.refreshUsage({ usageSummary: async () => { throw new Error('read failed'); } });
assert.equal(page.usage.entryCount, '1825'); assert(page.usageError.length > 0);
await page.refreshUsage({ usageSummary: async () => ({ firstEntryDate: '', entryCount: '0' }) });
assert.equal(page.usage.entryCount, '0'); assert.equal(page.usageError, '');
let resolveNet;
page.personalNetMinor = '10000';
const net = page.refreshAccountOverview({ accountOverview: () => new Promise(resolve => { resolveNet = resolve; }) });
assert.equal(page.accountOverviewLoading, true); assert.equal(page.personalNetMinor, '10000');
resolveNet({ netMinor: '12345', valuationMissing: [] }); await net;
assert.equal(page.personalNetMinor, '12345'); assert.equal(page.accountOverviewLoading, false);
await page.refreshAccountOverview({ accountOverview: async () => ({ netMinor: '', valuationMissing: ['USD', 'EUR'] }) });
assert.equal(page.personalNetMinor, '12345'); assert(page.personalNetError.includes('USD')); assert(page.personalNetError.includes('EUR'));
await page.refreshAccountOverview({ accountOverview: async () => { throw new Error('database'); } });
assert.equal(page.personalNetMinor, '12345'); assert(page.personalNetError.includes('读取失败'));
await page.refreshAccountOverview({ accountOverview: async () => ({ netMinor: '0' }) });
assert.equal(page.personalNetMinor, '0'); assert.equal(page.personalNetError, ''); assert.equal(page.accountError, '');
console.log('PASS 首次计算/保留旧值更新/失败原因/重试成功/零值/缺失汇率/异步完成自动替换');
