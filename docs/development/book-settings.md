# 账本币种与月起始日

当前完整备份版本为 V12，归档账本物理删除及余额保留见[删除说明](book-deletion.md)。下文 V11 章节记录设置迁移本身。

2026-11-21。用户确认新增设置、跨模块换算／周期接入及数据库迁移；本轮仅编写和主机验证，不操作设备数据库。

## 界面与规则

「我的 → 账本管理」使用独立 HDS 子页面；首页「选择账本」保留 Sheet，新建／编辑从选择器进入时也转到管理子页。管理页按设备上已正常显示的收支分类页接入 HdsNavigation > Scroll > Column，MINI 标题栏、enableComponentSafeArea、bindToScrollable、顶部 ignoreLayoutSafeArea 以及顶部／底部 expandSafeArea 均与该页一致；滚动容器 clip(false)，正文最大宽度 640 vp。标题随管理／新建／编辑模式变化，返回先退出表单，再退出管理页，保存期间阻止返回。

管理子页的账本卡片和创建入口使用不透明的 xq_app_surface_card（浅色 #FFFFFFFF、深色 #FF202224），首页选择 Sheet 继续使用原半透明面板。标题栏的 originalStyle、scrollEffectStyle、IMMERSIVE／ADAPTIVE 材质及 IMMERSIVE_GRADIENT_BLUR 与收支分类页一致，使用原生背景默认值，不额外覆盖背景、遮罩或半径。验证逐项比较两个页面的标题 style 及安全区声明；实际滚动效果仍需设备验收。

管理页表单仅用左右各 16 vp 页边距，不再叠加 Sheet 和内层面板边距；字段标题置于输入／选择控件上方，48 vp 控件采用实色主题底和浅描边。账本币种已锁定时改用只读底色、描边和锁图标，保持文字可读。

账本管理的新建／编辑表单增加「账本币种」和「月起始日」。默认 CNY · 人民币、每月 1 日。账本币种说明为「用于收支汇总、预算和账目折算」，选择已开启币种（含自定义币种）；正在使用的币种即使停用仍能显示。

任何交易（含草稿和软删除历史）、预算或预付款项目存在后，锁定账本币种。UI 说明锁定原因，数据库触发器同时保护；空账本可修改，不重算已有交易、余额或预算。资金账户跨账本共用，资产／个人净资产估值仍以 CNY 展示，不随当前账本切换。

月起始日为 1～31。短月取当月最后一天；周期按开始月份命名，例如 11 月、起始日 25 日，对应 11 月 25 日至 12 月 24 日。采用左闭右开查询 `[start,endExclusive)`，相邻周期无重叠或空隙。31 日周期在闰年为 2 月 29 日至 3 月 30 日。首页标明日期范围，进入／切换账本及保存账目后定位对应周期；日均可用金额按周期剩余天数计算。

月统计、年统计的月分桶、账单日历及账单流水的月／年范围沿用该周期；周和用户指定的自定义日期范围不变。月历的完整周覆盖整个周期，跨自然月日期同样可查看。

修改月起始日只改变查询分组，不改历史账目的日期、金额或已有预算区间。预算仍绑定精确的开始／结束日期，原预算记录保留；新周期另设预算。未设置时沿用既有默认预算 2500 主币单位，按账本币种精度生成最小单位金额。

## 换算与数据兼容

记一笔默认选择账本币种。外币保存时自动通过共享汇率服务换算到该账本币种；历史编辑沿用已有快照。普通收支、转账手续费、退款／报销及预付款核销在相应账本币种内汇总，金额格式、符号和预算输入随账本精度变化。预付款的全局净资产估值将其剩余账本金额再换为 CNY，缺少报价时继续沿用缺失汇率提示。

导出的 FX 精确快照新增可选 `bookCurrencyId`，旧快照缺失时按 CNY 解释。恢复／导入精确快照必须与目标账本币种一致；不一致时拒绝并提示切换账本，避免静默改写历史折算金额。普通 CSV 既有规则将无快照行视为 CNY；导入非 CNY 账本前预取所需报价、生成折算快照，事务内再次检查当前账本及币种未变。退款／报销仍按原交易的账本金额比例处理。

## V11 迁移和备份

V11 SQL 增加 `books.month_start_day INTEGER NOT NULL DEFAULT 1`（整数 1～31 约束），复用已有 `base_currency_id`。扩展币种锁定触发器，覆盖预付款；预付款核销发布校验改为读取所属账本币种。

