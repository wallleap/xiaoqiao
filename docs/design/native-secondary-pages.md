# 其它页面补全与查看清单

日期：2026-11-01。本文记录现有「小巧记账」Figma 的补页，应用代码、业务逻辑、数据库、依赖和配置未修改。

## 当前状态

- 已在 Figma 创建111个手机页面/状态，分为八个功能组，外层及字段内容使用原生 Auto Layout。这里的数量包含同一功能的空态、错误、确认、进行中等状态，不代表111个独立功能。
- 已完成二级分类 Sheet 的实际原型截图检查。其余补页的最终截图检查、窄屏复核和个别内容修订仍待完成，不能视为已验收。
- 平板与折叠屏20个场景已创建为原生 Figma 页面，暂放在第一页右侧16—18分区；尚未搬到第二页，最终组织未完成。
- 原有七个主页面保留；设置页130:206保留用户手调内容。补页以本清单节点为入口，历史稿不作为这轮开发依据。

## 视觉与布局标注

- 页面背景 F1F3F5；普通卡片 FFFFFF，100%不透明，无描边。深色金额/预算概览沿用原有方向。
- 品牌渐变 FD6E3E → FF0A0A；文字和图标按已有色彩 Token 的层级使用。Figma八位色为RRGGBBAA，鸿蒙资源为AARRGGBB，不能直接复制相互替代。
- 手机左右边距16vp，普通卡片圆角16vp，主要按钮/概览20vp，Sheet24vp。模块间距12/16vp，卡片内边距16vp，小间距4/8vp。
- 开发文字使用系统默认字体，金额数字使用DIN系列；字号单位fp，布局单位vp。Figma中的字体是预览，不新增开发字体依赖。
- 内容区域采用外层Fill视口、内层Hug内容，Overflow Vertical；底部操作独立于滚动内容。分类Sheet覆盖背景，背景副本的键盘隐藏，原记一笔页不变。
- 账户图标来自项目accounts资源，单色品牌图标配品牌底色，彩色图标使用白/黑底；分类使用现有彩色与线性资源。
- 这些页面尚未全部绑定为Figma Variables或共享组件实例；不得将可编辑的Auto Layout层等同于完整组件系统。

## 交互与信息规则

- 分类允许选父分类。点一级时先选中父分类；取消子分类Sheet仍保留父分类。多级通过继续下钻展示。
- 校准余额使用独立调整记录，显示调整前、调整后及差额，不伪装成消费或收入。设计不等同于数据库结构已实现。
- 多币种区分原币、账户实际扣款、统计折算和跨币种转账；保留本笔汇率、时间和来源。页面汇率是演示值，不表示实时或权威报价。
- 导出区分字段选择、生成、交给系统保存、已保存和失败。备份恢复区分预览、覆盖确认、写入及回滚；涉及本机/云端的状态仅出现在对应数据与同步流程。
- 华为账号与个人云空间保留可选入口和状态稿，服务可用性及接入需开发阶段确认；本轮没有接入或执行同步。
- 页面跳转、表单数据、系统授权和实际服务调用尚未全部连接。本轮不把静态状态稿描述为可运行应用。

## 手机页面入口

### 08 账户与转账

[打开本组](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-1161)

| 编号 | 页面 | Figma节点 |
| --- | --- | --- |
| A01 | 选择账户类型 | [182:272](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-272) |
| A02 | 新增账户 | [182:347](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-347) |
| A03 | 编辑账户 | [182:420](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-420) |
| A04 | 账户管理 | [182:497](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-497) |
| A05 | 转账详情 | [182:548](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-548) |
| A06 | 编辑转账 | [182:628](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-628) |
| A07 | 删除转账 | [182:695](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-695) |
| A08 | 校准余额 | [182:779](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-779) |
| A09 | 余额调整记录 | [182:827](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-827) |
| A10 | 调整记录详情 | [182:858](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-858) |
| Q01 | 选择账户图标 | [182:1063](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-1063) |
| R13 | 日常储蓄卡 | [182:919](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-919) |
| R14 | 已归档账户 | [182:1010](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-1010) |

