# 收入记账闭环

2026-11-05。用户确认在 `fb9bb64` 之后接通人民币收入新增、详情、编辑、删除和首页汇总。本轮不改表结构、schema checksum、依赖、权限、全局窗口或本地签名配置；测试只使用 UUID 隔离库。

## 用户行为

- 记一笔顶部HDS ChipGroup可在支出/收入之间切换。保留当前金额、账户、时间、备注，切换到相应分类列表并选择首项；切回支出恢复原优惠值。转账保留未接入提示，并保持当前类型。
- 收入使用收款账户、收入分类及到账金额；隐藏优惠和预算规则，仅保留资产规则。收入不填优惠、不占用支出预算。加减键盘、输入边界、日期/备注、分类多级Sheet和沉浸材质复用现有实现。
- 新增收入回到首页全部列表，收入总额、日期收支与余额随有效记录更新。详情复用小票样式，显示正向金额；左滑、长按、详情编辑都接通。编辑标题为“编辑收入”，不能转换为支出或转账。
- 编辑回填原金额、分类、账户、时间、备注及资产规则。保留同一ID、版本检查、未改时间时的原时区，以及原balance_mode/导入身份；取消不写库，删除沿用单笔软删除和二次确认。
- 当前只支持同币种CNY手动收入。完整多币种和转账仍未接入。

## 数据与初始化

`IncomeCommand` 独立提供amount/bookAmount/accountAmount，不接受优惠或预算字段。`IncomeRecord`将收入结算规范化为零优惠、预算false，并复用已有精确金额、日期与同币种结算校验。`IncomeService`分开暴露save和update，编辑必须提供正安全整数revision。

`RdbLedgerRepository`的private saveRecord/updateRecord复用支出已验证的串行事务；公开收入接口显式使用kind=income、leg=income、正向delta。支出接口仍使用kind=expense、负向delta。编辑按kind+ID+账本+revision读取和进入draft，检查分类类型和账户，替换本笔movement再发布；失败整体回滚。收入规则不依赖UI隐藏，域层和SQL约束均保持discount=0、include_in_budget=0。

在已确认兼容的schema下，LedgerDatabase通过db_meta的income_categories_v1执行一次默认分类补充：工资、奖金、兼职、理财、红包、其他收入。只在默认账本从未有过任何收入分类时插入；判断包含归档/删除记录。若已有收入分类则只写标记，不重命名、不覆盖、不复活。插入及标记同属原初始化事务，失败回滚。此为经用户确认的数据初始化补充，不进行结构迁移或历史账目重写；未知/不兼容数据库仍拒绝打开。

LedgerSnapshot新增incomeCategories，原categories继续仅表示支出分类，避免改变旧调用语义。类别图标复用现有彩色资源和稳定语义key。

## 文件职责

| 文件 | 变化 |
| --- | --- |
| domain/model/IncomeRecord.ets | 收入命令、精确结算校验与规则规范化 |
| domain/ports/IncomeRepository.ets、domain/services/IncomeService.ets | 收入新增/编辑端口和版本校验 |
| data/rdb/RdbLedgerRepository.ets | 共享原子写入，收入正向资金变动 |
| data/rdb/LedgerDatabase.ets | 一次性、不覆盖的默认收入分类 |
| data/rdb/LedgerWorkspace.ets、domain/model/LedgerSnapshot.ets | 收入分类查询、读写入口、可编辑详情 |
| components/ExpenseEditor.ets、pages/Index.ets | 表单类型切换、收入保存/回填、列表编辑入口 |
| presentation/ledger/CategoryIcons.ets | 收入语义key映射现有彩色资源 |
| ohosTest/ets/test/Income.test.ets、ExpenseFlow.test.ets、List.test.ets | 余额、规则、冲突/回滚、初始化保留及真实UI流程 |
| tools/verify-p0.mjs | 收入金额/规则/路由/冲突的纯主机检查 |

## 验证

主机32项检查通过，主包和测试包构建通过。首轮原生完整回归14/14通过。截图检查发现账户行通过通用builder值参数传入后仍保留“付款账户”初值；已改为账户行直接绑定isIncome/accountId，并加入“收款账户”的真实文本断言，最终版本再次完整回归14/14通过，0失败、0错误；账户文案断言通过。已检查最终收入输入页和小票截图，收款账户、收入分类、到账计算及正向收入显示正常。未自动提交本轮改动。

收入专项检查包括：正向账户余额、变更账户和月份、不计资产不影响余额、不使用账户、错误分类拒绝、版本冲突、发布失败后字段/版本回滚、删除后不可编辑、既有收入分类归档/删除不重建。UI回归在原支出流程后新增收入加减保存、收入详情、同ID编辑、取消不写及删除，保留原支出、优惠和预算断言。

深色、大字号、宽屏、旧API及跨时区仍须专项验收。现有构建中的重复组件ID（互斥分支）和抛出异常提示仍存在，未通过关闭检查来掩盖。

执行验证：`node tools/verify-p0.mjs`（32/32）、`python3 tools/generate-rdb-schema.py --check`（82条一致）、Hvigor的entry@default与entry@ohosTest `assembleHap --no-daemon`、`aa test -b cn.oicode.xiaoqiao -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 180000 -w 300`（14/14）、`git diff --check`，均通过。截图与日志留在临时目录；设备测试结束后重启正式入口，退出隔离库状态。