普通加载遇到旧库仍提示升级，不直接改设备数据库。用户执行既有升级入口后，先保存 `_before_book_settings_v11.db`，再在串行写事务中迁移。校验旧表记录数、账本／账户资料、预算／交易金额、有效账户流水、外键及 quick_check；失败回滚并保留副本。新建数据库逐步应用到 V11。

完整备份 manifest schema 更新为 11，兼容 schema 2～10；旧备份先在隔离候选库逐级迁移后再替换。账本币种和月起始日位于数据库中，随本地、云端及 WebDAV 共用的完整包保存，无额外设置文件。

## 文件职责

| 文件（相对项目根目录） | 核心变化 |
| --- | --- |
| entry/src/main/ets/pages/Index.ets | 管理子页与返回路由、16 vp 表单、新建／编辑设置、锁定说明、当前周期定位、日期范围、账本金额格式和日均预算 |
| entry/src/main/ets/domain/model/LedgerBook.ets | 币种、月起始日及只读锁定状态契约与校验 |
| entry/src/main/ets/domain/model/MonthlyBudget.ets | 周期边界、短月／闰年处理及日期归属月份 |
| entry/src/main/ets/domain/model/LedgerSnapshot.ets | 当前账本币种、周期日期及月起始日 |
| entry/src/main/ets/domain/model/EntryDetail.ets | 历史账目的账本币种 |
| entry/src/main/ets/domain/model/FxEntrySnapshot.ets | 可移植快照的账本币种及旧文件默认值 |
| entry/src/main/ets/domain/model/Prepaid.ets | 预付款所属账本币种 |
| entry/src/main/ets/data/rdb/LedgerWorkspace.ets | 设置读写、币种折算、统一周期查询、预算和导入兼容、全局预付款估值 |
| entry/src/main/ets/data/rdb/RdbStatisticsRepository.ets | 年统计按账本周期分月 |
| entry/src/main/ets/data/rdb/RdbPrepaidRepository.ets | 预付款付款／核销／退款使用所属账本币种 |
| entry/src/main/ets/components/ExpenseEditor.ets | 新记账默认币种和保存换算目标 |
| entry/src/main/ets/components/PrepaidPage.ets | 预付款表单的账本汇率与显示 |
| entry/src/main/ets/components/EntryDetailPage.ets | 历史账本金额和汇率币种显示 |
| entry/src/main/ets/components/BudgetPage.ets | 按账本币种精度设置预算 |
| entry/src/main/ets/components/StatisticsPage.ets | 月／年周期、范围说明及账本金额格式 |
| entry/src/main/ets/components/BillDetailsPage.ets | 自定义周期月历、流水范围和金额精度 |
| entry/src/main/ets/components/LedgerSearchPage.ets | 无原币快照时按账本币种格式化 |
| entry/src/main/ets/components/DataExchangePage.ets | 精确快照币种不符时的明确提示 |
| entry/src/main/ets/presentation/statistics/StatisticsPeriod.ets | 当前及前后月／年周期 |
| entry/src/main/ets/presentation/ledger/BillCalendar.ets | 周期日历及不同小数位的紧凑金额 |
| entry/src/main/ets/presentation/ledger/LedgerOverview.ets | 金额格式化支持传入币种，默认兼容 CNY |
| docs/database/schema-v11-book-settings.sql | 审核用 V11 SQL |
| tools/generate-book-settings-schema.py | 由 SQL 生成生产语句与 SHA-256，不操作数据库 |
| entry/src/main/ets/data/rdb/BookSettingsSchema.ets | 通过上述生成器生成的 V11 语句 |
| entry/src/main/ets/data/rdb/BookSettingsMigration.ets | 升级前备份、迁移、数据指纹和完整性检查 |
| entry/src/main/ets/data/rdb/TransferMigration.ets | 迁移链版本／校验和接受 V11 |
| entry/src/main/ets/data/rdb/LedgerDatabase.ets | 新库及已授权升级接入 V11 |
| entry/src/main/ets/data/rdb/LocalLedgerBackup.ets | 旧备份候选库升级到 V11 |
| entry/src/main/ets/data/backup/LedgerBackupPackage.ets | 完整包 schema 11 及旧版本兼容 |
| tools/verify-book-settings.mjs | 生产周期、月历、工作区查询／预算、统计、CRUD、USD 预付款核销及精确快照主机验证 |
| docs/database/verify_book_settings.py | V11 默认值、历史金额、回滚、备份／恢复、币种锁定及非 CNY 核销验证 |
| docs/database/verify_book_covers.py | 生产账本查询用例接入 V11 列，保留原断言 |
| tools/verify-expense-currency-picker.mjs | 现有编辑器主机夹具补默认账本币种，保留原断言 |

