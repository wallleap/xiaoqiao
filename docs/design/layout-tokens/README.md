# 小巧记账 · 圆角与间距 Token

版本：2026-10-30。布局尺寸使用vp；文字字号继续使用独立Typography中的fp。当前为设计源稿与开发参考，没有修改entry业务代码、资源或配置。

## 参考来源

- [华为圆角参数](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/corner-radius-parameter-0000002556468705)，页面更新时间2026-08-12；现场读取可见表格。
- [华为间隔参数](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/interval-parameter-0000002562577161)，页面更新时间2026-07-10；现场读取可见表格。

完整保留官方16个圆角Token、33个Padding Token，包括原表的大小写和跳级。不要自行补造Padding_level14/15/24/31、corner_radius_level14/15/17。28vp底部边距来自独立的屏幕margin表，不冒充不存在的Padding Token。

## 组件使用规则

|场景|应用别名|数值|来源|
|---|---|---|---|
|标签、角标|radius_tag|4vp|系统level2|
|图片、图标背景|radius_media|8vp|系统level4|
|输入框、数字键盘按键|radius_input / radius_keypad|12vp|应用对系统level6的场景映射|
|普通卡片、内容容器|radius_card|16vp|系统level8|
|预算、资产摘要卡|radius_summary|20vp|应用对系统level10的场景映射|
|按钮、菜单|radius_button / radius_menu|20vp|系统level10|
|Sheet、弹窗|radius_sheet / radius_dialog|32vp|系统level16|
|悬浮TabBar、胶囊控件|shape_capsule|短边/2|沿用用户确认的最大圆角，独立形状规则|
|头像、圆形按钮|shape_circle|直径/2|形状规则|

优先按角色统一，而不是把所有矩形都改成同一个圆角。品牌素材、分类图标内部与插图不改。票据主体、内嵌模块可以在页面margin内增加留白，例如票据外沿20vp不等于页面margin应改为20vp。角半径不得超过短边的一半。Sheet只对顶部两个角应用32vp，底边贴屏保持0；居中弹窗四角32vp。现有采用稿中的确认弹窗已统一32vp；未来Sheet按本规范实现。

## 间距规则

|场景|Token或别名|数值|
|---|---|---|
|主次文本上下|gap_text_vertical / Padding_level1|2vp|
|图标与文本、普通控件间|gap_inline / Padding_level4|8vp|
|数字键盘横纵间隔|gap_keypad / Padding_level4|8vp|
|同级卡片之间|gap_card / Padding_level6|12vp|
|普通卡片内边距|padding_card / Padding_level8|16vp|
|有明确边界的控件间|gap_control_large / Padding_level8|16vp|
|区块、宽屏列间、弹窗内边距|Padding_level12|24vp|

同级卡片间隔12vp，跨分组使用更大的16/24vp。文字间距指字形行框之间的空白，不是把两条文字baseline只相隔2vp。列表行高、点击热区、图标尺寸、状态栏高度、图表坐标不是间距Token，不能为了落入Token表机械改成统一数值。键盘列宽允许由可用宽度计算得到小数：390vp页面左右16、3个8间隔，对应4列各83.5vp；字体尺寸不缩放。

## 卡片外说明文字的对齐

卡片相邻的区块标题、日期范围和辅助说明，默认在卡片外边缘基础上再内收 8 vp（沿用 gap_inline / Padding_level4），左右对称，与卡片外沿保留轻量缩进。手机页面外边距 16 vp 时，文字距屏幕边缘为 24 vp；宽屏沿所在卡片或内容列计算，不另加整页固定坐标。卡片仍沿页面内容边界铺开。

说明文字与对应卡片相隔 8 vp（gap_inline / Padding_level4）。只给文字区域增加内边距，不通过空格、文字偏移或缩小卡片模拟；长文允许按可用宽度换行，不固定高度。标题栏、筛选控件及按钮保留各自布局。已应用于首页预算卡片上方的周期日期范围、资产页账户分组标题，以及统计页分类／标签／预算排行的卡片外标题、空状态和底部说明。资产页只内收文字，右侧使用中／已归档切换控件保持原位；统计排行卡片本身保持原宽。

## 多设备边距（vp）

|设备|左右|顶部参考|底部参考|
|---|---:|---:|---:|
|手机|16|36|28|
|折叠屏|24|36|28|
|平板|32|36|28|
|智慧屏|48|27|27|
|穿戴|26|20|20|
|PC|40|—|—|
|智能座舱|48|—|—|

