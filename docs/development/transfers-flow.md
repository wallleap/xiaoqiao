# 转账、还款、手续费与优惠券

2026-11-05。用户确认：普通转账、信用卡还款、借款还款、充值、提现；手续费和还款优惠全部绑定同一条转账，不生成独立收支账目。手续费计入支出，是否计入预算可选。本轮仍限定人民币同币种；不改依赖、权限、SDK或本地签名配置。

## 金额与余额

主金额表示转入金额（还款时为偿还本金），实际转出＝转入金额＋手续费－还款优惠。例：还款100、优惠5、手续费2，付款账户扣97、负债账户增加100（负债减少100）；支出和预算默认仅计2。关闭手续费预算后，支出仍为2，预算用量为0。本金和优惠不算普通收支。

所有金额以Money/BigInt精确计算，以整数分保存，SQLite边界检查安全整数。手续费、还款优惠在键盘中分别选择输入，支持加减，每个数和结果限制9位整数、2位小数；末尾运算符可继续输入，但不可保存。异常输入拒绝该次操作；删除和清空保持可用。实际转出和转入预览同时显示，点金额回到主金额输入。全额优惠可使实际转出为0，此时只有入账movement，不保存零金额movement。

用途选择信用卡/借款还款时，转入侧必须是负债账户，选择Sheet和写入层都校验。优惠仅用于这两种用途；切换到非还款用途会清空优惠并隐藏其入口。充值、提现暂按普通账户间转账处理，仍要求两侧人民币账户。

“计入资产”控制双方余额是否变化，与手续费是否统计支出/预算、账户是否参与净资产汇总独立。历史导入balance_mode=preserve保持不动余额。手工记账不是支付指令，不以余额不足阻止记录；允许记录负余额。

## 录入与小票

HdsNavigation中的支出/收入/转账沿用已有沉浸光感。转账隐藏收支分类和普通优惠，表单依次显示用途、左右账户卡、时间/备注、手续费预算、资产规则。左右账户等宽，中间44vp交换按钮；账户名最多两行。选择一侧时排除另一侧账户。还款交换后目标仍须为负债账户，否则提示并保持原方向。新写入要求账户使用中；编辑允许原侧保留原归档账户。

键盘上方使用手续费、还款优惠两枚自适应输入控件，当前编辑项用品牌色。表单与账户Sheet使用现有THICK材质；金额卡、键盘和安全区保持既有布局。

小票主金额为实际转出，明细展示转入金额、双方账户、手续费、还款优惠及手续费预算规则。新增、同ID编辑、删除均刷新首页、资产和预算；取消编辑不写库。

首页“全部”一笔转账只显示一行，主金额为实际转出，转出→转入账户说明和手续费小字。支出筛选在手续费大于0时显示同一条记录，主金额仅显示手续费，点击仍进入完整转账；收入筛选不显示。日期汇总、月支出和预算只累计手续费，本金与券不累计。搜索/账户筛选匹配任一侧。

## 数据结构与事务

V1基础SQL保持原文和checksum。新增`docs/database/schema-v2-transfer.sql`，由`tools/generate-transfer-schema.py`生成TransferSchema.ets；不得手工修改生成文件。

`transfer_details.transaction_id`与transactions一对一：purpose、currency_id、from_account_id、to_account_id、out_minor、in_minor、fee_minor、coupon_minor、fee_in_expense、fee_in_budget。它是同一条账目的附属字段，不是额外账目。主表gross/paid/book_minor保存转入/还款本金，普通discount_minor保持0，include_in_budget保持0，手续费预算使用独立字段。读写不得把本金误当实际扣款或手续费支出。

RdbTransferRepository经共享RdbSession串行事务处理：

1. 编辑检查ID、账本、类型和revision；拒绝分组、FX、非CNY记录，新建拒绝重复ID。
2. 检查双方账户、币种和归档状态，校验还款目标为负债。
3. 创建draft主表，或按revision将原记录转draft并递增版本；保留导入身份、balance_mode、created_at_ms和未编辑关联。
4. 写入/更新同一条transfer_details，整笔重建实际出账、入账movement。
5. 发布时SQL触发器核对账户、金额公式、用途、两腿方向/金额/数量、币种及时间；失败全部回滚。

软删除主表后，两侧movement和手续费统计同步失效。旧分组转账仍拒绝单笔编辑/删除，不自动转换旧关联手续费，不批量重写历史账目。旧转账没有transfer_details时继续走V1等额双腿规则，读取默认普通转账、手续费/优惠0。跨币种、外币汇率和类型转换另行设计。

## 旧库升级与回滚

旧库普通打开只识别并提示升级，不自动执行迁移。首页提供“备份并升级账本”，确认框说明本机备份、增加字段和失败回滚；确认后才调用LedgerDatabase.upgrade。新建空库在首次建库事务内安装V1+V2；UUID隔离测试库允许测试自动升级。