### 09 账本分类与标签

[打开本组](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2097)

| 编号 | 页面 | Figma节点 |
| --- | --- | --- |
| K01 | 选择账本 | [182:1162](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-1162) |
| K02 | 新建账本 | [182:1204](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-1204) |
| K03 | 编辑账本 | [182:1244](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-1244) |
| R15 | 分类与标签 | [182:1273](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-1273) |
| C01 | 新增分类 | [182:1471](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-1471) |
| C02 | 编辑分类 | [182:1551](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-1551) |
| C04 | 选择上级分类 | [182:1644](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-1644) |
| C08 | 选择子分类 | [190:3196](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-3196) |
| C09 | 继续选择子分类 | [190:3485](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-3485) |
| C03 | 处理关联账目 | [182:1856](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-1856) |
| R16 | 分类与标签 | [182:1915](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-1915) |
| C07 | 新增标签 | [182:1974](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-1974) |
| C05 | 编辑标签 | [182:2010](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2010) |
| C06 | 删除标签 | [182:2061](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2061) |

### 10 搜索与筛选

[打开本组](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2784)

| 编号 | 页面 | Figma节点 |
| --- | --- | --- |
| S01 | 搜索账目 | [182:2098](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2098) |
| S02 | 筛选账目 | [182:2172](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2172) |
| S04 | 选择月份 | [182:2281](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2281) |
| S05 | 选择日期范围 | [182:2350](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2350) |
| S03 | 搜索账目 | [182:2401](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2401) |
| E01 | 导出账单 | [182:2454](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2454) |
| E04 | 选择导出字段 | [182:2525](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2525) |
| E02 | 正在生成账单 | [182:2591](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2591) |
| E03 | 账单已生成 | [182:2627](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2627) |
| E06 | 账单已保存 | [182:2679](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2679) |
| E05 | 账单生成未完成 | [182:2729](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2729) |

### 11 统计与预算

[打开本组](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-3195)

| 编号 | 页面 | Figma节点 |
| --- | --- | --- |
| R07 | 统计 | [182:2785](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2785) |
| R08 | 统计 | [182:2860](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2860) |
| R10 | 预算 | [182:2927](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2927) |
| R11 | 预算 | [182:2977](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-2977) |
| P01 | 调整总预算 | [182:3060](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-3060) |
| P02 | 分类预算 | [182:3097](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-3097) |
| P03 | 编辑分类预算 | [182:3151](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=182-3151) |

### 12 数据与WebDAV

[打开本组](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5259)

| 编号 | 页面 | Figma节点 |
| --- | --- | --- |
| R17 | 数据与备份 | [190:3856](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-3856) |
| B01 | WebDAV 设置 | [190:3918](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-3918) |
| B02 | WebDAV 设置 | [190:3978](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-3978) |
| B03 | WebDAV 设置 | [190:4024](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4024) |
| B06 | 远端备份 | [190:4071](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4071) |
| B07 | 远端备份 | [190:4141](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4141) |
| B08 | 恢复预览 | [190:4186](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4186) |
| R22 | 检查所选备份 | [190:4269](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4269) |
| R23 | 保护当前账目 | [190:4327](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4327) |
| B09 | 恢复预览 | [190:4366](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4366) |
| B10 | 正在备份 | [190:4435](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4435) |
| B11 | 备份成功 | [190:4505](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4505) |
| B12 | 正在恢复 | [190:4572](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4572) |
| B13 | 恢复完成 | [190:4626](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4626) |
| R18 | 恢复前本机副本 | [190:4694](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4694) |
| R19 | 还原本机副本 | [190:4749](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4749) |
| B14 | 无法恢复这份备份 | [190:4831](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4831) |
| B15 | 备份未完成 | [190:4869](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4869) |
| B16 | 暂时无法连接 | [190:4917](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4917) |
| B17 | 备份版本不兼容 | [190:4961](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4961) |
| B18 | 暂时无法开始恢复 | [190:4999](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-4999) |
| B19 | 恢复未完成 | [190:5037](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5037) |
| B20 | 所选备份已不存在 | [190:5086](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5086) |
| B21 | 恢复前检查 | [190:5130](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5130) |
| R20 | 正在检查数据 | [190:5174](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5174) |
| R21 | 需要恢复数据 | [190:5207](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5207) |