手机、折叠屏和平板是当前适配范围，其余设备保存为官方参考。设备类型按设备与布局形态选择，不能把所有宽窗口当作PC。宽屏存在侧栏时，主内容与侧栏边界之间也留对应边距：1280平板示例侧栏228、主内容左起260；768折叠屏示例侧栏72、主内容左起96。

顶部36和底部28为设备参考，原生开发需结合窗口安全区和Navigation/TabBar的系统布局处理，避免机械叠加状态栏、导航栏与自定义留白。现有SVG保留模拟系统栏；首页TabBar在零系统inset的844vp画板中实测左右16、底部28。不能把这个绝对坐标直接搬到所有真机。原生安全区、软键盘与文字放大需接入后验证。

## 文件与开发使用

- layout.tokens.json：官方基础Token及明确vp单位。
- layout.manifest.json：组件语义映射、设备margin、例外与安全区规则。
- layout.csv：便于查阅、导入的全表。
- LayoutToken.ets：布局number常量开发参考；ArkUI布局number按vp使用。
- LayoutSemantic.ets：组件角色和设备边距别名，引用基础Token。
- layout.css：浏览器1倍设计预览，CSS px用于展示，不表示运行时fp/vp换算。
- huawei-radius-reference.json / huawei-spacing-reference.json：来源、可见正文及表格快照。
- application-audit.json：每屏、主题、圆角和边距变化记录。
- verification.json / browser-audit.json：结构检查和浏览器实测。
- figma-links.json：本轮六组Figma入口。

## 本轮应用与验证

119个既有页面/状态分别输出浅色和深色，共238屏。五组采用稿覆盖核心、账号/云空间、备份恢复、共用表单和多设备。238屏的文案、字体尺寸/字重/fp标注、颜色/透明度和素材内部均通过与上一版对比。普通卡片、按钮、确认弹窗、键盘按角色统一圆角；手机全宽卡片与常用卡片间距规范化，首页TabBar保留胶囊。

浏览器检查首页、记账、统计、资产、WebDAV、筛选，以及768折叠屏和1280平板；保存实际截图。局部控件/复杂图表的所有内距并未逐项人工测量；真实系统字体、DIN、文字放大和安全区仍需原生验证。没有运行鸿蒙构建，因为本轮未修改原生实现，ETS文件仅为未接入的开发参考。

Figma新增“圆角间距规范”五组采用稿和Token全表，旧稿保留，没有覆盖用户现有设计。当前使用可编辑SVG和元数据标注，尚未绑定Figma原生Variables；开发以本目录文件为准。浅深色均在本地交付，Figma新增的五组采用稿使用浅色（既有D10深色场景按原设定保留）。

## 检查过程记录

本地预览最初用object加载SVG，浏览器文件来源隔离导致contentDocument不可读，waitForFunction超时；改为内联SVG后完成几何检查。一次浏览器记录脚本误用了非Promise的fs.writeFile，修正为node:fs/promises后重跑通过。Figma曾短暂显示保存连接异常，写入前检查已恢复，随后再同步。最终通过情况见verification.json和Figma保存检查。项目目录无Git元数据，git status无法执行；本轮新增目录独立于既有色彩、文字规范，未修改无关文件。

## Figma入口

- [圆角与间距规范全表](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=114-2)
- [核心页面规范版](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=114-180)
- [账号与云空间规范版](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=124-2)
- [备份与恢复规范版](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=114-3532)
- [表单与辅助状态规范版](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=114-4552)
- [多设备规范版](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=122-2)

Figma导入的部分容器为带圆弧路径的Vector，圆角已画入路径，不保证属性面板显示独立Rectangle的rx数值，也未绑定原生圆角Variables；开发以语义Token和SVG rx元数据为准。原生组件接入时应使用borderRadius数值而不是复制整页SVG。

## 页面直达

- [R01 账目](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=114-186)
- [R03 记一笔](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=114-345)

最终Figma保存检查：六组稿件在重新打开文件后均可选中并核对尺寸。表单组首次URL定位等待超时，随后通过已保存的图层名称定位成功，未重复导入或生成重复稿。首页与记账页实际截图已检查。

## 后续修订：账号区域精简

头像卡片重复操作提示已删除；此修订优先于初始文字不变检查。见account-header-refinement.md与account-header-verification.json。
