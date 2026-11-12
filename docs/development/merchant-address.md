# 账目商户与地址

支出、收入和转账的新增、编辑页面均提供选填的“商户”和“地址”文本框，位于时间与备注之间。编辑时回填已保存的文本（包括导入账目），保存时去除首尾空白，支持修改和清空；详情、CSV/Excel 导出继续读取同一组字段。

文本录入复用 transactions.merchant_name_snapshot、address_text 和现有 merchant_id，不增加数据库迁移或商户管理页面。地图选点试接入范围见下文。手动新增商户文本只保存为该笔账目的名称快照，不自动创建全局商户字典。

## 保存约定

- ExpenseCommand、IncomeCommand、TransferCommand 新增可选 merchantName、addressText。undefined 表示编辑时保留原值，空字符串或纯空白表示清空。
- 文本随账目在原有事务内保存，继续受版本冲突校验与失败回滚保护。
- 导入账目的商户名称未改变时保留原商户关联；修改名称或清空时解除该笔 merchant_id，不改名或删除共享商户，不影响其他账目。
- 详情与列表/导出优先读取账目自己的名称快照，快照为空时才读取关联商户名称。地址始终是每笔账目的文本。
- 经纬度字段本轮不录入、不修改。

## 验证

- `node tools/verify-p0.mjs`：48/48 通过，新增三种手动账目命令的文本传递、首尾空白处理、清空与未指定语义检查。
- 主 HAP 完整编译（`assembleHap --no-daemon --no-incremental`）通过。
- 测试包首次编译因新增测试中的对象展开不被 ArkTS 支持而失败，已改为显式字段构造并重建通过。
- 原生 MerchantFields 专项覆盖三种账目新增、修改、清空、重开数据库、CSV 导出以及导入商户关联保留/解除和共享字典不变。
- 2026-11-11：当前模拟器 MerchantFields 原生专项 3/3 通过，Failure=0、Error=0；包含界面文本输入、保存与编辑回填。命令：`hdc shell aa test -b cn.oicode.xiaoqiao -m entry_test -s unittest OpenHarmonyTestRunner -s class MerchantFields -s timeout 60000 -w 60`。日志：`/tmp/xq-merchant-native.log`。
- 主 HAP、ohosTest HAP 均构建通过并覆盖安装，未卸载应用；测试使用独立数据库，界面测试使用现有 TestRunner 创建的隔离库。结束后强制结束测试进程并正常启动应用，恢复正常数据源。
- `git diff --check` 通过。构建仍有既有组件 ID、API 兼容性及异常处理等警告。

真实设备、API 24/25、深色、大字号、长地址显示及完整业务回归未专项执行。

## 原生地图选点试接入（2026-11-11）

地址输入框旁增加“地图选点”，支出、收入、转账共用。通过 `@kit.MapKit` 的 `sceneMap.chooseLocation` 打开原生选点控件，开启地点搜索与附近 POI，不请求地图快照。选择结果有非空地址时回填地址；只有选中带 siteId 的 POI 且当前商户为空时才填入地点名称，不把普通“标记点”当作商户。

本轮只把选择结果接入已有文本字段，经纬度与地点 ID 暂不持久化，重新打开选点页也不按历史坐标定位。当前未新增权限、Client ID、签名指纹或后台服务配置，也未升级地图套餐。手动输入继续可用。

地图打开期间防重复点击并阻止保存。取消、无地址结果、鉴权失败、服务未开通、网络错误或设备不支持时保留原文本。页面关闭后的异步结果忽略，取消后可以再次打开。错误提示使用 SDK 错误码分类，不显示服务端原始错误内容。

验证：`node tools/verify-p0.mjs` 52/52 通过（含真实选点方法的受控依赖回归）；主 HAP、测试 HAP 均构建通过。`MapPickerUnavailable` 是仅面向尚未配置地图服务应用的显式原生冒烟套件，不纳入默认全量回归；运行时需要指定 `-s class MapPickerUnavailable`，检查当前环境返回不可用提示且原商户、地址保留。地图服务完成配置后应改用正常选点专项，不能以此冒烟代替成功选点验收。

官方参考：[地点选取](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V14/map-location-selecting-V14/)、[sceneMap](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V14/map-scenemap-V14/)。接口签名、cancelCallback、错误码和 SystemCapability.Map.Core 已与本地 SDK 声明核对。

原生试接入验证结果：当前模拟器 `MapPickerUnavailable` 1/1 通过（Failure=0、Error=0，`/tmp/xq-map-native.log`），实际点击入口后收到不可用提示，原文本保持且按钮恢复可用。此结果仅证明当前环境的失败处理正常，未证明原生地图成功加载、搜索或选点成功，也未核实该接口费用。首次安装命令因同时连接多个设备未指定目标而失败；指定既有模拟器 `-t 127.0.0.1:5555` 后主包与测试包均安装成功，未操作另一设备。

接入后 MerchantFields 数据库与界面回归 3/3 通过（Failure=0、Error=0，`/tmp/xq-map-merchant-native.log`），覆盖三种账目商户地址保存、修改、清空及文本录入/编辑回填。测试结束后已结束测试进程，正常启动应用恢复原数据源。`git diff --check` 通过。成功选点、真实设备和费用归属仍待验证。

## 地图鉴权配置排查（2026-11-11）

