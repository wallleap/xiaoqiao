/** Execute production validation and book CRUD methods without HarmonyOS/device access. */
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const root = path.resolve(import.meta.dirname, '..');
const base = path.join(root, 'entry/src/main/ets');
const cache = new Map();
function load(file) {
  file = path.resolve(file);
  if (cache.has(file)) return cache.get(file).exports;
  const module = { exports: {} }; cache.set(file, module);
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  vm.runInThisContext(`(function(require,module,exports){${code}\n})`, { filename: file })(id => load(path.resolve(path.dirname(file), id + '.ets')), module, module.exports);
  return module.exports;
}
const { BOOK_PALETTES, BOOK_ICON_KEYS } = load(base + '/domain/model/BookCoverCatalog.ets');
const { ValidatedLedgerBook } = load(base + '/domain/model/LedgerBook.ets');
assert.equal(BOOK_PALETTES.length, 12); assert.equal(new Set(BOOK_ICON_KEYS).size, BOOK_ICON_KEYS.length);
const light = new Map(JSON.parse(fs.readFileSync(root + '/entry/src/main/resources/base/element/color.json')).color.map(c => [c.name, c.value]));
const dark = new Map(JSON.parse(fs.readFileSync(root + '/entry/src/main/resources/dark/element/color.json')).color.map(c => [c.name, c.value]));
for (const palette of BOOK_PALETTES) {
  for (const [index, role] of ['cover', 'spine', 'accent', 'ink', 'pages'].entries()) {
    assert.equal(light.get(`xq_book_cover_${palette.key}_${role}`), palette.light[index]);
    assert.equal(dark.get(`xq_book_cover_${palette.key}_${role}`), palette.dark[index]);
    assert.notEqual(palette.light[index], palette.dark[index]);
  }
  for (const icon of BOOK_ICON_KEYS) {
    const draft = new ValidatedLedgerBook({ id: 'b', name: ' 旅行 ', coverPalette: palette.key, coverIcon: icon }).draft;
    assert.equal(draft.name, '旅行'); assert.equal(draft.coverIcon, icon);
  }
}
for (const icon of BOOK_ICON_KEYS) assert(fs.existsSync(root + '/entry/src/main/resources/base/media/' + icon + '.svg'));
assert.throws(() => new ValidatedLedgerBook({ id: 'b', name: 'x', coverPalette: 'unknown' }));
assert.throws(() => new ValidatedLedgerBook({ id: 'b', name: 'x', coverIcon: 'file://private' }));
assert.equal(new ValidatedLedgerBook({ id: 'b', name: '旧调用' }).draft.coverPalette, 'butter');
const sql = fs.readFileSync(root + '/docs/database/schema-v10-book-covers.sql');
const schema = load(base + '/data/rdb/BookCoverSchema.ets');
assert.equal(schema.BOOK_COVER_SCHEMA_SHA256, crypto.createHash('sha256').update(sql).digest('hex'));
const source = ts.createSourceFile('workspace.ts', fs.readFileSync(base + '/data/rdb/LedgerWorkspace.ets', 'utf8'), ts.ScriptTarget.Latest, true);
const cls = source.statements.find(ts.isClassDeclaration);
const methods = ['books', 'createBook', 'updateBook'].map(name => cls.members.find(m => ts.isMethodDeclaration(m) && m.name.getText(source) === name).getText(source)).join('\n');
const code = ts.transpileModule('class Books {' + methods + '}\nexports.Books=Books;', { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
class Predicates { equalTo() { return this; } isNull() { return this; } }
const { LEDGER_USAGE_ROWS_SQL } = load(base + '/data/rdb/LedgerUsageQuery.ets');
const context = { exports: {}, LEDGER_USAGE_ROWS_SQL, ValidatedLedgerBook, DEFAULT_BOOK_ID: 'default', util: { generateRandomUUID: () => 'category' }, relationalStore: { RdbPredicates: Predicates } };
vm.runInNewContext(code, context);
function rows(values = []) { let i = -1; return { get rowCount() { return values.length; }, goToFirstRow() { i = 0; return !!values.length; }, goToNextRow() { return ++i < values.length; }, getString(n) { return String(values[i][n]); }, getLong(n) { return Number(values[i][n]); }, isColumnNull(n) { return values[i][n] == null; }, close() {} }; }
const book = new context.exports.Books();
const inserts = [], updates = [];
let matched = 1;
const db = {
  async querySql(sql) {
    if (sql.includes('FROM books b LEFT JOIN')) return rows([['b', '旅行', 3, null, 'lagoon', 'lucide_plane1', '27']]);
    if (sql.includes('MAX(sort_order)')) return rows([[1]]);
    if (sql.includes('WHERE id=?') && sql.includes('FROM books')) return rows([['default']]);
    return rows();
  },
  async insert(table, values) { inserts.push({ table, values }); },
  async update(values) { updates.push(values); return matched; }
};
book.session = { read: fn => fn(db), write: fn => fn(db) };
book.activeBookFromMeta = async () => 'b'; book.saveActiveBook = async () => {};
let result = await book.books(); assert.equal(result[0].coverPalette, 'lagoon'); assert.equal(result[0].coverIcon, 'lucide_plane1'); assert.equal(result[0].entryCount, '27');
await book.createBook('旅行', 'b', { coverPalette: 'mist', coverIcon: 'lucide_plane1' });
assert.equal(inserts[0].values.cover_palette, 'mist'); assert.equal(inserts[0].values.cover_icon, 'lucide_plane1');
await book.updateBook('b', '旅行改名', 3, { coverPalette: 'rose', coverIcon: 'lucide_heart1' });
assert.equal(updates.at(-1).cover_palette, 'rose'); assert.equal(updates.at(-1).revision, 4);
await book.updateBook('b', '仅改名', 4); assert(!Object.hasOwn(updates.at(-1), 'cover_palette'));
matched = 0; await assert.rejects(book.updateBook('b', '冲突', 3, { coverPalette: 'mist', coverIcon: 'lucide_plane1' }), /LEDGER_BOOK_CHANGED/);
console.log(`PASS 12 paired palettes × ${BOOK_ICON_KEYS.length} valid icons, theme/resource parity, default/invalid key validation, schema hash, production book read/create/update and revision conflicts`);
