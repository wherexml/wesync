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
