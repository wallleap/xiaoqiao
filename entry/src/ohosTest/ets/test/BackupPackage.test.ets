import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { LedgerBackupPackage } from '../../../main/ets/data/backup/LedgerBackupPackage';
import { BackupFileInfo, BackupFiles } from '../../../main/ets/data/backup/BackupFiles';
import { BackupZip } from '../../../main/ets/data/backup/BackupZip';
import { LedgerResources, StoredLedgerResource } from '../../../main/ets/data/backup/LedgerResources';
import { DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { REVIEW_SCHEMA_SHA256, REVIEW_SCHEMA_STATEMENTS } from '../../../main/ets/data/rdb/ReviewSchema';
import { RdbSession } from '../../../main/ets/data/rdb/RdbSession';
import { SpendingNatureMigration } from '../../../main/ets/data/rdb/SpendingNatureMigration';
import { BudgetNatureMigration } from '../../../main/ets/data/rdb/BudgetNatureMigration';
import { TransferMigration } from '../../../main/ets/data/rdb/TransferMigration';

async function context(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
  await Driver.create().waitForComponent(ON.id('ledger-tab-4'), 10000);
  return (await delegator.getCurrentTopAbility()).context;
}
async function refused(run: () => Promise<void>): Promise<void> {
  let failed = false; try { await run(); } catch (_) { failed = true; } expect(failed).assertTrue();
}
async function icon(host: common.Context, resources: LedgerResources, color: string): Promise<StoredLedgerResource> {
  const path = host.cacheDir + '/icon-' + util.generateRandomUUID() + '.svg';
  try {
    await BackupFiles.writeText(path, `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect width="24" height="24" fill="${color}"/></svg>`);
    return await resources.put('icons', path);
  } finally { await BackupFiles.remove(path); }
}
async function database(host: common.Context, name: string): Promise<relationalStore.RdbStore> {
  return relationalStore.getRdbStore(host, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
}
async function clean(host: common.Context, name: string, paths: string[]): Promise<void> {
  await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name);
  const stem = host.databaseDir + '/rdb/' + name.slice(0, -3);
  for (const folder of ['_stage', '_work', '_previous']) { await BackupFiles.remove(host.filesDir + '/ledger_backup/' + name.slice(0, -3) + '_package' + folder); }
  for (const suffix of ['_local_backup_pending.db',
    '_local_backup_previous.db', '_local_backup_candidate.db', '_local_backup_export.db']) { await BackupFiles.remove(stem + suffix); }
  await BackupFiles.remove(new LedgerResources(host, name).root);
  for (const path of paths) { await BackupFiles.remove(path); }
}
interface FixtureManifest { format: string; version: number; schema: number; createdAt: string; files: BackupFileInfo[]; }
class FailingFinish extends LedgerBackupPackage {
  async finish(): Promise<void> { throw new Error('SIMULATED_COMMIT_FAILURE'); }
}

export default function backupPackageTest() {
  describe('BackupPackage', () => {
    it('round_trips_database_images_custom_icons_and_previous_package', 0, async () => {
      const host = await context(); const name = 'xiaoqiao_app_test_package_' + util.generateRandomUUID() + '.db';
      const archive = host.cacheDir + '/' + name + '.xqbackup'; const previous = archive + '.previous';
      const source = archive + '.png';
      try {
        let workspace = await LedgerWorkspace.open(host, name); const resources = workspace.backup.resources;
        const png = new util.Base64Helper().decodeSync('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j2xkAAAAASUVORK5CYII=');
        await BackupFiles.write(source, png.buffer as ArrayBuffer);
        const image = await resources.put('images', source); const original = await icon(host, resources, '#ff5000');
        expect((await resources.put('images', source)).relativePath).assertEqual(image.relativePath);
        const db = await database(host, name);
        try {
          await db.executeSql('INSERT INTO attachments(id,content_sha256,relative_path,mime_type,byte_size,state,created_at_ms) VALUES(?,?,?,?,?,?,?)',
            ['image', image.sha256, image.relativePath, image.mimeType, image.bytes, 'ready', Date.now()]);
          await db.executeSql('UPDATE categories SET icon_key=? WHERE id=?', ['resource:' + original.relativePath, 'expense-food']);
        } finally { await db.close(); }
        await workspace.setMonthlyBudget('2026-11', '3000'); await workspace.backup.exportTo(archive);
        await BackupFiles.copy(archive, host.filesDir + '/xiaoqiao-package-fixture.xqbackup');
        const other = await icon(host, resources, '#00aa00');
        await workspace.setMonthlyBudget('2026-11', '4000');
        const preview = await workspace.backup.prepare(archive); expect(preview.resources).assertEqual(2);
        expect((await workspace.snapshot('2026-11')).budgetTotalMinor).assertEqual('400000');
        await workspace.backup.restore();
        expect(await fs.access(resources.root + '/' + other.relativePath)).assertFalse();
        expect(await fs.access(resources.root + '/' + image.relativePath)).assertTrue();
        expect((await workspace.snapshot('2026-11')).budgetTotalMinor).assertEqual('300000');
        await workspace.backup.exportTo(previous, true); await workspace.backup.prepare(previous); await workspace.backup.restore();
        expect((await workspace.snapshot('2026-11')).budgetTotalMinor).assertEqual('400000');
        expect(await fs.access(resources.root + '/' + other.relativePath)).assertTrue();
        await LedgerWorkspace.close(name); workspace = await LedgerWorkspace.open(host, name);
        expect((await workspace.snapshot('2026-11')).budgetTotalMinor).assertEqual('400000');
        await fs.unlink(resources.root + '/' + image.relativePath);
        await refused(async () => { await workspace.backup.exportTo(archive); });
      } finally { await clean(host, name, [archive, previous, source]); }
    });
    it('rejects_crc_path_traversal_and_unsafe_svg_before_changing_ledger', 0, async () => {
      const host = await context(); const name = 'xiaoqiao_app_test_package_' + util.generateRandomUUID() + '.db';
      const archive = host.cacheDir + '/' + name + '.xqbackup'; const bad = archive + '.bad';
      try {
        const workspace = await LedgerWorkspace.open(host, name); await workspace.setMonthlyBudget('2026-11', '3000');
        await workspace.backup.exportTo(archive);
        const valid = await BackupFiles.read(archive); expect(BackupZip.decode(valid).length).assertEqual(2);
        const corrupt = valid.slice(0); const data = new Uint8Array(corrupt); data[50] ^= 1;
        await BackupFiles.write(bad, corrupt); await refused(async () => { await workspace.backup.prepare(bad); });
        const hostile = valid.slice(0), view = new DataView(hostile), entries = new Uint8Array(hostile);
        const nameBytes = new util.TextEncoder().encodeInto('../evilxx.txt');
        const central = view.getUint32(hostile.byteLength - 6, true);
        entries.set(nameBytes, 30); entries.set(nameBytes, central + 46);
        await BackupFiles.write(bad, hostile); await refused(async () => { await workspace.backup.prepare(bad); });
        await BackupFiles.writeText(bad, '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>');
        await refused(async () => { await workspace.backup.resources.put('icons', bad); });
        expect((await workspace.snapshot('2026-11')).budgetTotalMinor).assertEqual('300000');
        await refused(async () => { await workspace.backup.restore(); });
      } finally { await clean(host, name, [archive, bad]); }
    });
    it('rejects_missing_database_resource_references_even_with_valid_zip_hashes', 0, async () => {
      const host = await context(); const name = 'xiaoqiao_app_test_package_' + util.generateRandomUUID() + '.db';
      const archive = host.cacheDir + '/' + name + '.xqbackup', stage = archive + '.source';
      try {
        const workspace = await LedgerWorkspace.open(host, name); await workspace.setMonthlyBudget('2026-11', '3000');
        const db = await database(host, name);
        try { await db.executeSql('INSERT INTO attachments(id,content_sha256,relative_path,mime_type,byte_size,state,created_at_ms) VALUES(?,?,?,?,?,?,?)',
          ['missing', '0'.repeat(64), 'images/' + '0'.repeat(64) + '.png', 'image/png', 10, 'ready', Date.now()]); }
        finally { await db.close(); }
        await BackupFiles.mkdir(stage); await workspace.localBackup.exportTo(stage + '/ledger.db');
        const files = [await BackupFiles.info(stage + '/ledger.db', 'ledger.db')];
        const manifest: FixtureManifest = { format: 'xiaoqiao', version: 1, schema: 2, createdAt: new Date().toISOString(), files: files };
        await BackupFiles.writeText(stage + '/manifest.json', JSON.stringify(manifest));
        await BackupZip.encode(stage, archive, [await BackupFiles.info(stage + '/manifest.json', 'manifest.json'), ...files]);
        await refused(async () => { await workspace.backup.prepare(archive); });
        expect((await workspace.snapshot('2026-11')).budgetTotalMinor).assertEqual('300000');
        await refused(async () => { await workspace.backup.restore(); });
      } finally { await clean(host, name, [archive, stage]); }
    });
    it('rolls_back_database_and_assets_when_commit_fails', 0, async () => {
      const host = await context(); const name = 'xiaoqiao_app_test_package_' + util.generateRandomUUID() + '.db';
      const archive = host.cacheDir + '/' + name + '.xqbackup';
      try {
        const workspace = await LedgerWorkspace.open(host, name);
        await icon(host, workspace.backup.resources, '#ff5000'); await workspace.setMonthlyBudget('2026-11', '3000');
        await workspace.backup.exportTo(archive);
        const newer = await icon(host, workspace.backup.resources, '#00aa00'); await workspace.setMonthlyBudget('2026-11', '4000');
        const failing = new FailingFinish(host, name, workspace.localBackup); await failing.prepare(archive);
        await refused(async () => { await failing.restore(); });
        expect((await workspace.snapshot('2026-11')).budgetTotalMinor).assertEqual('400000');
        expect(await fs.access(workspace.backup.resources.root + '/' + newer.relativePath)).assertTrue();
      } finally { await clean(host, name, [archive]); }
    });
    it('startup_recovers_database_and_assets_after_interrupted_swap', 0, async () => {
      const host = await context(); const name = 'xiaoqiao_app_test_package_' + util.generateRandomUUID() + '.db';
      const archive = host.cacheDir + '/' + name + '.xqbackup', rollback = archive + '.db';
      try {
        let workspace = await LedgerWorkspace.open(host, name);
        await icon(host, workspace.backup.resources, '#ff5000'); await workspace.setMonthlyBudget('2026-11', '3000');
        await workspace.backup.exportTo(archive);
        const newer = await icon(host, workspace.backup.resources, '#00aa00'); await workspace.setMonthlyBudget('2026-11', '4000');
        await workspace.backup.prepare(archive); await workspace.localBackup.exportTo(rollback);
        const db = await database(host, name);
        try { await workspace.backup.begin(db, rollback); } finally { await db.close(); }
        await workspace.setMonthlyBudget('2026-11', '6000'); await LedgerWorkspace.close(name);
        workspace = await LedgerWorkspace.open(host, name);
        expect((await workspace.snapshot('2026-11')).budgetTotalMinor).assertEqual('400000');
        expect(await fs.access(workspace.backup.resources.root + '/' + newer.relativePath)).assertTrue();
      } finally { await clean(host, name, [archive, rollback]); }
    });
    it('upgrades_v2_manifest_on_candidate_copy_before_restore', 0, async () => {
      const host = await context();
      const oldName = 'xiaoqiao_app_test_package_v2_' + util.generateRandomUUID() + '.db';
      const name = 'xiaoqiao_app_test_package_target_' + util.generateRandomUUID() + '.db';
      const archive = host.cacheDir + '/' + name + '.xqbackup', stage = archive + '.source';
      try {
        const old = await database(host, oldName);
        await RdbSession.forStore(old).write(async (db: relationalStore.RdbStore): Promise<void> => {
          for (const sql of REVIEW_SCHEMA_STATEMENTS) { if (!sql.startsWith('PRAGMA')) { await db.executeSql(sql); } }
          await db.insert('db_meta', { key: 'schema_checksum', value: REVIEW_SCHEMA_SHA256 });
          await db.insert('schema_migrations', { version: 1, checksum: REVIEW_SCHEMA_SHA256, applied_at_ms: 1 });
          await db.insert('currencies', { id: 'CNY', code: 'CNY', name: '人民币', symbol: '¥', minor_unit: 2,
            valid_from: '2026-01-01', source_version: 'v2-fixture' });
          await db.insert('books', { id: DEFAULT_BOOK_ID, name: 'V2 旧账本', base_currency_id: 'CNY',
            timezone: 'Asia/Shanghai', created_at_ms: 1, updated_at_ms: 1 });
          await TransferMigration.apply(db, '', false);
        });
        await BackupFiles.mkdir(stage);
        await RdbSession.forStore(old).read(async (db: relationalStore.RdbStore): Promise<void> => {
          await db.backup(stage + '/ledger.db');
        });
        await old.close();
        const files = [await BackupFiles.info(stage + '/ledger.db', 'ledger.db')];
        const manifest: FixtureManifest = { format: 'xiaoqiao', version: 1, schema: 2, createdAt: new Date().toISOString(), files: files };
        await BackupFiles.writeText(stage + '/manifest.json', JSON.stringify(manifest));
        await BackupZip.encode(stage, archive, [await BackupFiles.info(stage + '/manifest.json', 'manifest.json'), ...files]);

        const workspace = await LedgerWorkspace.open(host, name);
        const preview = await workspace.backup.prepare(archive);
        expect(preview.books).assertEqual(1);
        await workspace.backup.restore();
        expect((await workspace.snapshot('2027-01')).bookName).assertEqual('V2 旧账本');
        await LedgerWorkspace.close(name);
        const restored = await database(host, name);
        try {
          expect(await SpendingNatureMigration.status(restored)).assertEqual(4);
          expect(await BudgetNatureMigration.status(restored)).assertEqual(4);
        }
        finally { await restored.close(); }
      } finally {
        await clean(host, name, [archive, stage]);
        await relationalStore.deleteRdbStore(host, oldName);
      }
    });
  });
}
