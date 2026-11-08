# 账目图片附件

2026-11-08，账目图片附件接入记账、编辑、详情和批量导出流程，复用现有 `attachments`、`transaction_attachments` 表及完整备份资源目录，不需要数据库迁移。

## 当前范围

- 支出、收入和转账都可添加最多 9 张 PNG、JPG 或 WebP 图片。
- 图片通过系统文件选择器读取，存入当前数据库隔离的 `images/<sha256>.<ext>` 资源目录。
- 图片内容按 SHA-256 去重；账目与附件通过 `transaction_attachments` 关联，并按选择顺序保存。
- 新增和编辑账目在同一数据库事务中写入账目、账户变动及附件关联；失败时按原有事务整体回滚。
- 尚未写入任何账目的新图片在取消或移除时会做一次无引用检查并尽力清理；已写入过账目的不可变资源继续保留。
- 编辑时移除图片只删附件关联，不删除仍在资源目录中的不可变文件。
- 详情页显示图片缩略图，点击后打开大图预览。
- CSV/Excel 增加“附件数”字段；另可导出 `含图片.zip`，其中包含当前筛选范围的 CSV、附件清单和去重后的图片文件。
- 完整 `.xqbackup` 继续携带数据库及全部图片资源，跨设备恢复时同时恢复账目和附件关联。

## 导出 ZIP

附件 ZIP 使用标准 STORE ZIP，包含：

```text
docProps/xiaoqiao-entries.csv
docProps/attachments.json
xl/media/<sha256>.png|jpg|webp
```

`attachments.json` 记录格式版本、账本、账目 ID 和原始附件哈希；导出前会核对资源文件的大小和 SHA-256。CSV/Excel 自身仍不嵌入二进制图片。

## 代码

- `LedgerAttachment.ets`：附件草稿、详情模型及数量/路径/哈希校验。
- `RdbAttachmentLinks.ets`：附件元数据去重和账目关联事务。
- `ExpenseRecord.ets`、`IncomeRecord.ets`、`TransferRecord.ets`：收支和转账命令携带附件草稿。
- `ExpenseEditor.ets`：图片选择、缩略图、移除和保存。
- `EntryDetailPage.ets`：附件缩略图与大图 Sheet。
- `LedgerAttachmentZipExport.ets`：带图片资源的 ZIP 导出。
- `Attachments.test.ets`：隔离库验证保存、读取、更新、ZIP 内容及关联移除。

## 验证

资源存储、照片选择器所有权和媒体显示依赖设备文件系统；自动化测试使用应用内置 PNG 构造附件，不读取用户相册。真实相册选择、低版本设备和大图性能由设备交互专项验收。
