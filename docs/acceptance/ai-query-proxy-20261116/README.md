# AI 查询代理验收

本机 build 79，沿用原 Apple Development 证书、Bundle ID 和 ToolUpdate 精确摘要迁移。
没有输入连接密钥，没有修改 TCC，没有更改用户黑名单。共享 Agent skill 同步到现有目标。

- [完整本机检查](local-ci.json)：23/23，GitHub Actions 保持关闭。
- [真实安装验收](installed.json)：客户端明确禁止读取微信数据库、旧凭据目录，仍能通过应用代理完成状态、会话查找、消息列表、精确消息和搜索。
- [合成产品截图](synthetic-chat.png)：独立原生预览，只有合成数据；不作为代理权限验证的替代。
- [合成代理结果](synthetic.json)：`python3 scripts/rust-e2e-isolated.py --proxy-only`；完整检查：`python3 scripts/local-ci.py`。
- 复验：原生退出应用，`greenbubbles source status` 返回 `proxyUnavailable`；原生重开，不输入密钥，再运行同命令应 `ok: true`。
- 安装包位于 `/Applications/we-sync.app`；正常运行需要保持 we-sync 已打开并连接。代理失败不回退直读，不要求给 AI 宿主授予磁盘权限。

原生产品没有浏览器 URL；[验收目录](https://github.com/wherexml/wesync/tree/main/docs/acceptance/ai-query-proxy-20261116) 提供报告及截图。

实际受限查询在 macOS `sandbox-exec` 下额外拒绝客户端读取微信容器、旧凭据和 CLI 配置目录；只汇报布尔结果，不保存会话名、ID 或正文。原生合成预览保留现有表情/附件失败夹具，不代表真实连接失败。

最终复检 23/23，通过当前源码全套检查；代理专项 24/24（包含空请求拒绝）。此前发现的简写路由、错误分类和测试脚本问题均修复后重跑通过。
