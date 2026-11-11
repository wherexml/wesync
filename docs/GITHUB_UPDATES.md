# GitHub 更新

## 右下角自动更新调整：实施前失败场景

- 仅复用更新引擎而仍显示居中标准窗口，与 CyberMe V6 右/下 24px、就绪提醒不符。
- 后台找到更新却等待用户先点击下载；无更新或后台出错仍弹窗抢焦点。
- 关闭卡片取消已校验更新，菜单再次查看无法恢复；重复检查/重启触发重复任务。
- 下载取消后旧回调重新显示就绪；验签失败仍保留安装按钮；任意状态覆盖聊天点击区域。
- 自动下载错误地读取签名私钥、运行签名工具，或把本机构建钥匙串提示变成用户更新步骤。
- 安装路径不可写/所有权不兼容时静默请求提权；不得修改 ACL、TCC 或绕过系统钥匙串。
- 主窗口关闭/隐藏时丢失已就绪回调；用户正常退出时 Sparkle 后续安装与缓存持久化冲突。
- 测试只显示独立空白窗口，未检查生产聊天布局、右下角位置、滚动和重启后的自动连接。
- 未变化的 framework 仍逐次重签，反复触发开发端签名钥匙串访问；复用时遗漏原始内容、架构、证书、权限或策略版本，或损坏缓存被静默当作成功。

## 目标与边界

参考 CyberMe 的后台检查、签名验证、下载及确认重启流程。we-sync 保留 SwiftUI/AppKit，使用 Sparkle 的校验/安装引擎与自定义原生右下角卡片；应用菜单及菜单栏均提供“检查更新…”。GitHub 托管 appcast 与版本 DMG，不需要额外服务或用户登录。

公开发行版使用固定 Developer ID 团队。Apple Development 本机安装继续沿用其身份、凭据与权限，不自动替换成另一团队的发行版；手动检查可打开 GitHub 版本页。初始化更新签名密钥只进行一次，私钥保存在专用钥匙串条目，仓库仅保存公钥。

本轮建设更新机制，不发布新二进制版本，也不启用 GitHub Actions。现有已签名、公证的公开版本可以作为初始 feed 条目；后续正式发行必须先验证候选包，再更新 feed。

## 实施前失败场景

- 网络离线、TLS/重定向错误、损坏或过大的 feed、重复点击；不得阻塞主线程、影响聊天或在后台反复弹错。
- 把预发布、较旧 build、同版本或不兼容系统/架构当成升级；版本号、build 和 DMG 文件信息不一致。
- 包被篡改、更新签名不匹配、应用身份或嵌套签名不正确；不得关闭签名验证、Gatekeeper 或 TCC。
- SwiftPM 动态 framework 未嵌入、符号链接丢失、nested helper 未按同团队签名，导致打包或启动失败。
- 本机开发身份被公开发行团队覆盖，钥匙串、磁盘权限失效；普通升级不得迁移签名身份。
- 退出前缓存未保存、已记住 CLI 摘要改变后连接丢失、更新后重复窗口或无法自动连接。
- 下载取消、无写权限、安装失败或重启失败；不得破坏原应用、用户数据或旧备份。
- 更新私钥被输出、写入 Git、重新生成，或测试 feed/key 能通过生产环境变量开启。
- 仅合成检查通过就宣称安装版验收完成；仅创建本地 feed 就声称 GitHub 更新可访问。

## 验证计划

先以独立原生 E2E 验证“无更新、存在更新、签名拒绝、取消、实际安装与重启”，产出报告及合成截图。合成通道仅限 DEBUG 的独立 Preview Bundle ID，不改生产更新源、公钥或连接。

正式安装沿用原 Apple Development 身份，保留全部查询/输入 helper 字节；原生退出重开验证自动连接、设置、关于及检查更新入口。静态验证 framework、归档、版本、更新签名及旧版已公证 DMG，不额外发布一个版本来测试。

