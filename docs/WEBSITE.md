# we-sync 产品首页

首页是独立的静态网页，参考 VoiceMore 官网的深色底、居中标题和产品预览。只发布 `website/`，页面、样式、交互脚本和现有品牌图标随仓库维护。线上地址为 [wesync-mac.pages.dev](https://wesync-mac.pages.dev/)。

## 内容与验收

- 手机和桌面均能看到产品标题、源码入口和完整预览，无横向溢出。
- 合成预览可切换会话、搜索会话和正文。搜索无结果时清除旧正文，清空搜索后可继续浏览。键盘可操作。
- 无 JavaScript 时保留产品信息、源码入口和默认合成会话。
- 页面只使用合成会话，使用浏览器开发工具核对网络请求仅加载站点自身资源。
- 从源码构建和首次设置链接指向相应文档。应用安装包的发布与首页分开管理。

本机预览：

```sh
python3 -m http.server 38132 --bind 127.0.0.1 --directory website
```

在 `http://127.0.0.1:38132/` 验证以上场景。

## 部署

Cloudflare Pages 项目为 `wesync-mac`，通过控制台直接上传。部署前检查静态站点目录，按明确清单压缩产物：

```sh
mkdir -p .build/site
cd website
zip -X -FS ../.build/site/wesync-pages.zip index.html _headers assets/icon.svg assets/site.css assets/demo.js
```

在该项目中创建生产部署并上传 ZIP。部署后使用生产域名重复检查，验证 `_headers` 定义的内容安全策略，保存桌面和手机截图以及验收结果。
