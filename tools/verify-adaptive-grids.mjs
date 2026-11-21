/** Host-side breakpoint and content-width checks; does not replace device layout QA. */
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const module = { exports: {} };
const source = fs.readFileSync('entry/src/main/ets/presentation/layout/AdaptiveGrid.ets', 'utf8');
const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
vm.runInNewContext(code, { exports: module.exports });
const { adaptiveColumns, gridColumnsTemplate } = module.exports;
// Representative measured content widths (surrounding padding already removed).
assert.equal(adaptiveColumns(296, 72, 0, 7, 1), 4);
assert.equal(adaptiveColumns(272, 72, 0, 7, 1), 3);
assert.equal(adaptiveColumns(320, 72, 0, 7, 1.3), 3);
assert.equal(adaptiveColumns(320, 96, 8, 6, 1), 3);
assert.equal(adaptiveColumns(408, 96, 8, 6, 1), 4);
assert.equal(adaptiveColumns(320, 96, 8, 6, 1.3), 2);
for (const [minimum, gap, cap] of [[72, 0, 7], [96, 8, 6]]) {
  for (const scale of [1, 1.15, 1.3, 1.75, 2, 3.2]) {
    let previous = 1;
    for (let width = 1; width <= 1600; width++) {
      const count = adaptiveColumns(width, minimum, gap, cap, scale);
      assert(count >= previous && count <= cap);
      if (width >= minimum * scale) assert(count * minimum * scale + (count - 1) * gap <= width + 0.000001);
      if (count < cap) assert((count + 1) * minimum * scale + count * gap > width + 0.000001);
      assert.equal(gridColumnsTemplate(count).split(' ').length, count);
      previous = count;
    }
  }
}
for (const width of [0, -1, NaN, Infinity]) assert.equal(adaptiveColumns(width, 72, 0, 7, 1), 1);
for (const file of ['LocalBackupPage', 'ExchangeRatesPage']) {
  const page = fs.readFileSync(`entry/src/main/ets/components/${file}.ets`, 'utf8');
  assert(page.includes('.onAreaChange('));
  assert(page.includes('ui.fp2px(12) / ui.vp2px(12)'));
  assert(page.includes('adaptiveColumns(Number(area.width)'));
}
console.log('PASS: adaptive grid breakpoints, enlarged fonts, width bounds and page wiring');
