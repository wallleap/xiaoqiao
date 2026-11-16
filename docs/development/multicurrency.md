# 多币种记账

本轮范围已由用户确认：外币收支、外币账户、跨币种转账、部分/全额退款与报销，以及相关统计、导入导出和备份兼容。账本和预算沿用人民币 CNY 作为汇总币种；不改变已有账本本位币。旧人民币账目不重新计价。

## 官方数据来源

采用欧洲中央银行 ECB 的公开参考汇率，客户端直接请求以下官方 HTTPS 数据文件，无 API Key：

- 近 90 日：https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml
- 完整历史：https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml
- 官方说明：https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html
- API 备选：https://data.ecb.europa.eu/help/api/data-examples

ECB 按工作日发布欧元基准参考价，不是实时成交价。记账日期无报价时选择不晚于该日期的最近报价，保留真实报价日期；没有对应数据时要求手动填写，不用未来报价替代过去日期。交叉汇率按“目标币种/欧元 ÷ 原币种/欧元”计算，使用 BigInt 有理数并输出 12 位小数，金额换算只在目标币种边界 HALF_UP。参考报价落盘缓存，六小时后尝试更新，网络失败可使用已缓存报价并标记来源；没有缓存时不凭空假定 1:1。

ECB 数据免费，显示来源；交叉汇率属于本应用计算。公开数据不是银行实际结算价，用户可改汇率或填写实际到账/扣款金额。授权条款：https://www.ecb.europa.eu/services/using-our-site/disclaimer/html/index.en.html 。不把免费汇率包装为独家付费数据。

华为 Ability Gallery 的 Exchange Rate 文档描述的是能力提供方的 Fulfillment 契约，并非可直接调用的公开汇率数据服务，因此不据此虚构 HarmonyOS 汇率 SDK。

币种目录覆盖 ECB 当前常见的 30 种币种（含 EUR），小数位核对 ISO 4217 维护机构 SIX 的官方 List One；JPY/KRW/ISK 为 0 位，其余本轮币种为 2 位。目录以明确代码与精度保存，不从符号推断币种。

## 记账与账户

- 记一笔可选择币种，选择后重置金额草稿，避免把原数字直接解释成另一币种；编辑已有账目时保留原币种。
- 原币金额为主，列表辅以人民币折算额；详情显示保存的汇率、来源和日期。保存后汇率变化不会改变历史账目。
- 账本折算与账户结算各有独立快照。跨币种账户可填写到账汇率和实际结算金额，实际金额以 ACTUAL 保存；同币种结算必须金额一致。
- 创建账户时选择币种，余额、期初和校准都按账户原币记录。已有账户币种不可变更。
- 净资产将外币账户按最新可用参考价折算人民币，原币余额不变；有非零外币余额无法估值时，净资产显示不可用，不把外币分值直接与人民币分值相加。净资产估值随汇率变化，与历史收支快照口径不同。
- 换汇转账记录原币本金、实际转出、转入币种与金额、原币手续费/优惠、人民币手续费；转出与转入账户不能相同，偿还用途仍要求转入负债账户。本金不计收支，手续费按人民币计入支出/预算。

## 报销、退款

回款金额以原支出币种填写，两类累计不超过原实付。到账账户可以使用不同币种，保存实际到账金额与汇率。预算/支出冲减沿用原支出的账本折算比例，按回款到账日期记录；最后一笔收齐时分配剩余舍入尾差，避免全额收回后仍残留支出。到账账户余额按实际到账币种增加。编辑原账目不能把金额降到已回款之下，人民币折算额也不能低于已冲减额。

## V7 升级与备份

用户已确认数据库迁移方案：只编写升级，不在本轮直接操作设备数据库。沿用应用内升级确认入口。

- 新增 fx_transfer_details，与旧 transfer_details 通过只读 v_transfer_details 统一；不重建旧转账记录。
- expense_recoveries 追加人民币折算、账户原币金额/币种、汇率快照字段；旧值通过视图兼容，不重写原 amount_minor。
- 使用已有 fx_snapshots 保存收支与换汇快照，更新账目时在草稿事务内重建。
- 更新汇总/预算/有效账户流水视图，改用对应币种金额；补充 currencies 目录。
- V6→V7 升级前保存 `<数据库名>_before_multicurrency_v7.db`；事务内检查旧记录数、原金额/预算、有效账户流水指纹，以及外键和 quick_check，失败回滚并保留副本。回退到旧程序前必须恢复升级前副本，旧程序不能读取 V7。
- SQL 源：docs/database/schema-v7-multicurrency.sql；生成命令：`python3 tools/generate-multicurrency-schema.py`。只打包语句与校验和，不打开数据库或执行 SQL。
- 完整备份导出标记 schema=7，恢复 V2～V6 备份时先升级候选副本，再走既有预览与恢复确认；旧版应用不能读取新版备份。

## CSV 与数据边界

CSV 新增“多币种快照”和“人民币折算金额”，包含原币金额、账户金额、币种及汇率快照。默认完整导出保留这些字段。导入核对币种、金额、汇率、账户币种和安全整数边界；外币行缺失快照时明确拒绝，不静默按人民币导入。同名不同币种账户按名称+币种匹配；已有人民币 CSV 无需新增字段。

所有联网请求仅下载公共汇率，不发送账本、金额、头像、账号标识或凭据。不新增依赖或权限，不触碰本地签名配置。

## 验证与手动检查

