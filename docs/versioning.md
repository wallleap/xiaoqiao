# 应用版本号规则

本文档描述 `AppScope/app.json5` 中版本号字段的分工、自动计算规则与 AGC 发版流程。`hvigorfile.ts` 的构建期 hook 与 `tools/version.mjs` 均按本规则实现，三处保持一致。

## 字段分工

| 字段 | 语义 | 取值 | 谁来改 |
|---|---|---|---|
| `versionName` | 用户可见版本 | 纯数字三段 `major.minor.patch`，major≤2147、minor/patch≤99 | 人，发版时 |
| `buildVersion` | 同一 versionName 重复上传 AGC 的序号（revision） | 字符串 "0"–"99" | 脚本 `--bump-rev` |
| `versionCode` | 升级判定依据（AGC 每次上传必须大于上一包） | 公式自动计算 | 构建期 hook，不手写 |

## versionCode 计算公式

```
versionCode = major × 1,000,000 + minor × 10,000 + patch × 100 + revision
```

示例：

| versionName | buildVersion(revision) | versionCode |
|---|---|---|
| 1.0.0 | 0 | 1000000 |
| 1.1.0 | 0 | 1010000 |
| 1.1.0 | 3 | 1010003 |
| 1.1.1 | 0 | 1010100 |

性质：

- 升高任意版本段后（即使 revision 归零），新 versionCode 恒大于旧版本的所有 revision（revision ≤ 99 < 100）。
- revision 递增保证同一 versionName 重复上传时 versionCode 严格递增。
- 公式天然满足 32 位上限（versionCode ≤ 2147483647）。

构建期由 `hvigorfile.ts` 的 hook 在内存中自动覆盖 `versionCode`（不写回磁盘），公式非法（versionName 非三段纯数字、revision 越界）时构建直接失败。app.json5 中的静态 `versionCode` 由 `tools/version.mjs` 同步，仅保证文件可读性。

## 一键发版

`tools/release.mjs` 封装「版本设置/递增 → 发版前检查 → release 构建 → 定位产物 → AGC 上传指引」全流程，可通过 `bin/release` 入口调用（参数完全一致）：

```bash
bin/release                           # 以当前版本构建 AGC 发布包（.app）
bin/release 1.1.0                     # 设置版本 1.1.0 后构建（发新版本）
bin/release --bump-rev                # 同版本重传：revision +1 后构建
bin/release --ci                      # CI 发版：校验后打 tag 推送，触发 Actions 自动构建签名上传
bin/release --ci --dry-run            # 预演 CI 发版（不打 tag、不推送）
bin/release --check-only              # 仅发版前检查，不改文件、不构建
bin/release --dry-run                 # 预演，显示将执行的步骤
bin/release --product <name>          # 指定 product（默认 default）
```

行为约定：

- 工作区有未提交变更时仅警告不阻塞（本项目的 build-profile.json5 本地签名配置常态为已修改）。
- 版本变更会真实写入 `AppScope/app.json5`；构建失败时保留变更，修复后直接重跑。
- 本地模式 **不自动 git commit**（需人工确认后提交），**不自动上传 AGC**（无官方上传 API，需控制台人工操作）。
- 产物为 release 模式整包（`.app`）；脚本结尾会打印产物路径、AGC 填写的版本名称/版本号与提交提醒。
- `--ci` 模式要求 `AppScope/app.json5` 无未提交变更且已配置 git remote，否则直接失败。

## 管理命令

```bash
node tools/version.mjs                 # 显示当前版本信息
node tools/version.mjs set 1.2.0       # 设置 versionName，revision 归 "0"，同步 versionCode
node tools/version.mjs --bump-rev      # revision +1，同步 versionCode（同版本重传 AGC 时用）
node tools/version.mjs --check         # 校验静态值与公式一致（供 CI/提交前检查，不一致退出码 1）
```

revision 达上限 99 时，提升 `patch` 并将 revision 归零（`set` 新的三段版本号）。

## CI 自动发版（GitHub Actions）

`.github/workflows/` 下两条流水线：

| Workflow | 触发 | 作用 |
|---|---|---|
| `build-check.yml` | push / PR / 手动 | debug+release 双模式构建检测 + `version.mjs --check` 版本一致性校验，不签名不上传 |
| `release.yml` | push tag `v*` / 手动 | 四 job：prepare（tag ↔ app.json5 交叉校验）→ build-sign（构建签名）→ upload-agc → github-release |

