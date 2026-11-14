# V1 字段字典（生成文件）

依据 [schema-v1.sql](schema-v1.sql) 生成；不要手动维护重复字段定义。

生成命令：`python3 docs/database/render_reference.py`。这仅执行纯内存SQLite，不操作应用数据库。

金额`*_minor`为精确整数最小单位；时间戳`*_ms`为毫秒；JSON字段由域层按版本解析，DDL不依赖JSON1。

外键列下方逐列列出引用；多列联合外键必须结合SQL整体阅读。CHECK、触发器和唯一索引以SQL为准。

## account_movements

账户本币实际收付；来源只能是账目或余额调整之一。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| account_id | TEXT | 是 | — | accounts.id |
| currency_id | TEXT | 是 | — | accounts.currency_id |
| transaction_id | TEXT | 否 | — | transactions.id |
| adjustment_id | TEXT | 否 | — | balance_adjustments.id |
| leg | TEXT | 是 | — | — |
| delta_minor | INTEGER | 是 | — | — |
| occurred_at_ms | INTEGER | 是 | — | — |

## accounts

全局资金账户；不保存裸balance字段。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| name | TEXT | 是 | — | — |
| kind | TEXT | 是 | — | — |
| currency_id | TEXT | 是 | — | currencies.id |
| brand | TEXT | 否 | — | — |
| icon_key | TEXT | 否 | — | — |
| icon_variant | TEXT | 否 | — | — |
| brand_color | TEXT | 否 | — | — |
| include_in_net_assets | INTEGER | 是 | 1 | — |
| sort_order | INTEGER | 是 | 0 | — |
| archived_at_ms | INTEGER | 否 | — | — |
| created_at_ms | INTEGER | 是 | — | — |
| updated_at_ms | INTEGER | 是 | — | — |
| revision | INTEGER | 是 | 1 | — |
| deleted_at_ms | INTEGER | 否 | — | — |

## attachments

不可变图片文件元信息；数据库不保存图片原件。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| content_sha256 | TEXT | 是 | — | — |
| relative_path | TEXT | 是 | — | — |
| mime_type | TEXT | 是 | — | — |
| byte_size | INTEGER | 是 | — | — |
| width | INTEGER | 否 | — | — |
| height | INTEGER | 否 | — | — |
| state | TEXT | 是 | — | — |
| created_at_ms | INTEGER | 是 | — | — |
| deleted_at_ms | INTEGER | 否 | — | — |

## balance_adjustments

初始余额、校准及补偿调整；发布后不可改写。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| account_id | TEXT | 是 | — | accounts.id |
| kind | TEXT | 是 | — | — |
| before_minor | INTEGER | 是 | — | — |
| after_minor | INTEGER | 是 | — | — |
| delta_minor | INTEGER | 是 | — | — |
| reversal_of_id | TEXT | 否 | — | balance_adjustments.id |
| reason | TEXT | 是 | — | — |
| occurred_at_ms | INTEGER | 是 | — | — |
| created_at_ms | INTEGER | 是 | — | — |
| revision | INTEGER | 是 | 1 | — |
| posting_state | TEXT | 是 | 'draft' | — |

## books

账本及固定的统计本位币。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| name | TEXT | 是 | — | — |
| base_currency_id | TEXT | 是 | — | currencies.id |
| timezone | TEXT | 是 | — | — |
| icon_key | TEXT | 否 | — | — |
| sort_order | INTEGER | 是 | 0 | — |
| archived_at_ms | INTEGER | 否 | — | — |
| created_at_ms | INTEGER | 是 | — | — |
| updated_at_ms | INTEGER | 是 | — | — |
| revision | INTEGER | 是 | 1 | — |
| deleted_at_ms | INTEGER | 否 | — | — |

## budget_lines

分类预算额度，祖先汇总不用于相加得到总预算使用额。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| budget_id | TEXT | 是 | — | budgets.id |
| book_id | TEXT | 是 | — | categories.book_id, budgets.book_id |
| category_id | TEXT | 是 | — | categories.id |
| category_kind | TEXT | 是 | 'expense' | categories.kind |
| amount_minor | INTEGER | 是 | — | — |

## budgets

账本、币种与左闭右开日期区间的预算。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| book_id | TEXT | 是 | — | books.id |
| currency_id | TEXT | 是 | — | currencies.id |
| period_start_date | TEXT | 是 | — | — |
| period_end_date_exclusive | TEXT | 是 | — | — |
| total_minor | INTEGER | 是 | — | — |
| created_at_ms | INTEGER | 是 | — | — |
| updated_at_ms | INTEGER | 是 | — | — |
| revision | INTEGER | 是 | 1 | — |
| deleted_at_ms | INTEGER | 否 | — | — |

## categories

账本内收入/支出分类树；父节点也能记账。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| book_id | TEXT | 是 | — | categories.book_id, books.id |
| kind | TEXT | 是 | — | categories.kind |
| parent_id | TEXT | 否 | — | categories.id |
| name | TEXT | 是 | — | — |
| name_key | TEXT | 是 | — | — |
| icon_key | TEXT | 否 | — | — |
| sort_order | INTEGER | 是 | 0 | — |
| archived_at_ms | INTEGER | 否 | — | — |
| created_at_ms | INTEGER | 是 | — | — |
| updated_at_ms | INTEGER | 是 | — | — |
| revision | INTEGER | 是 | 1 | — |
| deleted_at_ms | INTEGER | 否 | — | — |

