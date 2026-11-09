# WebDAV 手动备份与恢复

## 范围和入口

设置页的「WebDAV 备份」支持保存连接信息、测试并读取远端列表、上传当前账本、下载并预览恢复。网络操作只在用户点击后执行。连接信息加载不联网。备份使用包含数据库、图片和自定义图标的 `.xqbackup` 完整包，见 [格式说明](backup-package.md)。恢复前保留副本并复用原有恢复失败回退与启动恢复机制。

服务器地址填写已经存在的 HTTPS WebDAV 父目录，末尾自动补 `/`。文件统一保存到该地址下的 `xiaoqiao/`。操作前用 PROPFIND 检查，404 时通过 MKCOL 创建，再读取验证确为目录。同名项是文件、创建无权限或父目录不存在时停止，不覆盖同名项。若创建遇到 405，重新检查以兼容另一设备刚创建目录的情况。本轮不做自动同步、增量合并、远端删除或多设备冲突合并。远端列表只显示当前目录的 `xiaoqiao-*.xqbackup` 文件，不递归子目录。其他设备上传的同格式文件也可预览，最终仍须通过本地结构和完整性检查。

## 凭据和网络约束

- 使用系统 Asset Store 保存一条包含地址、用户名、密码的记录，设备解锁后可读取，禁止系统同步。覆盖时原子替换整条记录，避免地址与密码错配。设置页可移除连接信息，移除不会删除任何远端文件。
- 连接信息按 UTF-8 JSON 合计不超过 1024 字节。密码输入使用系统密码控件，不记录请求头、密码、响应正文或服务端错误详情。
- `module.json5` 新增 `ohos.permission.INTERNET`。无第三方依赖。使用 NetworkKit HTTP 的 `customMethod` 发送 `PROPFIND` 和 `MKCOL`，Depth 为 1。地址拒绝明文 HTTP、URL 中的账号密码、查询和片段。Basic 认证只经正常验证证书的 HTTPS 发送，不绕过证书检查。
- 禁止自动重定向。远端 href 必须同源、属于配置目录且仅一层，拒绝目录穿越、编码斜线、控制字符和外站链接。XML 使用系统命名空间解析器，仅取 DAV 命名空间中成功 propstat 的属性，拒绝 DTD 和实体声明。
- 连接超时 15 秒，整次请求读超时 60 秒，列表响应最大 1 MiB。此版使用有上限的二进制响应缓冲，WebDAV 备份单文件最大 32 MiB，本地完整包同样为 32 MiB。上传前检查本地文件，下载后核对列表大小，再检查完整包和数据库。超限时提示包大小限制。
- 上传文件名包含 UTC 时间与 UUID，使用 `If-None-Match: *`，仅接受新建成功的 201。同名冲突不会被视为成功。不主动覆盖或清理远端文件。

## 恢复流程

检查/创建 xiaoqiao 目录 → 读取列表 → 点击备份 → 下载至随机命名的应用缓存 → 调用 LedgerBackupPackage.prepare → 删除下载缓存 → 显示账本、账目和账户数量 → 用户确认替换 → 调用既有 restore → 刷新首页及账户。

选择和预览不会修改当前账本。取消走既有 discard。下载失败、大小不符、数据库损坏、版本不兼容或资源不齐全时均不进入恢复确认。操作进行中沿用设置页 busy 锁，禁止跨页及并发备份恢复。网络异常只显示经过归类的本地提示。临时上传、下载文件在成功或失败后均尝试清理。

此版未加密完整备份包。账号密码不在账务数据库快照内。用户应使用自己的可信服务器。账目图片选择与预览已接入，见 [账目图片附件](attachments.md)。跨版本转换、证书私有 CA 配置和 WebDAV Digest/OAuth 不在本轮范围。

## 验证方法

常规原生回归注册 WebDav 类，验证真实系统 URL/XML 解析、安全存储保存/覆盖/删除，以及虚构远端传输下的隔离数据库备份、预览、恢复和坏文件拒绝。UI 用例只检查设置控件并截图，不对真实服务器发送请求。

WebDavHttp 是显式运行的本机 HTTP 适配器集成测试，仅在指定该类时注册。它通过 hdc 反向端口访问电脑的本机内存服务，验证真实 NetworkKit 请求的自定义方法、请求头、二进制收发、认证失败、目录创建/复用、同名冲突和重定向禁止。HTTP 只用于这个本机适配器测试，生产 WebDavClient 始终要求 HTTPS。该测试不验证公网 TLS 或具体服务商兼容性。

```sh
python3 tools/serve-webdav-fixture.py
# 另一个终端，测试结束后停止服务并移除转发
hdc -t 127.0.0.1:5555 rport tcp:18765 tcp:18765
hdc -t 127.0.0.1:5555 shell aa test -b cn.oicode.xiaoqiao -m entry_test -s unittest OpenHarmonyTestRunner -s class WebDavHttp -s timeout 120000 -w 180
hdc -t 127.0.0.1:5555 fport rm tcp:18765 tcp:18765
```

真实服务器的 HTTPS 证书、目录权限和厂商兼容性仍需用户填写地址后验证。开发验证不连接真实账号，不上传真实账务数据。

## 官方参考

- [HTTP 请求](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/http-request/)
- [HTTP 接口](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-http/)，本地 SDK 对 customMethod 和 maxRedirects 标注自 API 23 支持，低于项目最低 API 24。
- [Asset Store 接口](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-asset/)

## 本地图片与容量限制

图片保存在应用持久目录，随完整备份导出。完整备份包最多 32 MiB，图片与图标合计最多 2046 个，超限会提示失败。已保存过的图片解除账目关联后仍保留，并计入完整备份容量。
