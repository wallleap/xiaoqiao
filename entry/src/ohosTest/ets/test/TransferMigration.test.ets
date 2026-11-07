import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { REVIEW_SCHEMA_SHA256, REVIEW_SCHEMA_STATEMENTS } from '../../../main/ets/data/rdb/ReviewSchema';
import { TransferMigration } from '../../../main/ets/data/rdb/TransferMigration';
import { LedgerDatabase, DEFAULT_BOOK_ID } from '../../../main/ets/data/rdb/LedgerDatabase';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { RdbSession } from '../../../main/ets/data/rdb/RdbSession';
import { SpendingNatureMigration } from '../../../main/ets/data/rdb/SpendingNatureMigration';

let cachedMigrationContext: common.UIAbilityContext | undefined = undefined;

async function migrationContext(): Promise<common.UIAbilityContext> {
  if (cachedMigrationContext !== undefined) { return cachedMigrationContext; }
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  try {
    cachedMigrationContext = (await delegator.getCurrentTopAbility()).context;
    return cachedMigrationContext;
  } catch (_) { /* Class-only runs may start before EntryAbility is visible. */ }
  const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
  await delegator.addAbilityMonitor(monitor);
  try {
    await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
    cachedMigrationContext = (await delegator.waitAbilityMonitor(monitor, 10000)).context;
    return cachedMigrationContext;
  } finally { await delegator.removeAbilityMonitor(monitor); }
}

async function legacy(host: common.Context, name: string, reject: boolean): Promise<relationalStore.RdbStore> {
  const db = await relationalStore.getRdbStore(host, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
  await RdbSession.forStore(db).write(async (store: relationalStore.RdbStore): Promise<void> => {
    for (const sql of REVIEW_SCHEMA_STATEMENTS) { if (!sql.startsWith('PRAGMA')) { await store.executeSql(sql); } }
    await store.insert('db_meta', { key: 'schema_checksum', value: REVIEW_SCHEMA_SHA256 });
    await store.insert('schema_migrations', { version: 1, checksum: REVIEW_SCHEMA_SHA256, applied_at_ms: 1 });
    await store.insert('currencies', { id: 'CNY', code: 'CNY', name: '人民币', symbol: '¥', minor_unit: 2, valid_from: '2026-01-01', source_version: 'test' });
    await store.insert('books', { id: DEFAULT_BOOK_ID, name: '旧账本', base_currency_id: 'CNY', timezone: 'Asia/Shanghai', created_at_ms: 1, updated_at_ms: 1 });
    for (const id of ['a', 'b']) { await store.insert('accounts', { id: id, name: id, kind: 'asset', currency_id: 'CNY', created_at_ms: 1, updated_at_ms: 1 }); }
    await store.insert('transactions', { id: 'legacy', book_id: DEFAULT_BOOK_ID, kind: 'transfer', currency_id: 'CNY', gross_minor: 10000, discount_minor: 0, paid_minor: 10000, book_currency_id: 'CNY', book_minor: 10000, include_in_assets: 1, include_in_budget: 0, occurred_at_ms: 1, occurred_local_date: '1970-01-01', occurred_timezone: 'UTC', occurred_offset_minutes: 0, created_at_ms: 1, updated_at_ms: 1 });
    await store.insert('account_movements', { id: 'out', transaction_id: 'legacy', account_id: 'a', currency_id: 'CNY', leg: 'transfer_out', delta_minor: -10000, occurred_at_ms: 1 });
    await store.insert('account_movements', { id: 'in', transaction_id: 'legacy', account_id: 'b', currency_id: 'CNY', leg: 'transfer_in', delta_minor: 10000, occurred_at_ms: 1 });
    await store.executeSql("UPDATE transactions SET posting_state='posted' WHERE id='legacy'");
    if (reject) { await store.executeSql("CREATE TRIGGER reject_v2 BEFORE INSERT ON schema_migrations WHEN NEW.version=2 BEGIN SELECT RAISE(ABORT,'late migration failure'); END"); }
  });
  return db;
}
async function verifyLegacy(db: relationalStore.RdbStore): Promise<void> {
  const rows = await db.querySql("SELECT (SELECT COUNT(*) FROM transactions),(SELECT COUNT(*) FROM account_movements),(SELECT revision FROM transactions WHERE id='legacy'),(SELECT CAST(balance_minor AS TEXT) FROM v_account_balances WHERE account_id='a'),(SELECT CAST(balance_minor AS TEXT) FROM v_account_balances WHERE account_id='b')");
  try { expect(rows.goToFirstRow()).assertTrue(); expect(rows.getLong(0)).assertEqual(1); expect(rows.getLong(1)).assertEqual(2); expect(rows.getLong(2)).assertEqual(1); expect(rows.getString(3)).assertEqual('-10000'); expect(rows.getString(4)).assertEqual('10000'); }
  finally { rows.close(); }
}
export default function transferMigrationTest() {
  describe('TransferMigration', () => {
    it('verified_v1_upgrade_preserves_legacy_rows_and_restorable_backup', 0, async () => {
      const host = await migrationContext();
      const name = 'xiaoqiao_app_test_migration_' + util.generateRandomUUID() + '.db';
      try {
        const original = await legacy(host, name, false); await original.close();
        const db = await LedgerDatabase.open(host, name);
        try {
          expect(await TransferMigration.status(db)).assertEqual(3);
          expect(await SpendingNatureMigration.status(db)).assertEqual(3); await verifyLegacy(db);
          const details = await db.querySql('SELECT COUNT(*) FROM transfer_details');
          try { details.goToFirstRow(); expect(details.getLong(0)).assertEqual(0); } finally { details.close(); }
          await db.restore(TransferMigration.backupName(name));
          expect(await TransferMigration.status(db)).assertEqual(1); await verifyLegacy(db);
        } finally { await db.close(); }
      } finally {
        await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name);
        await relationalStore.deleteRdbStore(host, TransferMigration.backupName(name));
        await relationalStore.deleteRdbStore(host, SpendingNatureMigration.backupName(name));
      }
    });
    it('late_upgrade_failure_rolls_back_schema_marker_trigger_and_money', 0, async () => {
      const host = await migrationContext();
      const name = 'xiaoqiao_app_test_migration_failure_' + util.generateRandomUUID() + '.db';
      try {
        const original = await legacy(host, name, true); await original.close();
        let rejected = false;
        try { const unexpected = await LedgerDatabase.open(host, name); await unexpected.close(); } catch (_) { rejected = true; }
        expect(rejected).assertTrue();
        const db = await relationalStore.getRdbStore(host, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
        try {
          expect(await TransferMigration.status(db)).assertEqual(1); await verifyLegacy(db);
          const rows = await db.querySql("SELECT name FROM sqlite_master WHERE name='transfer_details'");
          try { expect(rows.rowCount).assertEqual(0); } finally { rows.close(); }
          // A failing late marker write must restore the original publication trigger too.
          const trigger = await db.querySql("SELECT sql FROM sqlite_master WHERE name='transaction_publish'");
          try { expect(trigger.goToFirstRow()).assertTrue(); expect(trigger.getString(0).includes('transfer_details')).assertFalse(); } finally { trigger.close(); }
          await db.restore(TransferMigration.backupName(name)); await verifyLegacy(db);
        } finally { await db.close(); }
      } finally { await relationalStore.deleteRdbStore(host, name); await relationalStore.deleteRdbStore(host, TransferMigration.backupName(name)); }
    });
  });
}