用户确认后，在 `entry/src/main/module.json5` 的 module.metadata 中添加应用级 `client_id`，与后台“小巧记账”（cn.oicode.xiaoqiao）一致。未引入 Client Secret 或 API 密钥。后台重载检查确认该应用地图服务复选框为开启、保存按钮禁用，未升级付费套餐。

本地原签名配置引用的 default_xiaoqiao 证书、Profile 和密钥库缺失。DevEco 自动签名可以临时生成未关联应用的材料，但勾选“关联已注册应用”后因后台证书数量达到上限失败；已取消未应用的对话框，build-profile.json5 与本轮开始时的 SHA-256 一致，没有覆盖用户原有签名改动。未废除、删除任何既有后台证书，也未提交新的 Profile。

只读核对结果：本地存在与后台 debug 证书公钥匹配的 CSR，但 CSR 不是私钥。可读取的本地密钥库经公钥比较不匹配该 debug 证书，因此未把它冒充调试签名使用。需要用户提供 debug/hokit_debug 对应的可用密钥库位置，或明确指定可废除的旧调试证书后重新申请。

验证：module.json5 JSON5 解析、应用 Client ID 一致性检查及 git diff --check 通过。普通 PackageHap 和未设置 SDK 环境的显式任务调用曾报任务不存在；补充 DEVECO_SDK_HOME 后执行 `hvigorw --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon`，ArkTS 编译及未签名打包完成，最终 SignHap 因原签名配置的 storeFile 不存在失败（日志 `/tmp/xq-map-auth-assemble.log`）。此签名材料缺失在本轮改动前已存在，与新增 client_id 无关。未安装本轮新包，未执行成功选点验收，不能将先前不可用场景测试作为本轮鉴权成功的证明。

## 详情页地图与坐标保存（2026-11-12）

本节取代早期试接入中“经纬度暂不持久化”的范围。选点成功时将 Map Kit 返回坐标四舍五入到百万分之一度，随商户、地址写入现有 `latitude_e6`、`longitude_e6`，不新增表、不做迁移，也不进行坐标系转换。支出、收入和转账共用该约定。编辑回填位置，再次选点以原位置为中心；仅编辑金额、商户、标签等内容不会丢失位置。

新增 `LedgerLocation`，坐标必须成对、为整数且在纬度 ±90000000、经度 ±180000000 范围内。命令的 location 为 undefined 时保留旧值，为 null 时清空。手动更改地址（忽略首尾空白）时编辑器清除旧坐标；兼容未携带 location 的旧调用方时，持久层也在地址文本变化时清除坐标，避免地址和地图不一致。图片、标签与账务版本冲突规则不变，所有位置写入仍在原账目事务内。

有坐标的详情页在地址下方显示 180vp 高的原生 `MapComponent`，以坐标为中心、缩放级别 16，添加一个地点标记。小地图关闭拖动、缩放、旋转、倾斜和“我的位置”按钮，不申请定位权限。点击预览或“查看地图”通过 `sceneMap.queryLocation` 打开原生地点详情。地图失败时保留地址并提供重试；不支持地图的设备只显示不可用提示。原生监听在组件销毁或重试时移除，忽略旧地图与已关闭页面的异步回调。

只有地址、没有坐标的历史或导入账目继续显示文字，不自动调用地理编码。此前只保存文字的选点账目，需要编辑并重新选点一次才会显示地图。CSV/Excel 当前仍导出商户、地址文字；完整备份包含数据库中的坐标。

验证记录：主机检查 `node tools/verify-p0.mjs` 54/54 通过；Hvigor `entry@default`、`entry@ohosTest` 的 `assembleHap --no-daemon` 均通过；`python3 tools/generate-rdb-schema.py --check` 确认源 SQL 与生成包的 82 条语句一致；`git diff --check` 通过。首次主包编译发现辅助方法 position 与 ArkUI 组件属性同名，已改名并重建通过。

独立 API 26 模拟器上的 `MerchantFields` 两项持久层检查通过（2/2，0 失败、0 错误），覆盖三种类型的位置保存、数据库重开后读取、更新到零坐标、显式清空，以及旧调用方更改地址时清除坐标。`LocationMapUI` 通过（1/1，0 失败、0 错误）：纯文字账目不展示地图，有坐标账目加载小地图和标记、入口完整露出、打开原生地点详情并显示“路线”，返回编辑保存后坐标和地图保留。已检查临时截图中的小地图、地点详情与底部操作栏。

`LocationMapUI` 只在显式指定该 class 时注册，使用 TestRunner 隔离库与公开地点坐标。运行命令为 `aa test -b cn.oicode.xiaoqiao -m entry_test -s unittest OpenHarmonyTestRunner -s class LocationMapUI -s timeout 60000 -w 60`。调试期间修正了首页刷新、截图路径、从页面留白滑动、等待原生页面退场动画和编辑后返回详情页等测试前置条件；未删除或降低地图加载、入口可见性及坐标保留断言。详情页滚动内容启用裁剪，避免内容绘制到固定操作栏下方。日志保存在临时目录 `/tmp/xq-location-{host,main-build,test-build,ui-native,db-native}.log`，截图未纳入仓库。

本次仅安装到独立空白模拟器 `127.0.0.1:15556`，未覆盖原模拟器或真机。未执行全量原生回归、真机、低版本、深色与大字号专项；本轮 UI 用例使用预置公开坐标，不代替搜索选点完整流程验收。旧账目不会自动补坐标；CSV/Excel 坐标导入导出仍未实现。
