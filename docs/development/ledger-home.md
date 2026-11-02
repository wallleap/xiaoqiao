# 第一个页面：账目首页

2026-11-02。P0 基础提交：`051854b`，`feat(storage): 建立金额与串行账务存储基础`。

## 当前范围

将 Hello World 替换为原生 ArkUI 首页，沿用已确认的账目设计：浅灰页面、纯白无描边账目卡、深色预算摘要、彩色分类图标、原版橙红渐变中央记账动作。文字使用系统默认，所有字号显式使用 fp；布局尺寸为 vp。数字保留 DIN 接入目标，当前使用系统字体回退，未安装字体或新增依赖。

本次是首页显示与局部交互，不是完整记账应用。正常启动显示空状态，不写入示例账目，不触发正式建库或迁移。尚未接入正式数据查询，页面中的日常账本、CNY 是首版展示约定，不代表已经建立数据库记录。

## 文件与依赖

- `pages/Index.ets`：首页、搜索、收支切换、账户筛选 Sheet、账本选择 Sheet、空状态及可用宽度变化后的双栏布局。
- `components/AmountText.ets`：较小货币符号、金额字号适配、完整金额查看与无障碍文本。
- `presentation/ledger/LedgerOverview.ets`：展示模型、整数金额格式化、关键词/收支/账户条件相交的纯筛选逻辑；不依赖数据库。
- `resources/base/element/color.json`、`resources/dark/element/color.json`：合入已有 77 个颜色 Token，保留原有资源，不在页面重复复制色表。深色资源具备映射，但深色截图尚未验收。
- `ohosTest/ets/test/LedgerHome.test.ets`：隔离预览与原生 UI 交互验证；通过 AppStorage 的非持久 `ledgerPreview` 标记临时启用示例，finally 恢复为 false。
- `ohosTest/ets/testrunner/OpenHarmonyTestRunner.ets`：框架注册后再动态加载测试，避免 UiTest 过早加载时 Driver 为 null。
- `tools/verify-p0.mjs`：增加金额分组保持精度、筛选条件相交及原数组不变的检查。

使用本机 SDK 中真实的 `@kit.UIDesignKit` HdsTabs，配置 `barFloatingStyle` 与 `hdsMaterial.MaterialType.IMMERSIVE`。中央记账是动作占位，不允许切换到一个空白内容页；其他尚未开发的导航项同样阻止切换并说明尚未接入。导航高亮没有底色。图标复用现有 media 素材，不另行下载。

## 已接入与未接入

已接入：搜索显隐与输入、收支切换、账户筛选的暂选/重置/确认、日期分组、空结果提示、账本选择面板和金额完整值查看。

未接入：正式账本/账目/预算查询、账本管理、预算编辑、记一笔页面、账单详情跳转及统计/资产/设置页面。相关按钮明确提示未接入，不伪造保存成功。正常状态没有假账户可选；预览中的账户来自隔离样例。

宽度达到 720vp 时摘要与列表并排，手机纵向排列；正文最大宽度 1040vp，滚动内容为悬浮导航预留底部空间。当前真实截图验收仅覆盖 API 26 手机模拟器，平板、折叠屏、深色模式与放大字体仍需后续设备检查。

## 验证方式

```sh
node tools/verify-p0.mjs
hvigorw --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
hvigorw --mode module -p product=default -p module=entry@ohosTest -p buildMode=debug assembleHap --no-daemon
hdc shell aa test -b cn.oicode.xiaoqiao -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000 -w 60
```

原生截图由 UiTest 保存到本应用 EntryAbility 的 filesDir，文件名为 `xiaoqiao-home-empty.png`、`xiaoqiao-home-preview.png`、`xiaoqiao-home-filter.png`。检查的是实际模拟器渲染，未以浏览器页面代替 ArkUI。

初次编译因组件字段 `size`、`width` 与基类方法冲突失败，已重命名后通过；UiTest 曾因过早导入导致 Driver 为 null，已修正 Runner 加载顺序；图标按钮的定位由 description 改为稳定 id，不移除交互断言。

