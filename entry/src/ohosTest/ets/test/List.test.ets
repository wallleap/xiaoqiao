import abilityTest from './Ability.test';
import p0Test from './P0.test';
import ledgerHomeTest from './LedgerHome.test';
import expenseFlowTest from './ExpenseFlow.test';
import accountsTest from './Accounts.test';
import incomeTest from './Income.test';
import entryEditTest from './EntryEdit.test';

export default function testsuite() {
  abilityTest();
  p0Test();
  ledgerHomeTest();
  expenseFlowTest();
  entryEditTest();
  incomeTest();
  accountsTest();
}