### 13 华为账号与云空间

[打开本组](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6326)

| 编号 | 页面 | Figma节点 |
| --- | --- | --- |
| H02 | 我的小巧 | [190:5260](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5260) |
| H03 | 华为账号 | [190:5395](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5395) |
| H04 | 华为账号 | [190:5460](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5460) |
| H05 | 连接华为账号 | [190:5515](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5515) |
| H06 | 连接华为账号 | [190:5555](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5555) |
| H08 | 华为云空间同步 | [190:5600](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5600) |
| H09 | 开启云空间同步 | [190:5665](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5665) |
| H10 | 开启前检查 | [190:5696](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5696) |
| H11 | 正在同步 | [190:5747](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5747) |
| H12 | 华为云空间同步 | [190:5808](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5808) |
| H13 | 华为云空间同步 | [190:5873](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5873) |
| H14 | 华为云空间同步 | [190:5928](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5928) |
| H15 | 华为云空间同步 | [190:5983](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-5983) |
| H16 | 华为云空间同步 | [190:6048](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6048) |
| H17 | 华为云空间同步 | [190:6106](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6106) |
| H18 | 华为云空间同步 | [190:6161](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6161) |
| H19 | 华为账号已变化 | [190:6216](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6216) |
| H20 | 需要重新授权 | [190:6271](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6271) |

### 14 币种商户与图片

[打开本组](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6948)

| 编号 | 页面 | Figma节点 |
| --- | --- | --- |
| FX01 | 币种与汇率 | [190:6327](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6327) |
| FX02 | 常用币种 | [190:6383](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6383) |
| FX03 | 手动汇率 | [190:6459](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6459) |
| FX04 | 暂时无法更新汇率 | [190:6524](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6524) |
| FX05 | 本笔金额与扣款 | [190:6574](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6574) |
| R25 | 外币账目详情 | [190:6630](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6630) |
| M01 | 商户与地点 | [190:6723](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6723) |
| M02 | 编辑商户 | [190:6785](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6785) |
| M03 | 账目图片 | [190:6830](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6830) |
| M04 | 图片暂时无法读取 | [190:6902](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6902) |

### 15 首次使用与辅助状态

[打开本组](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-7760)

| 编号 | 页面 | Figma节点 |
| --- | --- | --- |
| R02 | 小巧记账 | [190:6949](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6949) |
| R04 | 编辑账目 | [190:6993](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-6993) |
| F01 | 编辑账目 | [190:7121](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-7121) |
| F02 | 编辑账目 | [190:7216](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-7216) |
| F03 | 账目详情 | [190:7318](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-7318) |
| F05 | 编辑账目 | [190:7371](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-7371) |
| L04 | 提醒与外观 | [190:7476](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-7476) |
| T01 | 主题设置 | [190:7527](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-7527) |
| T02 | 大字模式 | [190:7567](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-7567) |
| N01 | 记账提醒 | [190:7605](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-7605) |
| N02 | 记账提醒 | [190:7661](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-7661) |
| R24 | 帮助与关于 | [190:7707](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-7707) |

## 验证记录与未完成项

- 本地133份SVG及布局描述的XML、子层引用和可达性检查通过。
- 预算剩余、统计合计、跨币种转账、手续费舍入、资产折算和余额校准的设计示例使用Decimal校验通过；这不是应用金额计算测试。
- C08子分类Sheet实际截图检查已通过，显示遮罩、白色弹层及取消保留父分类的说明。
- 尚未完成：其余补页逐页实际截图、长文案/320宽度、宽屏问题修正、最终归组/状态重命名和原型跳转连线。
- 工作区检查命令 `git status --short` 返回128：当前目录不是Git仓库，无法提供Git diff；本轮没有运行应用构建，因为没有修改应用代码。