TransferMigration先校验V1注册记录及checksum，再调用原生RdbStore.backup生成`<库名>_before_transfer_v2.db`。备份成功后才在串行事务中增加表、替换发布触发器与汇总视图，运行foreign_key_check/quick_check，比较旧表行数、原账目ID/版本/状态/金额和每账户精确余额，最后写入version2及扩展checksum。没有改写原交易、movement或余额。新建空库无历史数据可比较，跳过历史指纹；仍在同一事务检查结构完整性。原生RDB在首次DDL提交前读连接不能可靠读取新表，因此不对未提交的新表执行旧库指纹查询。

失败回滚表/触发器/视图/标记，保留备份；备份失败不开始迁移。未知schema/校验值拒绝打开，不重建不覆盖。恢复备份必须停止使用账本，核对目标后调用原生restore；这是恢复到升级前状态，会丢失升级后的新增记录，不自动执行。迁移和备份恢复验证仅操作UUID测试库，正式账本升级尚未执行。

## 文件职责

| 文件 | 核心变化 |
| --- | --- |
| domain/model/TransferRecord.ets、ports/TransferRepository.ets、services/TransferService.ets | 用途、精确金额和优惠校验，新增/编辑端口 |
| data/rdb/RdbTransferRepository.ets | 同一条转账明细及双方资金事务、版本冲突保护 |
| data/rdb/TransferMigration.ets、LedgerDatabase.ets | 识别旧库、备份、事务升级与首次建库 |
| docs/database/schema-v2-transfer.sql、tools/generate-transfer-schema.py、TransferSchema.ets | 增量表、发布约束、统计视图及生成校验 |
| LedgerWorkspace.ets、EntryDetail.ets、LedgerSnapshot.ets | 实际金额/用途/手续费读取与统计 |
| LedgerOverview.ets、Index.ets | 支出筛选只显示手续费、日汇总、升级确认入口 |
| ExpenseEditor.ets、EntryDetailPage.ets | 用途、手续费/券键盘输入、账户卡和小票 |
| Transfers.test.ets、TransferMigration.test.ets、TransfersFlow.ets | 事务、余额、迁移回滚/恢复、真实UI验证 |
| tools/verify-p0.mjs | 精确金额、错误输入、筛选与日汇总检查 |

## 验证进度

基础同币种转账阶段已通过主机37项、API26设备18/18项及双包构建。当前扩展验证以本节后续结果为准。

扩展新增原生覆盖：97/100实际双侧、同条记录和明细数量、手续费支出与预算视图、预算关闭、编辑目标校验与回滚、全额优惠零转出、关闭重开、删除恢复余额、posted明细不可直接改；旧库升级保留原金额/版本/余额、备份恢复、晚期迁移失败回滚原触发器/视图/结构；UI正常转账及还款用途、手续费与优惠加减、97/100预览、支出筛选、小票、编辑回填与删除。

深色、大字号、宽屏、旧API、跨时区仍待专项验收。正式账本未执行V2迁移，未自动提交本轮改动。

### 本轮最终结果

- `node tools/verify-p0.mjs`：39/39通过。
- `python3 tools/generate-rdb-schema.py --check`：V1基础82条一致；`python3 tools/generate-transfer-schema.py --check`：V2扩展10条一致。
- Hvigor `entry@default`、`entry@ohosTest` 的 `assembleHap --no-daemon`：均通过。构建仍有异常处理、互斥分支重复组件ID等警告，未关闭检查。
- API26模拟器：`aa test -b cn.oicode.xiaoqiao -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 300000 -w 600`，最终21/21通过，0失败、0错误；总耗时287135ms。用例全程使用UUID隔离库，未执行真实账本升级。
- `git diff --check`通过。未提交，未修改已有本地签名配置。
- 首轮新库初始化在未提交DDL期间读取历史指纹失败，导致14项连带错误；修正新建空库与既有库校验分支后完整21/21通过。截图又发现键盘附加金额的按值Builder参数不刷新，改为直接状态绑定，并加入`手续费1+1 / 还款优惠7−2`文字断言，最终完整21/21通过。
- 最终模拟器截图已目视检查：录入显示100、实际转出97、转入100，键盘表达式同步；支出页仅计手续费2，预算扣2，卡片注明转出97；小票显示97/100及手续费2/优惠5，无重叠。长账户名按两行/列表省略规则显示。
- 临时证据：`/tmp/xq-fees-native-final.log`、`/tmp/xq-fees-host-final.log`、`/tmp/xq-fees-build-final.log`、`/tmp/xq-fees-test-build-final.log`，截图`/tmp/xiaoqiao-repayment-input-final.png`、`/tmp/xiaoqiao-repayment-expense-final.png`、`/tmp/xiaoqiao-repayment-receipt.png`。它们不纳入Git。

测试注册涉及`ohosTest/ExpenseFlow.test.ets`、`ohosTest/List.test.ets`；账户/收入/详情文档中的转账入口引用保留于`docs/development/accounts-flow.md`、`income-flow.md`、`entry-detail-edit.md`。写入规则与升级语义同步于`docs/database/write-contract.md`。正式应用下次启动若识别到V1，将先提示备份并升级；只有用户在应用中确认才执行。
