import abilityTest from './Ability.test';
import p0Test from './P0.test';
import ledgerHomeTest from './LedgerHome.test';

export default function testsuite() {
  abilityTest();
  p0Test();
  ledgerHomeTest();
}