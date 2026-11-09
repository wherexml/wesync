# Rust 依赖升级审查

依赖 PR 先同步当前 main，再运行 `python3 scripts/local-ci.py`；GitHub Actions 保持关闭。原 Dependabot 提交仅改 Cargo 清单/锁文件时，仍需核对 `docs/distribution-dependencies.json` 和 `THIRD_PARTY_NOTICES.md`，不得跳过基线或许可证检查。

## 实施前失败场景

- TOML 升级可能改变配置解析；合法配置、非法输入与未知字段仍须遵守现有限制。
- Argon2/BIP39 升级可能导致旧快照无法解密；保持现有参数、恢复词格式、zeroize 功能，验证旧版生成与新版读取，以及反向读取。错误口令必须拒绝。
- zstd 升级可能破坏旧压缩内容读取或引入原生库链接冲突；验证历史恢复、压缩消息及审计流程，不为去重升级固定的上游 wx-cli。
- thiserror 升级须保持错误处理与完整构建，不改变用户数据格式。
- 依赖许可、来源、最低编译器或安全审计发生变化时，先核实再更新基线；不得新增审计豁免使检查变绿。
- 本机检查不替代安装验收。最终 CLI 使用原 Apple Development 身份、精确工具摘要迁移，原生退出重开并检查自动连接、消息加载、刷新及再次冷启动。

## 2026-10-17：PR #1–#5

原始 PR 均各含一个 Dependabot 提交。#1 toml 为 6 增/36 删，#2 argon2 为 22 增/12 删，#3 bip39 为 3 增/3 删，#4 zstd 为 24 增/6 删，#5 thiserror 为 14 增/14 删；全部是 Cargo 清单或锁文件变更，非新增业务功能。

逐 PR 完整本机报告保存在 `.build/local-ci/`；脱敏汇总保存在 `docs/acceptance/dependency-upgrades-20261017.json`。安装签名及原生重启结果单独记录，不将合成测试表述为原生验收。

### #1 toml 0.9 → 1.1

`query_profile.rs` 通过 `toml::from_slice` 读取受限配置，现有 API 可编译，无需改动业务逻辑。原 PR 未同步分发基线和许可证清单，已按锁定依赖重新生成并审查；上游 Git 固定版本及未知许可证清单保持不变。锁文件继续保留 main 已修复的 rustls 版本。

跨版本命令（先保存升级前 CLI）：

```sh
cargo build --locked --manifest-path Native/GreenBubbles/Cargo.toml --example dependency_upgrade_fixture
python3 scripts/dependency-upgrade-e2e.py OLD_CLI NEW_CLI REPORT.json --fixture-generator Native/GreenBubbles/target/debug/examples/dependency_upgrade_fixture
```

脚本生成临时 SQLCipher 数据库，随机凭据仅经 stdin 传递，保护文件在临时目录中随测试销毁；产物只保留二进制 SHA-256 和各项结果。覆盖 TOML 输出设置与无效输入，以及恢复词/Argon2 口令保护快照的双向验证、消息读取、错误口令/恢复词拒绝。初版夹具使用 Python 明文 SQLite 时，升级前后均在逻辑备份处拒绝；此记录不声称明文来源转换已通过，本次兼容性范围为实际加密来源。

### #2 argon2 0.5 → 0.6

现有 `Argon2::new`、`Params::new` 和 `hash_password_into` 可编译；固定 Argon2id v19、64 MiB、3 次、并行度 1、32 字节输出，未改格式标识与口令边界。更新 blake2/password-hash 和新增 phc 的许可证条目，同步分发基线；需通过跨版本快照互读后才合并。

### #3 bip39 2.2 → 3.0

应用使用系统随机熵、`from_entropy_in` 和 `parse_in_normalized`，不调用新版改变的助记词生成接口；继续固定英语 24 词与 zeroize。分发基线和 CC0 许可条目随版本更新，快照格式及恢复保护器标识不变。跨版本验收覆盖旧新恢复词双向解锁与错误恢复词拒绝。

### #4 zstd 0.13 → 0.14

主 CLI 使用 0.14，上游固定 wx-db 仍使用 0.13，保留两个 Rust 封装且共用 zstd-sys 2.1.0；底层 zstd 仍为 1.5.7。不修改 wx-cli 固定来源。新版 zstd/zstd-safe/zstd-sys 的许可声明变为 BSD-3-Clause，已核对包内 LICENSE 并重新生成许可证清单与原生依赖基线。现有压缩暂存往返、加密 WAL 恢复及 CLI 快照验收覆盖构建与运行兼容性。

### #5 thiserror 2.0.20 → 2.0.21 与集成安装

补丁升级仅改变错误派生宏及对应锁定包，保持原错误枚举和错误码；同步分发基线与许可证清单。

安装脚本修复前的失败场景：更新 CLI 后仍携带旧许可证/SBOM；本机 Apple Development 包继续显示旧 Developer ID 构建来源；记录本次源码时误将保留的发送工具称为重新构建。处理方式是在最终签名前同步仓库许可证和已审查 SBOM，记录本机更新来源、构建输入摘要、签名团队与保留工具摘要，并明确本机证书更新不代表 Developer ID 分发。验收使用真实 staging、严格签名校验、资源比对及安装冷启动，不新增单元测试。

## 集成验收结果

五个升级候选逐一通过完整 23 项本机检查，每个候选的 14 项跨版本 CLI 检查均通过。原有 3 条允许审计警告和 1 项手动性能 ignored 保持原状，没有增加豁免。

