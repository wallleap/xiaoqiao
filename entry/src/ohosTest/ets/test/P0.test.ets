import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Decimal, util } from '@kit.ArkTS';
import { relationalStore } from '@kit.ArkData';
import { CurrencyUnit } from '../../../main/ets/core/money/CurrencyUnit';
import { Money } from '../../../main/ets/core/money/Money';
import { ExchangeRate } from '../../../main/ets/core/money/ExchangeRate';
import { ExpenseCommand } from '../../../main/ets/domain/model/ExpenseRecord';
import { RecordExpense } from '../../../main/ets/domain/services/RecordExpense';
import { RdbLedgerRepository } from '../../../main/ets/data/rdb/RdbLedgerRepository';
import { ValidationDatabase } from '../../../main/ets/data/rdb/ValidationDatabase';
import { REVIEW_SCHEMA_STATEMENTS } from '../../../main/ets/data/rdb/ReviewSchema';

function command(id: string, accountId: string = 'cash', assets: boolean = true, budget: boolean = true): ExpenseCommand {
  const unit = new CurrencyUnit('CNY', 'CNY', 2);
  return {
    id: id, bookId: 'book', categoryId: 'food', gross: Money.parse('30.00', unit),
    discount: Money.parse('2.00', unit), bookPaid: Money.parse('28.00', unit),
    accountId: accountId, accountPaid: Money.parse('28.00', unit),
    includeInAssets: assets, includeInBudget: budget, note: 'P0 TEST ONLY',
    occurredAtMs: 1790830800000, localDate: '2026-10-01', timezone: 'Asia/Shanghai', offsetMinutes: 480
  };
}

async function scalar(store: relationalStore.RdbStore, sql: string): Promise<string> {
  const result = await store.querySql(sql);
  try {
    if (!result.goToFirstRow()) {
      throw new Error('EXPECTED_TEST_ROW');
    }
    return result.getString(0);
  } finally {
    result.close();
  }
}

let cachedContext: common.UIAbilityContext | undefined = undefined;

async function testContext(): Promise<common.UIAbilityContext> {
  if (cachedContext !== undefined) {
    return cachedContext;
  }
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
  await delegator.addAbilityMonitor(monitor);
  try {
    await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
    const ability = await delegator.waitAbilityMonitor(monitor, 10000);
    cachedContext = ability.context;
    return cachedContext;
  } finally {
    await delegator.removeAbilityMonitor(monitor);
  }
}

