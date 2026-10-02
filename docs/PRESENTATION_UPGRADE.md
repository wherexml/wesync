# Rich history presentation

Scope: improve the GreenBubbles native direct-history browser without opening or changing WeChat during development or acceptance. All acceptance data is synthetic. Existing credentials, WeChat files and the running WeChat app are out of scope.

Failure cases to exercise before release:
- A quote has reply text, quoted sender/content, only XML, or no recoverable content; never invent missing words.
- Images are available, missing, malformed, too large, or fail integrity verification; text stays readable and retry is explicit.
- Attachment work completes after changing sources; stale results must not enter the new conversation.
- A sender has no avatar, a valid imported avatar, or a corrupt image; use a stable name fallback and preserve imports across restart.
- Same sender identifiers in different sources must not share avatars accidentally.
- Message and search responses must use explicit JSON regardless of a user's CLI default.
- The offline fixture CLI must reject every path outside its own synthetic directory and log only command names.

Avatars are imported by the user into GreenBubbles's own private store. The app does not scrape WeChat avatars or fetch remote avatar URLs. Attachment previews call GreenBubbles's existing inspect/materialize interface on demand and verify the returned hash/size. Testing uses a separate preview app identity and synthetic CLI.

## Delivered local build (2026-10-02)

- Image messages have explicit load, retry and enlarged preview. Existing GreenBubbles attachment APIs perform resolution; the UI validates kind, size and SHA-256, drops stale source-session results and removes temporary decoded files. Up to 20 thumbnails remain in memory until source close. No background attachment enumeration.
- Structured and existing XML quote content render as reply/reference cards; absent content remains explicitly unavailable.
- Conversation/person avatars support right-click → 选择头像图片…; imports are normalized, stored privately and separated by source/person. Missing avatars use a stable colored name. This is manual import, not automatic contact-photo collection.
- The selected CLI path is remembered if still executable. Build 3 additionally supports optional Keychain persistence and automatic reconnection, described below.

## Repeatable offline acceptance

Run `python3 scripts/package-presentation-preview.py`, then open `.local-install/GreenBubbles Preview.app`. The preview has a separate application identity and a fixture CLI that rejects every non-fixture source. Its debug-only harness runs actual production models, subprocess queries, attachment verification, avatar persistence and SwiftUI rendering. Results appear in `Contents/Resources/offline-fixture/{acceptance.json,requests.jsonl,presentation.png}`. The release binary excludes the harness.

Open the fixture conversation, click an image to open/close its preview, and right-click an avatar to import `Contents/Resources/offline-fixture/sample.png`. These native CUA interactions passed separately from the in-process render.

14 automated offline checks passed. Debug/release compilation and `git diff --check` passed. No unit tests were added or run. The failure matrix is a design checklist, not a claim that every listed edge case has a dedicated automated check. Real WeChat acceptance was deliberately NOT_RUN under the user's instruction.

## Installation and rollback

The local release UI is installed in `/Applications/GreenBubbles.app`, bundle build 2, local marker 2026-10-02, with an ad-hoc signature verified using `codesign --verify --deep --strict`. Both bundled Rust CLI binaries are byte-for-byte unchanged from the backup. The app was not connected to real sources during acceptance. Quit and reopen GreenBubbles to load the new binary.

Original app backup: `.local-install/GreenBubbles-before-presentation-20261002.zip`. To roll back, quit GreenBubbles, extract that archive to a temporary directory, then replace only `/Applications/GreenBubbles.app` with the extracted original bundle. Leave user data/configuration alone.

Evidence: `../docs/acceptance/greenbubbles-presentation-2026-10-02/` includes the synthetic render, 14-check report, native interaction receipt and installation receipt. This is a local enhancement, not an upstream release or a claim of notarization.

## Remembered connection failure checklist (before implementation)

