import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { RdbSession } from './RdbSession';
import { LedgerResources } from '../backup/LedgerResources';
import { currencyUnit } from '../../core/money/Currencies';
import { Money } from '../../core/money/Money';

export interface BookDeletionResult { cleanupPending: boolean; }
interface BalanceCarry { accountId: string; currencyId: string; total: bigint; carry: bigint; }

/** Confirmed physical deletion uses V12 writer-side balance/integrity triggers, without exporting a backup. */
export class RdbBookDeletion {
  private readonly session: RdbSession;
  private readonly resources: LedgerResources;
  private busy: boolean = false;
  constructor(session: RdbSession, resources: LedgerResources) { this.session = session; this.resources = resources; }

  private async requireArchived(id: string, revision: number): Promise<void> {
    await this.session.read(async (db: relationalStore.RdbStore): Promise<void> => {
      const rows = await db.querySql('SELECT revision,archived_at_ms,deleted_at_ms FROM books WHERE id=?', [id]);
      try {
        if (!rows.goToFirstRow() || rows.getLong(0) !== revision || rows.isColumnNull(1) || !rows.isColumnNull(2)) {
          throw new Error('BOOK_DELETE_UNAVAILABLE');
        }
      } finally { rows.close(); }
      const prepaid = await db.querySql('SELECT id FROM v_prepaid_balances WHERE book_id=? AND (remaining_minor<>0 OR remaining_book_minor<>0) LIMIT 1', [id]);
      try { if (prepaid.rowCount > 0) { throw new Error('BOOK_DELETE_PREPAID_OPEN'); } } finally { prepaid.close(); }
    });
  }

  async execute(id: string, revision: number): Promise<BookDeletionResult> {
    if (this.busy || !id || !Number.isSafeInteger(revision) || revision < 1) { throw new Error('BOOK_DELETE_UNAVAILABLE'); }
    this.busy = true;
    try {
      await this.requireArchived(id, revision);
      await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
        const balances: Map<string, BalanceCarry> = new Map();
        const rows = await db.querySql("SELECT a.id,a.currency_id,CAST(COALESCE(m.delta_minor,0) AS TEXT),CASE WHEN m.transaction_id IN (SELECT id FROM transactions WHERE book_id=?) OR (m.adjustment_id IS NULL AND m.id IN (SELECT e.id FROM prepaid_events e JOIN prepaid_projects p ON p.id=e.project_id WHERE p.book_id=?)) THEN 1 ELSE 0 END FROM accounts a LEFT JOIN v_effective_movements m ON m.account_id=a.id ORDER BY a.id", [id, id]);
        try {
          while (rows.goToNextRow()) {
            const accountId = rows.getString(0);
            const value = balances.get(accountId) || { accountId: accountId, currencyId: rows.getString(1), total: BigInt(0), carry: BigInt(0) };
            const delta = BigInt(rows.getString(2)); value.total += delta;
            if (rows.getLong(3) === 1) { value.carry += delta; }
            balances.set(accountId, value);
          }
        } finally { rows.close(); }
        // Keep the V12 context column for schema compatibility; this policy marker is not a saved backup URI.
        await db.insert('book_deletion_context', { id: 1, book_id: id, revision: revision, backup_uri: 'disabled-by-user', occurred_at_ms: Date.now() });
        for (const value of balances.values()) {
          const currency = currencyUnit(value.currencyId);
          const expected = Money.fromMinor(value.total, currency).toSafeMinorNumber();
          const carry = Money.fromMinor(value.carry, currency).toSafeMinorNumber();
          Money.fromMinor(value.total - value.carry, currency).toSafeMinorNumber();
          await db.insert('book_deletion_balances', { account_id: value.accountId, currency_id: value.currencyId,
            expected_minor: expected, carry_minor: carry, adjustment_id: util.generateRandomUUID() });
        }
        // Trigger checks run on the writer: querySql may use a separate reader and cannot verify uncommitted deletes.
        const changed = await db.delete(new relationalStore.RdbPredicates('books').equalTo('id', id).equalTo('revision', revision));
        if (changed !== 1) { throw new Error('BOOK_DELETE_UNAVAILABLE'); }
      });
      let cleanupPending: boolean = true;
      try { cleanupPending = await this.cleanup(); } catch (_) { /* Durable queue is retried when the workspace next opens. */ }
      return { cleanupPending: cleanupPending };
    } finally { this.busy = false; }
  }

  async cleanup(): Promise<boolean> {
    const paths = await this.session.read(async (db: relationalStore.RdbStore): Promise<string[]> => {
      const rows = await db.querySql('SELECT relative_path FROM book_deletion_files ORDER BY relative_path');
      const values: string[] = [];
      try { while (rows.goToNextRow()) { values.push(rows.getString(0)); } } finally { rows.close(); }
      return values;
    });
    if (paths.length === 0) { return false; }
    return this.session.write(async (db: relationalStore.RdbStore): Promise<boolean> => {
      let pending: boolean = false;
      for (const path of paths) {
        if (!LedgerResources.safe(path) || (!path.startsWith('images/') && !path.startsWith('icons/'))) { pending = true; continue; }
        const references = await db.querySql("SELECT relative_path FROM attachments WHERE relative_path=? UNION ALL SELECT icon_key FROM categories WHERE icon_key=? UNION ALL SELECT icon_key FROM accounts WHERE icon_key=? UNION ALL SELECT icon_key FROM category_history_nodes WHERE icon_key=? LIMIT 1", [path, 'resource:' + path, 'resource:' + path, 'resource:' + path]);
        let used: boolean;
        try { used = references.rowCount > 0; } finally { references.close(); }
        if (!used) {
          try { await this.resources.remove(path.startsWith('images/') ? 'images' : 'icons', path); }
          catch (_) { pending = true; continue; }
        }
        await db.executeSql('DELETE FROM book_deletion_files WHERE relative_path=?', [path]);
      }
      return pending;
    });
  }
}
