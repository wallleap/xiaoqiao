import { CategoryDeletionMigration } from './CategoryDeletionMigration';
import { BookDeletionMigration } from './BookDeletionMigration';
import { BookSettingsMigration } from './BookSettingsMigration';
import { RdbCurrencySettings } from './RdbCurrencySettings';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { RdbSession } from './RdbSession';
import { TransferMigration } from './TransferMigration';
import { SpendingNatureMigration } from './SpendingNatureMigration';
import { RecoveryMigration } from './RecoveryMigration';
import { BookCoverMigration } from './BookCoverMigration';
import { AccountDetailsMigration } from './AccountDetailsMigration';
import { PrepaidMigration } from './PrepaidMigration';
import { MulticurrencyMigration } from './MulticurrencyMigration';
import { NatureColorMigration } from './NatureColorMigration';
import { BudgetNatureMigration } from './BudgetNatureMigration';

const MAX_BACKUP_BYTES: number = 128 * 1024 * 1024;

export interface BackupResourceRef { path: string; sha256: string; bytes: number; }
export interface BackupResourceSwap {
  begin(db: relationalStore.RdbStore, rollback: string): Promise<void>;
  finish(): Promise<void>;
  recover(db: relationalStore.RdbStore): Promise<void>;
}

export interface LocalBackupPreview {
  books: number;
  entries: number;
  accounts: number;
  bytes: number;
  resources?: number;
}

/** One instance per foreground workspace. All file operations and restore run on its serial queue. */
export class LocalLedgerBackup {
  private readonly context: common.Context;
  private readonly session: RdbSession;
  private readonly directory: string;
  private readonly prefix: string;
  private readonly candidateName: string;
  private prepared: boolean = false;

  constructor(context: common.Context, name: string, session: RdbSession) {
    this.context = context;
    this.session = session;
    this.directory = context.databaseDir + '/rdb/';
    this.prefix = this.directory + name.slice(0, -3) + '_local_backup';
    this.candidateName = name.slice(0, -3) + '_local_backup_candidate.db';
  }

  private get candidate(): string { return this.directory + this.candidateName; }
  private get pending(): string { return this.prefix + '_pending.db'; }
  private get previous(): string { return this.prefix + '_previous.db'; }

  private static async removeTemporary(path: string): Promise<void> {
    try { if (await fs.access(path)) { await fs.unlink(path); } } catch (_) { /* The next operation uses the same staging path. */ }
  }

  private static async syncFile(path: string): Promise<void> {
    const file = await fs.open(path, fs.OpenMode.READ_WRITE);
    try { await fs.fsync(file.fd); } finally { await fs.close(file); }
  }