## 本轮最终检查

- 主机检查 20 项：P0 的 18 项，加首页金额分组/筛选的 2 项。
- 主 HAP 与测试 HAP 均通过 ArkTS 编译和资源打包；未配置发布签名，模拟器可安装 unsigned HAP。
- base/dark 各 77 项设计颜色与原 Token 文件逐值匹配，无重复资源名；首页与金额组件字号未使用裸数 vp。
- UI 测试在主界面真实点击，保留正向命中、反向不存在、搜索空结果、关闭搜索恢复、账户过滤和账本 Sheet 的断言。
- 筛选结果截图先等待面板及遮罩完全消失，避免把收起动画中间帧当成稳定效果；另保存筛选 Sheet 自身截图。
- 两种选择面板共用一个 bindSheet，按内容选择 280/440vp 高度，避免重复绑定时高度来源混淆。
- 金额点击可查看完整值；此次未完成系统大字号、宽屏/折叠屏和深色视觉验收，不以代码分支存在代替实机验证。

页面改动尚未提交，独立于 P0 提交保留供评审。没有改动 SDK、依赖、权限、签名配置或生产数据库。

UI 检查补充：Dialog/Sheet 关闭和筛选条件改变后，先等待旧元素消失再断言，避免在异步布局尚未更新时读到上一帧；保留所有反向断言，不删除断言。视觉截图另加 600ms 的短动画稳定时间：实测无障碍树会先移除 Sheet，但屏幕上的退出动画仍在运行。

颜色检查修正：筛选 Sheet 显式使用白色表面；Radio 选中色使用 xq_brand；重置为浅灰次按钮，完成为品牌色主按钮，避免默认蓝色混入。

最终验证汇总：主机 20/20，通过主 HAP 与测试 HAP 构建，API 26 模拟器 Hypium 5/5（P0 原生 3 项、首页 UI 综合流程 1 项、原有模板 1 项）。UI 综合流程额外验证点击摘要金额可打开并关闭完整金额弹窗。实际截图已检查空状态、示例列表、筛选面板与筛选结果；其余设备与主题未验收。

## HDS 实装补齐

按用户确认，首页进一步使用真实 UIDesignKit 组件：

| 区域 | 实际组件/API | 业务定制边界 |
|---|---|---|
| 顶部导航 | HdsNavigation、MINI 标题模式、原生 menu、IMMERSIVE 材质 | 账本选择通过 stackBuilder 标题插槽承载；搜索为原生导航菜单项 |
| 账目卡片 | HdsListItemCard、primaryText、secondaryText | 分类图标用原生 PrefixImage 加载已有 SVG；精确金额与较小货币符号用 SuffixCustomBuilder |
| 底部导航 | HdsTabs、barFloatingStyle、IMMERSIVE 材质 | 保留原有图标、品牌渐变和记账入口 |
| 即时反馈 | HdsSnackBar | 统一复用实例，替换 showToast；提供关闭操作，三秒后自动消失，页面销毁时 dismiss |

Search、Radio、bindSheet 继续使用 ArkUI 原生能力；本机 UIDesignKit 没有与它们一一对应的独立同名 HDS 导出，不自行包装后宣称是 HDS。预算摘要和金额属于保留的业务定制。

HdsNavigation 的 stackBuilder 经原生侧调用，必须显式绑定页面实例；初次直接传方法导致运行时 this 丢失，已改为 `this.bookTitle.bind(this)`。初次编译还修正了导航菜单的语义属性：SDK 使用 label，不存在 accessibilityText 字段。验证须重跑原有完整 UI 流程，并新增 SnackBar 实际显示和自动消失检查，不能只以 import 或编译通过作为接入证明。

本轮只修改首页、首页 UI 测试和相关说明；金额算法、数据库、资源图标与颜色取值保持原有实现。新增组件均来自现有 SDK，没有安装依赖、修改权限或 SDK 配置。

