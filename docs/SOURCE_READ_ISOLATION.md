# 数据库读取隔离

SQLite 的 `SQLITE_OPEN_READ_ONLY` 和 `PRAGMA query_only` 不禁止底层驱动创建 WAL 或重建 SHM。原版本在合成的加密会话库中能读到尚未 checkpoint 的已提交会话，但会在源目录新建 `session.db-shm`。两版 SQLCipher 都包含这个默认行为；此证据无法确定真实微信数据库损坏提示的成因。

会话、正文、搜索、数据库内附件和备份转换都通过私有临时副本打开 SQLite。源 DB、WAL 和可选回滚日志只以只读描述符打开，必须是当前用户拥有的常规文件；源 SHM 不参与复制。每次检查整个文件组的设备、inode、大小和时间戳，也检查不存在的 sidecar 未突然出现。检测到变化重试一次，再失败就返回错误，不回退到原地打开。跨库读仍不保证同一时刻。

macOS 优先用 APFS 写时复制；不支持时，每次捕获的字节拷贝合计不超过 1 GiB，拷贝循环使用 10 秒期限。副本目录位于本机临时目录，权限为 `0700`，数据库与复制的 sidecar 为 `0600`，保留原加密状态。SQLite 连接关闭后清理；进程被强制终止时，系统临时目录可能留下受权限保护的副本。

用合成库复验，不在真实微信库上重现：

```sh
cargo test --locked --manifest-path Native/GreenBubbles/Cargo.toml \
  --test live_query_cli cli_reads_wal_commits_without_changing_source_files -- --exact
```

该命令通过真实 CLI 分别查询加密、明文会话库。唯一最新会话位于已提交、尚未 checkpoint 的 WAL 中，源没有 SHM。断言读到该会话、原库和 WAL 字节不变、没有新建 SHM。若真实 AI 黑名单拦截独立测试，按 [本机 CI](LOCAL_CI.md) 走隔离账户。安装验证沿用[同证书工具摘要迁移](LOCAL_SIGNING.md)，原生冷启动确认自动重连、打开会话和主动刷新。对照及脱敏安装结果见[验收记录](acceptance/source-read-isolation-20261109.json)。
