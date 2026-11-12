# 账目详情与支出编辑闭环

2026-11-05。接续 `e08f956`，用户确认优先实现详情与编辑。只接入已有表结构和当前人民币支出能力，不执行生产迁移、批量修复或历史数据改写；已有本地签名配置保持不动。

## 操作范围

- 点击真实账目进入账单式详情：分类、实付金额、原金额/优惠、记录时间、账本、分类路径、资金账户、预算/资产规则、备注。没有“本机已保存”等技术状态文案。
- 详情读取独立的单笔快照，不使用列表缺省值拼凑编辑数据；读取失败/已删除显示重试和返回，不伪造空白表单。
- 详情“编辑账目”、左滑编辑、长按编辑共用同一 ExpenseEditor。保留原账目ID、版本、金额/优惠、分类、账户、日期、备注和规则；标题显示“编辑账目”。
- 保存后刷新详情与首页；日期跨月时首页选到修改后的月份。取消编辑不写库，返回详情重新读取，以发现外部修改。
- 详情删除沿用现有单笔软删除与二次确认。删除成功回到首页；失败保留详情。
- 本文首轮可编辑范围为同币种CNY支出。后续已接入同币种CNY[收入新增/编辑](income-flow.md)和[转账闭环](transfers-flow.md)；带FX快照/外币结算的记录仍只读。预览数据不查询或写入真实库。

## 数据契约

`EntryDetail` 独立保存 categoryId、accountId、revision、原金额/优惠/实付、本位币金额、币种定义、两个计入规则、balanceMode和完整时间信息。分类路径沿父分类读取，允许直接选父分类；已归档的原分类/账户可原样回填，不能新选其它已归档项。

编辑不改时间时保留原 occurredAtMs、timezone、offsetMinutes、localDate，编辑页按原偏移显示时间，不因当前设备时区不同而静默换日。用户明确修改日期/时间后按当前设备本地时间记录。

`UpdateExpense` 复用 ExpenseRecord 做金额、精度、优惠、同币种结算和日期校验；单独的 ExpenseUpdateRepository 端口避免更改原新增接口。expectedRevision 必须为正安全整数，并为递增保留范围。

`RdbLedgerRepository.updateExpense` 在共享 RdbSession 串行事务中：

1. 查询有效已发布支出，检查账本、expectedRevision及币种/FX范围。
2. 检查分类、账户可用性；允许保持原归档关联，不允许切换到其它归档或已删除项。
3. 按ID、账本、版本、类型、posted及未删除条件进入draft，revision加1；受影响行数必须为1。
4. 更新表单字段，替换本笔资金变动，时间同步；金额与账户余额全部使用精确最小单位，不额外手工扣加余额。
5. 重新发布，执行既有发布触发器。任一步失败整体回滚，不留draft、不产生新账目、不改变原资金影响。

不改 balance_mode、导入身份、来源身份、created_at_ms、商户、附件、标签及其它未编辑字段；preserve历史导入即使改金额或账户仍不影响余额。并发冲突/已删除在编辑器中阻止继续保存，提示返回详情刷新，不覆盖新版本。

## 文件职责

| 文件 | 核心变化 |
| --- | --- |
| domain/model/EntryDetail.ets | 真实详情与编辑快照 |
| domain/ports/ExpenseUpdateRepository.ets、domain/services/UpdateExpense.ets | 编辑端口、复用域校验 |
| data/rdb/RdbLedgerRepository.ets | 同ID、版本检查、完整事务更新 |
| data/rdb/LedgerWorkspace.ets | 单笔详情读取、分类路径、编辑用例入口 |
| components/EntryDetailPage.ets | HDS导航、账单式详情、编辑/删除与错误状态 |
| components/ExpenseEditor.ets | 回填、更新时间保留、编辑保存和冲突处理 |
| components/LedgerSwipeActions.ets | 接通左滑与长按编辑 |
| components/AmountText.ets | 可选打开回调，账目金额进入详情，摘要完整金额弹窗保留 |
| pages/Index.ets | 详情/编辑路由、刷新与删除返回 |
| ohosTest/.../EntryEdit.test.ets、ExpenseFlow.test.ets、List.test.ets | 事务、保留策略与真实UI闭环回归 |
| tools/verify-p0.mjs | 编辑命令校验与错误传递主机检查 |

## 验证记录

主包及测试包构建已通过；主机29项检查通过，Schema包仍与源SQL的82条语句一致。新增原生用例检查跨账户/跨月份、预算/资产标志、同ID与版本、旧版本冲突、发布失败回滚、删除后拒绝编辑、preserve导入余额策略与身份保留。真实UI用例覆盖详情、两次编辑保存、列表汇总，以及侧滑/长按编辑取消不产生写入；所有写操作限定UUID隔离测试库。

首次编译发现 ArkTS 不接受不同接口对象的隐式结构转换，以及 Row 容器不能设置 fontSize；已使用显式目标对象和对子Text设置字号修正，未通过弱化检查绕开。

API 26 模拟器原生完整回归通过：`Tests run: 12, Failure: 0, Error: 0, Pass: 12, Ignore: 0`。其中真实UI测试完成新增→详情→两次编辑保存→首页汇总、左滑编辑取消、长按编辑取消与删除确认；两个新增持久层测试验证跨账户/月、规则切换、版本冲突、发布失败完整回滚，以及导入身份/余额策略保留。

已检查原生测试生成的亮色详情截图（`xiaoqiao-entry-receipt.png`）：金额、原金额删除线/优惠、分类路径、备注和底部按钮没有重叠，顶部与底部系统区域保留可用间距。测试截图与日志留在临时目录，不纳入仓库。测试结束后重启正式入口，退出隔离库测试状态。

执行命令包括 `node tools/verify-p0.mjs`、`python3 tools/generate-rdb-schema.py --check`、Hvigor `entry@default` / `entry@ohosTest` 的 `assembleHap --no-daemon`、`aa test -b cn.oicode.xiaoqiao -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 180000 -w 300` 和 `git diff --check`，均通过。

未修改表结构、SDK、依赖、权限、全局窗口或签名配置；深色、大字号、宽屏、低版本与完整多币种编辑尚未验收。跨设备时区显示保留已实现，但尚未做设备切换时区的UI专项检查。未自动提交。

## 小票视觉调整（2026-11-05）

用户要求详情卡片更像小票。本次仅修改 EntryDetailPage 的视觉：纸张主体圆角由20vp缩小为4vp；金额区与明细区之间保留虚线并加两侧半圆缺口；底边增加连续小撕口。缺口复用页面背景变量，纸张复用卡片背景变量，不引入图片或新颜色。分类图标由44vp缩至32vp，明细行上下内边距由12vp改为9vp，减少普通信息卡的松散感。保留系统字体与DIN金额、原有数据和全部操作行为。

主包、测试包构建及 git diff --check 已通过。API 26 模拟器完整回归再次通过：12/12，0失败、0错误。检查本轮真实详情截图，纸张边缘、两侧缺口、贯穿虚线和底部撕口正常显示，明细与操作按钮无重叠。截图保存在临时目录 `xiaoqiao-ticket-receipt.png`，未纳入仓库。此次仅验收亮色手机布局，深色、大字号及宽屏仍未专项验收。

商户、地址已接入手动新增和编辑，支持回填、修改与清空，详见[商户与地址](merchant-address.md)。

2026-11-12：有保存坐标的账目在地址下方展示原生小地图，点击可打开原生地点详情；手动改地址清除旧坐标。只有地址文字的旧账目仍按文字显示，编辑并重新选点后可保存坐标。范围及验证见[商户与地址](merchant-address.md)。