- Never save an unverified connection or put credentials in preferences, arguments or logs.
- A fresh app restores only its own exact Keychain entry; no Keychain enumeration.
- Missing/locked/denied/corrupt credentials and changed CLI fail into a usable manual connection page without retry loops.
- Startup must respect an explicitly supplied history bundle and run at most once.
- User can disable remembering and delete the saved connection; subsequent startup stays disconnected.
- Synthetic acceptance must cover credential roundtrip/deletion, successful fresh-model restore and restore failure; never connect to real WeChat.

## Remembered connection delivered (local build 3)

The connection sheet defaults to “记住此连接，下次启动自动打开”. After both status and conversation queries succeed, the app writes one exact, app-owned, non-synchronizing Keychain item containing the successful connection and credential. It never enumerates Keychain or writes the credential to defaults, process arguments, receipts or logs. The entry is accessible when this Mac is unlocked. A SHA-256 binding to the selected CLI prevents handing the credential to a replaced executable without a fresh manual connection.

Startup restores once and goes directly to Chats. An explicitly supplied history bundle takes precedence. Errors return to a usable welcome/manual flow without automatic retry loops. “忘记已保存的连接” deletes this app's item and disables future automatic restoration; the current session remains open. Save errors are visible in the sidebar. Unchecking remember takes effect when connecting.

Migration: the previous build kept the credential only in memory, so the first successful connection in build 3 needs one manual entry. This task intentionally did not retrieve existing real credentials or connect to WeChat. Normal subsequent restarts restore automatically; a changed credential, unavailable source, Keychain denial or changed CLI may require manual intervention.

Acceptance: 20 synthetic integration checks passed, including actual Keychain synthetic-secret roundtrip/removal and a fresh model reconnect. A second native process launch exercised the production startup path without calling manual connect or typing a key and showed Chats. The native remember checkbox and forget action were verified through CUA. The preview's own synthetic Keychain entry was then removed via its Forget button. No real credentials were read. No unit tests were added/run. Debug/release compilation and diff checks passed; an existing unrelated weak-capture warning remains.

Repeat the packaged preview normally for the full checks. Then quit, create the empty `Contents/Resources/offline-fixture/verify-restart` file, and reopen the same preview binary to verify actual restart; inspect `restart-acceptance.json`. Remove that marker to rerun full checks. All sources are strictly synthetic. Receipts: `../docs/acceptance/greenbubbles-remember-2026-10-02/`.

Installed `/Applications/GreenBubbles.app` build 3 has a verified ad-hoc signature; both bundled CLI binaries are unchanged. Before-build-3 backup: `.local-install/GreenBubbles-before-remember-20261002.zip`. Quit GreenBubbles and restore that bundle to roll back. Production startup was not exercised, to honor the no-WeChat-access instruction.

## Explorer parity failure checklist (before implementation)

- WXGF must become a decoded preview locally; missing codec, corrupt/oversized payload and conversion timeout must leave retry usable.
- Only cached, exact-identity avatars may be displayed. Missing/unsupported entries retain a clear fallback; no network scraping.
- Empty compressed app-message blobs must not mask valid raw XML; nested quotes must retain reply and reference separately.
- Own messages use explicit source account identity, never a guess from status/name; unknown identity stays unclassified.
- Personal/group tabs default to personal and compose with search and pagination; internal placeholders must not appear as people.
- Remove message-type footers; preserve honest unavailable/truncation errors without technical clutter.
- Native layout follows the reference's narrow white incoming/green outgoing bubbles, avatar side, muted timestamps, compact sender names and image-only cards.
- Synthetic E2E and bounded GreenBubbles-only verification produce scrubbed receipts; no WeChat app operation or raw DB scripts.

### DAT tail failure checklist (before implementation)

- Non-default V1/V2 XOR tails must reconstruct PNG/JPEG bytes, not merely a recognizable header.
- Reject overlapping/truncated AES/tail sections and inconsistent known trailers.
- WXGF may use a consistent key from at most eight already-resolved sibling candidates; never recursively scan other conversations.
- No tail needs no inferred key; legacy XOR remains supported. Unknown keys produce an explicit failure rather than silently corrupting images.
- Acceptance compares fully decoded pixels or original synthetic image bytes, not just file signatures.

## Explorer chat UI update (2026-10-02, local build 4)