## currencies

版本化币种定义，历史精度不可原地修改。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| code | TEXT | 是 | — | — |
| numeric_code | TEXT | 否 | — | — |
| name | TEXT | 是 | — | — |
| symbol | TEXT | 是 | — | — |
| minor_unit | INTEGER | 是 | — | — |
| valid_from | TEXT | 是 | — | — |
| valid_to | TEXT | 否 | — | — |
| source_version | TEXT | 是 | — | — |
| is_enabled | INTEGER | 是 | 1 | — |

## db_meta

数据集标识与元信息；初始化由后续迁移器写入。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| key（主键） | TEXT | 是 | — | — |
| value | TEXT | 是 | — | — |

## fx_quotes

追加保存的参考报价，不能覆盖历史账目快照。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| from_currency_id | TEXT | 是 | — | currencies.id |
| to_currency_id | TEXT | 是 | — | currencies.id |
| rate_decimal | TEXT | 是 | — | — |
| provider | TEXT | 是 | — | — |
| quoted_at_ms | INTEGER | 是 | — | — |
| fetched_at_ms | INTEGER | 是 | — | — |

## fx_snapshots

本笔账本折算或具体账户结算的金额对及汇率依据。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| transaction_id | TEXT | 是 | — | account_movements.transaction_id, transactions.id |
| account_movement_id | TEXT | 否 | — | account_movements.id |
| role | TEXT | 是 | — | — |
| from_currency_id | TEXT | 是 | — | currencies.id |
| to_currency_id | TEXT | 是 | — | currencies.id |
| from_minor | INTEGER | 是 | — | — |
| to_minor | INTEGER | 是 | — | — |
| rate_decimal | TEXT | 是 | — | — |
| rate_source | TEXT | 是 | — | — |
| rate_time_ms | INTEGER | 是 | — | — |
| rounding_mode | TEXT | 是 | — | — |
| calculation_version | INTEGER | 是 | — | — |

## import_batches

导入确认、计数和提交状态；默认preserve。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| book_id | TEXT | 是 | — | books.id |
| file_sha256 | TEXT | 是 | — | — |
| file_name | TEXT | 是 | — | — |
| sheet_name | TEXT | 否 | — | — |
| header_row | INTEGER | 是 | — | — |
| encoding | TEXT | 否 | — | — |
| delimiter | TEXT | 否 | — | — |
| profile_snapshot_json | TEXT | 是 | — | — |
| balance_mode | TEXT | 是 | 'preserve' | — |
| status | TEXT | 是 | 'staged' | — |
| total_count | INTEGER | 是 | — | — |
| selected_count | INTEGER | 是 | 0 | — |
| skipped_count | INTEGER | 是 | 0 | — |
| confirmed_at_ms | INTEGER | 否 | — | — |
| committed_at_ms | INTEGER | 否 | — | — |
| error_code | TEXT | 否 | — | — |
| created_at_ms | INTEGER | 是 | — | — |

## import_profiles

解析与映射配置，不存更新余额的隐含默认。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| name | TEXT | 是 | — | — |
| source_kind | TEXT | 是 | — | — |
| profile_version | INTEGER | 是 | — | — |
| parse_options_json | TEXT | 是 | — | — |
| column_mapping_json | TEXT | 是 | — | — |
| value_mapping_json | TEXT | 是 | — | — |
| created_at_ms | INTEGER | 是 | — | — |
| updated_at_ms | INTEGER | 是 | — | — |

## import_rows

导入暂存行；交易反查使用transactions.import_row_id。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| batch_id | TEXT | 是 | — | import_batches.id |
| sheet_name | TEXT | 是 | '' | — |
| row_number | INTEGER | 是 | — | — |
| raw_json | TEXT | 是 | — | — |
| normalized_json | TEXT | 否 | — | — |
| validation_status | TEXT | 是 | 'pending' | — |
| issue_codes_json | TEXT | 是 | '[]' | — |
| duplicate_candidate_ids_json | TEXT | 是 | '[]' | — |
| selected | INTEGER | 是 | 0 | — |

## merchants

全局商户字典，交易独立保存名称和地址快照。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| name | TEXT | 是 | — | — |
| normalized_name | TEXT | 是 | — | — |
| default_address | TEXT | 否 | — | — |
| archived_at_ms | INTEGER | 否 | — | — |
| created_at_ms | INTEGER | 是 | — | — |
| updated_at_ms | INTEGER | 是 | — | — |
| revision | INTEGER | 是 | 1 | — |
| deleted_at_ms | INTEGER | 否 | — | — |

## schema_migrations

已完成迁移版本、校验和及时间。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| version（主键） | INTEGER | 是 | — | — |
| checksum | TEXT | 是 | — | — |
| applied_at_ms | INTEGER | 是 | — | — |

