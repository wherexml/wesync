# WeSync 改名与兼容边界

2026-10-16：应用展示名称为 **WeSync**，私有仓库为 `wherexml/wesync`。项目源自 GreenBubbles，保留原始历史、MIT 许可与归属。此次不发布版本标签或更改仓库可见性。

## 实施前的失败场景

- 改 Bundle ID、证书或团队可能使钥匙串、磁盘权限与缓存失去连续性。
- 将安装目录直接改名会使已记住的 CLI 绝对路径和 Homebrew 命令软链接失效。
- 改工具字节却没有受签名保护的摘要迁移，会阻止自动连接。
- 仅改 Info.plist 会遗漏菜单栏、侧栏、欢迎页和发行包名称。
- 从脏工作区构建会将尚未完成的搜索框变动混入安装包。
- 更新本地打包脚本却遗漏 release workflow，会造成发布流程找不到 App 或 DMG。

## 迁移约定

- 安装到 `/Applications/WeSync.app`，`CFBundleName` 和 `CFBundleDisplayName` 为 `WeSync`。
- 保持 `me.greenbubbles.GreenBubbles`、现有 Apple Development 证书、团队、entitlements、CLI/helper 标识、凭据服务名、缓存路径与协议不变。
- 保留 `/Applications/GreenBubbles.app` → `WeSync.app` 的兼容软链接，使现有连接及 `greenbubbles` 命令继续使用同一路径。它不是第二份安装包。
- 签名工具更新对比解析软链接后的路径，仍只接受当前包内工具；继续验证确切前驱/后继摘要、应用与工具完整签名及相同证书。
- 本次复制安装包内 CLI/helper，不重新编译或重签这些工具。仅编译主应用的改名源码。
- 本机源码目录、Swift/Rust 模块名、图标资源文件名与 `wechatsync-*` skills 保留兼容名称。
- 源码使用 `git archive HEAD` 加本次改名文件构建，排除既有搜索框未提交修改。
- 后续本机 staging 默认从 WeSync 安装包读取；初次改名显式指定旧安装包。

## 重复验收

1. 记录旧安装包的 Bundle ID、证书、designated requirement、helper 摘要和连接可用状态，不读取凭据内容。
2. 使用现有证书签署不同资源封装的两个副本，要求与旧安装包的 DR 一致；严格验证全部签名和 helper 字节不变。
3. 原生退出，确认进程不存在；保留旧包用于回滚，安装 WeSync 并建立旧路径软链接。
4. 通过原生应用入口打开 WeSync，验证无需输入密码/密钥即可自动连接；打开会话并主动刷新。
5. 检查侧栏、应用菜单及菜单栏菜单的 WeSync 名称；关闭和打开窗口。
6. 再次完整退出、确认进程不存在、原生冷启动并刷新，确认没有钥匙串或磁盘权限确认。
7. 验证旧路径命令、打包路径、仓库名、Private 可见性、origin 和 CI。

脱敏结果记录于 `docs/acceptance/wesync-rename-20261016.json`。不保存真实聊天截图、联系人、正文或凭据。
