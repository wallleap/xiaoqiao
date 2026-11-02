# P0 验证记录

2026-11-02，本地 DevEco SDK 26，模拟器 API 26。

| 检查 | 结果 | 范围 |
|---|---|---|
| `node tools/verify-p0.mjs` | 18/18 通过 | 主机执行纯金额、业务与 FIFO 队列代码；不是鸿蒙 API 模拟 |
| `python3 tools/generate-rdb-schema.py --check` | 通过 | 82 条完整语句，生成文件匹配 SQL 源 SHA-256 |
| `python3 docs/database/verify_schema.py` | 57/57 通过 | SQLite 3.54.0、纯内存设计验证 |
| 主应用 `entry@default assembleHap` | 通过 | unsigned HAP，资源打包成功 |
| 测试 `entry@ohosTest assembleHap` | 通过 | 原生 ArkTS 编译覆盖新增 core/domain/data 和测试代码 |
| API 26 模拟器安装 | 通过 | 主 HAP、测试 HAP 均可安装 |
| Hypium 默认模板测试 | 通过 | 原有 assertContain，不计入 P0 功能覆盖 |
| 原生 BigInt、Decimal | 通过 | 大整数字符串往返；原生 Decimal 与精确分数算法舍入交叉检查 |
| 原事务接口外键探针 | 通过 | 合法结构但缺失币种引用的插入被 14800032 拒绝，回滚后无残留 |
| 原生 RDB P0 流程 | 通过 | 同币种支出、优惠、预算/资产独立标记、回滚、双 Repository 队列、失败后恢复、重开后的余额 |
| 资源映射与 SHA-256 | 2180/2180 通过 | 2178 SVG、2 README，内容不变 |

最终设备测试汇总：4 项执行，Pass 4、Error 0、Failure 0；其中 P0 原生测试 3 项，原有模板测试 1 项。`aa test` 外层退出码和 TestFinished-ResultCode 为 0，不能据此声称测试通过，必须检查 Hypium 汇总。

## 已修正的验证问题

- 原 media 子目录不符合资源打包要求：用户选择重命名后放平，分组前缀和映射表保留来源。
- ArkTS 不接受直接 throw 未声明类型的捕获值：按 Error 抛出；TestRunner 为接口，使用 implements。
- 测试 getAppContext 无法直接用于 RDB，createModuleContext 对该上下文亦失败；通过 AbilityMonitor 等待 EntryAbility，再使用其 UIAbilityContext，现已成功进入原生数据库建表阶段。
- 测试曾立即读取顶层 Ability，启动尚未就绪而失败；改为生命周期监听等待。
- 创建的完整 SQL 表、视图与触发器已由 SDK 接受；最初 createTransaction 实际外键状态检查失败，原生测试报 Error。用户确认后验证原事务接口，并改用 RdbSession 串行调度，最终写入、回滚、并发排队与重新打开后的余额断言均通过。
- 多个数据库测试各自启动并监听同一个已在前台的 Ability，后一个监听可能超时。测试改为复用首次获取的 UIAbilityContext，保留完整 RDB 断言后重跑通过。

单独尝试 `compileArkTS` 和 `:entry:default@CompileArkTS` 时因任务名不存在失败，属于调用方式问题；后续统一使用 `assembleHap`，完整 ArkTS 编译已通过。

## 外键问题与最终处理

`PRAGMA foreign_keys=ON` 是连接相关设置。初次 querySql 读取的连接为 0，随后直接检查 createTransaction 的 IMMEDIATE 连接也为 0，原生初始化主动拒绝继续。这是本次模拟器的实测结果，不能推广为所有版本的 SDK 结论。

用户已确认“验证原事务接口，通过后改为串行写入”。先用隔离数据库行为探针验证 RdbStore 原事务接口：插入一条只有外键缺失的账本记录，必须被 14800032 拒绝；回滚后记录数为零。探针通过后才切换持久层。

最终 RdbSession 在同一句柄上共享 FIFO 队列，读写均排队；使用 execute 检查写连接的外键状态，beginTransaction 后逐项 await SQL，全部成功才 commit。失败 rollBack，回滚失败则使会话失效。没有修改表结构、业务规则或放宽外键检查。

原生综合测试实际验证：30 元减 2 元优惠按 28 元入账；不计资产但计预算、不计预算但计资产；不存在账户导致完整回滚；双 Repository 连续排队写入、队列后读取；重复 ID 失败后下一笔仍可保存；无 draft 残留、5 条交易与 5 条 movement 对应、foreign_key_check 无异常；重开后余额 -112.00 元；超出 JS 安全整数的 SQLite INTEGER 转文本读取保持精确。

未执行生产迁移；应用首页、EntryAbility 均未修改，未建立正式账本。

完整复现命令在 [P0 基础说明](p0-foundation.md)。构建日志暂存系统临时目录，不提交。正式签名、真机、API 24 兼容验证均未完成。

早期失败尝试可能留下仅以 `xiaoqiao_p0_<UUID>.db` 命名的测试库；不含真实账目。现已把 finally 覆盖到 create 失败路径，后续失败也清理当前测试自己的名称，不扫描或删除其它数据库。

本次未模拟 rollback 本身失败、磁盘满或进程被杀；不可用会话分支已有保护，但尚无原生故障注入验证。多连接/多 worker 不在当前串行队列保证范围内。
