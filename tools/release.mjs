#!/usr/bin/env node
/**
 * 一键发版脚本（零依赖），流程与 docs/versioning.md 保持一致：
 *   版本设置/递增 → 发版前检查 → release 构建 → 定位 .app 产物 → AGC 上传指引
 *
 * 用法：
 *   node tools/release.mjs                 使用当前版本构建 AGC 发布包（.app）
 *   node tools/release.mjs 1.1.0           先设置版本为 1.1.0，再构建
 *   node tools/release.mjs --bump-rev      同版本重传 AGC：revision +1 后构建
 *   node tools/release.mjs --ci            CI 发版：校验后打 tag 并推送，触发 GitHub Actions
 *                                          自动构建签名 → 上传 AGC → GitHub Release
 *   node tools/release.mjs --check-only    仅执行发版前检查，不改文件、不构建
 *   node tools/release.mjs --dry-run       预演：显示将执行的步骤，不改文件、不构建
 *
 * 选项：
 *   --product <name>   构建的 product（默认 default）
 *
 * --ci 标签规则（与 .github/workflows/release.yml 对应）：
 *   buildVersion=0  → v<versionName>          如 v1.2.0
 *   buildVersion>0  → v<versionName>-r<N>     如 v1.2.0-r3
 *
 * 说明：本地模式不自动 git commit、不自动上传 AGC（无官方上传 API，需在控制台人工操作）；
 *       --ci 模式要求版本变更已提交，由 CI 完成构建签名与上传。
 */
import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const VERSION_SCRIPT = join(ROOT, 'tools', 'version.mjs');
const APP_JSON5_PATH = join(ROOT, 'AppScope', 'app.json5');

function fail(msg) {
  console.error(`✗ ${msg}`);
  process.exit(1);
}

function run(cmd, args) {
  const res = spawnSync(cmd, args, { stdio: 'inherit', cwd: ROOT });
  if (res.status !== 0) {
    fail(`命令执行失败: ${cmd} ${args.join(' ')}`);
  }
}

function readApp() {
  return JSON.parse(readFileSync(APP_JSON5_PATH, 'utf-8')).app;
}

const SKIP_DIRS = new Set(['oh_modules', 'node_modules', '.git', '.hvigor', 'hvigor', '.idea', '.cxx', '.clangd']);

function findNewestByExt(dir, ext) {
  let newest = null;
  const walk = (current) => {
    let entries;
    try {
      entries = readdirSync(current, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = join(current, entry.name);
      if (entry.isDirectory()) {
        if (!SKIP_DIRS.has(entry.name)) {
          walk(full);
        }
      } else if (entry.name.endsWith(ext)) {
        const mtime = statSync(full).mtimeMs;
        if (!newest || mtime > newest.mtime) {
          newest = { path: full, mtime };
        }
      }
    }
  };
  walk(dir);
  return newest;
}

function parseArgs(argv) {
  const opts = { version: null, bumpRev: false, ci: false, dryRun: false, checkOnly: false, product: 'default' };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--bump-rev') {
      opts.bumpRev = true;
    } else if (arg === '--ci') {
      opts.ci = true;
    } else if (arg === '--dry-run') {
      opts.dryRun = true;
    } else if (arg === '--check-only') {
      opts.checkOnly = true;
    } else if (arg === '--product') {
      const next = argv[i + 1];
      if (!next) {
        fail('--product 需要一个 product 名称参数');
      }
      opts.product = next;
      i++;
    } else if (/^\d+\.\d+\.\d+$/.test(arg)) {
      if (opts.version) {
        fail(`重复的版本参数: "${arg}"`);
      }
      opts.version = arg;
    } else {
      fail(`未知参数: ${arg}，用法见脚本头部注释`);
    }
  }
  if (opts.version && opts.bumpRev) {
    fail('版本号与 --bump-rev 不能同时使用：发新版本传 x.y.z，同版本重传用 --bump-rev');
  }
  if (opts.ci && (opts.version || opts.bumpRev)) {
    fail('--ci 不能与版本号/--bump-rev 同时使用：请先设置版本并提交，再单独执行 --ci');
  }
  if (opts.ci && opts.checkOnly) {
    fail('--ci 与 --check-only 不能同时使用');
  }
  return opts;
}

/**
 * CI 发版：校验后打 tag 并推送，由 GitHub Actions（release.yml）完成
 * 构建 → 签名 → 上传 AGC → GitHub Release。
 * 标签规则：buildVersion=0 → v<versionName>；>0 → v<versionName>-r<N>。
 */
