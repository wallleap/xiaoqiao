# Figma 查看入口与版本规则

整理日期：2026-11-01。本次整理 Figma 页面组织，并补充其它手机页面/状态；不修改应用业务代码。

## 查看顺序

| Figma Page | 用途 |
| --- | --- |
| 01 当前审阅 | 原有七个主页面、08—15手机补页；新增19导入导出与20平板导入导出；右侧16—18为新宽屏稿，尚未完成归组和验收 |
| 02 待统一 · 流程与多设备 | 表单与辅助状态、WebDAV 备份恢复、多设备、宽屏备份插画四组待统一稿 |
| 03 设计规范与历史归档 | 设计规范与组件、应用图标、历史页面三个独立分区 |

## 原有七个主页面

第一行是四个主入口，第二行是记账、详情和预算。

| 名称 | Figma 节点 |
| --- | --- |
| 01 账目 | [148:126](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=148-126) |
| 02 统计 | [148:336](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=148-336) |
| 03 资产 | [148:539](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=148-539) |
| 04 设置 | [130:206](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=130-206)，保留用户手调内容 |
| 05 记一笔 | [159:284](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=159-284) |
| 06 账目详情 | [160:122](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=160-122) |
| 07 预算 | [162:190](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=162-190) |

## 其它手机页面

八组补页依次为账户与转账、账本分类与标签、搜索与筛选、统计与预算、数据与WebDAV、华为账号与云空间、币种商户与图片、首次使用与辅助状态。

打开 [其它页面补全与查看清单](native-secondary-pages.md)，按功能组进入对应Figma节点。补页包含不同状态，尚未全部完成实际截图验收；平板与折叠屏的新原生稿已生成，暂放第一页右侧16—18分区；原第二页仍是待统一旧稿，尚未归档。

## 导入与导出

本轮新增内容集中在 [19 手机导入导出](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=200-11947) 与 [20 平板导入导出](https://www.figma.com/design/dJYnqnP48fRqzhv6VFurSH/?node-id=205-12339)。原E01—E06导出稿已从10搜索组移入19，沿用原节点，不另建重复版本。流程规则、余额默认策略及验证限制见 [导入导出说明](import-export.md)。

## 后续维护

- 已审阅页面在同一个节点继续更新，避免新增多个“采用”“最终”“重建”版本。
- 尚未统一的旧功能与多设备稿暂留第二页，新手机补页按08—15功能分组收纳在第一页；旧稿不作为新增补页的开发依据。
- 历史稿只用于追溯和对照，不作为当前开发依据；本次没有删除历史稿。
- 颜色、字体、圆角、间距和组件放在规范分区，图标候选单独保留。
- 当前稿完整程度及交互限制见 [主页面说明](layout-tokens/native-main-pages.md) 和 [表单页面说明](layout-tokens/native-form-pages.md)。新增补页及其未完成检查见 [补页说明](native-secondary-pages.md)。


## 2026-11-02 本轮查看建议

优先从 [导入导出示例原型](https://www.figma.com/proto/dJYnqnP48fRqzhv6VFurSH/?node-id=200-10625&scaling=min-zoom&content-scaling=fixed&page-id=0%3A1&hide-ui=1) 查看已连接的导入、余额选择与导出切换路径。原型使用固定示例，完整数据交互与全部分支尚未连接。关键手机页已检查320宽度，两张平板稿已检查1024宽度，检查后恢复原画板尺寸。


## 控件选型约束

自2026-11-02起，后续UI按“HDS沉浸光感控件 → 其他HDS控件 → ArkUI基础控件 → 必要业务定制”的顺序选型，覆盖此前泛指的官方控件优先规则。现有页面对应关系、业务定制例外与开发核实要求见 [华为控件优先规则](huawei-controls.md)。该规则不代表现有Figma图层已全部替换为官方控件实例。
