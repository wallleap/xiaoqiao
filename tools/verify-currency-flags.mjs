/** Offline verification of every imported SVG, license, currency mapping and resource reference. */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const root = path.resolve(import.meta.dirname, '..');
const manifest = JSON.parse(fs.readFileSync(root+'/tools/currency-flags/catalog.json'));
assert.equal(manifest.files.length, 542);
const variants = new Map();
for (const file of manifest.files) {
  const bytes = fs.readFileSync(root+'/entry/src/main/resources/base/media/'+file.resource+'.svg');
  assert.equal(bytes.length, file.bytes);
  assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'), file.sha256);
  assert(/^[a-z][a-z0-9_]*$/.test(file.resource));
  if (!variants.has(file.region)) variants.set(file.region, new Set());
  variants.get(file.region).add(file.ratio);
}
assert.equal(variants.size, 271);
for (const ratios of variants.values()) assert.equal(ratios.size, 2);
assert(fs.readFileSync(root+'/tools/currency-flags/LICENSE.flag-icons.txt','utf8').includes('Panayiotis Lipiridis'));
const definitions = fs.readFileSync(root+'/entry/src/main/ets/core/money/Currencies.ets','utf8');
const codes = [...definitions.matchAll(/code: '([A-Z]{3})'/g)].map(m=>m[1]);
assert.equal(Object.keys(manifest.currencyRegions).length, codes.length);
for (const code of codes) {
  const region = manifest.currencyRegions[code];
  assert(region, code); assert(variants.has(region), code);
}
const expected = { CNY:'cn',USD:'us',EUR:'eu',HKD:'hk',JPY:'jp',GBP:'gb',AUD:'au',CAD:'ca',SGD:'sg',KRW:'kr',CHF:'ch',THB:'th',NZD:'nz',MYR:'my',IDR:'id',INR:'in',PHP:'ph',BRL:'br',CZK:'cz',DKK:'dk',HUF:'hu',ILS:'il',ISK:'is',MXN:'mx',NOK:'no',PLN:'pl',RON:'ro',SEK:'se',TRY:'tr',ZAR:'za' };
assert.deepEqual(manifest.currencyRegions, expected);
const file = root+'/entry/src/main/ets/presentation/exchange/CurrencyFlags.ets';
const output = ts.transpileModule(fs.readFileSync(file,'utf8'), { compilerOptions:{ target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS } }).outputText;
const context = { exports:{}, $r: name=>name };
vm.runInNewContext(output,context);
for (const code of codes) assert.equal(context.exports.currencyFlag(code), 'app.media.flag_4x3_'+expected[code]+(code==='EUR'?'_compat':''));
assert.equal(context.exports.regionFlag('eu'),'app.media.flag_4x3_eu_compat');
const compatible=JSON.parse(fs.readFileSync(root+'/tools/currency-flags/compatibility.json','utf8'));
assert.equal(compatible.length,2);
for(const item of compatible){
  const bytes=fs.readFileSync(root+'/entry/src/main/resources/base/media/'+item.resource+'.svg');
  assert.equal(bytes.length,item.bytes);assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),item.sha256);
  assert(!/<(?:use|defs)\b/.test(bytes.toString()));
  assert.equal((bytes.toString().match(/fill="#fc0"/g)||[]).length,120);
  const original=manifest.files.find(file=>file.region==='eu' && file.ratio===item.ratio);assert.equal(item.sourceSha256,original.sha256);
}
assert.equal(context.exports.currencyFlag('UNKNOWN'), 'app.media.lucide_globe1');
console.log('PASS 542 original SVG hashes, 2 explicit-color EU compatibility variants, 271 paired regions, license, currency/region mappings and fallback');