function releaseCi(dryRun) {
  // 1. 版本变更必须已提交（tag 打在当前 HEAD，CI 会做 tag ↔ app.json5 交叉校验）
  const st = spawnSync('git', ['status', '--porcelain', '--', 'AppScope/app.json5'], { cwd: ROOT, encoding: 'utf-8' });
  if (st.status === 0 && st.stdout.trim()) {
    fail('AppScope/app.json5 有未提交变更：请先提交版本变更，再执行 --ci（CI 会校验 tag 与仓库版本一致）');
  }
  // 2. 需要 git remote（推 tag 触发 Actions）
  const rem = spawnSync('git', ['remote'], { cwd: ROOT, encoding: 'utf-8' });
  const remoteName = rem.status === 0
    ? rem.stdout.split('\n').map((s) => s.trim()).filter(Boolean)[0]
    : undefined;
  if (!remoteName) {
    fail('未配置 git remote：--ci 需要推送到 GitHub 触发 Actions（先 git remote add origin <url>）');
  }
  // 3. 计算标签名
  const app = readApp();
  const revision = app.buildVersion ?? '0';
  const tag = revision === '0' ? `v${app.versionName}` : `v${app.versionName}-r${revision}`;
  const message = `release ${app.versionName} (rev ${revision}, versionCode ${app.versionCode})`;

  if (dryRun) {
    console.log('▶ 预演（不执行）CI 发版:');
    console.log('  1. node tools/version.mjs --check');
    console.log(`  2. git tag -a ${tag} -m "${message}"`);
    console.log(`  3. git push ${remoteName} ${tag}`);
    console.log('  4. GitHub Actions release.yml 自动: prepare 校验 → 构建签名 → 上传 AGC → GitHub Release');
    console.log(`  目标 tag: ${tag}`);
    return;
  }

  // 4. 发版前检查（版本公式一致性）
  run('node', [VERSION_SCRIPT, '--check']);

  // 5. tag 不能已存在
  const exists = spawnSync('git', ['rev-parse', '-q', '--verify', `refs/tags/${tag}`], { cwd: ROOT });
  if (exists.status === 0) {
    fail(`tag ${tag} 已存在：若为同版本重传，请先执行 node tools/version.mjs --bump-rev 并提交，再重新 --ci`);
  }

  // 6. 打 tag 并推送
  console.log(`▶ 创建并推送 tag: ${tag}`);
  run('git', ['tag', '-a', tag, '-m', message]);
  run('git', ['push', remoteName, tag]);

  console.log(`\n✓ tag ${tag} 已推送到 ${remoteName}`);
  console.log('  GitHub Actions 将自动: prepare 校验 → 构建签名 → 上传 AGC → 创建 GitHub Release');
  console.log('  进度见仓库 Actions 页面；前置条件（签名材料/AGC secrets 配置）见 docs/versioning.md');
}

function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (opts.ci) {
    releaseCi(opts.dryRun);
    return;
  }

  const git = spawnSync('git', ['status', '--porcelain'], { cwd: ROOT, encoding: 'utf-8' });
  if (git.status === 0 && git.stdout.trim()) {
    const files = git.stdout.trim().split('\n');
    console.warn(`⚠ 工作区有未提交变更（构建仍将继续，发版前建议先提交）:`);
    for (const line of files) {
      console.warn(`    ${line}`);
    }
  }

  const current = readApp();
  let targetVersionName = current.versionName;
  let targetRevision = current.buildVersion ?? '0';
  if (opts.version) {
    targetVersionName = opts.version;
    targetRevision = '0';
  } else if (opts.bumpRev) {
    targetRevision = String(Number.parseInt(targetRevision, 10) + 1);
  }

  if (opts.dryRun) {
    console.log('▶ 预演（不修改文件、不构建）:');
    if (opts.version) {
      console.log(`  1. node tools/version.mjs set ${opts.version}   # ${current.versionName} → ${opts.version}，revision → 0`);
    } else if (opts.bumpRev) {
      console.log(`  1. node tools/version.mjs --bump-rev            # revision ${current.buildVersion} → ${targetRevision}`);
    } else {
      console.log('  1. 版本不变，跳过版本变更');
    }
    console.log('  2. node tools/version.mjs --check');
    console.log(`  3. devecocli build --product ${opts.product} --build-mode release`);
    console.log('  4. 定位 .app 产物并输出 AGC 上传指引');
    console.log(`  目标版本: ${targetVersionName} (rev ${targetRevision})`);
    return;
  }

  if (opts.version) {
    run('node', [VERSION_SCRIPT, 'set', opts.version]);
  } else if (opts.bumpRev) {
    run('node', [VERSION_SCRIPT, '--bump-rev']);
  }

  run('node', [VERSION_SCRIPT, '--check']);

  const app = readApp();
  console.log('\n▶ 发版版本信息:');
  console.log(`  versionName : ${app.versionName}`);
  console.log(`  versionCode : ${app.versionCode}`);
  console.log(`  buildVersion: ${app.buildVersion}`);

  if (opts.checkOnly) {
    console.log('\n✓ 发版前检查通过（--check-only，未构建）');
    return;
  }

  console.log(`\n▶ 构建 release 发布包 (product=${opts.product}) ...`);
  const build = spawnSync('devecocli', ['build', '--product', opts.product, '--build-mode', 'release'], { stdio: 'inherit', cwd: ROOT });
  if (build.error) {
    fail(`无法启动 devecocli（请确认已安装并在 PATH 中）: ${build.error.message}`);
  }
  if (build.status !== 0) {
    fail(`构建失败 (exit ${build.status})，请修复后重跑；版本变更已写入 AppScope/app.json5`);
  }

  const newestApp = findNewestByExt(ROOT, '.app');
  const newestHap = findNewestByExt(ROOT, '.hap');

  console.log('\n✓ 发布包构建完成');
  if (newestApp) {
    const builtAt = new Date(newestApp.mtime);
    console.log(`  产物 (.app): ${relative(ROOT, newestApp.path)}`);
    console.log(`  构建时间    : ${builtAt.toLocaleString()}`);
  } else {
    console.warn('  ⚠ 未找到 .app 产物（整包需 --product 指定有效 product）；最新 .hap:');
    if (newestHap) {
      console.warn(`    ${relative(ROOT, newestHap.path)}`);
    } else {
      console.warn('    （也无 .hap，请检查构建输出）');
    }
  }

  console.log('\n▶ 下一步（人工操作）:');
  console.log('  1. AGC 控制台 → 我的应用 → 该应用 → 版本管理/软件包 → 上传软件包');
  if (newestApp) {
    console.log(`     选择: ${newestApp.path}`);
  }
  console.log(`  2. 页面版本信息填写: 版本名称=${app.versionName}，版本号=${app.versionCode}`);
  console.log(`  3. 记得提交版本变更: git add AppScope/app.json5 && git commit -m "chore(release): 发布 ${app.versionName}"`);
}

main();
