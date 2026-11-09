# we-sync 产品首页

[线上首页](https://wesync-mac.pages.dev/) 复刻 VoiceMore V3 的深色、青紫波形和页面节奏。顺序为全屏首屏、演示播放器、逐字点亮、四屏横移、六张能力卡、隐私、FAQ 和底部源码入口。简中、繁中、英文从一份模板生成。

## 验收

- 首屏波形随时间和指针变化，演示滚动进入后播放，可暂停、重播。合成会话可用键盘切换，搜索无结果时隐藏正文，清空后可继续浏览。
- 桌面功能区固定在视口内，随纵向滚动横移四屏并更新进度。手机和减少动态效果模式按顺序堆叠。
- 检查手机菜单、语言切换保留锚点、FAQ 展开和收起、源码与首次设置链接。
- 无 JavaScript 时保留文本、默认会话、FAQ 和各语言链接。预览只加载同源的静态资源，使用合成会话。

## 构建和部署

```sh
python3 scripts/build-website.py
python3 -m http.server 38133 --bind 127.0.0.1 --directory .build/website
```

在 `http://127.0.0.1:38133/` 复验。构建同时输出 `.build/website.zip`，只包含三个语言页面、静态资源和 `_headers`。在 Cloudflare Pages 项目 `wesync-mac` 中创建生产部署并上传 ZIP。线上复验时保存桌面、手机和滚动场景截图，核对内容安全策略。