## tags

账本内标签。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| book_id | TEXT | 是 | — | books.id |
| name | TEXT | 是 | — | — |
| name_key | TEXT | 是 | — | — |
| color_token | TEXT | 否 | — | — |
| sort_order | INTEGER | 是 | 0 | — |
| created_at_ms | INTEGER | 是 | — | — |
| updated_at_ms | INTEGER | 是 | — | — |
| revision | INTEGER | 是 | 1 | — |
| deleted_at_ms | INTEGER | 否 | — | — |

## transaction_attachments

图片与账目的多对多关联、顺序和说明。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| transaction_id（主键） | TEXT | 是 | — | transactions.id |
| attachment_id（主键） | TEXT | 是 | — | attachments.id |
| sort_order | INTEGER | 是 | — | — |
| caption | TEXT | 否 | — | — |

## transaction_tags

同账本标签关联。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| transaction_id（主键） | TEXT | 是 | — | transactions.id |
| tag_id（主键） | TEXT | 是 | — | tags.id |
| book_id | TEXT | 是 | — | tags.book_id, transactions.book_id |

## transactions

用户账目；draft仅供原子写入过程使用，posted才可能进入业务视图。

| 字段 | 类型 | 必填 | 默认 | 外键 |
| --- | --- | --- | --- | --- |
| id（主键） | TEXT | 是 | — | — |
| book_id | TEXT | 是 | — | import_batches.book_id, categories.book_id, books.id |
| kind | TEXT | 是 | — | categories.kind |
| group_id | TEXT | 否 | — | — |
| category_id | TEXT | 否 | — | categories.id |
| currency_id | TEXT | 是 | — | currencies.id |
| gross_minor | INTEGER | 是 | — | — |
| discount_minor | INTEGER | 是 | 0 | — |
| paid_minor | INTEGER | 是 | — | — |
| book_currency_id | TEXT | 是 | — | currencies.id |
| book_minor | INTEGER | 否 | — | — |
| include_in_budget | INTEGER | 是 | 0 | — |
| include_in_assets | INTEGER | 是 | 1 | — |
| balance_mode | TEXT | 是 | 'apply' | import_batches.balance_mode |
| reimbursement_status | TEXT | 是 | 'none' | — |
| merchant_id | TEXT | 否 | — | merchants.id |
| merchant_name_snapshot | TEXT | 否 | — | — |
| address_text | TEXT | 否 | — | — |
| latitude_e6 | INTEGER | 否 | — | — |
| longitude_e6 | INTEGER | 否 | — | — |
| note | TEXT | 是 | '' | — |
| import_batch_id | TEXT | 否 | — | import_batches.id, import_rows.batch_id |
| import_row_id | TEXT | 否 | — | import_rows.id |
| source_provider | TEXT | 否 | — | — |
| source_namespace | TEXT | 否 | — | — |
| source_record_id | TEXT | 否 | — | — |
| source_fingerprint | TEXT | 否 | — | — |
| duplicate_override | INTEGER | 是 | 0 | — |
| occurred_at_ms | INTEGER | 是 | — | — |
| occurred_local_date | TEXT | 是 | — | — |
| occurred_timezone | TEXT | 是 | — | — |
| occurred_offset_minutes | INTEGER | 是 | — | — |
| posting_state | TEXT | 是 | 'draft' | — |
| created_at_ms | INTEGER | 是 | — | — |
| updated_at_ms | INTEGER | 是 | — | — |
| revision | INTEGER | 是 | 1 | — |
| deleted_at_ms | INTEGER | 否 | — | — |

## 派生视图

| 视图 | 含义 |
| --- | --- |
| category_closure | 递归计算分类祖先/后代及depth，含自身；只有parent_id一套真相。 |
| v_posted_transactions | 已发布、未删除且所属导入批次已提交的可见账目。 |
| v_effective_movements | 计入资产且apply的可见交易资金变动，加已发布余额调整。 |
| v_account_balances | 全局账户各自币种下的余额，包含已归档但未删除账户。 |
| v_book_totals | 按账本/本位币汇总收支，转账本金不计收支。 |
| v_budget_usage | 按直接账目累计预算支出，不累加父子分类行。 |
| v_budget_line_usage | 单个分类额度包含后代支出的使用额。 |
| v_net_assets_by_currency | 仅累计账户级计入总资产的账户，按币种分组，不做隐含跨币换算。 |


## V6 预算分类自定义颜色（2026-11-14）

源文件 schema-v6-nature-color.sql；通过 tools/generate-nature-color-schema.py 生成 NatureColorSchema.ets，不手改生成代码。新增 spending_natures.custom_color TEXT NULL，非空须为大写 #RRGGBB。旧 color_token CHECK 保留，自定义色以 neutral 令牌配合该字段保存；旧行无更新。升级代码 NatureColorMigration 遵循 v5 备份、事务、旧数据指纹／外键／完整性校验及迁移标记，普通开库要求显式升级确认。回退使用升级前备份，不直接降级表结构；迁移代码未在用户数据执行。备份容器 schema 6 可接收 v2–v5 候选备份并逐级迁移。
