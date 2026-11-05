# 账户管理闭环

后续进展：人民币同币种转账已接入，见[转账闭环](transfers-flow.md)。本文中的转账未接入描述保留账户管理首轮的范围。

2026-11-05。用户确认在 `6301e52` 后完成人民币资产/负债账户列表、新增、期初余额、名称/品牌图标编辑、归档及收支记账选择。本轮不改表结构、checksum、依赖、SDK、权限、窗口配置或本地签名配置。验证仅使用UUID隔离数据库。

## 用户行为与边界

资产Tab接通正式账户列表和净资产汇总，保留现有悬浮Tab Bar、HdsNavigation和正文滚动。显示CNY净资产、总资产、总负债；汇总按有效资金变动的正负余额计算，且只包括“计入总资产”的账户。归档账户若仍计入总资产，其余额继续进入汇总，并显示说明，不将归档当成清零。

新增页提供账户名称、资产/负债类型、品牌图标、期初余额/期初待还金额及“计入总资产”。名称去首尾空白、1–40字符；CNY最多两位小数，最小单位须在安全整数范围内。输入非负金额，资产存为正余额，负债待还金额存为负余额；资产账户暂不在创建时录入负的透支余额。零余额也保留一条完整的opening事件。

当前提供现金、微信、支付宝、普通银行卡、工商/中国/建设/农业/招商银行、信用卡、花呗、借呗12种品牌模板。复用现有 `accounts_*` SVG（先前已从rawfile方案按用户要求重命名为media资源）。单色白图标配品牌背景；AccountAvatar保留彩色图标使用主题黑/白底的分支。资源内容未修改。

编辑可改名称、品牌图标及是否计入总资产；账户类型和币种固定，余额只读，不改写期初余额。本轮未接余额校准、删除账户、交易明细页、外币账户或转账。已有归档账户可查看/编辑，并可恢复使用；归档有二次确认，不清理历史账目或余额。

新建账户进入收支记账的账户Sheet。选中名称直接绑定状态，保存收支后首页和资产页刷新。无论从哪个Tab新增收支，保存成功回到账目Tab；取消返回原Tab。编辑旧账允许保留原归档账户；新账保存时在事务内重新检查账户仍使用中，避免已打开的表单写入刚归档的账户。

## 写入与精度

- AccountDraft校验账户ID、名称、类型、白名单品牌、CNY币种、期初余额符号及安全范围，并复制输入快照。
- RdbAccountRepository.create在同一个RdbSession串行事务内创建accounts、draft opening调整及对应adjustment movement，然后发布调整。发布失败整体回滚，不留下空账户、draft或孤立movement。同ID重试拒绝，不重复建账。
- 期初余额不是income/expense，没有transactions记录，不占预算。负债还款/收入通过普通正向movement减少负债，支出增加负债；删除收支沿用既有有效变动规则重新反映余额。
- 元数据编辑和归档/恢复必须匹配ID、类型/币种（编辑）及revision；失败提示返回刷新，不覆盖新版本。元数据编辑忽略opening字段，不修改任何余额事件。
- 账户列表从v_effective_movements逐笔读取整数文本，用BigInt聚合，避免浮点与SQLite SUM溢出。最终显示保持精确字符串；读出不支持的币种时资产页显示错误而不把它当成人民币。
- 归档不设置deleted_at_ms；收支选择器查询只含未归档账户。历史详情仍能读取已归档关联。

## 文件职责

| 文件 | 变化 |
| --- | --- |
| domain/model/AccountProfile.ets | 账户快照/命令、品牌模板、输入及版本校验 |
| data/rdb/RdbAccountRepository.ets | 精确余额/净资产读取，账户+期初原子创建，元数据/归档写入 |
| data/rdb/LedgerWorkspace.ets | 账户用例入口 |
| data/rdb/RdbLedgerRepository.ets | 新收支写入前拒绝归档/删除账户 |
| presentation/ledger/AccountIcons.ets、components/AccountAvatar.ets | 静态资源映射、品牌背景及单色/彩色图标底色 |
| components/AccountsPage.ets、AccountEditor.ets | 资产Tab、空状态、账户卡、表单与THICK品牌Sheet |
| pages/Index.ets | Tab切换、账户编辑路由、归档确认及保存后刷新 |
| ohosTest/.../Accounts.test.ets、AccountsFlow.ets、ExpenseFlow.test.ets、List.test.ets | 隔离库事务及账户→记账真实UI回归 |
| tools/verify-p0.mjs | 品牌、名称、符号、币种、金额边界与revision校验 |

## 验证记录

主机34项检查、主包及测试包构建通过。首次编译发现size/id字段与ArkUI组件方法重名，以及InputType枚举拼写错误，已改为diameter/draftId和NUMBER_DECIMAL，未关闭检查。git diff --check通过，schema仍为82条源SQL语句。

首轮设备回归15/16通过，账户相关持久层用例通过，UI用例在输入法尚未附着时发送Back导致页面提前返回；已等待原生输入法附着并断言编辑页仍在。截图另发现短内容居中、标题/状态栏继承白色和子汇总builder参数缓存，已改为顶部对齐、显式主题文字颜色及直接绑定账户快照。第二轮15/16通过，归档断言失败：按ID复用的列表行保留旧版本点击闭包。已按ID+revision+balance更新行，并在Index打开编辑时按ID重新取得最新快照；保留全部版本检查，新增改名回填和归档状态断言。最终完整原生回归16/16通过，0失败、0错误。新断言确认改名回填、归档/恢复、账户选择以及收支增删后的余额均正确；两次失败未通过删除断言或降低版本保护绕开。原有UI流程追加账户创建、品牌选择、改名/排除汇总、归档/恢复、记账选账户及余额更新；因此单项UI测试时限设为240秒，保留全部原断言。持久层测试覆盖资产/负债/零期初、收支独立、余额精度、净资产、元数据不改余额、版本冲突、归档保留/阻止新写入、关闭重开、创建中途失败完整回滚和重复ID拒绝。

创建与编辑截图已检查；当前亮色列表的标题对比度、顶部位置和总资产读数修正后正常。深色、大字号、宽屏、旧API和余额校准尚未专项验收。构建仍含原有异常处理及互斥分支重复组件ID警告，不以构建通过代替上述验收。未自动提交。

最终验证命令：`node tools/verify-p0.mjs`（34/34）、`python3 tools/generate-rdb-schema.py --check`（82条一致）、Hvigor entry@default / entry@ohosTest 的 `assembleHap --no-daemon`、`aa test -b cn.oicode.xiaoqiao -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 240000 -w 480`（16/16）、`git diff --check`，均通过。实际新增账户及资产页截图保存在临时目录。测试结束后重启正式入口，退出UUID隔离库；未改写用户账目，未提交本轮改动。
