# we-sync Agent Skills

| Skill | 用途 |
| --- | --- |
| [we-sync-setup](../skills/we-sync-setup/SKILL.md) | 安装、重装和验证本机连接 |
| [we-search](../skills/we-search/SKILL.md) | 按会话、发言人和时间范围读取或搜索消息 |

两项 skill 都使用本机 `greenbubbles` CLI。直接让 Agent 读取对应的
`SKILL.md` 即可使用，也可以安装到 Agent 的发现目录。

## 安装或重装

在仓库或解压后的 CLI 包根目录执行：

```sh
python3 scripts/install-skills.py --agent codex --update
```

重开 Agent 会话后使用 `$we-sync-setup` 或 `$we-search`。
安装程序支持 `codex`、`claude`、`opencode`、`kimi`、`gemini` 和
`grok`。用 `--project PATH` 限定到项目，用 `--dest PATH` 选择其他
发现目录。用 `--bundle PATH` 生成只含两项 skill 的可移植包。

`--update` 只覆盖安装器管理且未修改的同名文件。如果已有本机定制版本，
先将其移到发现目录外备份，再安装或合并。旧的 `wechatsync-setup`、
`wechatsync-context`、`wechatsync-personal-memory` 也可移出发现目录，
避免出现重复入口。已有笔记和批处理继续使用
[个人记忆工作流](PERSONAL_MEMORY.md)。

## 复用连接

```sh
python3 skills/we-sync-setup/scripts/doctor.py
```

doctor 先检查 CLI 的消息查询能力，再调用 `source status`，不读聊天正文。
可以用 `--greenbubbles PATH` 选择现有二进制，用 `--profile NAME` 验证
已配置的其他来源。如果 PATH 里没有 CLI，它会查找已安装应用的内置工具。
验证通过即可继续搜索，无需重复输入密钥或建立 profile。

桌面应用通过 macOS 钥匙串恢复已记住的连接，CLI 通过已有私有凭据文件恢复。
重装 skill 不改动两者。重装应用时按 [本机签名](LOCAL_SIGNING.md) 保持原签名
身份、应用 ID 和工具摘要迁移，安装后退出再原生启动并验证自动连接。

首次没有桌面连接时，只在原生连接表单输入一次已验证的数据库密钥。
CLI 可直接使用已有私有密钥文件。初次没有可用凭据时，由账号所有者按
[采集说明](PASSPHRASE_ACQUISITION.md) 完成授权。连接失败先按
[setup 指引](../skills/we-sync-setup/references/setup.md) 判断是二进制、
来源选择、凭据还是 macOS 权限问题。

## 验收与隐私

运行现有安装验收：

```sh
python3 -m unittest discover -s scripts -p 'test_skill_package.py' -v
```

验收会将可移植包移到带空格的路径，再在六种 Agent 的独立项目目录中安装两遍。
本机 doctor 只输出连接状态。实际搜索受 [AI 读取黑名单](AI_READ_BLACKLIST.md)
约束；使用云端模型时，提供给模型的消息由该模型服务处理。
