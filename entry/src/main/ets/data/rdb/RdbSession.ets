import { relationalStore } from '@kit.ArkData';
import { SerialTaskQueue } from './SerialTaskQueue';

export class LedgerRollbackFailure extends Error {
  readonly originalError: Error;
  readonly rollbackError: Error;

  constructor(originalError: Error, rollbackError: Error) {
    super('LEDGER_WRITE_AND_ROLLBACK_FAILED');
    this.originalError = originalError;
    this.rollbackError = rollbackError;
  }
}

/** One owner per store handle. Do not use the raw store concurrently outside this session. */
export class RdbSession {
  private static readonly sessions: WeakMap<relationalStore.RdbStore, RdbSession> = new WeakMap();
  private readonly store: relationalStore.RdbStore;
  private readonly queue: SerialTaskQueue = new SerialTaskQueue();
  private unusable: boolean = false;

  private constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  static forStore(store: relationalStore.RdbStore): RdbSession {
    const existing = RdbSession.sessions.get(store);
    if (existing !== undefined) {
      return existing;
    }
    const session = new RdbSession(store);
    RdbSession.sessions.set(store, session);
    return session;
  }

  read<T>(work: (store: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    return this.queue.run(async (): Promise<T> => {
      this.requireUsable();
      return work(this.store);
    });
  }

  /** An exclusive maintenance operation can quarantine the handle if rollback fails. */
  invalidate(): void { this.unusable = true; }

  write<T>(work: (store: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    return this.queue.run(async (): Promise<T> => {
      this.requireUsable();
      // execute() inspects the writer connection; querySql() may inspect a different reader.
      await this.store.executeSql('PRAGMA foreign_keys=ON');
      const enabled = await this.store.execute('PRAGMA foreign_keys');
      if (enabled !== 1) {
        throw new Error('FOREIGN_KEYS_NOT_ENABLED');
      }
      // Begin outside catch: a failed begin must not roll back somebody else's transaction.
      this.store.beginTransaction();
      try {
        const value = await work(this.store);
        this.store.commit();
        return value;
      } catch (error) {
        try {
          this.store.rollBack();
        } catch (rollbackError) {
          this.unusable = true;
          throw new LedgerRollbackFailure(error as Error, rollbackError as Error);
        }
        throw error as Error;
      }
    });
  }

  private requireUsable(): void {
    if (this.unusable) {
      throw new Error('RDB_SESSION_UNUSABLE');
    }
  }
}