## 验证边界

- `node tools/verify-book-settings.mjs`：管理子页／选择 Sheet 分流、编辑返回层级、保存中返回保护、HDS 结构；372 组周期边界、闰年及短月；真实执行生产工作区查询／预算／CRUD、统计和预付款仓储方法，使用临时 SQLite 独立读写连接，避免事务内新写数据误读；验证跨月边界、日元零位精度、历史预算保留、币种锁定及 USD 核销。
- `python3 docs/database/verify_book_settings.py`：5 项迁移／数据库验证，仅操作内存数据库。
- 原有账本封面、币种选择／设置、汇率页面、账户估值、个人汇总及预付款操作主机回归。
- 本轮未执行 Hvigor／ArkTS 原生构建、模拟器或真机视觉／触摸验收、设备数据库升级及设备完整备份恢复。

## 修改预算首次渲染崩溃修复

设备日志报告 `BudgetPage.symbol()` 首次渲染读取 `this.currency.id` 时 currency 为 undefined。移除该组件的 currency getter 和所有属性读取，改为普通 `amountCurrency()` 方法：优先使用已载入快照币种，其次使用工作区账本币种，尚未就绪时用 CNY。符号、金额、精度校验及两个 MoneyAmountField 统一调用此方法，不修改预算保存／分配规则。

`node tools/verify-budget-page.mjs` 执行页面的生产渲染／加载／保存方法，覆盖无工作区、币种尚未就绪、快照币种优先、JPY 零位精度、读取失败和保存成功。以旧属性访问方式、未安装组件 getter 的方法测试环境可复现同类 id 空值错误；修复后通过。此验证不包含 ArkUI 原生组件运行时，设备上的不闪退结果仍需复测。

本次修复文件：`components/BudgetPage.ets`、`tools/verify-budget-page.mjs` 及本文。


## 选择账本 Sheet 的背景与边距

首页选择器沿用“管理币种”的专用 THICK 沉浸材质工厂（interactive=false），在弹出前动态准备，避免复用 interactive=true 的 menu 材质导致按压形变。仅在宿主已具备沉浸材质能力时加载 API 26 模块，失败或旧系统回退为 xq_app_surface_page；筛选、预算 Sheet 的原材质不变。

根容器边距与管理币种一致：左右 16 vp、上 20 vp、下 16 vp，内部间距 12 vp；标题最小高度 40 vp，为关闭按钮预留右侧 48 vp。选择卡片和创建入口使用 xq_exchange_currency_card_background；选择卡片 12 vp 内边距、14 vp 圆角、8 vp 行间距。保留列表弹性及自身滚动，原高度公式不变。管理子页仍使用实色卡片。

本次修改 Index.ets、verify-book-settings.mjs 和本文。主机验证保留 340 vp 单账本默认高度、专用材质／主题回退、其它类型 Sheet 不变及标题和根边距；未进行设备材质／触摸验收。

## 归档账本的显示

归档条目使用中性浅灰／深灰卡片、36 vp 封面（65% 不透明度）、次级文字及独立“已归档”标记，区别于使用中的 46 vp 实色卡片；按钮使用反差背景，名称与交易笔数仍保持可读。仅修改 Index.ets 的归档行展示，现有编辑和恢复功能保留。

账本删除方案已获用户确认并接入物理删除与通用余额结转，详见[归档账本删除](book-deletion.md)。本轮未执行设备数据操作。

账本管理列表顺序：使用中账本 → 创建新账本 → 已归档标题及归档账本。创建入口紧跟正常账本，不放在归档列表末尾。

已归档分区使用独立实色卡片，每次进入账本管理默认折叠；标题显示归档数量，点击展开／收起。展开内容淡入并轻微位移，配合 260 ms EaseInOut 布局过渡和箭头旋转；只有标题切换折叠，不影响内部编辑、恢复和删除按钮。

底部 HdsSnackBar 提示接入 pressBackCallback：先关闭提示，再调用 Index.onBackPress，保持管理／编辑等现有返回层级；主页面无子页时仅关闭提示，不主动退出应用。
