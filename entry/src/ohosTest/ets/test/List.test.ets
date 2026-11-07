import backupPackageTest from './BackupPackage.test';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import webDavHttpTest from './WebDavHttp.test';
import webDavTest from './WebDav.test';
import accountCalibrationTest from './AccountCalibration.test';
import transferMigrationTest from './TransferMigration.test';
import abilityTest from './Ability.test';
import p0Test from './P0.test';
import ledgerHomeTest from './LedgerHome.test';
import expenseFlowTest from './ExpenseFlow.test';
import transfersTest from './Transfers.test';
import accountsTest from './Accounts.test';
import incomeTest from './Income.test';
import entryEditTest from './EntryEdit.test';
import localLedgerBackupTest from './LocalLedgerBackup.test';
import booksTest from './Books.test';
import spendingNatureTest from './SpendingNature.test';
import spendingNatureFlowTest from './SpendingNatureFlow';
import budgetNatureTest from './BudgetNature.test';
import budgetNatureFlowTest from './BudgetNatureFlow';

export default function testsuite() {
  abilityTest();
  p0Test();
  ledgerHomeTest();
  expenseFlowTest();
  entryEditTest();
  incomeTest();
  accountsTest();
  accountCalibrationTest();
  transfersTest();
  transferMigrationTest();
  localLedgerBackupTest();
  webDavTest();
  backupPackageTest();
  booksTest();
  spendingNatureTest();
  spendingNatureFlowTest();
  budgetNatureTest();
  budgetNatureFlowTest();
  if (abilityDelegatorRegistry.getArguments().parameters['-s class'] === 'WebDavHttp') { webDavHttpTest(); }
}
