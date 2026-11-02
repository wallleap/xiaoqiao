# P0：金额与持久层基础

日期：2026-11-02。P0 先建立可验证的金额、业务和数据库边界，暂不接入页面，也不对用户数据库执行迁移。

## 代码组织与依赖

```text
entry/src/main/ets/
  core/money/           CurrencyUnit、Money、ExchangeRate；无鸿蒙 API 依赖
  domain/model/         ExpenseCommand、校验后的 ExpenseRecord
  domain/ports/         LedgerRepository 接口
  domain/services/      RecordExpense 用例；只依赖模型与接口
  data/rdb/             RdbSession、串行队列、RDB 实现、验证库工厂、生成的 SQL 包
```

后续页面通过用例调用业务能力，不直接拼 SQL。domain 不依赖 data 或 UI；data 实现 domain 的接口。继续按具体功能新增用例，避免把所有功能放进一个数据库工具类。

## 金额契约

- 币种定义包含稳定版本 ID、三字母代码及 0～4 位精度；同代码不同版本也不允许直接运算。
- Money 内部使用 BigInt 最小单位。输入十进制字符串，超出币种精度直接报错；不使用 parseFloat 或二进制浮点做金额运算。
- JSON 保存 `{currencyId, amountMinor}`，金额为整数字符串。显示由精度还原小数。
- V1 SQL 单个金额限于 ±9,007,199,254,740,991 最小单位；越界必须报错，只有验证范围后才能转 number 传入 INTEGER 列。
- 查询余额使用 `CAST(balance_minor AS TEXT)` 后转 BigInt，避免 getLong 返回 number 的精度损失。SQLite SUM 超过 64 位的异常直接向上传递；分批 BigInt 汇总后续补充。
- 汇率是正十进制字符串，方向为一单位原币兑换多少目标币。核心将有限小数转为 BigInt 分数，按目标币种精度一次 HALF_UP 舍入，中点远离零。这样不依赖 Decimal 的全局默认精度。设备测试用原生 Decimal 交叉核对常见向量，但不修改 Decimal 全局配置。

## 首条写入路径

`RecordExpense → ExpenseRecord → LedgerRepository → RdbLedgerRepository`。

当前覆盖手动新增同币种支出：原额减优惠得实付；预算与资产标记相互独立。每笔写入使用 RdbStore 原事务接口 beginTransaction/commit/rollBack，先存 draft 交易与资金变动，再校验发布为 posted，最后提交。先等待每项异步 SQL 完成，再同步 commit。任一步失败回滚；回滚本身失败单独抛出 LedgerRollbackFailure，调用方必须把状态视为未确认，同一个会话拒绝继续读写。

ExpenseRecord 在异步写入前复制输入，防止调用方修改原命令导致金额与字段不一致。日期必须与时间戳和记录的 UTC 偏移匹配；IANA 时区与当时偏移的对应校验尚待时区适配层。ID 当前只检查非空，由调用方生成；未承诺完整输入校验或数据库升级能力。

完整多币种的表结构已设计，但本用例明确拒绝缺少 FX 快照的外币结算。收入、转账、编辑/删除、余额校准、导入、附件、备份和正式启动初始化还未实现；不能把本 P0 骨架作为完整账务服务交付。

## SQL 的唯一来源

源文件为 `docs/database/schema-v1.sql`。`ReviewSchema.ets` 由脚本生成，包含 SHA-256 与 82 条完整语句，触发器体不会按分号误切分。

```sh
python3 tools/generate-rdb-schema.py
python3 tools/generate-rdb-schema.py --check
python3 docs/database/verify_schema.py
node tools/verify-p0.mjs
```

主机脚本只转译、执行纯 ETS 核心，不模拟 @kit，也不替代 ArkTS 编译或设备测试。默认使用 DevEco 已带的 TypeScript；其它环境可用 `P0_TYPESCRIPT_PATH` 指向已安装的编译器，无需新增项目依赖。

ValidationDatabase 只允许 `xiaoqiao_p0_*.db` 名称，拒绝已有表的数据库；不接入 EntryAbility。设备测试使用 UUID 临时库并关闭、删除，仅清理自己的测试库。

## 构建与设备检查

```sh
hvigorw --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
hvigorw --mode module -p product=default -p module=entry@ohosTest -p buildMode=debug assembleHap --no-daemon
hdc install entry/build/default/outputs/default/entry-default-unsigned.hap
hdc install entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap
hdc shell aa test -b cn.oicode.xiaoqiao -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 30000 -w 60
```

设备结果见 [验证记录](p0-verification.md)。createTransaction 连接外键关闭的问题已通过原事务接口与串行会话方案避开，API 26 模拟器的 P0 原生检查通过。构建存在 SDK“函数可能抛异常”提示，调用方必须处理 Promise 拒绝；发布签名尚未配置。本地模拟器可安装 unsigned HAP，这不代表满足真机或上架要求。

资源构建原先因 media 子目录失败；经用户确认选择重命名图标后已修正，见 [资源说明](../assets/media-resources.md)。没有修改签名、SDK、权限或依赖配置。

## 串行会话的使用约束

- `RdbSession.forStore` 用 WeakMap 为同一 RdbStore 句柄复用一个队列；创建多个 Repository 也不会产生多个事务队列。
- 读操作与写操作都排队，避免读取尚未提交的中间状态。排队任务失败时错误仍传给原调用者，后续任务继续执行；回滚失败则将会话标为不可用。
- 每笔写入在开始事务前设置 `PRAGMA foreign_keys=ON`，并用 `execute('PRAGMA foreign_keys')` 检查写连接。`querySql` 可能读取另一个池连接，不能用于判断该写连接状态。
- 禁止在会话以外并行使用同一个原始 store；禁止为同一个数据库文件重复创建句柄或跨 worker 各自建立队列。正式数据库生命周期管理器尚未接入，未来必须提供单一所有者。
- 关闭 store 前由所有者等待在途用例结束。不要在 write 回调内部再次调用同一会话的 read/write，以免形成队列自等待。
- 本方案是当前 API 26 模拟器实测选择，不宣称所有 SDK/设备均有同样表现。API 24、真机、磁盘满与进程中断恢复仍需验证。
