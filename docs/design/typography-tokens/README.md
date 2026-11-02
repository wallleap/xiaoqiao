# 小巧记账 Typography / 文字层级

2026-10-30。按用户要求：正文使用系统默认字体，数字使用DIN系列；UI只标注字体目标，不安装/嵌入/切换到真实DIN字库。开发字号显式使用fp，不使用vp字号或无单位裸数。

参考：[华为《文本排版》](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/typography-0000002622688363)。官方表原单位为vp；本应用按用户要求保留数字，将**开发字号约定为fp**。这是应用接入约定，不能误写成官方表已经使用fp。

## 字体与单位

- `system-default`是语义标记，不是需要传入fontFamily的字体名称。原生正文不硬编码fontFamily，让系统选择默认字体。
- `DIN series`也是设计目标标记，不是已登记的可用字体名称。仅数字字形运行段标注DIN；中文、币种代码、单位、货币符号使用系统字体。日期/时间中的数字同样标注DIN。
- 真实DIN字库与具体字重文件由后续开发接入确认；此轮没有下载、安装、登记或打包字体。预览沿用已有Noto Sans SC/Inter替代字形，不把预览截图当作DIN字体效果。
- Manifest、CSV、分设备JSON和ETS参考文件均以fp交付。SVG/Figma设计坐标仍是设计像素，`data-font-unit="fp"`和规范板用于标注开发单位，不将SVG数值解释为运行时vp字号。
- fp用于适配系统字体设置。接入时不要再重复手工乘系统字体倍率。行高按实际字体自然度量处理，文字容器允许随字号增高；关键动作、金额和说明不能靠截字隐藏。

## 分设备策略

当前应用设备范围是手机、平板、折叠屏，现有119个页面/状态统一采用Phone字号层级。宽屏只改变布局，不直接套PC字号。PC尺寸独立保存供PC场景选择；Watch仅为参考。Caption_S在Phone/PC没有值，不能把8fp穿戴说明字用到手机。

## 基础层级（开发单位fp）

|场景|Token|字重|Phone|PC|Watch|
|---|---|---|---|---|---|
|展示性文本  Display|Display_L|Light / 300|56fp|54fp|56fp|
|展示性文本  Display|Display_M|Light / 300|48fp|46fp|48fp|
|展示性文本  Display|Display_S|Light / 300|38fp|36fp|38fp|
|标题文本  Title|Title_L|Bold / 700|30fp|28fp|30fp|
|标题文本  Title|Title_M|Bold / 700|24fp|22fp|24fp|
|标题文本  Title|Title_S|Bold / 700|20fp|18fp|20fp|
|副标题文本  Subtitle|Subtitle_L|Medium / 500|18fp|16fp|18fp|
|副标题文本  Subtitle|Subtitle_M|Medium / 500|16fp|14fp|16fp|
|副标题文本  Subtitle|Subtitle_S|Medium / 500|14fp|12fp|14fp|
|正文文本  Body|Body_L|Medium / 500|16fp|14fp|16fp|
|正文文本  Body|Body_M|Regular / 400|14fp|14fp|14fp|
|正文文本  Body|Body_S|Regular / 400|12fp|14fp|12fp|
|说明文本  Caption|Caption_L|Medium / 500|12fp|12fp|12fp|
|说明文本  Caption|Caption_M|Medium / 500|10fp|9fp|10fp|
|说明文本  Caption|Caption_S|Medium / 500|不适用|不适用|8fp|

## 页面场景映射

|场景|采用层级|
|---|---|
|页面主标题|Title_M 24fp Bold|
|弹窗标题、较小标题|Title_S 20fp Bold|
|区块标题、按钮文字|Subtitle_M 16fp Medium|
|列表主要名称|Body_L 16fp Medium|
|正文、常规表单标签|Body_M 14fp Regular / Subtitle_S 14fp Medium，按信息作用区分|
|辅助说明|Body_S 12fp Regular|
|图标说明、短标签|Caption_L 12fp Medium|
|密集图表刻度|Caption_M 10fp Medium，不用于长篇说明|
|摘要金额|Number_Display：Display_S 38fp Light，数字标注DIN|
|记账输入金额|Number_Input：Display_M 48fp Light，数字标注DIN|
|紧凑金额字段|Title_L 30fp Bold，数字标注DIN；如768宽编辑器金额区|
|数字键盘|Number_Keypad：Title_L的30fp尺寸，Regular400字重；属于按键角色覆盖，不是标题字重|
|货币符号|大额展示14fp Regular；紧凑金额行10fp Medium；系统字体|

长金额按38→30→24fp分级适配；金额输入按48→38→30→24fp。仍放不下时展示可横向查看的完整值或进入完整值详情，不能截掉金额含义。该规则为后续原生接入要求，当前静态稿未实现动态计算。

## 文件

|文件|用途|
|---|---|
|typography.manifest.json|15项基础层级、3项数字角色、字体目标、单位与设备策略主索引|
|typography.csv|Phone/PC/Watch字号和字重对照|
|typography.phone.tokens.json / typography.pc.tokens.json / typography.watch.tokens.json|运行时fp语义JSON；为小巧记账格式，不直接当作CSS长度或通用DTCG长度导入|
|Typography.ets|显式fp资源值参考，未接入entry|
|huawei-reference.json|官方可见表和页面文字摘录，保留原vp单位|
|application-audit.json|文字节点、原字号、目标层级和新fp值的映射记录|
|verification.json / browser-audit.json|文字内容/形状不变、单位、实际边界与同层碰撞检查|

设计产物位于xiaoqiao-unified-20261029/typography-tokens：build-typography.py从color-tokens的浅灰白卡稿读取，生成238个浅深色单页和采用稿、文字规范板及评审HTML。颜色、业务文案、字段与非文字几何保持原样，只有字号、字重、数字标注和三处为避免碰撞调整的文字位置变化。

## 验证与限制

- 已运行build-typography.py和verify-typography.py：15基础层级，Phone/PC/Watch分别14/14/15项可用值；运行时JSON的fontSize全部显式fp；238个页面文字内容及非文字形状/颜色一致。
- 浏览器逐页检查119个采用稿：文字边界与同层文字碰撞均0问题。首轮发现R03、D08、D13三处金额/说明间距不足，已分别调整间距或采用紧凑金额层级后复验通过，没有降低检查标准。
- Figma仍为可编辑矢量稿：已标注字体角色及fp，没有建立原生Text Style或Typography Variables绑定。
- 未进行DIN真实字形、字重文件和字体回退验证；当前检查针对预览替代字体。
- 未修改entry业务、权限、字体登记或依赖。未运行鸿蒙编译和真机字体缩放测试。后续应验证100%%、130%%、175%%、200%%字号下的换行、金额完整显示、按钮可见和滚动可达；静态SVG不等于原生fp缩放已实现。

## Figma入口与生成顺序

- [Typography / fp规范板](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=95-10719)
- [主页面](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=100-2)
- [记一笔](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH?node-id=95-167)

本地设计生成顺序：先生成基础SVG，再运行color-tokens/build-color-tokens.py，最后运行typography-tokens/build-typography.py。当前采用稿以最后的文字层级输出为准，不能仅重生成颜色稿后覆盖Figma。


### 摘要卡配色恢复

摘要卡恢复深色，但本轮字号、字重、DIN标注、fp约定及文字位置未改变；普通白卡和浅灰页面保留。