  private static async copy(source: string, target: string): Promise<void> {
    const input = await fs.open(source, fs.OpenMode.READ_ONLY);
    try {
      const stat = await fs.stat(input.fd);
      if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_BACKUP_BYTES) { throw new Error('BACKUP_SIZE_UNSUPPORTED'); }
      const output = await fs.open(target, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        await fs.copyFile(input.fd, output.fd);
        if ((await fs.stat(output.fd)).size !== stat.size) { throw new Error('BACKUP_COPY_INCOMPLETE'); }
        await fs.fsync(output.fd);
      } finally { await fs.close(output); }
    } finally { await fs.close(input); }
  }

  private static async schema(db: relationalStore.RdbStore): Promise<string> {
    const rows = await db.querySql("SELECT type,name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name");
    const objects: string[][] = [];
    try {
      while (rows.goToNextRow()) { objects.push([rows.getString(0), rows.getString(1), rows.isColumnNull(2) ? '' : rows.getString(2)]); }
    } finally { rows.close(); }
    return JSON.stringify(objects);
  }

  private static async check(db: relationalStore.RdbStore, allowLegacy: boolean = false): Promise<void> {
    const version = await CategoryDeletionMigration.status(db);
    if (version !== 13 && (!allowLegacy || ![2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].includes(version))) { throw new Error('BACKUP_VERSION_UNSUPPORTED'); }
    if (version >= 7) { await RdbCurrencySettings.read(db); }
    const integrity = await db.querySql('PRAGMA integrity_check(1)');
    try {
      if (integrity.rowCount !== 1 || !integrity.goToFirstRow() || integrity.getString(0) !== 'ok') {
        throw new Error('BACKUP_INTEGRITY_FAILED');
      }
    } finally { integrity.close(); }
    const references = await db.querySql('PRAGMA foreign_key_check');
    try { if (references.rowCount !== 0) { throw new Error('BACKUP_FOREIGN_KEY_FAILED'); } } finally { references.close(); }
  }

  private static async preview(db: relationalStore.RdbStore, bytes: number): Promise<LocalBackupPreview> {
    const counts = await db.querySql('SELECT (SELECT COUNT(*) FROM books WHERE deleted_at_ms IS NULL),' +
      '((SELECT COUNT(*) FROM v_posted_transactions)+(SELECT COUNT(*) FROM v_expense_recoveries)),(SELECT COUNT(*) FROM accounts WHERE deleted_at_ms IS NULL),' +
      '(SELECT COUNT(*) FROM attachments)');
    try {
      if (!counts.goToFirstRow()) { throw new Error('BACKUP_PREVIEW_FAILED'); }

      return { books: counts.getLong(0), entries: counts.getLong(1), accounts: counts.getLong(2), bytes: bytes };
    } finally { counts.close(); }
  }

  private async inspectCandidate(schema: string): Promise<LocalBackupPreview> {
    const candidate = await relationalStore.getRdbStore(this.context, { name: this.candidateName,
      securityLevel: relationalStore.SecurityLevel.S1 });
    try {
      let version = await CategoryDeletionMigration.status(candidate);
      if (version === 2) {
        await SpendingNatureMigration.upgradeCandidate(candidate);
        version = 3;
      }
      if (version === 3) {
        await BudgetNatureMigration.upgradeCandidate(candidate);
        version = 4;
      }
      if (version === 4) {
        await RecoveryMigration.upgradeCandidate(candidate);
        version = 5;
      }
      if (version === 5) {
        await NatureColorMigration.upgradeCandidate(candidate);
        version = 6;
      }
      if (version === 6) { await MulticurrencyMigration.upgradeCandidate(candidate); version = 7; }
      if (version === 7) { await PrepaidMigration.upgradeCandidate(candidate); version = 8; }
      if (version === 8) { await AccountDetailsMigration.upgradeCandidate(candidate); version = 9; }
      if (version === 9) { await BookCoverMigration.upgradeCandidate(candidate); version = 10; }
      if (version === 10) { await BookSettingsMigration.upgradeCandidate(candidate); version = 11; }
      if (version === 11) { await BookDeletionMigration.upgradeCandidate(candidate); version = 12; }
      if (version === 12) { await CategoryDeletionMigration.upgradeCandidate(candidate); version = 13; }
      if (version !== 13) { throw new Error('BACKUP_VERSION_UNSUPPORTED'); }
      if (await LocalLedgerBackup.schema(candidate) !== schema) { throw new Error('BACKUP_SCHEMA_MISMATCH'); }
      await LocalLedgerBackup.check(candidate);
      return await LocalLedgerBackup.preview(candidate, (await fs.stat(this.candidate)).size);
    } finally { await candidate.close(); }
  }

  static async resources(db: relationalStore.RdbStore): Promise<BackupResourceRef[]> {
    const result: BackupResourceRef[] = [];
    const rows = await db.querySql('SELECT relative_path,content_sha256,byte_size,state FROM attachments');
    try {
      while (rows.goToNextRow()) {
        if (rows.getString(3) !== 'ready') { throw new Error('BACKUP_RESOURCE_NOT_READY'); }
        result.push({ path: rows.getString(0), sha256: rows.getString(1), bytes: rows.getLong(2) });
      }
    } finally { rows.close(); }
    const icons = await db.querySql("SELECT icon_key FROM categories WHERE icon_key LIKE 'resource:%' UNION SELECT icon_key FROM accounts WHERE icon_key LIKE 'resource:%' UNION SELECT icon_key FROM category_history_nodes WHERE icon_key LIKE 'resource:%'");
    try {
      while (icons.goToNextRow()) {
        const path = icons.getString(0).slice(9);
        result.push({ path: path, sha256: path.split('/').pop()?.split('.')[0] || '', bytes: 0 });
      }
    } finally { icons.close(); }
    return result;
  }

  async exportTo(uri: string, previous: boolean = false): Promise<BackupResourceRef[]> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<BackupResourceRef[]> => {
      if (previous) { await LocalLedgerBackup.copy(this.previous, uri); return []; }
      const path = this.prefix + '_export.db';
      try {
        await LocalLedgerBackup.check(db); await LocalLedgerBackup.preview(db, 0);
        const resources = await LocalLedgerBackup.resources(db);
        await db.backup(path); await LocalLedgerBackup.copy(path, uri); return resources;
      } finally { await LocalLedgerBackup.removeTemporary(path); }
    });
  }

  async hasPrevious(): Promise<boolean> { return fs.access(this.previous); }

  async prepare(uri: string, checkResources?: (references: BackupResourceRef[]) => Promise<void>): Promise<LocalBackupPreview> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<LocalBackupPreview> => {
      this.prepared = false;
      try {
        await LocalLedgerBackup.copy(uri, this.candidate);
        const preview = await this.inspectCandidate(await LocalLedgerBackup.schema(db));
        if (checkResources !== undefined) {
          const candidate = await relationalStore.getRdbStore(this.context, { name: this.candidateName,
            securityLevel: relationalStore.SecurityLevel.S1, isReadOnly: true });
          try { await checkResources(await LocalLedgerBackup.resources(candidate)); } finally { await candidate.close(); }
        }
        this.prepared = true;
        return preview;
      } finally { if (!this.prepared) { await LocalLedgerBackup.removeTemporary(this.candidate); } }
    });
  }

  async discard(): Promise<void> {
    await this.session.read(async (): Promise<void> => {
      this.prepared = false;
      await LocalLedgerBackup.removeTemporary(this.candidate);
    });
  }

  async restore(resources?: BackupResourceSwap): Promise<void> {
    await this.session.read(async (db: relationalStore.RdbStore): Promise<void> => {
      if (!this.prepared || await fs.access(this.pending)) { throw new Error('BACKUP_RESTORE_NOT_READY'); }
      this.prepared = false;
      const temporary = this.prefix + '_rollback_work.db';
      try {
        const schema = await LocalLedgerBackup.schema(db);
        const expected = await this.inspectCandidate(schema);
        await LocalLedgerBackup.check(db);
        await LocalLedgerBackup.preview(db, 0);
        await db.backup(temporary);
        if ((await fs.stat(temporary)).size > MAX_BACKUP_BYTES) { throw new Error('BACKUP_SIZE_UNSUPPORTED'); }
        await LocalLedgerBackup.syncFile(temporary);
        // A pending rollback copy is also the startup recovery marker.
        await fs.rename(temporary, this.pending);
        try {
          if (resources !== undefined) { await resources.begin(db, this.pending); }
          await db.restore(this.candidate);
          await LocalLedgerBackup.check(db);
          if (await LocalLedgerBackup.schema(db) !== schema) { throw new Error('BACKUP_RESTORED_SCHEMA_MISMATCH'); }
          const actual = await LocalLedgerBackup.preview(db, 0);
          if (actual.books !== expected.books || actual.entries !== expected.entries || actual.accounts !== expected.accounts) {
            throw new Error('BACKUP_RESTORED_DATA_MISMATCH');
          }
          await fs.rename(this.pending, this.previous);
          if (resources !== undefined) { await resources.finish(); }
        } catch (_) {
          try { await this.recover(db); if (resources !== undefined) { await resources.recover(db); } }
          catch (_) {
            this.session.invalidate();
            throw new Error('BACKUP_RECOVERY_REQUIRED');
          }
          throw new Error('BACKUP_RESTORE_ROLLED_BACK');
        }
      } finally {
        await LocalLedgerBackup.removeTemporary(temporary);
        await LocalLedgerBackup.removeTemporary(this.candidate);
      }
    });
  }

  /** Called before exposing a newly opened store, or inside the live session's exclusive restore task. */
  async recover(db: relationalStore.RdbStore): Promise<void> {
    if (!await fs.access(this.pending)) { return; }
    try {
      await db.restore(this.pending);
      await LocalLedgerBackup.check(db, true);
      await fs.rename(this.pending, this.previous);
    } catch (_) { throw new Error('BACKUP_RECOVERY_REQUIRED'); }
  }
}