HDS 运行时布局修正：本次环境中 HdsListItemCard 的百分比 cardWidth 未正确解析，实际渲染窄至竖线。改为由账目列 onAreaChange 取得实际可用宽度，给 cardWidth 传数值 vp，并保留外层 Fill。新增真实标题可见和卡片宽度断言。沉浸导航覆盖内容顶部的情况，通过滚动内容的 56vp 导航预留空间加 12vp 内容间距处理；标题插槽显式应用页面左右边距。

卡片插槽对齐：分类图标交给原生 PrefixImage 管理，金额插槽补充右侧 16vp。UI 测试同时检查实际卡片宽度、标题可见与金额到卡片右缘的留白，保留原有搜索/筛选/弹窗断言。

前缀改用 SDK 原生 PrefixImage，移除自定义 Image/Row 前缀：实测自定义前缀的宽度与文字起点未同步，无法稳定保证间距。UI 测试通过卡片范围定位图像并检查与标题的间距，不依赖 SDK 内部生成的 ID。

HDS 补齐最终结果：主 HAP、测试 HAP 构建通过；主机检查 20/20；API 26 手机模拟器 Hypium 5/5，Failure 0、Error 0。原有搜索/筛选/金额弹窗流程、HdsSnackBar 显示与三秒自动消失，以及卡片宽度、图标文字间隔、金额右侧留白均已验证。最终截图已目视确认。没有修改数据库和依赖配置；本轮未提交。

## 正文统一滚动、导航固定

日期、搜索框、预算摘要、收支/账户筛选栏、日期分组及全部账目共用一个纵向 Scroll。Navigation 标题与搜索入口、底部 HdsTabs 位于正文 Scroll 外。显式启用 ScrollDirection.Vertical 和滚动交互，关闭 Navigation 动态隐藏；HdsTabs.scrollable(false) 仅禁用横向切页，不影响正文的纵向滚动。

内容超过视口时，摘要与列表整体移动，不给预算或筛选栏另做吸顶，也不在列表内嵌套第二个滚动区。正文保留底部空间，末项能滚到悬浮 Tabs 上方。

隔离的 ledgerScrollPreview 用于 UI 测试临时追加 12 行，正常启动不启用、不持久化。测试执行真实上滑、滚至末项、返回顶部，检查摘要离开原位置、末项未被 Tabs 遮挡，并对比 Navigation 与 Tabs 的上下边界完全不变。finally 恢复所有预览标记。

滚动最终验证：API 26 手机模拟器 Hypium 5/5，通过长列表实际上滑、末项完整可见、Navigation/Tabs 四个边界坐标不变及真实下滑返回顶部检查。测试工具的 scrollToBottom 在本次悬浮栏布局中未找到末项，改用正文可见区域内的真实滑动，未放宽末项或固定栏断言。搜索菜单新增 Scroller 回顶，便于从深处打开正文内的搜索框。主 HAP 与测试 HAP 构建通过，主机检查 20/20，git diff --check 通过。测试样例不持久化，页面改动未提交。

短内容拖动：正文 Scroll 配置 `edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })`。即使空状态或内容不足一屏，也接受拖动并回弹；溢出时正常滚动，不添加假数据或额外空白制造滚动距离。此前长列表验证没有覆盖正常启动的短内容体验，本次补充该配置及短内容手势后的导航固定检查。

短内容最终验证：主 HAP 和测试 HAP 构建通过；API 26 模拟器原生测试 5/5、Failure 0、Error 0。另在正常启动且无示例数据的空状态执行低速拖动，抓取拖动前及手指移动中的截图，确认正文实际移动、Navigation/Tabs 固定；松手后回弹。短内容不是通过增加假记录或额外空白实现滚动。

## 标题栏渐变模糊

首页标题栏切换为 HDS 原生 `ScrollEffectType.IMMERSIVE_GRADIENT_BLUR`，通过 `bindToScrollable([bodyScroller])` 关联实际正文，而不是只设置静态背景。滚动 0～56vp 期间，从顶部状态的 0 模糊过渡到 24 的模糊半径；maskExtraHeight 为 32vp，向标题栏下方柔和衔接。原始/滚动背景都设透明，移除不透明浅灰背板；标题栏 divider 显式 OFF，避免硬分割线。

