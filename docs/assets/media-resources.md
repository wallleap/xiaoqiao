# 图标资源命名

2026-11-02：为修复鸿蒙资源打包不允许 `media` 内嵌套目录的问题，经用户选择“重命名图标”，将原 accounts、colorful、lucide 三组共 2,178 个 SVG（另有两份原 README 移入本目录） 放平到 `entry/src/main/resources/base/media`。

- 分组前缀分别为 `accounts_`、`colorful_`、`lucide_`。
- 连字符等字符转为下划线；中文名使用稳定编号，原名称保存在映射表中。
- 完整对应关系与文件 SHA-256 见 [media-resource-map.csv](media-resource-map.csv)。本次只改路径与名称，不改 SVG 内容。
- 使用方式例如 `$r('app.media.accounts_alipay')`、`$r('app.media.accounts_cash')`。
- 迁移前已检查现有 ETS/JSON 与设计说明，未发现依赖原图标子目录的运行代码引用。
- 新图标沿用分组前缀；不要重新建立 media 子目录，不要因调整排序给已有编号重新命名。

## 旗帜资源

完整导入 flag-icons 两种比例 SVG，统一使用 flag_4x3_／flag_1x1_ 前缀，原文件内容不变。来源、许可证、清单、币种映射和导入命令见 [币种旗帜](currency-flags.md)。