参考：CyberMe 的 `native/mygo/update.go` 与 `internal/updatefeed/feed.go`、[Sparkle 官方接入](https://sparkle-project.org/documentation/)、[发布更新](https://sparkle-project.org/documentation/publishing/)。

## 实现契约

- 固定 Sparkle **2.10.1**，SwiftPM revision/checksum 锁定。完整许可证与上游 artifact 比较，进入分发依赖基线，并独立放入应用包。`sparkle_bundle.py` 先签 Autoupdate、Updater.app、两个 XPC 再签 framework；主包最后签名，不关闭 library validation，保留 Downloader 沙盒。
- 更新源固定为 `https://raw.githubusercontent.com/wherexml/wesync/main/updates/appcast.xml`；下载只允许本仓库 HTTPS GitHub Releases 的 DMG。生产代码没有 feed/key 环境变量覆盖，只有 release 默认通道。
- Ed25519 公钥固定在源码和封装；专用 Sparkle 钥匙串 account 为 `me.greenbubbles.GreenBubbles.sparkle`。仅首次生成，普通发布只使用既有 key，不导出、不枚举钥匙串、不重新生成。
- `SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction` 均开启，`SUSignedFeedFailureExpirationInterval=0`，不会因为 feed 验证失败一段时间就降级。后台默认每小时检查，启动时遵守用户偏好检查一次，菜单可关闭。自定义 SPUUserDriver 在普通更新被验证且应用可写时直接开始下载，不先弹下载确认；就绪后显示重启按钮，系统画像上报关闭。
- 公开客户端仅在 Bundle ID 与 Developer ID 团队 `T695TT4HT9` 同时验证通过时启动 updater。本机 Apple Development 安装保留原团队，通过菜单查看 GitHub 版本页，普通升级不自动迁移权限身份。
- Sparkle 接管安装替换与重启；应用原有 `applicationShouldTerminate` 继续等候缓存末次写入。未来 CLI 改变时，封装内 ToolUpdate 精确绑定旧公开摘要和新摘要，既有安全校验仍要求主应用与工具同签名。

## 发布步骤

先按 [MACOS_RELEASE.md](MACOS_RELEASE.md) 获得新版本发布授权并完成源码检查、递增 build、Developer ID 签名、公证、贴票据、Draft/公开下载验证，再准备 feed：

```sh
python3 scripts/prepare-github-update.py \
  --dmg .build/distribution/we-sync-版本-macos-arm64.dmg \
  --out .local-install/新的更新源输出目录 --published
```

该脚本验证 DMG/App 的固定团队、Gatekeeper、票据、版本和架构，核对已有公开 stable 资产的 SHA-256，使用既有 key 签署 archive 与 appcast，并用 Sparkle 工具复验。无 `--published` 时只能准备候选，不能把它当作公开资产已验证。脚本不上传、不重新公证已有包、不安装。把核对后的 appcast 原样复制到 `updates/appcast.xml`，提交推送后回读准确 URL 并核对摘要及签名。

初始 feed 指向已有 `v0.10.1` 公证 DMG；没有修改该 Release 或资产。**旧版 0.10.1 未包含 updater，需要先手动安装首次带更新机制的公开版本，此后才能应用内升级。** 当前本机 build 74 仍为 Apple Development，不自动迁移到公开团队。新公开二进制尚未发布。

## 旧版基础机制 E2E（build 74 历史记录）

使用已安装的 Apple Development 身份运行：

```sh
python3 scripts/update-e2e/prepare.py --identity 现有证书SHA1 \
  --out .local-install/新的更新验收目录
```

该进程构建仅含生产 `HistoryUpdater` 与原生合成 Host 的独立应用，生成一次性合成密钥并写入私有测试目录，启动随机五位 loopback 端口。只在 DEBUG 且 `me.greenbubbles.UpdaterPreview` + `GBUpdatePreview` 时使用合成通道；release 中没有该分支。不启动业务 model、不访问真实连接钥匙串、不操作微信。所有测试标记均在独立目录。

1. 原生打开输出的应用，`current.xml` 复制为 server/appcast.xml，点击检查，确认最新版提示。
2. 替换为 `invalid.xml`，确认签名失败；替换为 `bad-archive.xml`，确认损坏 archive 被拒绝、旧 build 保留。
3. 替换为 `available.xml`，检查并关闭提示，确认暂缓不更改 build；再次检查、安装、确认重启，观察 build 1 → 2 和 `events.jsonl` 的新启动记录，再检查同版不重复提示。
4. `slow-download.py --root <同一目录> --identity <原证书>` 准备下一 build 的慢速包。原生进入下载后立即点击取消，观察 cancelled 事件、build 与合成用户数据不变。该进程另开随机五位 loopback 端口，测试结束只停止自己创建的 server。
5. 核对签名、合成数据 sentinel、安装前后 build 与窗口截图，输出脱敏 JSON。密钥材料、原始目录和安装包不提交。

本轮实际完成 build 1 → 2、再次检查同版、build 2 → 3，以及下载 build 4 时取消。首次取消尝试包过快已到就绪阶段，不计作取消通过；随后加慢并重新验证。未模拟磁盘满、进程崩溃或重启失败的全部回滚；不能把签名失败保留旧包等同所有失败模式均验证。

## 基础机制验收（build 74 历史记录）

当时本机安装 **0.10.0（74）**，两次原生冷启动自动连接，无凭据输入或权限变更；应用/菜单栏的检查更新、设置、关于与刷新通过。主程序在两次启动后与候选摘要相同，既有 CLI/输入 helper 字节保留。独立原生升级 E2E **13/13**，真实已公证包与临时篡改副本的预检通过，完整本机 CI **23/23**。未新增单元测试。截图、计时/失败边界与可审计报告见 [验收记录](acceptance/github-updates-20261111/README.md)。

## 当前交互与钥匙串边界（build 75）

`HistoryUpdater` 使用 `SPUUpdater` + `SPUUserDriver`，`HistoryUpdateNotice` 为独立 SwiftUI 子视图，叠加在生产主窗口右下角，右/下各 24 pt、宽 320 pt。发现普通新版后直接下载和验签，后台不弹窗、不抢焦点，就绪后显示“更新已就绪 / 重启更新”。菜单可查看进行中的下载并取消；关闭卡片保留已准备更新，再次检查可恢复。无新版只在主动检查时短暂提示，错误仅在主动可见状态显示并可原地重试。

进程退出仍等候缓存末次写入。用户正常退出时 Sparkle 可以完成已准备更新；卡片不主动中断会话。安装路径与上级目录不可写、所有者不为当前用户或无法保持现有组时，不启动需要提权的安装流程，转为手动查看版本。此限制不代替系统安全检查，也不改变现有 ACL、TCC 或钥匙串规则。

用户确认原提示属于钥匙串/签名工具一类，但未留具体弹窗标题或进程，不能归因到某一个签名工具。更新客户端使用固定公钥和系统代码签名验证，不运行 `generate_keys`、`sign_update` 或 `codesign --sign`，不读取更新签名私钥。签名私钥访问属于开发端制包；原连接仍由应用原有钥匙串条目恢复。完整合成聊天应用实测自动下载、验证、点击重启及新版自动启动，Agent 未输入任何密码。没有用放宽钥匙串访问控制来消除提示。

本机同证书打包复用 framework 时，复用键绑定原始 artifact 全部字节（含架构和原始 entitlements）、权限、精确证书 SHA-1 和签名策略版本，回执再绑定整个已签名 framework 的字节和权限。复用前深度验证签名及同证书要求；匹配回执却出现内容变化直接报错。新版本/证书/策略为缓存 miss。只对本机同证书封装启用；公开 Developer ID 分发仍走原签名、公证门槛。旧包副本只验证，新主包签一次；缓存命中不重复签 5 个未变化 framework 组件。新主包签名仍遵守 macOS 正常钥匙串授权。

## 当前原生复验步骤

1. 用原 Apple Development 身份运行 `python3 scripts/update-e2e/prepare.py --identity <现有证书SHA1> --out <新的私有目录> --automatic`。默认使用生产主程序和三条合成消息，完整聊天界面；仅 DEBUG、独立 Preview Bundle ID 与专用标记允许 loopback 更新源。合成连接的 vault 读写均被隔离，fixture 不依赖已有安装或真实聊天。
2. 原生打开输出应用，不点检查或下载，观察自动到达就绪卡片；滚动聊天、关闭卡片、从菜单恢复。点击重启，核对 Info.plist build 1 → 2、events 中新进程的 started、聊天恢复及 sentinel 文件保留。截图使用实际窗口，不以静态图代替升级。
3. 签名失败场景使用独立新目录、默认非 automatic 模式，把 server/invalid.xml 或 bad-archive.xml 复制为 appcast.xml 后主动检查，确认角落错误、无安装按钮、原版本不变。恢复有效 feed 后重试。
4. 慢速取消场景在启动应用前运行 `slow-download.py --root <新目录> --identity <原证书>`，先完成测试制包签名，再进入客户端过程；后台下载时从菜单查看进度并取消，确认原版本保留。切回有效完整 archive 后重试、重启并恢复聊天。
5. 默认 fixture 显式使用浅色外观，限于 DEBUG 合成进程，不改变真实应用或系统明暗偏好。较早暗色截图保留为当时实际结果。`--minimal-host` 仅供传输隔离调试，不能作为产品 UI 验收。结束原生退出所有测试应用、停止自己创建的五位 loopback server、恢复用户真实聊天窗口。
6. 真实安装采用同身份 staging，既有查询/输入 helper 字节保持不变；两次原生退出冷启动、自动连接、更新入口、刷新、设置及关于须通过。framework 缓存另用签名候选执行命中/字节一致与临时篡改副本拒绝，不能静默重新签署坏缓存。

本轮完整产品 UI 原生断言 **18/18**、签名复用/损坏拒绝通过、最终本机 CI **23/23**。本机 **0.10.0（75）** 两次冷启动自动连接，无密码输入，原身份和既有 helper 字节保留。验收初期曾把最小测试壳留在前台，用户看到黑色空窗口；已关闭并恢复真实聊天，此后改用完整聊天作为默认验收。一次自动化焦点变化和一次超时经重新读取 UI 状态后恢复，没有跳过安装验收。[记录与截图](acceptance/update-corner-20261111/README.md)。本轮未发布新 DMG，开发/公开签名通道边界保持。