Implemented against the read-only `wechat-web-explorer/static/app.js` and `styles.css` reference:

- Two-column chat layout; Personal/Group tabs, Personal by default; hide service/internal placeholders.
- Exact-identity cached avatars from GreenBubbles bounded queries. No avatar URLs are fetched. Unavailable avatars retain initials.
- Explicit account-holder identity places own messages/avatar on the right with green bubbles. System notices are centered.
- Compact sender/timestamps, no Text/Image/App type footer; quote reply above its referenced text. Empty compressed blobs no longer override available XML.
- Image previews load on demand, at most two concurrently; integrity checked; PNG/JPEG V1/V2 tails recovered from validated trailers. WXGF locally converts through installed ffmpeg, with timeout and size limits.
- Current-chat search, refresh, older-message pagination, latest-message shortcut, and click-to-enlarge images.

Evidence is in `../docs/acceptance/greenbubbles-explorer-2026-10-02/` relative to the repository root.

- Native offline transport/model/render acceptance: 24/24 checks, including cached avatar decoding, outgoing identity, quotes, missing-image retry, WXGF conversion, integrity rejection and saved-connection lifecycle.
- Actual isolated preview process restart: PASS, Personal tab selected, no key entry or manual connection.
- CUA native interaction: Personal/Group switch, group selection, current-chat search and return, image enlargement, compact left/right presentation. Synthetic content only.
- CLI DAT E2E: 9/9 assertions, byte-for-byte PNG equality and actual pixel decoding for non-default/default/short/absent XOR tails; malformed envelope rejected without output.
- Bounded real verification used only the GreenBubbles CLI; latest scrubbed counts are in `real-presentation.json`. Three selected real images fully decoded. No direct WeChat operation or raw database script was used. These samples do not establish that every historical attachment is available.

Reproduce synthetic checks:

```sh
cargo build --release --manifest-path Native/GreenBubbles/Cargo.toml
python3 scripts/verify-dat-presentation.py
python3 scripts/package-presentation-preview.py
```

Open `.local-install/GreenBubbles Preview.app` using the native UI. Its fixture CLI refuses external source paths and credentials. Remove its synthetic `verify-restart` marker to run all checks; create the marker and reopen to exercise startup restoration. Reports appear in the preview app's `Contents/Resources/offline-fixture/`. No unit tests were added or run.

Deployment: `/Applications/GreenBubbles.app`, local build 4, ad-hoc signature verified. The original `greenbubbles-send` helper is unchanged. Existing connection was updated only in the exact GreenBubbles Keychain item, using the previously verified local credential file; no Keychain enumeration. Backup: `.local-install/GreenBubbles-before-explorer-20261002.zip`. macOS permission binding after the app-signature change requires native reauthorization; final live startup acceptance is tracked in the installation receipt.

Limits: images not downloaded by WeChat and missing quote source text remain unavailable. Unknown tail keys fail explicitly instead of publishing corrupt images. This implements the requested chat presentation in SwiftUI, not the reference project's iPhone-backup backend or all export/date-navigation features.

### Installed-app acceptance completed

The previous on/off toggle and re-add did not replace the obsolete permission identity. Reset only `SystemPolicyAllFiles` for `me.greenbubbles.GreenBubbles`, then reselect the installed app through the unlocked native System Settings. The same existing permission scope was restored. System Quit & Reopen connected successfully. A separate manual quit was verified by process absence, then native reopening automatically connected to the Personal tab without a database key or administrator password. Real cached avatars and quote bodies were visually checked; a real image opened in the preview sheet. See `installed-app-e2e.json`. No app binaries changed during this permission repair. Future updates still require a stable signing identity; this acceptance proves normal relaunch of build 4, not permission portability across newly signed builds.

## Other tab acceptance matrix
Before implementation: verify personal remains default; official accounts with legacy IDs are classified using contact verify_flag; gh_ accounts and known system services appear in Other; groups take precedence; same-name people and @openim contacts remain personal; internal placeholders stay hidden. All visible conversations belong to exactly one tab. Run synthetic native E2E then installed quit/reopen without credential entry.

