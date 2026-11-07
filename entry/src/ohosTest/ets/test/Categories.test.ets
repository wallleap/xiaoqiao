import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';
import { CategoryProfile } from '../../../main/ets/domain/model/CategoryProfile';

let cachedContext: common.UIAbilityContext | undefined = undefined;

async function testContext(): Promise<common.UIAbilityContext> {
  if (cachedContext !== undefined) { return cachedContext; }
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  try {
    cachedContext = (await delegator.getCurrentTopAbility()).context;
    return cachedContext;
  } catch (_) { /* Class-only execution can start before EntryAbility is on top. */ }
  const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility', moduleName: 'entry' };
  await delegator.addAbilityMonitor(monitor);
  try {
    await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
    cachedContext = (await delegator.waitAbilityMonitor(monitor, 10000)).context;
    return cachedContext;
  } finally { await delegator.removeAbilityMonitor(monitor); }
}

export default function categoriesTest() {
  describe('Categories', () => {
    it('creates_multi_level_categories_reorders_moves_and_archives_safely', 0, async () => {
      const host = await testContext();
      const name = 'xiaoqiao_app_test_categories_' + util.generateRandomUUID() + '.db';
      try {
        const workspace = await LedgerWorkspace.open(host, name);
        await workspace.createCategory({ id: 'cat-pet', kind: 'expense', name: '宠物', iconKey: 'gift' });
        await workspace.createCategory({ id: 'cat-pet-food', kind: 'expense', parentId: 'cat-pet', name: '宠物粮', iconKey: 'food' });
        await workspace.createCategory({ id: 'cat-cat-food', kind: 'expense', parentId: 'cat-pet-food', name: '猫粮', iconKey: 'food' });
        let values = await workspace.categories();
        let catFood = values.find((item: CategoryProfile) => item.id === 'cat-cat-food');
        expect(catFood === undefined ? '' : catFood.parentId).assertEqual('cat-pet-food');
        let duplicate = false;
        try { await workspace.createCategory({ id: 'cat-duplicate', kind: 'expense', parentId: 'cat-pet', name: '宠物粮', iconKey: 'food' }); }
        catch (_) { duplicate = true; }
        expect(duplicate).assertTrue();

        const root = values.find((item: CategoryProfile) => item.id === 'cat-pet');
        expect(root === undefined ? 0 : root.sortOrder > 0).assertTrue();
        await workspace.moveCategory('cat-pet', root === undefined ? 1 : root.revision, -1);
        values = await workspace.categories();
        const movedRoot = values.find((item: CategoryProfile) => item.id === 'cat-pet');
        expect(movedRoot === undefined ? root?.sortOrder || 0 : movedRoot.sortOrder < (root?.sortOrder || 0)).assertTrue();

        let cycle = false;
        try {
          await workspace.updateCategory({ id: 'cat-pet', kind: 'expense', parentId: 'cat-cat-food', name: '宠物', iconKey: 'gift' },
            movedRoot === undefined ? 1 : movedRoot.revision);
        } catch (_) { cycle = true; }
        expect(cycle).assertTrue();

        values = await workspace.categories();
        const child = values.find((item: CategoryProfile) => item.id === 'cat-pet-food');
        await workspace.updateCategory({ id: 'cat-pet-food', kind: 'expense', parentId: 'cat-pet', name: '宠物食品', iconKey: 'gift' },
          child === undefined ? 1 : child.revision);
        expect((await workspace.categories()).find((item: CategoryProfile) => item.id === 'cat-pet-food')?.name).assertEqual('宠物食品');

        let parentArchive = false;
        const currentRoot = (await workspace.categories()).find((item: CategoryProfile) => item.id === 'cat-pet');
        try { await workspace.archiveCategory('cat-pet', currentRoot === undefined ? 1 : currentRoot.revision, true); }
        catch (_) { parentArchive = true; }
        expect(parentArchive).assertTrue();
        let grandchild = (await workspace.categories()).find((item: CategoryProfile) => item.id === 'cat-cat-food');
        await workspace.archiveCategory('cat-cat-food', grandchild === undefined ? 1 : grandchild.revision, true);
        let childNow = (await workspace.categories()).find((item: CategoryProfile) => item.id === 'cat-pet-food');
        await workspace.archiveCategory('cat-pet-food', childNow === undefined ? 1 : childNow.revision, true);
        const rootNow = (await workspace.categories()).find((item: CategoryProfile) => item.id === 'cat-pet');
        await workspace.archiveCategory('cat-pet', rootNow === undefined ? 1 : rootNow.revision, true);
        expect((await workspace.snapshot('2027-04')).categories.some((item) => item.id === 'cat-pet')).assertFalse();

        const archivedRoot = (await workspace.categories()).find((item: CategoryProfile) => item.id === 'cat-pet');
        await workspace.archiveCategory('cat-pet', archivedRoot === undefined ? 1 : archivedRoot.revision, false);
        const archivedChild = (await workspace.categories()).find((item: CategoryProfile) => item.id === 'cat-pet-food');
        await workspace.archiveCategory('cat-pet-food', archivedChild === undefined ? 1 : archivedChild.revision, false);
        expect((await workspace.snapshot('2027-04')).categories.some((item) => item.id === 'cat-pet-food')).assertTrue();
      } finally {
        await LedgerWorkspace.close(name);
        await relationalStore.deleteRdbStore(host, name);
      }
    });
  });
}
