import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { AccountCommand, AccountDraft, AccountOverview, AccountProfile, requireAccountRevision } from '../../domain/model/AccountProfile';
import { RdbSession } from './RdbSession';

export class RdbAccountRepository {
  private readonly session: RdbSession;
  constructor(store: relationalStore.RdbStore) { this.session = RdbSession.forStore(store); }

  async snapshot(): Promise<AccountOverview> {
    return this.session.read(async (db: relationalStore.RdbStore): Promise<AccountOverview> => {
      const accounts: AccountProfile[] = [];
      const rows = await db.querySql("SELECT id,name,kind,currency_id,COALESCE(brand,''),COALESCE(icon_key,'bank_card'),COALESCE(icon_variant,'monochrome'),COALESCE(brand_color,'#5378B8'),include_in_net_assets,revision,archived_at_ms FROM accounts WHERE deleted_at_ms IS NULL ORDER BY sort_order,created_at_ms,id");
      try {
        while (rows.goToNextRow()) {
          if (rows.getString(3) !== 'CNY') { throw new Error('UNSUPPORTED_ACCOUNT_CURRENCY'); }
          accounts.push({ id: rows.getString(0), name: rows.getString(1), kind: rows.getString(2), currencyId: rows.getString(3),
            brand: rows.getString(4), iconKey: rows.getString(5), iconVariant: rows.getString(6), brandColor: rows.getString(7),
            includeInNetAssets: rows.getLong(8) === 1, revision: rows.getLong(9), archived: !rows.isColumnNull(10), balanceMinor: '0' });
        }
      } finally { rows.close(); }
      // Sum individual integer-text movements with BigInt, never SQLite SUM or floating point.
      const movements = await db.querySql('SELECT account_id,CAST(delta_minor AS TEXT) FROM v_effective_movements');
      const balances: Map<string, bigint> = new Map();
      try { while (movements.goToNextRow()) { const id = movements.getString(0);
        balances.set(id, (balances.get(id) || BigInt(0)) + BigInt(movements.getString(1))); } }
      finally { movements.close(); }
      let assets: bigint = BigInt(0); let liabilities: bigint = BigInt(0);
      for (const account of accounts) {
        const balance = balances.get(account.id) || BigInt(0); account.balanceMinor = balance.toString();
        if (account.includeInNetAssets) {
          if (balance >= BigInt(0)) { assets += balance; } else { liabilities -= balance; }
        }
      }
      return { accounts: accounts, assetsMinor: assets.toString(), liabilitiesMinor: liabilities.toString(), netMinor: (assets - liabilities).toString() };
    });
  }

  async create(command: AccountCommand): Promise<void> {
    const draft = new AccountDraft(command); const value = draft.command;
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const now = Date.now();
      await db.insert('accounts', { id: value.id, name: value.name, kind: value.kind, currency_id: 'CNY',
        brand: draft.style.brand, icon_key: draft.style.key, icon_variant: 'monochrome', brand_color: draft.style.color,
        include_in_net_assets: value.includeInNetAssets ? 1 : 0, created_at_ms: now, updated_at_ms: now });
      const adjustment = util.generateRandomUUID();
      const minor = value.opening.toSafeMinorNumber();
      await db.insert('balance_adjustments', { id: adjustment, account_id: value.id, kind: 'opening', before_minor: 0,
        after_minor: minor, delta_minor: minor, reason: '设置期初余额', occurred_at_ms: now, created_at_ms: now });
      await db.insert('account_movements', { id: util.generateRandomUUID(), account_id: value.id, currency_id: 'CNY',
        adjustment_id: adjustment, leg: 'adjustment', delta_minor: minor, occurred_at_ms: now });
      await db.update({ posting_state: 'posted' }, new relationalStore.RdbPredicates('balance_adjustments').equalTo('id', adjustment));
    });
  }

  async update(command: AccountCommand, revision: number): Promise<void> {
    const draft = new AccountDraft(command); requireAccountRevision(revision);
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      // Opening is immutable after creation. Metadata edits cannot move money or change the account kind/currency.
      const changed = await db.update({ name: draft.command.name, brand: draft.style.brand, icon_key: draft.style.key,
        icon_variant: 'monochrome', brand_color: draft.style.color, include_in_net_assets: command.includeInNetAssets ? 1 : 0,
        updated_at_ms: Date.now(), revision: revision + 1 }, new relationalStore.RdbPredicates('accounts')
        .equalTo('id', command.id).equalTo('kind', command.kind).equalTo('currency_id', 'CNY')
        .equalTo('revision', revision).isNull('deleted_at_ms'));
      if (changed !== 1) { throw new Error('ACCOUNT_CHANGED'); }
    });
  }

  async archive(id: string, revision: number, archived: boolean): Promise<void> {
    requireAccountRevision(revision);
    if (id.trim().length === 0) { throw new Error('INVALID_ACCOUNT'); }
    await this.session.write(async (db: relationalStore.RdbStore): Promise<void> => {
      const changed = await db.update({ archived_at_ms: archived ? Date.now() : null, revision: revision + 1,
        updated_at_ms: Date.now() }, new relationalStore.RdbPredicates('accounts').equalTo('id', id)
        .equalTo('currency_id', 'CNY').equalTo('revision', revision).isNull('deleted_at_ms'));
      if (changed !== 1) { throw new Error('ACCOUNT_CHANGED'); }
    });
  }
}