遵循用户“无需自动测试，由用户手动测试”的要求，未运行构建、自动化测试、设备部署、迁移、恢复或真实资金数据操作。已下载官方 ECB XML 核对响应结构，核对 SIX 官方币种精度，检查相对导入和迁移源/生成校验和，并执行 git diff --check；这些检查不等于编译或运行验证。

手动检查重点：

1. V6 旧账确认升级，人民币记录、预算与余额保持；旧备份恢复可升级到 V7。
2. USD 支出/收入、JPY 整数金额；联网报价、手填报价、离线有/无缓存。
3. 外币原币账户、人民币结算账户，实际结算金额保存及编辑后保持。
4. CNY→USD、USD→JPY 换汇，两端余额、手续费和预算折算。
5. 外币支出分次退款/报销直到全额，校验限额、尾差、跨币种到账与删除回款。
6. 月/年统计与净资产，CSV 完整导出后导回、损坏/缺失快照被拒绝。

## 改动文件索引

| 文件 | 核心变化 |
| --- | --- |
| core/money/Currencies.ets | 30 币种目录、小数位与精确交叉报价 |
| core/money/FxConversion.ets | 同币种一致性、参考/实际结算快照校验 |
| data/exchange/OfficialExchangeRates.ets | ECB 官方历史数据、缓存、按日期选价 |
| domain/model/FxEntrySnapshot.ets | CSV 可携带的精确金额与汇率快照 |
| domain/model/ExpenseRecord.ets | 外币支出的账本与账户双转换校验 |
| domain/model/IncomeRecord.ets | 外币收入双转换参数 |
| domain/model/TransferRecord.ets | 原币本金、到账金额、折算手续费校验 |
| domain/model/ExpenseRecovery.ets | 回款原币、账本和到账字段 |
| domain/model/AccountProfile.ets | 外币账户、净资产估值缺失信息 |
| domain/model/AccountCalibration.ets | 按账户币种校准 |
| domain/model/EntryDetail.ets | 详情汇率及账户结算字段 |
| domain/model/LedgerSnapshot.ets | 列表完整多币种快照 |
| data/rdb/RdbFxSnapshots.ets | 写入及读取账本/结算汇率快照 |
| data/rdb/RdbLedgerRepository.ets | 收支按账户币种入账、编辑时重建快照 |
| data/rdb/RdbTransferRepository.ets | 两种账户币种的转账流水与 V7 明细 |
| data/rdb/RdbRecoveryRepository.ets | 原币限额、账本尾差与跨币种到账 |
| data/rdb/RdbAccountRepository.ets | 外币期初、余额、校准及归档 |
| data/rdb/RdbStatisticsRepository.ets | 统计使用账本折算与手续费折算 |
| data/rdb/LedgerWorkspace.ets | 外币净资产估值、列表/详情/CSV 联动 |
| data/rdb/MulticurrencyMigration.ets | V7 备份、事务升级和完整性校验 |
| data/rdb/MulticurrencySchema.ets | 由 SQL 源生成的迁移语句与校验和 |
| data/rdb/TransferMigration.ets | 兼容验证 V7 迁移链 |
| data/rdb/LedgerDatabase.ets | 新库与显式升级接入 V7 |
| data/rdb/LocalLedgerBackup.ets | 恢复旧备份候选副本时升级 V7 |
| data/backup/LedgerBackupPackage.ets | 备份包版本兼容 |
| data/exchange/LedgerCsvExport.ets | 原币字段、人民币折算及完整快照导出 |
| data/exchange/LedgerCsvImport.ets | 快照/金额一致性和账户币种匹配 |
| components/ExpenseEditor.ets | 币种、汇率、实际结算和折算预览 |
| components/ExpenseRecoveryPanel.ets | 外币回款限额、跨币种到账输入 |
| components/AccountEditor.ets | 创建账户选币种并固定现有账户币种 |
| components/AccountsPage.ets | 原币余额与人民币参考净资产 |
| components/AccountCalibrationPage.ets | 使用账户小数位与币种标签 |
| components/AccountAdjustmentHistoryPage.ets | 原币历史金额显示 |
| components/MoneyAmountField.ets | 响应币种精度变化的金额输入 |
| components/EntryDetailPage.ets | 原币/折算/结算及来源日期 |
| components/AmountText.ets | 支持自定义币种符号 |
| presentation/ledger/LedgerOverview.ets | 保留快照及按原币计算回款徽标 |
| pages/Index.ets | 原币金额、折算说明和 V7 升级文案 |
| docs/database/schema-v7-multicurrency.sql | 新增表、字段、发布约束和派生视图 |
| tools/generate-multicurrency-schema.py | 打包迁移源，禁止手动改生成文件 |
| docs/development/multicurrency.md | 方案、数据来源、边界与手动验证说明 |

代码路径均位于 entry/src/main/ets 下；docs、tools 行使用项目根目录路径。

编译反馈修复：金额换算方法改名为 settlementAmount，避免与已有 settlement UI Builder 重名；保留无参数 Builder 调用。通过方法重名与调用静态检查，未运行构建。

金额输入反馈修复：ExpenseEditor 不再用 currency getter 向金额校验传参，改为 amountCurrency() 显式构造当前币种，键盘、优惠、转账、预览及保存统一调用；汇率输入与原币金额输入保持独立。补充币种配置/精度错误提示。该调整尚未设备验证，不能仅凭静态检查断言已复现并修复设备上的全部输入问题。