最终 build 43 → 44 沿用同一 Apple Development 身份，严格签名、DR 稳定、精确工具摘要迁移、11 项 staging 检查及安装包与候选资源比对通过。原生两次完整退出并确认进程消失后重开，自动连接、消息加载和主动刷新均通过，未输入密钥/密码，未观察到权限弹窗，黑名单数量保持。已安装 release CLI 的额外 14 项跨版本检查通过。旧包在忽略目录 `.build/dependency-review-20261017/installed-build43-backup.app`，未提交本机包或私人界面内容。

新旧 CLI 的加密来源快照兼容已验证；初版明文 SQLite 夹具在升级前后均无法创建快照，属于已有行为，本次未声称修复。安装为本机开发证书更新，不是公证公开发行。完整状态和复验步骤见 [脱敏验收记录](acceptance/dependency-upgrades-20261017.json)。

## 2026-10-24：本机检查发现的传递依赖补丁

转发文件修复的全量检查命中 RUSTSEC-2026-0385、0382、0381。仅将 ctutils 升至 0.4.4、rustls-webpki 升至 0.103.16、webpki-roots 升至 1.0.10，保持直接依赖和 wx-cli 固定版本不变。分发基线重新生成比对无差异（记录直接/原生依赖）；许可证清单更新三项版本，许可文本不变。没有新增审计豁免。

## 2026-11-06：压缩依赖和 Tokio 安全修复

实现前沿用上述失败契约：不得新增审计豁免；旧新快照双向互读、错误保护器拒绝、黑名单隔离与同身份工具摘要迁移均须验证。

锁定 zstd 0.13.4 / 0.14.3、zstd-safe 7.4.0 / 8.2.0、zstd-sys 2.1.2+zstd.1.5.7，并将 Tokio 1.53.1 升至 1.53.3。修复审计报告的 7 个漏洞命中及新增 unsound 警告；剩余 ansi_term/atty 的 3 条既有警告，不新增忽略规则。wx-cli Git revision、直接依赖约束和底层 zstd 1.5.7 不变。Cargo 同时重新解析已有 Windows 专属依赖边，不增加包版本。

zstd 0.13.4 与 zstd-safe 7.4.0 的包内 LICENSE 已核对为 BSD-3-Clause；重新生成并审查 `THIRD_PARTY_NOTICES.md` 和 `docs/distribution-dependencies.json`。

真实黑名单非空时，跨版本验收使用 `scripts/dependency-upgrade-isolated.py OLD_CARGO_LOCK REPORT.json`：仅复制当前 Rust 源码、两份锁文件及合成脚本，在 Docker 独立账户构建新旧二进制，测试阶段断网，不挂载 home、真实聊天或策略。适用于仅依赖变化；不把当前源码配旧锁文件称为旧应用完整源码重建。既有 14 项跨版本 CLI 检查覆盖加密快照、压缩内容、恢复词和口令双向读取。运行前后比较主机策略摘要及权限；不清空用户黑名单、不加生产豁免。

本轮完整本机 CI 23 项及跨版本 14 项全部通过。build 57 → 58 保持原 Apple Development 身份，精确 CLI/helper 摘要迁移、许可证/SBOM 同步和严格验签通过；两次原生完整退出重开自动连接，消息读取和主动刷新均通过，未输入凭据或触发权限变更。证据见 [security-upgrade-20261106/summary.json](acceptance/security-upgrade-20261106/summary.json) 和 [compatibility.json](acceptance/security-upgrade-20261106/compatibility.json)。

复现本轮旧依赖基线：`git show 33bede0:Native/GreenBubbles/Cargo.lock > /tmp/wesync-before-20261106.lock`，再运行 `python3 scripts/dependency-upgrade-isolated.py /tmp/wesync-before-20261106.lock .build/dependency-compatibility-repeat.json`。先通过 `python3 scripts/rust-e2e-isolated.py` 准备固定 Docker 镜像；全量本机 CI 也会准备该镜像。

## RUSTSEC-2026-0459

实施前核对以下失败情况：依赖审计变绿但实际仍编入旧 SQLCipher，wx-cli 与主程序链接不同版本，升级后读不到旧版生成的加密库或快照，以及同签名重装后丢失工具绑定。跨版本用旧版生成加密库，新旧 CLI 双向读快照和拒绝错误凭据，同时核对候选程序实际报告的 SQLite 和 SQLCipher 版本。仅重置 we-sync 的系统隐私授权，保留其钥匙串连接。重新授予所需文件访问后，验证连续两次原生冷启动免输密钥。

`rusqlite` 升级至 0.41.1，`libsqlite3-sys` 升级至 0.39.1，实际链接
SQLCipher 4.20.0 / SQLite 3.54.1。两个本地兼容包仅转发 API，分别让仍要求
0.40 的 wx-cli 与主程序共享一个 Rust 类型和链接目标，以及将绑定库要求的
旧源码定位器转发到新的 `sqlcipher-src`。移除转接层前先核对上游依赖约束。
许可证和分发清单根据实际源码包更新。

复验使用原修订的源码与锁文件，在独立账户生成旧加密库并测试双向快照。

```sh
git show 485c6d6:Native/GreenBubbles/Cargo.lock > .build/sqlcipher-baseline.lock
python3 scripts/dependency-upgrade-isolated.py .build/sqlcipher-baseline.lock \
  .build/sqlcipher-compatibility.json --baseline-revision 485c6d6 \
  --expect-engine 3.54.1 4.20.0
```

2026-11-09，完整本机 CI 23 项通过。隔离账户 15 项兼容检查通过，旧数据
由 SQLCipher 4.14.0 / SQLite 3.51.3 生成。新旧程序双向验证并读取加密快照，
拒绝错误口令与恢复词。候选 macOS release 的实际版本也为 SQLCipher 4.20.0 /
SQLite 3.54.1。见 [跨版本验收](acceptance/sqlcipher-20261109/compatibility.json)。