### 运行环境

- 默认托管 `ubuntu-24.04` + 公开 CI 镜像 `ghcr.io/wallleap/harmonyos-ci`（预装 DevEco Command Line Tools 26 + JDK17，匿名拉取）。
- 仓库 Variables（Settings → Secrets and variables → Actions → Variables）：

| Variable | 说明 |
|---|---|
| `CI_IMAGE` | 覆盖 CI 镜像（如自建镜像） |
| `CI_RUNNER` | 设为 `self-hosted` 时走自托管裸机（需预装 SDK/Node/JDK17，不用容器） |
| `OHPM_REGISTRY` | ohpm 私有源（可选） |

### tag 规则

```
buildVersion=0  →  v1.2.0        # 常规发版
buildVersion>0  →  v1.2.0-r3     # 同版本重传
```

仓库为唯一事实源：CI 不注入版本，tag 仅与 `AppScope/app.json5` 交叉校验（tag 版本 == versionName、`-rN` == buildVersion），不一致即失败。versionCode 由构建期 hook 按公式计算。

### 发版操作

```bash
bin/release 1.2.0            # 或 node tools/version.mjs set 1.2.0
git add AppScope/app.json5 && git commit -m "chore(release): 发布 1.2.0"
git push
bin/release --ci             # 打 tag v1.2.0 并推送，触发 Actions 自动完成后续
```

同版本重传：`bin/release --bump-rev` → 提交 → `bin/release --ci`（tag 形如 `v1.2.0-r3`）。

### 首次使用前置

1. 推送仓库到 GitHub 并确认 Actions 可用。
2. 配置签名材料 Secrets（材料文件不入仓库；本机 `signature/` 目录已被 `.gitignore` 忽略）。先生成 base64（macOS 用 `base64 -i <file>`，Linux 用 `base64 -w0 <file>`），再粘贴到仓库 Secrets：

```bash
base64 -i signature/release.p12          # → Secret RELEASE_P12_B64
base64 -i signature/release.cer          # → Secret RELEASE_CER_B64
base64 -i signature/releaseProfile.p7b   # → Secret RELEASE_P7B_B64
```

3. 配置其余仓库 Secrets：

| Secret | 说明 |
|---|---|
| `SIGN_STORE_PASSWORD` | 发布证书 `.p12` 密码 |
| `SIGN_KEY_PASSWORD` | 发布私钥密码（通常与 store 相同） |
| `SIGN_KEY_ALIAS` | 密钥别名 |
| `AGC_CLIENT_ID` / `AGC_CLIENT_SECRET` | AGC Connect API 凭证（AGC「团队管理 → 常规」创建） |
| `AGC_APP_ID` | AGC 应用 ID |

4. AGC 后台为当前版本创建**草稿**（上传 API 要求草稿 state=7）。

CI 内签名材料由 Secrets 解码到 runner 临时目录（`$RUNNER_TEMP`），仅签名 job 内使用、结束即清理，不进入仓库和构建产物。真正需要保密的只有 `.p12` 密码——`.p12` 本身是加密容器，`.cer`/`.p7b` 是公开材料；仓库本身可公开。若不想配置 CI 签名，可用手动触发 `--skip-agc-upload` 仅出包，或改用本地 `bin/release` 流程。

## AGC 发版流程

1. **新版本开发**：`node tools/version.mjs set 1.1.0`，随代码提交。
2. **测试版（内测/公测）**：构建产物上传 AGC。若同一 versionName 需要再次上传（被驳回、修复后重提），先 `node tools/version.mjs --bump-rev` 再构建上传。
3. **正式版**：同样规则。revision 跨测试与正式全局单调递增使用，正式包 versionCode 恒大于此前所有测试包，满足 AGC「版本号必须大于上一版本」的校验。
4. `versionName` 永远纯数字三段，不带 `-beta` 等后缀；测试/正式的区分由 AGC 渠道表达。

## 相关文件

- `AppScope/app.json5`：版本字段载体
- `hvigorfile.ts`：构建期 versionCode 自动计算 hook
- `tools/version.mjs`：版本管理脚本（公式与 hook 一致）
- `tools/release.mjs`：一键发版脚本（含 `--ci` 模式）
- `bin/release`：一键发版入口（参数与 release.mjs 一致）
- `.github/workflows/build-check.yml`：CI 构建检测流水线
- `.github/workflows/release.yml`：CI 自动发版流水线
