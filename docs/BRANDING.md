# we-sync 品牌与图标

2026-10-02：采用用户提供的 `01-twin-bots.svg`。原稿原样保存在
`assets/greenbubbles-twin-bots.svg`，两个机器人的路径和绿色不变。

- 产品图标：`assets/greenbubbles-icon.svg`，白色圆角底，底外透明；原稿居中缩放，保留留白。README 和正式发布包使用同一 SVG。
- 菜单栏：`assets/greenbubbles-menubar.svg`，透明背景、透明眼睛、黑色剪影。应用以 22pt、`isTemplate = true` 显示，由 macOS 处理深浅模式。不要给菜单栏加白底。
- `Resources/Brand/GreenBubbles-black.png` 保持现有运行时资源名，44px 用于 Retina 显示；正式打包脚本也必须包含它。

运行 `python3 scripts/generate-brand-assets.py` 生成 ICNS、全部 iconset 尺寸和菜单栏 PNG。脚本仅栅格化 SVG，不重新绘制原稿。来源摘要保存在 `Resources/Brand/generation.json`。预览打包脚本使用这些生成物；正式打包脚本直接从 SVG 生成。

## 验收与安装边界

检查产品图标的白底、透明外角和绿色原稿；在亮色、暗色背景检查 22pt 菜单栏轮廓及眼睛。ICNS 必须能用 `iconutil -c iconset` 解包。运行生成脚本、`bash -n scripts/package-send-helper.sh` 和 `git diff --check` 可重复验证资源流程。

初次资源交付时因缺少稳定签名而阻塞。用户随后授权解决签名并安装：通过系统证书助手创建固定本机代码签名身份，完成首次权限迁移，先安装图标 build 7，再安装此前已准备好的菜单栏与中文界面 build 8。两次构建的签名身份一致，查询与发送工具保持原样。详见 [LOCAL_SIGNING.md](LOCAL_SIGNING.md)。

当前安装验收见 `docs/acceptance/brand-20261002/installed-acceptance.json`。Finder 产品图标、原生菜单开关窗口和退出、首次更新后自动连接已通过。最后一次冷启动等待用户在系统钥匙串提示中为应用自己的连接选择“始终允许”；完成前仍不声明最终验收通过。菜单栏图形未能由自动化工具单独截图，不能将合成亮暗预览描述为真实系统外观验收。

获得稳定合法签名并验证权限迁移后，打包安装，再通过原生 UI 退出和重开应用，确认无需密钥自动连接，检查 Dock/Finder 产品图标、菜单栏亮暗外观与菜单打开行为。所有步骤通过后才可记录交付完成。

## we-sync 展示名称

应用及发行 App/DMG 名为 `we-sync`，内置工具在只读连接设置中同样显示该名称。菜单栏、侧栏及欢迎页无障碍标签沿用统一名称。签名、旧路径兼容及重启验收见 [改名规范](WESYNC_RENAME.md) 和 [本机签名](LOCAL_SIGNING.md)。
