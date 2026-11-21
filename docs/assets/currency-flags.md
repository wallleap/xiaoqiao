# 国家／地区旗帜与币种映射

## 来源与完整资源

- 上游：https://github.com/lipis/flag-icons
- 固定提交：`ac7e0eb3259eb62aa6100c435607e2fe03896a97`。
- 导入全部 `flags/4x3` 和 `flags/1x1` SVG，各 271 个，合计 542 个、3,867,684 字节（约 3.69 MiB，未压缩）。这是旗帜／地区／组织标志数，不等同于国家数。
- MIT 许可证原文保留于 `tools/currency-flags/LICENSE.flag-icons.txt`，上游 `country.json` 原样保留在同目录。
- `tools/currency-flags/catalog.json` 保存下载地址、固定版本、压缩包 SHA-256、各 SVG 原路径／资源名／字节数／SHA-256 及币种映射。
- 不引入 npm 依赖，不加载 CDN；下载的 archive 不执行任何脚本，只读取两种比例 SVG、许可证和旗帜元数据。

所有 SVG 原样保存在 HarmonyOS 扁平 media 目录，以 `flag_4x3_cn.svg`、`flag_1x1_cn.svg` 命名；上游地区码的连字符转为下划线，不修改文件内容。

## 当前币种映射

| 币种 | 标志代码 | 币种 | 标志代码 | 币种 | 标志代码 |
| --- | --- | --- | --- | --- | --- |
| CNY | cn | USD | us | EUR | eu |
| HKD | hk | JPY | jp | GBP | gb |
| AUD | au | CAD | ca | SGD | sg |
| KRW | kr | CHF | ch | THB | th |
| NZD | nz | MYR | my | IDR | id |
| INR | in | PHP | ph | BRL | br |
| CZK | cz | DKK | dk | HUF | hu |
| ILS | il | ISK | is | MXN | mx |
| NOK | no | PLN | pl | RON | ro |
| SEK | se | TRY | tr | ZAR | za |

EUR 使用欧盟旗帜，HKD 使用香港区旗。映射仅用于辅助识别，不更改币种名称、金额精度、汇率来源或国家／地区列表。页面对未选旗帜的币种显示货币代码占位，不猜测旗帜；底层默认资源查找函数保留地球图标作为资源回退。

## 展示

`CurrencyFlagBadge.ets` 复用生成的 `CurrencyFlags.ets`，汇率列表为 28×21vp、基准币种为 24×18vp，保持 4:3 比例，3vp 小圆角，0.5vp 主题细描边。旗帜在浅色／深色模式均不改色，不加 tint；无障碍保留父级币种名称，不重复朗读装饰图。

目前在汇率列表和基准币种胶囊显示，其他页面可复用该组件。1:1 资源同时保留，当前 UI 使用 4:3。

## 导入与验证

`python3 tools/import-currency-flags.py` 从固定上游下载并核对压缩包 SHA-256。可传 `--archive /path/to/archive.tar.gz` 离线重建。导入时校验 XML、资源名、重复名、外部／活动内容及 30 个映射资源；现有同名文件内容不一致时停止，不覆盖用户素材。

该脚本生成映射和清单，应通过脚本更新，不手工修改生成文件。上游许可与 SVG 文件原样保留。

`node tools/verify-currency-flags.mjs` 核对所有 542 个文件大小和 SHA-256、271 个完整比例对、许可证、当前币种覆盖、30 个精确映射、资源引用及未知币种回退。

本轮未运行原生构建或真机 SVG 显示验收；资源校验与主机逻辑测试不能替代设备兼容性检查。

## 自定义币种旗帜

生成的 `CurrencyFlags.ets` 另提供全部 271 个地区的静态资源索引 `REGION_FLAGS`，供币种管理搜索及选择；通过导入脚本生成，不手写动态资源名称。用户旗帜选择保存于数据库的币种设置中，随完整备份恢复。`CurrencyFlagBadge` 优先使用用户选择，再使用初始币种映射；未选或资源不可用时显示货币代码占位。管理页面保存后通过刷新标识更新旗帜，避免同一币种节点继续显示旧资源。


## 欧盟旗帜渲染兼容资源

欧元仍映射欧盟旗帜（蓝底、十二颗金色星）。设备截图中的暗色星环与源 SVG 的 #fc0 不符；源文件使用多层 defs/use 与组继承填色。为消除该渲染依赖，导入脚本额外生成 `flag_4x3_eu_compat.svg` 和 `flag_1x1_eu_compat.svg`：递归展开 use、保留全部变换和路径几何、给每条 path 显式填色。不修改上游 542 个原始 SVG；默认 EUR 和地区 eu 的实际显示映射改用兼容资源。

派生文件元数据见 tools/currency-flags/compatibility.json，包含原始哈希、派生哈希与大小，许可证沿用原 MIT 声明。资源验证检查两种比例、无 defs/use、120 个显式金色三角路径（原星形分解结构）及映射。渲染问题判断依据设备截图与源文件差异；尚未在 ArkUI 设备验证兼容版本的最终颜色。

颜色与图案依据：[欧盟官方旗帜说明](https://european-union.europa.eu/principles-countries-history/symbols/european-flag_en)。
