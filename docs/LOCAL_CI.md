# 本机检查

2026-10-17 起，私有仓库 `wherexml/wesync` 停用 GitHub Actions，推送和 PR 不再启动云端 CI。Swift、Rust、macOS 构建及合成 E2E 在本机运行。发布和 Homebrew 工作流保留，仓库级 Actions 关闭期间也暂停；重新启用须经用户要求。

## 实施前失败场景

- 缺少 Swift、Rust、审计工具或版本不符时，应报告失败，不跳过检查或静默安装。
- 任一步失败、进程中断或未执行完整检查时，不得给出全部通过结论；保留逐步日志和结果。
- 个人 CLI 的默认输出配置不能影响合成验收；进程级测试使用临时配置路径，不改写用户配置，AI 黑名单仍使用原有受保护路径。
- 检查须包含旧 CI 的构建、格式、既有测试、依赖审计、许可证复现、打包与安全检查、合成 E2E；不读取真实聊天数据或输出凭据。
- 黑名单 E2E 临时追加合成条目并恢复原策略，执行期间不得编辑高级设置中的黑名单；其既有 finally 恢复行为保持不变。
- 禁用后推送不得产生新 Actions run；保留的手动/可复用 CI 工作流不应恢复 push/PR 自动触发。

## 使用

要求 macOS 14+、Swift 6、Rust/Cargo、Python 3.11+、Ruby，以及已运行的本机 Docker（例如 OrbStack）。入口会从本机已安装版本选择受支持的 Python，并让全部子检查使用同一解释器；不会使用系统默认 Python 3.9 运行既有日期解析测试，也不会自动安装 Python。审计工具一次安装：

```sh
cargo install cargo-audit --locked --version 0.22.2
cargo install cargo-about --locked --features cli --version 0.9.2
```

在仓库执行：

```sh
python3 scripts/local-ci.py
```

`--list` 只列检查，不执行。检查失败会停止，返回非零状态；报告将后续检查标记为 `NOT_RUN`。日志与 `summary.json` 位于忽略目录 `.build/local-ci/<运行编号>/`，内含执行命令、代码状态和退出码，可重复运行复核。日志只留本机，提交验收时仅提取脱敏状态。

`local-ci.py` 是检查清单的唯一维护入口。保留的手动 CI 也调用它；不要再另维护一套命令。脚本运行已有测试，不在实现后新增单元测试。三项合成验收产物仍写入原文档目录，核对差异后再提交。

先本机全部通过，再提交、推送。应用代码变更和安装仍须按 `AGENTS.md` 进行稳定签名与原生冷启动验收；本机合成检查不代替实机验收。本脚本不安装应用，也不修改已记住连接。

## 仓库状态复核

```sh
gh api repos/wherexml/wesync/actions/permissions
gh run list --repo wherexml/wesync --limit 5
```

权限返回 `enabled: false`。关闭范围仅为此私有仓库，不修改账户套餐、预算或其他仓库。远端旧失败记录保留为历史，不再要求 GitHub `test` 状态作为日常交付门槛。

2026-10-17 合并依赖 PR 时，GitHub 仍记录 `workflowName: Dependabot Updates`、`event: dynamic` 的机器人分支更新。这不表示仓库 CI 被重新开启，也不能替代本机检查；检查新记录时同时核对工作流名称和事件，而非仅判断 run 列表是否变化。仓库权限仍须为 `enabled: false`，不得恢复 push/PR CI。

## 2026-10-17 验收

本机完整 23 项检查通过，三项合成 E2E 成功，黑名单策略恢复。依赖审计保留原有三条允许警告，未新增忽略项；原有手动性能用例继续标记 ignored。既有 CLI 进程测试改用临时配置，避免个人默认 JSON 输出影响默认简洁格式断言，全部原断言保留。未修改应用功能或安装应用。脱敏结果见 [本机检查验收](acceptance/local-ci-20261017.json)。

## 独立账户端到端检查的失败契约

真实用户黑名单非空时，合成 Connector 测试也被拒绝，不能通过清空用户策略或修改生产拒绝逻辑解决。Rust 原生库/二进制检查继续在 macOS 执行；完整 Rust E2E 使用本机 Docker 独立账户，复制白名单源码与合成夹具，不挂载用户 home、钥匙串、聊天目录、真实策略或 Docker socket。测试阶段禁网，策略正反例在容器账户内执行。容器不可用、依赖准备失败、任一测试失败都返回失败，不静默跳过。测试前后核对真实策略摘要和权限未改变。容器测试不替代 macOS 构建与原生安装验收。

2026-11-06：zstd/Tokio 安全修复后完整 23 项本机检查通过；既有 3 条维护状态警告保留，无新增审计豁免。额外 14 项双向依赖兼容 E2E 在独立容器断网执行并验证主机策略未变。build 58 的同身份工具迁移与两次原生冷启动通过，见 [安全升级验收](acceptance/security-upgrade-20261106/summary.json)。GitHub Actions 继续关闭。