本地源与检查记录：可视化工作区 `xiaoqiao-supplement-20261101/` 中的 `manifest.json`、`categories.json`、`wide-manifest.json`、`progress-*.json`、`source-validation.json` 和 `previews/`。

## 平板与折叠屏入口

这20个场景已生成，但首轮截图发现的问题尚未修完，不能作为已验收稿。当前仍在第一页右侧的16—18分区，第二页的旧稿尚未归档。

| 编号 | 页面 | Figma节点 |
| --- | --- | --- |
| D01 | 设置 · 未登录 | [190:8317](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-8317) |
| D02 | 设置 · 已登录 | [190:8451](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-8451) |
| D03 | 华为云空间同步 | [190:8776](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-8776) |
| D04 | 首次开启 · 数据检查 | [190:8862](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-8862) |
| D05 | 账目明细 | [190:7761](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-7761) |
| D06 | 数据与恢复预览 | [190:8934](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-8934) |
| D07 | 分类与标签 | [190:9086](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-9086) |
| D08 | 记一笔 · 折叠屏 | [190:10114](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-10114) |
| D09 | 备份与恢复 · 折叠屏 | [190:10289](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-10289) |
| D10 | 设置 · 深色与长昵称 | [190:8585](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-8585) |
| D11 | 账目 · 大字模式 | [190:8661](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-8661) |
| D12 | 云空间同步 · 系统开关 | [190:9384](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-9384) |
| D13 | 账目概览 | [190:7915](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-7915) |
| D14 | 统计 | [190:8029](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-8029) |
| D15 | 预算中心 | [190:8123](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-8123) |
| D16 | WebDAV 设置 | [190:9470](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-9470) |
| D17 | 记一笔 · 宽屏 | [190:9549](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-9549) |
| D18 | 资产与多币种估值 | [190:8202](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-8202) |
| D19 | 搜索与筛选 | [190:9749](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-9749) |
| D20 | 导出账单与附件 | [190:9962](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=190-9962) |

### 首轮截图待修问题

- D05/D13/D11：预算环导入后呈分段线。连续矢量弧线的源已准备，原生替换尚未验证。
- D17/D08：预算与资产规则需恢复紧凑分组，分类图标需再核对一致性。
- D10：深色分割线过亮；部分列表同时有文字箭头与图标箭头。
- 收入与转账的完整表单代表态已准备本地源，尚未导入。
- 浏览器控制权交还用户后暂停操作；尚未完成最终页面清理。


## 新增导入与导出

原E01—E06导出画板已从10组迁入19组，节点不变。新增Excel/CSV导入、支付宝/微信字段建议、源列映射、账户与分类匹配、余额处理、问题检查与结果；平板另置20组。请以 [导入导出说明](import-export.md) 中的分区和节点为准。旧表格中的E类名称仅保留追溯，当前位置以19组为准。


2026-11-02：导入导出核心示例路径和余额选择Sheet已连接并实际点击验证。四张关键手机稿补查320宽度、两张平板稿补查1024宽度，检查后恢复原尺寸。本项不代表本文全部旧补页均已验收，详细范围见导入导出说明。

## 首页账目行文字宽度

账目行按右侧金额区域实测宽度分配左侧标题和时间/账户的剩余宽度，保留卡片边距及文字与金额间距；不再固定预留 176vp。副标题单行显示，仅在剩余空间确实不足时省略。不同收支筛选分别记录金额宽度，以适配转账金额口径变化。

账目标题行使用“分类 (备注)”，无备注时只显示分类，备注与分类相同时不重复；备注换行合并为空格，超长标题单行省略。退款/报销到账继续使用对应回款类型作为标题前缀。
