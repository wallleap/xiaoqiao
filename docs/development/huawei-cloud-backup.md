# 华为账号与云空间备份

接入范围：普通华为账号客户端连接 + 云空间文件备份／恢复。保留本地账本为日常写入源，不实现结构化多端账目合并，不接入 Cloud Foundation Kit 或自建账号服务器。

## 准备与入口

- 设置页“华为账号与云备份”进入独立 HDS 子页面。
- 复用 entry/module.json5 已有 client_id 和 INTERNET 权限，未修改签名配置；开发者中心的应用 Client ID、包名、调试／发布证书指纹仍需实际核对。
- 经用户确认，在 AppScope/app.json5 声明 cloudFileSyncEnabled=true。不启用 cloudStructuredDataSyncEnabled。
- 普通账号登录使用 Account Kit 的 LoginWithHuaweiIDButton、LoginType.ID，不获取手机号。连接身份仅留在当前进程内存，不保存或输出 OpenID、授权码和令牌；进程重启后需再次连接。这是客户端与系统账号的关联，不代表应用服务端账号认证。
- 未新增外部依赖、服务器、付费 API 或数据库迁移。

## 运行环境与系统设置

参照官方适配指南：HarmonyOS 6.0.0.115 及以上、云空间 6.0.0.300 及以上，API 21 Release 及以上；代码额外检查 SDK 版本与云文件系统能力。不支持时保留本地／WebDAV 备份。

用户在系统设置 → 华为账号 → 云空间中开启本应用同步。页面提供系统云空间链接，无法拉起时显示手动操作路径。开关未打开、账号异常、网络、电量或空间不足时，按系统返回结果显示相应提示。

## 备份与恢复

1. 登录和打开页面不生成备份；用户点击“立即备份”并确认上传完整账本、账户、备注和附件后，才生成现有 .xqbackup 包。
2. 在本地 cacheDir 完整生成包，确认当前系统账号匹配后，复制至 /data/storage/el2/cloud/xiaoqiao-backups/<OpenID的SHA256>/ 下的临时文件，再重命名为唯一的 backup-时间戳-UUID.xqbackup。临时文件不进入可恢复列表。
3. 沿用完整包 32 MiB 限制，备份包未另设密码，不将摘要命名空间当作加密措施。备份按时间保留为独立文件，不自动覆盖或清理旧云记录。
4. FileSync.on('progress') 监听系统状态，FileSync.start() 返回只表示请求被接受；页面区分“已写入云目录／已请求同步”与“系统同步已完成”。列表是当前设备云目录视图，不证明每份文件都已完成服务器上传。最近同步时间也是系统返回值。
5. 恢复时先通过 CloudFileCache 缓存文件（最长等待 120 秒），复制到本地 cacheDir，交由已有 backup.prepare 做包、数据库和资源校验。展示账本、账目、账户摘要；再次确认覆盖并核对账号后才调用 backup.restore。
6. 沿用现有恢复前副本、回滚及恢复异常处理；恢复后刷新首页和账户读取。账号变化后清理页面预览，不读取另一账号命名空间。断开应用连接不会关闭系统同步开关或删除云端文件。
7. 页面操作期间通过原有 backupBusy 阻止跳转和其它写入；离开页面解除同步监听，丢弃未执行的恢复预览；不停止用户已授权的系统后台同步。

应用的对外隐私声明发布前应同步说明备份范围、华为云空间存储目的、系统开关、用户删除云数据和导出方式。本轮只更新仓库内开发说明，未发布隐私声明。

## 官方参考

- [Account Kit 简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/account-introduction/)
- [华为账号登录按钮](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/account-unionid-login-button/)
- [端云文件协同适配指导](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/app-cloud-sync-filesync/)
- [云空间设置链接及用户数据管理](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-sync-with-cloud)

## 本轮验证边界

仅核对本地 SDK 的账号按钮、getHuaweiIDState、FileSync、CloudFileCache、文件读写接口及仓库调用关系，执行 git diff --check。按用户要求未运行构建、测试、模拟器或真机；没有实际登录、上传、下载或恢复账本，也未在开发者后台开通或部署服务。

待手动确认：登录与取消、Client ID／签名匹配、系统开关可见、同账号两设备上传下载、后台同步状态、离线／空间不足、账号切换、恢复预览取消、恢复与回滚及旧备份保留。费用和正式上线条件以华为后台及最新政策为准，本轮未验证开发者账号实际服务开通状态。


编译反馈修复：HuaweiAccountConnection 静态方法通过类名访问 openID 与 disconnect，避免 ArkTS 的 arkts-no-standalone-this 错误。已静态检查新增云备份类的静态方法，无同类 this 用法；未重新运行构建，待用户手动编译确认。
