# 2026-11-11 菜单与交互验收

安装版：we-sync 0.10.0（65）。[脱敏总记录](summary.json)。

| 范围 | 结果 |
| --- | --- |
| 完整本机 CI | 23/23 PASS |
| 150 个会话预热及缓存 E2E | 316/316 PASS |
| 缓存恢复、分页、失败保留 E2E | 17/17 PASS |
| 最终安装包两次原生冷启动 | 自动连接、正文、刷新、设置、折叠偏好 PASS |
| 签名与 helper | 原证书、DR、所有 helper 字节保留 |

- [最终合成折叠栏截图](sidebar.png)
- [合成设置截图](settings.png)
- [安装版关于窗口](about.png)
- [完整本机检查结论](local-ci.json)、[预热结果](preload.json)、[缓存结果](message-cache.json)

重复命令、失败场景和指标边界见 [交互规范](../../INTERACTION_RESPONSIVENESS.md)。聊天截图只使用合成数据；关于截图仅含公开版本信息。心跳最大间隔不是每次点击延迟或帧率，未进行同硬件前后基准对照。