Other-tab implementation: bounded contact enrichment reads optional verify_flag bit 8 and exports isOfficialAccount. Native classification combines this with gh_ and system service IDs; no display-name heuristics. Verified the three user-provided accounts using the bounded CLI. Synthetic native E2E: 27 checks PASS, real preview process restart PASS. Installed build 5 currently awaiting macOS Keychain confirmation; real installed restart is not yet passed.

## Manual category move failure matrix (before implementation)
- Personal and group context menus move to Other immediately; the selected conversation clears if now hidden.
- Other moves back to original structural kind (group suffix => group, otherwise personal), including automatically classified official accounts.
- Explicit overrides win over automatic metadata, survive refresh and process restart, and remain isolated by source path.
- Restoring automatic classification removes the override. Hidden placeholders cannot be moved.
- First-pass cleanup only matches unmistakable advertising names; uncertain names stay untouched. Keep reversible local override records, no WeChat mutations.

Manual category delivery (build 6): context menus support Move to Other, Move back to Personal/Group, Restore automatic. Source-scoped SHA256 preference keys store overrides; no WeChat changes. Synthetic native E2E 35 checks PASS, process restart preserves group override. Installed app full quit/process absence/reopen PASS, default Personal, no key/password entry; Other retains moved marketing account. User confirmed actual moving acceptance. 20 manual overrides preserved at final check. First-pass review covered 500 recent conversations (not all): 181 automatically classified official accounts, one explicit coupon promotion moved by agent; subsequent user edits preserved. Evidence: ../docs/acceptance/greenbubbles-manual-category-2026-10-02/. Stable signing across future updates remains unresolved.

## Message/input/menu-bar failure matrix (before implementation)
- Emoji XML is never displayed, copied into labels, or logged; safe bounded XML parsing rejects entities, malformed input and arbitrary URLs. Available sticker previews use HTTPS allowlisted CDN only, redirect policy, byte/time limits, and cancellation; unavailable assets have a compact honest fallback.
- Real keyboard typing, paste, Chinese input, clear and Return search work after window activation and menu-bar reopen; editing does not reset marked text.
- Initial message page is bounded to 40; revisit cache is source-isolated and capped; explicit refresh bypasses cache; pagination and switching cancel stale loads.
- Loading has compact skeletons and image placeholders. Current content remains during refresh, no blocking work on key input path.
- Menu bar opens/hides the window, Dock visibility persists, close keeps menu-bar app alive, Quit terminates. Full installed restart must restore connection and manual categories without credential entry.

## 2026-10-02 搜索、加载与菜单栏收尾

原生 NSSearchField 修复首次点击输入焦点，保留 marked-text 编辑；默认首屏 40 条，8 个会话首屏短时缓存，刷新保留当前内容；图片使用紧凑加载卡，消息初始加载使用骨架行；表情独立解析与动画恢复见 STICKER_RECOVERY.md。黑色双气泡图标由 imagegen 生成，支持菜单栏常驻与可持久化 Dock 开关。菜单栏拥挤时可从“显示 → 菜单栏选项”调用相同菜单。

最终预览 49 项 E2E 与原生退出/重启免 key 验收通过；英文键盘及中文粘贴搜索通过，中文 IME 完整组合输入未验收。真实 CLI 单次对比仅证实返回体积减少约 60%，未证实查询延迟改善。正式 build 7 已暂存但未安装，需稳定合法签名后执行正式 App 重启验收。证据见父项目 docs/acceptance/greenbubbles-polish-2026-10-02/。

后续安装进展：同日已建立固定本机代码签名身份，图标迁移占用 build 7；上述菜单栏/中文界面的 release 程序连同新双机器人图标安装为 build 8。首次权限迁移成功，7 → 8 更新无需重设磁盘权限。原生菜单与 Finder 图标通过；最终冷启动钥匙串确认及复验状态见 `docs/acceptance/brand-20261002/installed-acceptance.json`，不以先前合成验收代替真实重启验收。
