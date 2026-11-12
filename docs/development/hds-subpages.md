# HDS 子页面滚动沉浸光感

2026-11-12，用户反馈多数子页面缺少沉浸光感。检查现有 HdsNavigation 使用点后，统一普通滚动子页面的标题栏配置；保留业务、路由、全局窗口和主页面已确认的布局。

## 配套规则

- 标题栏保留 `enableComponentSafeArea:true`，不额外设置 `avoidLayoutSafeArea:true`。前者将标题栏定义为正文需避让的组件级安全区，后者是标题栏自身主动避让系统安全区，不能混作一套通用开关。初始正文由组件处理避让，滚动后允许进入标题栏背景采样区。
- `systemMaterialEffect` 使用既有 `IMMERSIVE / ADAPTIVE`；`scrollEffectOpts` 显式开启 `IMMERSIVE_GRADIENT_BLUR`。
- 正文的真实 Scroller 通过 `bindToScrollable` 绑定到导航，正文 `Scroll.clip(false)`，让滚动内容能进入标题栏背后的材质采样范围。不增加正文顶部固定偏移或忽略正文顶部安全区。
- `originalStyle` 和 `scrollEffectStyle` 都使用既有主题标题色、返回图标色，沿用系统状态栏颜色处理，不增加自定义蒙层、模糊半径或颜色资源。
- 有固定底部按钮时，为操作栏设置页面背景、较高层级并扩展到底部系统安全区，覆盖正文溢出到按钮背后的绘制；按钮和原事件不改变，滚动区域仍按剩余高度布局。详情页的小地图自身裁剪保留。

## 文件范围

ETS 文件位于 `entry/src/main/ets/components`。

| 文件／页面 | 核心修改 |
|---|---|
| CategoryManagementPage.ets／收支分类 | 补开滚动光感、滚动状态主题色、安全区配套和正文裁剪。此项为最初截图修复，纳入本次统一规则。 |
| BudgetPage.ets／月预算 | 补开滚动光感、滚动状态主题色、安全区配套和正文裁剪。 |
| AccountEditor.ets／新增和编辑账户 | 补开滚动光感及滚动状态主题色、安全区配套，保留原有 clip(false)，补充固定操作栏背景和层级。 |
| AccountCalibrationPage.ets／余额校准 | 补开滚动光感、安全区与裁剪；给原刷新／确认按钮增加同位置的独立底部操作容器，配置背景、层级和底部安全区。 |
| AccountAdjustmentHistoryPage.ets／余额调整记录 | 补开滚动光感、滚动状态主题色、安全区和正文裁剪。 |
| SpendingNaturePage.ets／预算分类 | 已有滚动光感，补齐正文裁剪、安全区配套及滚动状态主题色。 |
| TagManagementPage.ets／标签 | 已有滚动光感，补齐正文裁剪、安全区配套及滚动状态主题色。 |
| DataExchangePage.ets／导入与导出 | 已有滚动光感，补齐正文裁剪、安全区配套及滚动状态主题色。 |
| EntryDetailPage.ets／账目详情 | 已有滚动光感，补齐安全区与正文 clip(false)，为底部删除／编辑操作栏增加背景、层级及底部安全区，替代此前通过整个正文裁剪阻止底部穿透的处理。 |

账目首页 Index、资产 AccountsPage、统计 StatisticsPage、设置 LocalBackupPage 已有对应滚动光感、滚动绑定和不裁剪配置，本轮检查后保留。弹层、地图原生页面和嵌入式 WebDAV 面板不作为独立 HDS 导航页改造。

ExpenseEditor（记一笔／编辑收支／转账）是固定金额和分类区域配合局部表单滚动的独立结构，已有沉浸材质但主动关闭滚动光感，且未绑定整个页面滚动。其局部 Scroll 不会经过标题栏，直接打开开关不能形成与普通列表相同的效果。本轮保留其布局与键盘交互；如需整页随滚动沉浸，需要单独调整固定区和滚动结构。

文档同步：本说明、category-management.md 和 entry-detail-edit.md。已有 build-profile.json5 的本机签名改动保持原样。

## 验证边界

仅做源代码差异、HDS 本地声明及既有已确认配置的核对，`git diff --check` 通过。按用户要求没有运行构建、自动化测试、安装或设备截图，不能将配置补齐当作视觉验收通过。

用户手动重点查看：

1. 九个页面滚动卡片经过标题栏时的渐变模糊和背景连续性，回到顶部及下拉回弹后的标题位置。
2. 账目详情、账户编辑、余额校准的底部按钮及间隙没有正文透出，原按钮可点；账目详情地图标记、更多菜单与回款入口正常。
3. 输入法展开、收起时的保存／校准按钮，分类和导入页面的 Sheet 选择后返回。
4. 深色、大字号、宽屏，以及内容不足一屏时的标题、返回按钮和系统状态栏可读性；短页面没有滚动背景时，模糊变化可能较轻。


## 官网复核与重叠修正（2026-11-12）

用户提供预算分类标题与正文重叠截图后，重新打开并核对华为官方[设置动态模糊样式](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ui-design-navigation-dynamic-blur)的完整示例，以及[HdsNavigation API](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ui-design-hdsnavigation)的安全区参数说明。

前次批量修改只核对了本地 SDK 声明和已有页面，没有重新逐项对照完整官方示例，将 avoidLayoutSafeArea:true 误作为所有子页面的配套配置。官网动态模糊示例设置 enableComponentSafeArea:true、正文 clip(false) 和滚动绑定，没有设置 avoidLayoutSafeArea；API 说明该参数负责标题栏自身的系统安全区避让，并不是正文避让标题栏。结合截图和本轮差异，新增该参数与原页面顶部扩展叠加是重叠问题的主要嫌疑，不能只凭参数名称批量套用。

已撤掉上述九个子页面本轮新增的 avoidLayoutSafeArea:true，恢复其原先默认值；保留滚动沉浸光感、组件安全区、clip(false) 和固定底部操作栏背景。不增加固定顶部 padding，不修改主 Tab 已由用户确认的安全区组合。本次属于代码修正，仍需手动查看首屏标题避让与滚动光感，未运行构建或设备验证，不能声称重叠已通过视觉复验。
