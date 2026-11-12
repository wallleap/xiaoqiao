import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BackupResourceRef, BackupResourceSwap, LocalBackupPreview, LocalLedgerBackup } from '../rdb/LocalLedgerBackup';
import { BackupFiles, BackupFileInfo } from './BackupFiles';
import { BackupZip } from './BackupZip';
import { LedgerResources } from './LedgerResources';

interface BackupManifest { format: string; version: number; schema: number; createdAt: string; files: BackupFileInfo[]; }
interface ResourceJournal { version: number; hadAssets: boolean; databaseSha256: string; assets: BackupFileInfo[]; }

/** All user-facing backups use this package. LocalLedgerBackup is the serialized database leg. */
export class LedgerBackupPackage implements BackupResourceSwap {
  readonly resources: LedgerResources;
  private readonly context: common.Context;
  private readonly database: LocalLedgerBackup;
  private readonly stage: string;
  private readonly work: string;
  private readonly previous: string;
  private prepared: boolean = false;
  constructor(context: common.Context, name: string, database: LocalLedgerBackup) {
    this.context = context; this.database = database; this.resources = new LedgerResources(context, name);
    const prefix = context.filesDir + '/ledger_backup/' + name.slice(0, -3) + '_package';
    this.stage = prefix + '_stage'; this.work = prefix + '_work'; this.previous = prefix + '_previous';
  }
  private static references(refs: BackupResourceRef[], files: BackupFileInfo[]): void {
    for (const ref of refs) {
      if (!LedgerResources.safe(ref.path)) { throw new Error('PACKAGE_RESOURCE_PATH'); }
      const file = files.find((item: BackupFileInfo) => item.path === 'assets/' + ref.path);
      if (file === undefined || file.sha256 !== ref.sha256 || (ref.bytes > 0 && file.bytes !== ref.bytes)) { throw new Error('PACKAGE_RESOURCE_MISSING'); }
    }
  }
  async exportTo(uri: string, previous: boolean = false): Promise<void> {
    const directory = this.context.cacheDir + '/xiaoqiao-package-' + util.generateRandomUUID();
    const archive = directory + '.xqbackup';
    try {
      await BackupFiles.mkdir(directory + '/assets/images'); await BackupFiles.mkdir(directory + '/assets/icons');
      let references: BackupResourceRef[];
      let source: string;
      if (previous) {
        if (!await this.hasPrevious()) { throw new Error('PACKAGE_PREVIOUS_MISSING'); }
        const journal = JSON.parse(await BackupFiles.text(this.previous + '/journal.json')) as ResourceJournal;
        await this.verifyRollback(this.previous, this.previous + '/assets', journal);
        await BackupFiles.copy(this.previous + '/ledger.db', directory + '/ledger.db');
        references = JSON.parse(await BackupFiles.text(this.previous + '/references.json')) as BackupResourceRef[];
        source = this.previous + '/assets';
      } else {
        references = await this.database.exportTo(directory + '/ledger.db'); source = this.resources.root;
      }
      const assets = await LedgerResources.catalog(source);
      LedgerBackupPackage.references(references, assets);
      for (const file of assets) {
        const relative = file.path.slice(7);
        await BackupFiles.copy(source + '/' + relative, directory + '/' + file.path);
      }
      const files = [await BackupFiles.info(directory + '/ledger.db', 'ledger.db'), ...assets];
      const manifest: BackupManifest = { format: 'xiaoqiao', version: 1, schema: 5, createdAt: new Date().toISOString(), files: files };
      await BackupFiles.writeText(directory + '/manifest.json', JSON.stringify(manifest));
      await BackupZip.encode(directory, archive, [await BackupFiles.info(directory + '/manifest.json', 'manifest.json'), ...files]);
      await BackupFiles.copy(archive, uri);
    } finally { await BackupFiles.remove(directory); await BackupFiles.remove(archive); }
  }
  async hasPrevious(): Promise<boolean> { return fs.access(this.previous + '/ledger.db'); }
  private async inspect(): Promise<BackupFileInfo[]> {
    const manifest = JSON.parse(await BackupFiles.text(this.stage + '/manifest.json')) as BackupManifest;
    if (manifest.format !== 'xiaoqiao' || manifest.version !== 1 || (manifest.schema !== 2 && manifest.schema !== 3 && manifest.schema !== 4 && manifest.schema !== 5) || !Array.isArray(manifest.files) ||
      manifest.files.length === 0 || manifest.files.length > 2047) { throw new Error('PACKAGE_VERSION'); }
    const paths: Set<string> = new Set();
    for (const file of manifest.files) {
      if (!BackupZip.validPath(file.path) || file.path === 'manifest.json' || paths.has(file.path) ||
        !Number.isSafeInteger(file.bytes) || file.bytes <= 0 || !/^[a-f0-9]{64}$/.test(file.sha256)) { throw new Error('PACKAGE_MANIFEST'); }
      const actual = await BackupFiles.info(this.stage + '/' + file.path, file.path);
      if (actual.bytes !== file.bytes || actual.sha256 !== file.sha256 || actual.crc32 !== file.crc32) { throw new Error('PACKAGE_HASH'); }
      paths.add(file.path);
    }
    if (!paths.has('ledger.db')) { throw new Error('PACKAGE_MANIFEST'); }
    const assets = await LedgerResources.catalog(this.stage + '/assets');
    if (assets.length !== manifest.files.length - 1) { throw new Error('PACKAGE_MANIFEST'); }
    return manifest.files;
  }
  async prepare(uri: string): Promise<LocalBackupPreview> {
    await this.discard();
    try {
      const archive = await BackupFiles.read(uri);
      const entries = BackupZip.decode(archive);
      await BackupFiles.mkdir(this.stage + '/assets/images'); await BackupFiles.mkdir(this.stage + '/assets/icons');
      for (const entry of entries) { await BackupFiles.write(this.stage + '/' + entry.path, entry.data); }
      const files = await this.inspect();
      if (files.length !== entries.length - 1) { throw new Error('PACKAGE_MANIFEST'); }
      const preview = await this.database.prepare(this.stage + '/ledger.db', async (refs: BackupResourceRef[]): Promise<void> => {
        LedgerBackupPackage.references(refs, files);
      });
      this.prepared = true;
      return { books: preview.books, entries: preview.entries, accounts: preview.accounts, bytes: archive.byteLength, resources: files.length - 1 };
    } catch (error) { await this.discard(); throw error as Error; }
  }
  async discard(): Promise<void> { this.prepared = false; await this.database.discard(); await BackupFiles.remove(this.stage); }
  async restore(): Promise<void> {
    if (!this.prepared) { throw new Error('BACKUP_RESTORE_NOT_READY'); }
    await this.inspect(); this.prepared = false;
    try { await this.database.restore(this); } finally { await BackupFiles.remove(this.stage); }
  }
  /** Runs inside LocalLedgerBackup's exclusive database queue after its rollback snapshot is durable. */
  async begin(db: relationalStore.RdbStore, rollback: string): Promise<void> {
    if (await fs.access(this.work + '/journal.json')) { throw new Error('BACKUP_RECOVERY_REQUIRED'); }
    await BackupFiles.remove(this.work); await BackupFiles.mkdir(this.work);
    await BackupFiles.copy(rollback, this.work + '/ledger.db');
    await BackupFiles.writeText(this.work + '/references.json', JSON.stringify(await LocalLedgerBackup.resources(db)));
    const assets = await LedgerResources.catalog(this.resources.root);
    LedgerBackupPackage.references(await LocalLedgerBackup.resources(db), assets);
    const journal: ResourceJournal = { version: 1, hadAssets: await fs.access(this.resources.root),
      databaseSha256: (await BackupFiles.info(this.work + '/ledger.db', 'ledger.db')).sha256, assets: assets };
    await BackupFiles.writeText(this.work + '/journal.pending', JSON.stringify(journal));
    await fs.rename(this.work + '/journal.pending', this.work + '/journal.json');
    if (journal.hadAssets) { await fs.rename(this.resources.root, this.work + '/assets'); }
    else { await BackupFiles.mkdir(this.work + '/assets'); }
    await BackupFiles.mkdir(this.context.filesDir + '/ledger_assets');
    await fs.rename(this.stage + '/assets', this.resources.root);
  }
  async finish(): Promise<void> {
    await BackupFiles.remove(this.previous);
    // Atomic directory rename commits DB + resources, and retains the previous complete snapshot.
    await fs.rename(this.work, this.previous);
  }
  private async verifyRollback(directory: string, assetsRoot: string, journal: ResourceJournal): Promise<void> {
    if (journal.version !== 1 || typeof journal.hadAssets !== 'boolean' || !Array.isArray(journal.assets) ||
      (await BackupFiles.info(directory + '/ledger.db', 'ledger.db')).sha256 !== journal.databaseSha256) { throw new Error('BACKUP_RECOVERY_REQUIRED'); }
    const actual = await LedgerResources.catalog(assetsRoot);
    if (actual.length !== journal.assets.length || actual.some((file: BackupFileInfo) => !journal.assets.some((old: BackupFileInfo) =>
      old.path === file.path && old.sha256 === file.sha256 && old.bytes === file.bytes))) { throw new Error('BACKUP_RECOVERY_REQUIRED'); }
  }
  async recover(db: relationalStore.RdbStore): Promise<void> {
    if (!await fs.access(this.work + '/journal.json')) { return; }
    try {
    const journal = JSON.parse(await BackupFiles.text(this.work + '/journal.json')) as ResourceJournal;
    await this.verifyRollback(this.work, await fs.access(this.work + '/assets') ? this.work + '/assets' : journal.hadAssets ? this.resources.root : this.work + '/assets', journal);
    await db.restore(this.work + '/ledger.db');
    if (await fs.access(this.work + '/assets')) {
      await BackupFiles.remove(this.resources.root);
      if (journal.hadAssets) { await fs.rename(this.work + '/assets', this.resources.root); }
    } else if (!journal.hadAssets) { await BackupFiles.remove(this.resources.root); }
    // Remove only the marker first. Recovery can be safely repeated until this point.
    await fs.unlink(this.work + '/journal.json');
    try { await BackupFiles.remove(this.work); } catch (_) { /* Unreferenced recovery debris can be cleaned on the next restore. */ }
    } catch (_) { throw new Error('BACKUP_RECOVERY_REQUIRED'); }
  }
}
