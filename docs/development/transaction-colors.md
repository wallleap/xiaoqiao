# 收支转账颜色

入口：设置 → 外观 → 收支转账颜色。使用独立 HDS 子页面、实际 Scroller 绑定、IMMERSIVE_GRADIENT_BLUR 及配对安全区。左上角返回和系统返回均先回设置；设置页保留挂载与滚动位置，保存期间拦截返回和重复选择。

## 色板与交互

| 类型 | 可选颜色 | 默认 |
| --- | --- | --- |
| 支出 | 红、橙、绿、黑 | 橙 |
| 收入 | 红、绿、黑 | 绿 |
| 转账 | 蓝、黑 | 黑 |

支出／收入仅红色、绿色互斥：一方已选的颜色在另一方禁用并显示锁定状态，换色后恢复可选。**黑色除外，两者可同时选黑色**；转账独立。保存和备份读取也校验同一约束，不用自动换色掩盖冲突。无自定义颜色输入。

色板点击保存后立即发布响应式设置，页面同时预览三类金额；保存失败保持原选项并给出错误。支持恢复默认。选项至少 64×76 vp，Flex 自动换行，锁定状态有无障碍说明。黑色在浅色模式为主题主文字色，深色模式随主题适配为可读浅色。固定深色预算卡使用对应颜色的浅色版本，黑色使用浅色文字，避免黑底黑字。

## 生效范围

- 首页账目金额、每日收支及预算卡收支汇总；账单日历、列表、搜索和账目详情。
- 统计收支数字、柱图、折线、图例、分类环图、排行进度及明细金额。颜色变化触发 Canvas 重绘；分类环图按所选颜色生成同色系深浅，色值加入 ForEach 键，确保选色后更新。
- 记账金额、实付／收入／实际转出金额、转账手续费；退款及报销回款使用收入色。
- 预付款付款显示转账色，核销显示支出色，退款显示收入色。

业务金额与品牌／动作颜色分离：按钮、导航选中态、焦点、分类图标和标签自有配色保留原有规则；标签自有色与本设置分开管理。净资产、账户余额及余额校准不是收支金额，不按正负值擅自改成收支色。

## 保存及完整备份恢复

`TransactionColors.ets` 定义合法色板、互斥约束及主题资源映射。`RdbTransactionColors.ets` 将版本 1 JSON 保存在现有 `db_meta.transaction_colors_v1`，全账本共用。不增加数据表，不需要新数据库迁移或修改备份包格式。

`LedgerWorkspace.saveTransactionColors` 在串行数据库事务中持久保存，提交成功后才通过 AppStorage 发布；失败不改变已生效颜色。打开账本及恢复后的 `Index.loadLedger` 读取并发布已保存设置。各金额页面以 StorageProp 订阅，AmountText 的 color 属性可响应更新。

完整 SQLite 备份本身包含 db_meta，故本地、WebDAV、华为云所共用的完整备份包均包含颜色。恢复与数据库、图片继续共用原有备份／回滚边界，无额外偏好文件需要分别提交。备份校验显式读取并验证该设置；非法枚举、版本或冲突组合拒绝恢复。旧备份不含该键时按默认色板读取，不向旧数据库静默写入默认值。

## 文件与验证

- 页面：SettingsPage、TransactionColorsPage、Index；全局展示：AmountText、BillDetailsPage、EntryDetailPage、ExpenseEditor、ExpenseRecoveryPanel、LedgerSearchPage、PrepaidPage、StatisticsPage。
- 设置：presentation/ledger/TransactionColors、data/rdb/RdbTransactionColors、LedgerWorkspace、LocalLedgerBackup。
- 主题资源：base/dark/element/color.json。

`node tools/verify-transaction-colors.mjs` 覆盖所有 20 个合法组合、红绿互斥与黑色例外、非法配置、真实 db_meta 保存、失败不发布、完整 SQLite 备份恢复、旧备份默认值、主题资源及设置子页面返回保护。相关主机回归运行分类删除、记账币种选择、预付款清理、个人汇总及账本设置脚本。

验证使用主机及临时数据库，未运行原生构建、设备数据库操作或真机视觉验收。原生 HDS 布局、深浅色切换与 Canvas 绘制的最终视觉仍需设备验收。
