# 账户手动排序

资产页标题栏保留“添加账户”，在其右侧新增 Lucide 更多图标。通过原生 PromptAction.openMenu 将 Menu 锚定到 HDS 标题栏的 accounts-more 节点，菜单目前只有“排序”一项，采用可用的沉浸 menuMaterial，失败显示重试提示。菜单内容在关闭、页面离开和打开失败时释放，重复点击不会重复创建。

“排序”进入独立 HDS 账户排序子页面，只显示使用中的账户，不混入归档账户。采用 List／ForEach.onMove 原生长按拖动排序及系统动画；稳定键使用账户 ID。页面提示长按拖动，行尾显示拖动手柄。修改只作用于局部顺序，点击“保存排序”才提交。未变化、拖动中、保存中和退出确认时禁用保存；保存失败保留局部顺序与错误提示，返回重新进入可读取最新账户状态。标题栏返回与系统返回均在有未保存变化时确认丢弃，保存中阻止离开。

沿用页面左右 16 vp、实色卡片、卡片外文字内收 8 vp，主题按钮、浅深色资源和 HDS IMMERSIVE_GRADIENT_BLUR；导航绑定实际 List Scroller。账户名称、币种、图标供识别，不修改账户属性或金额。

保存接口为 LedgerWorkspace.reorderAccounts → RdbAccountRepository.reorder，复用 accounts.sort_order，不新增字段或迁移。完整使用中集合及每项 revision 在 RdbSession.write 事务内校验；重复 ID、非法版本、成员变化、并发修改均拒绝。写入仅修改使用中账户 sort_order／revision／updated_at_ms；任一项失败则事务回滚。不改已归档／已删除账户、资金流水和余额。资产列表与记账账户选项原已按 sort_order 查询，保存后统一重新加载。完整备份已有 accounts 表，顺序随现有备份流程保存和恢复，无需扩展备份格式。

验证：`node tools/verify-account-order.mjs` 在隔离的内存 SQLite 执行生产排序 SQL，覆盖合法保存、集合及版本冲突、部分更新失败回滚、并发陈旧保存、余额与归档记录保持不变；执行生产页面方法验证拖动局部顺序、未保存离开确认、失败保留、菜单关闭释放。配套运行账户详情和系统返回回归。未执行原生构建、真机拖动／菜单定位／沉浸材质视觉验收，也未操作设备数据库。

菜单单色 SVG 不使用 MenuItem.startIcon 的默认渲染：它不会继承 contentFontColor，深色模式可能仍显示黑色描边。保留原生 MenuItem，内部用 Image.fillColor(xq_icon_primary) 与 Text(xq_font_primary) 显式适配主题，不修改图标源文件。