正文与固定 Navigation/Tabs 的布局、短内容回弹保持不变。UI 测试新增滚动后标题栏截图，保留此前全部交互、固定边界及末项露出断言。效果使用 SDK 原生渲染，最终以模拟器截图进行视觉检查。

渐变模糊最终验证：主 HAP 与测试 HAP 构建通过，API 26 手机模拟器 Hypium 5/5、Failure 0、Error 0，git diff --check 通过。已检查滚动中及末尾截图，原生背景模糊和向下衰减可见，标题文字未模糊，分割线消失；长列表、短内容回弹及固定栏断言均通过。深色与其他设备的视觉效果仍待验收。本轮仅修改首页样式、截图测试与本文档，未提交。

## 账目收支筛选：ChipGroup

按[华为子页签规范](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/chipsgroup-0000001929788350)，移除“最近账目”标题及手绘下划线选项，改为现有 ArkUI SDK 的 `ChipGroup`。三个选项为“全部 / 支出 / 收入”，单选、不可关闭，默认全部；选中项为品牌色填充及白色文本，未选中项为白底及二级文本。右侧使用 `IconGroupSuffix` 保留账户筛选入口。

收支和账户条件仍相交，账户面板的暂选、重置、确认行为不变。整组随正文滚动，不新增吸顶。组件来自 `@kit.ArkUI`，没有新增依赖，不将其称为不存在的 HdsChipGroup。UI 测试新增标题不存在及支出筛选断言，保留收入、全部、搜索、账户筛选和固定导航检查。

ChipGroup 验证结果：主 HAP、测试 HAP 构建通过；主机检查 20/20；API 26 手机模拟器 Hypium 5/5，Failure 0、Error 0。已检查实际示例列表截图，三个胶囊和右侧筛选入口显示完整，无文字裁切。平板、折叠屏、深色及系统大字号尚未验收。本轮未提交。

## 滚动后深色标题栏

标题栏保留原生渐变模糊，`originalStyle` 为透明背景、深色原生标题/搜索图标，`scrollEffectStyle` 为已有深色摘要背景 Token、白色原生标题/搜索图标。通过 `systemBarStyle` 同步配置滚动前后的深色/白色状态栏文字。

账本名称及下箭头属于 stackBuilder 自定义内容，原生 titleStyle 不控制其颜色；正文 onDidScroll 读取同一 Scroller，在原生 0～56vp 过渡的中点 28vp 切换为反色 Token，回到顶部时恢复。仅状态变化时触发刷新。没有改变导航位置、正文滚动和业务筛选。

深色标题栏验证：主 HAP、测试 HAP 均构建通过；API 26 手机模拟器原生测试 5/5，Failure 0、Error 0，保留实际上滑、回顶及 Navigation/Tabs 固定边界检查。目视检查顶部和滚动截图：顶部状态栏及搜索恢复深色，滚动后账本名称、下箭头、搜索与状态栏均为白色，背景为向下衰减的深色渐变模糊。git diff --check 通过；其他设备、深色主题和大字号未验收。本轮未提交。

视觉反馈调整：原深色背景过重，滚动遮罩改为半透明灰色 `#BF454D52`（ArkUI ARGB，约 75% 不透明度），不再直接使用深色预算卡背景。初次使用更浅的 60% 灰色时，截图中白字对比不足，因此调整为中间灰。保持原生渐变模糊、白色前景、28vp 自定义标题切换及顶部恢复行为；这是标题栏局部遮罩，不改全局品牌色或卡片 Token。

半透明灰色版本已通过主 HAP、测试 HAP 构建及 API 26 模拟器原生测试 5/5（Failure 0、Error 0），git diff --check 通过。已查看滚动截图；其他设备和主题未验收，未提交。
