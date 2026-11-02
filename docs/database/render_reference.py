"""Generate a field dictionary from the review DDL using an in-memory database."""
from pathlib import Path
import sqlite3

ROOT = Path(__file__).parent
DESCRIPTIONS = {
    'db_meta': '数据集标识与元信息；初始化由后续迁移器写入。',
    'schema_migrations': '已完成迁移版本、校验和及时间。',
    'currencies': '版本化币种定义，历史精度不可原地修改。',
    'fx_quotes': '追加保存的参考报价，不能覆盖历史账目快照。',
    'books': '账本及固定的统计本位币。',
    'accounts': '全局资金账户；不保存裸balance字段。',
    'categories': '账本内收入/支出分类树；父节点也能记账。',
    'tags': '账本内标签。',
    'merchants': '全局商户字典，交易独立保存名称和地址快照。',
    'transactions': '用户账目；draft仅供原子写入过程使用，posted才可能进入业务视图。',
    'transaction_tags': '同账本标签关联。',
    'balance_adjustments': '初始余额、校准及补偿调整；发布后不可改写。',
    'account_movements': '账户本币实际收付；来源只能是账目或余额调整之一。',
    'fx_snapshots': '本笔账本折算或具体账户结算的金额对及汇率依据。',
    'budgets': '账本、币种与左闭右开日期区间的预算。',
    'budget_lines': '分类预算额度，祖先汇总不用于相加得到总预算使用额。',
    'attachments': '不可变图片文件元信息；数据库不保存图片原件。',
    'transaction_attachments': '图片与账目的多对多关联、顺序和说明。',
    'import_profiles': '解析与映射配置，不存更新余额的隐含默认。',
    'import_batches': '导入确认、计数和提交状态；默认preserve。',
    'import_rows': '导入暂存行；交易反查使用transactions.import_row_id。',
}
VIEWS = {
    'category_closure': '递归计算分类祖先/后代及depth，含自身；只有parent_id一套真相。',
    'v_posted_transactions': '已发布、未删除且所属导入批次已提交的可见账目。',
    'v_effective_movements': '计入资产且apply的可见交易资金变动，加已发布余额调整。',
    'v_account_balances': '全局账户各自币种下的余额，包含已归档但未删除账户。',
    'v_book_totals': '按账本/本位币汇总收支，转账本金不计收支。',
    'v_budget_usage': '按直接账目累计预算支出，不累加父子分类行。',
    'v_budget_line_usage': '单个分类额度包含后代支出的使用额。',
    'v_net_assets_by_currency': '仅累计账户级计入总资产的账户，按币种分组，不做隐含跨币换算。',
}

def render():
    db = sqlite3.connect(':memory:')
    try:
        db.executescript((ROOT / 'schema-v1.sql').read_text())
        out = ['# V1 字段字典（生成文件）', '',
               '依据 [schema-v1.sql](schema-v1.sql) 生成；不要手动维护重复字段定义。', '',
               '生成命令：`python3 docs/database/render_reference.py`。这仅执行纯内存SQLite，不操作应用数据库。', '',
               '金额`*_minor`为精确整数最小单位；时间戳`*_ms`为毫秒；JSON字段由域层按版本解析，DDL不依赖JSON1。', '',
               '外键列下方逐列列出引用；多列联合外键必须结合SQL整体阅读。CHECK、触发器和唯一索引以SQL为准。', '']
        names = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]
        assert set(names) == set(DESCRIPTIONS)
        for name in names:
            out += [f'## {name}', '', DESCRIPTIONS[name], '', '| 字段 | 类型 | 必填 | 默认 | 外键 |', '| --- | --- | --- | --- | --- |']
            foreign = {}
            for r in db.execute(f'PRAGMA foreign_key_list("{name}")'):
                foreign.setdefault(r[3], []).append(f'{r[2]}.{r[4]}')
            for _, col, typ, notnull, default, pk in db.execute(f'PRAGMA table_info("{name}")'):
                label = col + ('（主键）' if pk else '')
                out.append(f'| {label} | {typ} | {"是" if notnull or pk else "否"} | {default if default is not None else "—"} | {", ".join(foreign.get(col, [])) or "—"} |')
            out += ['']
        out += ['## 派生视图', '', '| 视图 | 含义 |', '| --- | --- |']
        for name, meaning in VIEWS.items():
            out.append(f'| {name} | {meaning} |')
        assert not db.execute('PRAGMA foreign_key_check').fetchall()
        (ROOT / 'schema-reference.md').write_text('\n'.join(out) + '\n')
        print(f'Generated schema-reference.md: {len(names)} tables, {len(VIEWS)} views')
    finally:
        db.close()

if __name__ == '__main__':
    render()