export default function p0Test() {
  describe('P0Native', () => {
    it('bigint_and_native_decimal_rounding', 0, () => {
      const cny = new CurrencyUnit('CNY', 'CNY', 2);
      const usd = new CurrencyUnit('USD', 'USD', 2);
      const amount = Money.fromMinorText('900719925474099312345', cny);
      expect(Money.fromData(amount.toData(), cny).minor.toString()).assertEqual('900719925474099312345');
      const rate = new ExchangeRate(usd, cny, '0.5');
      for (const input of ['0.01', '-0.01', '12.34']) {
        const native = new Decimal(input).mul('0.5').toFixed(2, Decimal.ROUND_HALF_UP);
        expect(rate.convert(Money.parse(input, usd)).toDecimalString()).assertEqual(native);
      }
    });

    it('legacy_transaction_enforces_foreign_keys', 0, async () => {
      const context = await testContext();
      const name = 'xiaoqiao_p0_legacy_' + util.generateRandomUUID() + '.db';
      const store = await ValidationDatabase.open(context, name);
      try {
        for (const statement of REVIEW_SCHEMA_STATEMENTS) {
          await store.executeSql(statement);
        }
        // Probe the writer through behavior: this valid book has only one error, a missing currency FK.
        store.beginTransaction();
        let violation = false;
        try {
          await store.executeSql("INSERT INTO books(id,name,base_currency_id,timezone,created_at_ms,updated_at_ms) VALUES('bad','TEST','missing','Asia/Shanghai',1,1)");
        } catch (error) {
          const failure = error as BusinessError;
          expect(failure.code).assertEqual(14800032);
          violation = true;
        } finally {
          store.rollBack();
        }
        expect(violation).assertTrue();
        expect(await scalar(store, 'SELECT CAST(COUNT(*) AS TEXT) FROM books')).assertEqual('0');
      } finally {
        await store.close();
        await ValidationDatabase.remove(context, name);
      }
    });

    it('rdb_atomic_write_reopen_and_integer_bridge', 0, async () => {
      const context = await testContext();
      const name = 'xiaoqiao_p0_' + util.generateRandomUUID() + '.db';
      let store: relationalStore.RdbStore | undefined = undefined;
      try {
        store = await ValidationDatabase.create(context, name);
        await store.executeSql("INSERT INTO currencies(id,code,name,symbol,minor_unit,valid_from,source_version) VALUES('CNY','CNY','TEST','TEST',2,'2026-01-01','P0 TEST')");
        await store.executeSql("INSERT INTO books(id,name,base_currency_id,timezone,created_at_ms,updated_at_ms) VALUES('book','TEST','CNY','Asia/Shanghai',1,1)");
        await store.executeSql("INSERT INTO categories(id,book_id,kind,name,name_key,created_at_ms,updated_at_ms) VALUES('food','book','expense','TEST','test',1,1)");
        await store.executeSql("INSERT INTO accounts(id,name,kind,currency_id,created_at_ms,updated_at_ms) VALUES('cash','TEST','asset','CNY',1,1)");
        await store.executeSql("INSERT INTO budgets(id,book_id,currency_id,period_start_date,period_end_date_exclusive,total_minor,created_at_ms,updated_at_ms) VALUES('budget','book','CNY','2026-10-01','2026-11-01',100000,1,1)");
        const repository = new RdbLedgerRepository(store);
        const service = new RecordExpense(repository);
        await service.execute(command('expense'));
        await service.execute(command('excluded', 'cash', false));
        expect(await scalar(store, 'SELECT CAST(balance_minor AS TEXT) FROM v_account_balances')).assertEqual('-2800');
        expect(await scalar(store, 'SELECT CAST(expense_minor AS TEXT) FROM v_book_totals')).assertEqual('5600');
        let rejected = false;
        try {
          await service.execute(command('invalid', 'missing-account'));
        } catch (_) {
          rejected = true;
        }
        expect(rejected).assertTrue();
        expect(await scalar(store, "SELECT CAST(COUNT(*) AS TEXT) FROM transactions WHERE id='invalid'")).assertEqual('0');
        expect(await scalar(store, "SELECT CAST(COUNT(*) AS TEXT) FROM transactions WHERE posting_state='draft'")).assertEqual('0');
        expect(await scalar(store, 'SELECT CAST(used_minor AS TEXT) FROM v_budget_usage')).assertEqual('5600');
        // Two repository objects share one queue for the same store handle, including reads.
        const secondRepository = new RdbLedgerRepository(store);
        const secondService = new RecordExpense(secondRepository);
        const firstWrite = service.execute(command('parallel-a'));
        const secondWrite = secondService.execute(command('parallel-b', 'cash', true, false));
        const queuedRead = repository.readBalance('cash', new CurrencyUnit('CNY', 'CNY', 2));
        await Promise.all([firstWrite, secondWrite]);
        expect((await queuedRead).toDecimalString()).assertEqual('-84.00');
        // A rejected queued transaction must not prevent the following transaction from committing.
        const duplicate = service.execute(command('expense')).then((): boolean => false, (): boolean => true);
        const recovery = secondService.execute(command('after-rejection'));
        expect(await duplicate).assertTrue();
        await recovery;
        expect(await scalar(store, 'SELECT CAST(used_minor AS TEXT) FROM v_budget_usage')).assertEqual('11200');
        expect(await scalar(store, 'SELECT CAST(expense_minor AS TEXT) FROM v_book_totals')).assertEqual('14000');
        expect(await scalar(store, 'SELECT CAST(COUNT(*) AS TEXT) FROM transactions')).assertEqual('5');
        expect(await scalar(store, 'SELECT CAST(COUNT(*) AS TEXT) FROM account_movements')).assertEqual('5');
        expect(await scalar(store, "SELECT CAST(COUNT(*) AS TEXT) FROM transactions WHERE posting_state='draft'")).assertEqual('0');
        const foreignKeyCheck = await store.querySql('PRAGMA foreign_key_check');
        try {
          expect(foreignKeyCheck.rowCount).assertEqual(0);
        } finally {
          foreignKeyCheck.close();
        }
        // SQLite INTEGER is exact beyond Number's safe range when read as text.
        expect(await scalar(store, "SELECT CAST(CAST('9007199254740993' AS INTEGER) AS TEXT)")).assertEqual('9007199254740993');
        await store.close();
        store = await ValidationDatabase.open(context, name);
        const balance = await new RdbLedgerRepository(store).readBalance('cash', new CurrencyUnit('CNY', 'CNY', 2));
        expect(balance.toDecimalString()).assertEqual('-112.00');
      } finally {
        if (store !== undefined) {
          await store.close();
        }
        await ValidationDatabase.remove(context, name);
      }
    });
  });
}
