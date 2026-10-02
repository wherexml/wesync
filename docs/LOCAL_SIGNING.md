# 本机稳定签名与图标更新

## 为什么旧更新会丢权限

2026-10-02 检查：已安装 build 6 的 ad-hoc 签名以程序摘要 `cdhash` 标识身份。更新资源并重签会改变这个身份，因此不能把“签名校验通过”当成“下次更新仍保留权限”。

Apple 支持使用自签代码签名证书，为本机应用建立固定的 designated requirement。它不等于 Developer ID 分发或 Apple 公证，也不需要把证书设为全系统受信任根。参考 [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/) 和 [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。

## 专用身份

通过系统 Certificate Assistant 创建 `GreenBubbles Local Code Signing`：RSA 2048、SHA-256、用途仅 Digital Signature / Code Signing、3650 天。私钥留在登录钥匙串，不导出，不写入代码仓库，不枚举其他钥匙串项目。后续更新重复使用同一证书，不为每次发布生成新证书。

首次 `codesign` 使用私钥时，macOS 可能请求本机登录密码。应用在首次迁移后读取原有连接项目，也可能独立出现钥匙串确认；这是两个不同授权。由用户在系统安全窗口确认并按需选择“始终允许”；密码不得发给 Agent。不要通过修改私钥访问列表或降低系统保护来跳过确认。

## 更新流程

1. 原生 UI 确认当前安装版本能够连接。保留应用自己的连接记录。
2. `python3 scripts/generate-brand-assets.py` 生成品牌资源。
3. 运行 `python3 scripts/stage-local-brand-update.py --identity <证书SHA1> --output .build/<新的暂存目录>`。
4. 脚本沿用已安装程序，仅更新图标和 bundle build。它签署两个资源不同的副本，验证 designated requirement 相同、签名完整，并验证查询与发送工具字节未变。不会安装，不会修改连接，不会改 TCC。
5. 首次从 ad-hoc 迁移到固定证书前，须明确它是新身份，已有授权可能需要在系统设置中重新绑定。确认候选包完整、旧包可回滚、连接记录保留后，退出应用、备份旧包，再安装。
6. 使用原生 UI 重开；必要时只在系统设置恢复该应用原有的完全磁盘访问权限。钥匙串安全确认必须由用户完成。禁止直接编辑 TCC 数据库、放宽签名匹配条件或把普通本机证书冒充 Developer ID。
7. 完整退出再重开，确认自动连接无需数据库密钥，检查产品图标与菜单栏图标和菜单操作。再用同一证书签署更新副本并验证身份稳定性；静态身份检查不等于实际权限迁移已通过。

签名迁移、安装、自动连接、菜单栏验收分别记录结果，全部通过前不声明交付完成。向他人分发仍使用现有 Developer ID 发布脚本。

## 2026-10-02 实际迁移

build 6 → 7 建立固定证书身份；原权限开关关闭、重新选择应用仍未恢复连接。通过系统 `tccutil reset SystemPolicyAllFiles me.greenbubbles.GreenBubbles` 撤销仅该应用的旧授权，然后原生系统设置重新选择 `/Applications/GreenBubbles.app`，重开恢复连接。没有直接编辑权限数据库。

build 7 → 8 安装此前准备好的菜单栏/中文界面 release 程序，同一固定证书签名，保留查询工具及发送工具字节。无需再次变更磁盘授权即自动连接。菜单隐藏/打开/退出通过，Finder 白底图标通过。最终冷启动待原生钥匙串确认后复验，结果以 `docs/acceptance/brand-20261002/installed-acceptance.json` 为准。
