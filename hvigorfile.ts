import { appTasks, OhosPluginId, OhosAppContext } from '@ohos/hvigor-ohos-plugin';
import { hvigor } from '@ohos/hvigor';

/**
 * versionCode 自动计算规则（与 tools/version.mjs、docs/versioning.md 保持一致）：
 *   versionCode = major * 1000000 + minor * 10000 + patch * 100 + revision
 *   - versionName: "major.minor.patch"，纯数字三段
 *   - revision: app.json5 的 buildVersion 字段（"0"-"99"），同一 versionName
 *     重复上传 AGC（如测试版被拒重传）时递增，由 `node tools/version.mjs --bump-rev` 维护
 */
function computeVersionCode(versionName: string, buildVersion: string): number {
  const parts: number[] = versionName.split('.').map((p) => Number.parseInt(p, 10));
  if (parts.length !== 3 || parts.some((p) => Number.isNaN(p) || p < 0)) {
    throw new Error(`versionName 必须为 x.y.z 三段纯数字，当前: "${versionName}"`);
  }
  const [major, minor, patch] = parts;
  if (major > 2147 || minor > 99 || patch > 99) {
    throw new Error(`版本段超出范围: "${versionName}"（major≤2147, minor/patch≤99）`);
  }
  const revision: number = Number.parseInt(buildVersion || '0', 10);
  if (Number.isNaN(revision) || revision < 0 || revision > 99) {
    throw new Error(`buildVersion 必须为 0-99 的整数，当前: "${buildVersion}"`);
  }
  return major * 1000000 + minor * 10000 + patch * 100 + revision;
}

hvigor.afterNodeEvaluate((node) => {
  const ctx = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext | undefined;
  if (!ctx) {
    return; // 仅根 app 节点绑定了 OHOS_APP_PLUGIN，模块节点跳过
  }
  const appJson = ctx.getAppJsonOpt();
  const revision: string = appJson.app.buildVersion ?? '0';
  const computed: number = computeVersionCode(appJson.app.versionName, revision);
  if (appJson.app.versionCode !== computed) {
    console.info(`[version] versionCode 自动计算: ${computed} (versionName=${appJson.app.versionName}, revision=${revision}, 原值=${appJson.app.versionCode})`);
    appJson.app.versionCode = computed;
    ctx.setAppJsonOpt(appJson);
  }
});

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
