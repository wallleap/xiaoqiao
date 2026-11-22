#!/usr/bin/env node
/**
 * 应用版本号管理脚本（零依赖），规则与 hvigorfile.ts 的构建期 hook、docs/versioning.md 保持一致：
 *   versionCode = major * 1000000 + minor * 10000 + patch * 100 + revision
 *
 * 用法：
 *   node tools/version.mjs                 显示当前 versionName / versionCode / buildVersion
 *   node tools/version.mjs set 1.2.0       设置 versionName，buildVersion 归 "0"，同步 versionCode
 *   node tools/version.mjs --bump-rev      buildVersion +1（同版本重传 AGC 时用），同步 versionCode
 *   node tools/version.mjs --check         校验静态 versionCode 是否等于公式值（供 CI/提交前检查）
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const APP_JSON5_PATH = join(dirname(fileURLToPath(import.meta.url)), '..', 'AppScope', 'app.json5');

function computeVersionCode(versionName, buildVersion) {
  const parts = String(versionName).split('.').map((p) => Number.parseInt(p, 10));
  if (parts.length !== 3 || parts.some((p) => Number.isNaN(p) || p < 0)) {
    throw new Error(`versionName 必须为 x.y.z 三段纯数字，当前: "${versionName}"`);
  }
  const [major, minor, patch] = parts;
  if (major > 2147 || minor > 99 || patch > 99) {
    throw new Error(`版本段超出范围: "${versionName}"（major≤2147, minor/patch≤99）`);
  }
  const revision = Number.parseInt(buildVersion || '0', 10);
  if (Number.isNaN(revision) || revision < 0 || revision > 99) {
    throw new Error(`buildVersion 必须为 0-99 的整数，当前: "${buildVersion}"`);
  }
  return major * 1000000 + minor * 10000 + patch * 100 + revision;
}

function readAppJson() {
  return JSON.parse(readFileSync(APP_JSON5_PATH, 'utf-8'));
}

function writeAppJson(appJson) {
  writeFileSync(APP_JSON5_PATH, JSON.stringify(appJson, null, 2) + '\n', 'utf-8');
}

function show(appJson) {
  console.log(`versionName : ${appJson.app.versionName}`);
  console.log(`versionCode : ${appJson.app.versionCode}`);
  console.log(`buildVersion: ${appJson.app.buildVersion}`);
}

function main() {
  const args = process.argv.slice(2);
  const appJson = readAppJson();

  if (args.length === 0) {
    show(appJson);
    return;
  }

  if (args[0] === 'set') {
    const versionName = args[1];
    if (!versionName) {
      console.error('用法: node tools/version.mjs set <x.y.z>');
      process.exit(1);
    }
    appJson.app.versionName = versionName;
    appJson.app.buildVersion = '0';
    appJson.app.versionCode = computeVersionCode(versionName, '0');
    writeAppJson(appJson);
    console.log('已更新:');
    show(appJson);
    return;
  }

  if (args[0] === '--bump-rev') {
    const revision = Number.parseInt(appJson.app.buildVersion || '0', 10);
    if (Number.isNaN(revision) || revision < 0) {
      console.error(`buildVersion 非法: "${appJson.app.buildVersion}"`);
      process.exit(1);
    }
    if (revision >= 99) {
      console.error('revision 已达上限 99，请提升 patch 并将 revision 归零（set 新的 x.y.z）');
      process.exit(1);
    }
    const next = String(revision + 1);
    appJson.app.buildVersion = next;
    appJson.app.versionCode = computeVersionCode(appJson.app.versionName, next);
    writeAppJson(appJson);
    console.log('已更新:');
    show(appJson);
    return;
  }

  if (args[0] === '--check') {
    const computed = computeVersionCode(appJson.app.versionName, appJson.app.buildVersion);
    if (appJson.app.versionCode !== computed) {
      console.error(
        `versionCode 不一致: 静态值 ${appJson.app.versionCode} ≠ 公式值 ${computed} ` +
        `(versionName=${appJson.app.versionName}, buildVersion=${appJson.app.buildVersion})，` +
        `请运行 node tools/version.mjs set ${appJson.app.versionName} 修复`
      );
      process.exit(1);
    }
    console.log(`版本号一致: ${appJson.app.versionName} (rev ${appJson.app.buildVersion}) → versionCode ${computed}`);
    return;
  }

  console.error(`未知参数: ${args[0]}，支持: set <x.y.z> | --bump-rev | --check`);
  process.exit(1);
}

main();
