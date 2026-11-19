# 普通查询静默启动验收

本机安装 build 82，使用既有 Apple Development 身份、Bundle ID 和已记住连接；未输入密钥、未修改 TCC 或黑名单。

| 场景 | 结果 |
| --- | --- |
| [单次冷启动](cold.json) | 查询自动启动应用并恢复连接，窗口不可见、前台不变 |
| [4 路并发冷启动](concurrent.json) | 查询均成功，仅一个应用进程，窗口不可见、前台不变 |
| [已运行重复查询](running.json) | 查询成功，不显示或激活窗口 |
| [主窗口关闭后查询](closed-window.json) | 查询成功，窗口保持关闭，前台不变 |
| [手动打开与刷新](interactive.json) | 用户式 Finder 打开可恢复唯一主窗口，聊天和刷新正常 |
| [完整本机检查](local-ci.json) | 构建、既有测试、安全和隔离 E2E |

上述查询客户端通过 sandbox-exec 拒绝微信容器、旧凭据目录和 CLI 配置目录的直接读取；查询仍经应用代理成功。窗口观察器使用 NSWorkspace/CoreGraphics 连续采样，只记录计数、布尔值和耗时，不记录窗口标题或聊天内容。先等候 NSWorkspace 初始化及退出动画，再建立前台基线；不把原本已在前台的应用误计为被查询激活。

## 复验

原生退出 we-sync，保持其他应用前台，然后运行：

```sh
python3 scripts/verify-background-query.py --case cold --out /tmp/wesync-cold.json
python3 scripts/verify-background-query.py --case running --out /tmp/wesync-running.json
```

再次原生退出后运行 `--case concurrent`。测试工具只调用普通查询，不自行打开、隐藏或激活任何窗口。完整检查入口为 `python3 scripts/local-ci.py`。

[产品版本截图](installed-about.png) 仅包含关于窗口，不包含个人会话。此前打包发现已安装 Sparkle 语言资源有删减导致缓存回执不匹配，经过检查后使用保留的同版本、同证书完整包作为基线，未静默重签 Sparkle 或改变系统授权。

最终完整本机检查 23/23、代理合成 E2E 24/24 通过。当前安装仍为 build 82，应用保持后台运行；[汇总](summary.json)。
