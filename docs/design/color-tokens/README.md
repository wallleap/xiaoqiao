# 小巧记账 Design Color Token

版本：2026-10-30。50个华为通用基础/语义Token＋27个小巧记账应用扩展，共77个；Light/Dark各一套。

参考：[华为《色彩》系统基础与语义Token全量表](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/color-0000001776857164#section17672143841113)。以2026-10-30浏览器读取的官方表为依据，未使用下方智能穿戴表。

## 文件与接入

|文件|用途|
|---|---|
|colors.manifest.json|开发主索引：官方参考、应用实际值、别名来源、ARGB、CSS RGBA、Figma RGBA浮点；先查此文件|
|huawei-reference.json|50个官方原值，独立保留，避免将产品覆盖误写为华为默认|
|colors.light.tokens.json / colors.dark.tokens.json|DTCG颜色对象：sRGB components与alpha；按工具支持情况导入，不保证所有插件无损识别|
|colors.csv|Token、场景、浅深ARGB及RGBA对照|
|colors.css|浏览器颜色变量，八位色为RRGGBBAA|
|harmony.light.color.json / harmony.dark.color.json|HarmonyOS base/dark颜色资源草案，各77项，资源名xq_前缀；未替换entry现有资源|
|ColorToken.ets|资源名索引示例，未接入应用，也未当作已编译的原生实现|
|interaction-review.html|透明度与hover/pressed/focus/select示例，使用同一colors.css|
|verification.json|数值转换、SVG画笔及浅深模式结构检查结果|

原生接入时先审阅资源名，再将草案合入对应base/element与dark/element资源。组件使用语义资源，例如`$r('app.color.xq_font_primary')`，不要在业务页复制硬编码。此轮没有修改权限、依赖、构建配置、数据库或业务逻辑。

## 透明度约定

- 本文和Harmony资源：`#AARRGGBB`；CSS八位Hex：`#RRGGBBAA`。
- Figma交付使用明确的`RGB＋Opacity`，例如ARGB `#99000000` → RGB `#000000`＋60%；CSS为`#00000099`。若当前Figma输入框接受八位Hex，必须按该输入框标明的格式核对，不能假定A在前。
- SVG采用`fill="#000000" fill-opacity="0.6"`或对应stroke-opacity，避免导入器对八位Hex次序的差异。
- `#E5`透明度为229/255≈89.8039%；`#19`为25/255≈9.8039%，`#0C`为12/255≈4.7059%；“90%/10%/5%”只是便于理解的近似说明，文件保留准确8bit值。
- Figma颜色r/g/b为0–1的未预乘sRGB通道，a独立存放。不要把整个组件组设为60%，否则背景和子图标也会变淡；也不要再叠加一次alpha。

## 产品取值原则

1. 华为默认brand为蓝色；小巧记账覆盖brand为Light `#FFFF5425`、Dark `#FFFF956D`，高亮文字另用Light `#FFC83B14`以改善小字号辨识。原版渐变`#FFFD6E3E → #FFFF0A0A`在两种模式均保留。
2. `warning`为一级警示、`alert`为二级警示、`confirm`为确认状态；收入/普通支出是账目业务语义，使用app_income/app_expense，不将支出一律标成错误。状态正文有独立的加深/提亮色，警示图标仍可用官方语义色。
3. 官方表中background_primary Dark=`#FFE5E5E5`，comp_background_gray Dark=`#FFE5E5EA`，与深色页面通常需要的黑色基底不同。原值完整保留，页面显式用app_surface_page：浅灰（#F1F3F5）/黑；卡片、Sheet和浮动TabBar用app_surface_card：纯白/#202224；键盘用app_surface_keyboard：#F1F3F5/#2E3033。
4. 普通正文用font_primary，辅助说明用font_secondary；三级/四级用于更弱或禁用信息，不能把关键金额、关键提示降为四级。文本与图标分开映射。
5. 分类彩色素材、账户品牌颜色不全局改色。单色账户图标按brand配背景；彩色账户标志的承载底为浅色白、深色黑。
6. 卡片边框和弱列表分割线用应用扩展app_border_subtle/app_divider_subtle，标准comp_divider的20%透明值保留供需要更强边界的场景使用。
7. TabBar选中项保留有色图标和文字，没有选中底色。interactive_select用于复选/选择控件，不套到TabBar。
8. Hover/Pressed是覆盖层，Focus是描边；interactive_click是点击反馈语义，和Pressed选一种反馈，不相加。表面模式跟随系统或用户选择；不可对整个视图做反色滤镜。

## UI语义映射

|UI场景|使用Token|
|---|---|
|页面／卡片／键盘|app_surface_page / app_surface_card / app_surface_keyboard|
|标题、金额与正文|font_primary；普通支出app_expense|
|辅助文案与普通操作图标|font_secondary / icon_secondary|
|当前页签、链接、焦点|font_emphasize / icon_emphasize / interactive_focus|
|摘要卡|app_surface_summary + font_on_primary / font_on_secondary|
|收入与优惠|app_income / app_discount|
|警示与错误|warning / alert及app_warning_text、app_alert_text、对应弱背景|
|原版渐变主操作|app_gradient_start / app_gradient_end + app_button_on_gradient|
|开关|interactive_active / app_switch_track_off + app_switch_thumb|
|模态遮罩、列表分割|app_scrim / app_divider_subtle|

## 应用实际取值（ARGB）

|Token|场景类别|Light|Dark|取值来源|
|---|---|---|---|---|
|brand|品牌色|`#FFFF5425`|`#FFFF956D`|app override|
|warning|一级警示色|`#FFE84026`|`#FFD94838`|Huawei reference|
|alert|二级警示色|`#FFED6F21`|`#FFDB6B42`|Huawei reference|
|confirm|确认色|`#FF64BB5C`|`#FF5BA854`|Huawei reference|
|font_primary|一级文本|`#E5000000`|`#E5FFFFFF`|Huawei reference|
|font_secondary|二级文本|`#99000000`|`#99FFFFFF`|Huawei reference|
|font_tertiary|三级文本|`#66000000`|`#66FFFFFF`|Huawei reference|
|font_fourth|四级文本|`#33000000`|`#33FFFFFF`|Huawei reference|
|font_emphasize|高亮文本|`#FFC83B14`|`#FFFF956D`|app override|
|font_on_primary|一级文本反色|`#FFFFFFFF`|`#FFFFFFFF`|Huawei reference|
|font_on_secondary|二级文本反色|`#99FFFFFF`|`#99FFFFFF`|Huawei reference|
|font_on_tertiary|三级文本反色|`#66FFFFFF`|`#66FFFFFF`|Huawei reference|
|font_on_fourth|四级文本反色|`#33FFFFFF`|`#33FFFFFF`|Huawei reference|
|icon_primary|一级图标|`#E5000000`|`#E5FFFFFF`|Huawei reference|
|icon_secondary|二级图标|`#99000000`|`#99FFFFFF`|Huawei reference|
|icon_tertiary|三级图标|`#66000000`|`#66FFFFFF`|Huawei reference|
|icon_fourth|四级图标|`#33000000`|`#33FFFFFF`|Huawei reference|
|icon_emphasize|高亮图标|`#FFFF5425`|`#FFFF956D`|app override|
|icon_sub_emphasize|高亮辅助图标|`#66FF5425`|`#66FF956D`|app override|
|icon_on_primary|一级图标反色|`#FFFFFFFF`|`#FFFFFFFF`|Huawei reference|
|icon_on_secondary|二级图标反色|`#99FFFFFF`|`#99FFFFFF`|Huawei reference|
|icon_on_tertiary|三级图标反色|`#66FFFFFF`|`#66FFFFFF`|Huawei reference|
|icon_on_fourth|四级图标反色|`#33FFFFFF`|`#33FFFFFF`|Huawei reference|
|background_primary|一级背景（实色/不透明色）|`#FFFFFFFF`|`#FFE5E5E5`|Huawei reference|
|background_secondary|二级背景（实色/不透明色）|`#FFF1F3F5`|`#FF191A1C`|Huawei reference|
|background_tertiary|三级背景（实色/不透明色）|`#FFE5E5EA`|`#FF202224`|Huawei reference|
|background_fourth|四级背景（实色/不透明色）|`#FFD1D1D6`|`#FF2E3033`|Huawei reference|
|background_emphasize|高亮背景（实色/不透明色）|`#FFFF5425`|`#FFFF5425`|app override|
|comp_foreground_primary|前背景|`#FF000000`|`#FFE5E5E5`|Huawei reference|
|comp_background_primary|白色背景|`#FFFFFFFF`|`#FF202224`|Huawei reference|
|comp_background_primary_contrary|常亮背景|`#FFFFFFFF`|`#FFE5E5E5`|Huawei reference|
|comp_background_gray|灰色背景|`#FFF1F3F5`|`#FFE5E5EA`|Huawei reference|
|comp_background_secondary|二级背景|`#19000000`|`#19FFFFFF`|Huawei reference|
|comp_background_tertiary|三级背景|`#0C000000`|`#0CFFFFFF`|Huawei reference|
|comp_background_emphasize|高亮背景|`#FFFF5425`|`#FFFF5425`|app override|
|comp_background_neutral|黑色中性高亮背景|`#FF000000`|`#FFFFFFFF`|Huawei reference|
|comp_emphasize_secondary|20%高亮背景|`#33FF5425`|`#33FF956D`|app override|
|comp_emphasize_tertiary|10%高亮背景|`#19FF5425`|`#19FF956D`|app override|
|comp_divider|分割线颜色|`#33000000`|`#33FFFFFF`|Huawei reference|
|comp_common_contrary|通用反色|`#FFFFFFFF`|`#FF000000`|Huawei reference|
|comp_background_focus|获焦态背景色|`#FFF1F3F5`|`#FF000000`|Huawei reference|
|comp_focused_primary|获焦态一级反色|`#E5000000`|`#E5FFFFFF`|Huawei reference|
|comp_focused_secondary|获焦态二级反色|`#99000000`|`#99FFFFFF`|Huawei reference|
|comp_focused_tertiary|获焦态三级反色|`#66000000`|`#66FFFFFF`|Huawei reference|
|interactive_hover|通用悬停交互式颜色|`#0C000000`|`#0CFFFFFF`|Huawei reference|
|interactive_pressed|通用按压交互式颜色|`#19000000`|`#19FFFFFF`|Huawei reference|
|interactive_focus|通用获焦交互式颜色|`#FFD94720`|`#FFFF956D`|app override|
|interactive_active|通用激活交互式颜色|`#FFFF5425`|`#FFFF956D`|app override|
|interactive_select|通用选择交互式颜色|`#33FF5425`|`#33FF956D`|app override|
|interactive_click|通用点击交互式颜色|`#19000000`|`#19FFFFFF`|Huawei reference|
|app_surface_page|应用页面浅灰背景|`#FFF1F3F5`|`#FF000000`|app extension|
|app_surface_card|卡片／Sheet／悬浮TabBar表面|`#FFFFFFFF`|`#FF202224`|app extension|
|app_surface_keyboard|键盘按键、图片占位表面|`#FFF1F3F5`|`#FF2E3033`|app extension|
|app_surface_summary|预算／资产深色摘要卡表面|`#FF272D31`|`#FF202224`|app extension|
|app_border_subtle|卡片白色轮廓（预留光效）|`#FFFFFFFF`|`#19FFFFFF`|app extension|
|app_divider_subtle|列表弱分割线|`#0C000000`|`#19FFFFFF`|app extension|
|app_scrim|模态遮罩|`#66000000`|`#99000000`|app extension|
|app_income|收入金额、收入方向箭头|`#FF008664`|`#FF55C9A5`|app extension|
|app_expense|普通支出金额，不等同错误|`#E5000000`|`#E5FFFFFF`|app extension|
|app_discount|优惠金额|`#FF008664`|`#FF55C9A5`|app extension|
|app_warning_background|一级警示弱背景|`#19E84026`|`#19D94838`|app extension|
|app_alert_background|二级警示弱背景|`#19ED6F21`|`#19DB6B42`|app extension|
|app_confirm_background|确认弱背景|`#1964BB5C`|`#195BA854`|app extension|
|app_gradient_start|原版渐变起点|`#FFFD6E3E`|`#FFFD6E3E`|app extension|
|app_gradient_end|原版渐变终点|`#FFFF0A0A`|`#FFFF0A0A`|app extension|
|app_button_on_gradient|渐变按钮图文|`#FFFFFFFF`|`#FFFFFFFF`|app extension|
|app_switch_thumb|开关滑块固定白色|`#FFFFFFFF`|`#FFFFFFFF`|app extension|
|app_switch_track_off|未开启开关轨道|`#33000000`|`#33FFFFFF`|app extension|
|app_focus_ring|键盘焦点描边|`#FFD94720`|`#FFFF956D`|app extension|
|app_receipt_line|账单虚线／齿边|`#33000000`|`#33FFFFFF`|app extension|
|app_chart_fill|支出图表填充|`#19FF5425`|`#19FF956D`|app extension|
|app_summary_secondary|深色摘要次级文字|`#99FFFFFF`|`#99FFFFFF`|app extension|
|app_summary_accent|摘要预算进度|`#FFFFAB7B`|`#FFFFAB7B`|app extension|
|app_warning_text|一级警示正文|`#FFB52C1A`|`#FFFF9084`|app extension|
|app_alert_text|二级警示正文|`#FFA34600`|`#FFFFB38A`|app extension|
|app_confirm_text|确认状态正文|`#FF287B27`|`#FF8FD185`|app extension|
|app_disabled_content|禁用内容|`#33000000`|`#33FFFFFF`|app extension|

## 交付范围与限制

- 已对119个既有页面/状态分别生成浅色和深色配色；不改变文字、位置、尺寸、业务字段或交互流程。D10“深色与长昵称”示例在采用稿中保持深色语境。
- Figma五组采用稿及视觉规范应用新画笔；另有Token全表和16屏浅深对照。Figma当前仍为可编辑矢量稿，颜色通过RGB＋opacity落地，**尚未绑定Figma原生Variables或样式库**；开发以本目录Token文件为准。
- 并非77个Token都出现在正常页面：hover、pressed、focus等条件状态在interaction-review.html展示；特殊反色和弱层级在全表保留。
- 彩色素材内部以及插图演示色保留；application-audit记录了未被主题化的装饰色。
- 本轮未进行鸿蒙构建或真机测试，未修改entry业务/资源。开发草案须在原生接入时按项目工具链验证。
- 已改善主要高亮/状态正文的辨识，但未声称整套WCAG合规。原版渐变按钮的白字、弱层级以及各类素材仍需结合实际字号、背景和无障碍设置专项检查。

## Figma入口

- [颜色Token全表](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=100-2917)
- [浅深色UI对照](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=100-2922)
- [资产采用稿](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=100-415)

Figma实际画笔验证：资产页辅助文字为RGB 000000＋Fill 60%；深色对照为RGB FFFFFF＋Fill 60%。见figma-alpha-proof.json。

## 浅灰页面与纯白卡片更新

浅色app_surface_page=`#FFF1F3F5`，app_surface_card为`#FFFFFFFF`，app_surface_summary恢复为`#FF272D31`；普通卡片app_border_subtle使用`#FFFFFFFF`白色描边（默认1px），便于后续开发叠加光效。摘要卡使用反色文字和图标，保持深色表面的可读性。列表内部分割线、输入校验与选中态边界保留各自语义。深色SVG内容与改前逐字节一致；本轮未添加光效实现。


文字规范已独立交付至项目docs/design/typography-tokens：系统默认字体、数字DIN只标注、字号fp；当前Figma单页链接已更新为文字层级版本。

## 最新约定：摘要卡恢复深色

预算剩余、资产估值、账户余额这类摘要卡恢复原先的深色表面：Light #FF272D31，Dark #FF202224；主文字font_on_primary、辅助font_on_secondary、图标icon_on_*。收入/优惠在深色摘要卡内取各自Dark前景值，保持原语义与可读性。普通卡片仍白色，页面仍浅灰，白色边线与字体/fp规则均保留。原生代码未改动。
