# Sticker recovery

## Failure matrix (before implementation)

- Preserve existing emoji identification and XML redaction. Parse bounded XML without external entities. Never log resource URLs or AES keys.
- Original CDN unavailable: try encrypted original, then thumbnail; failed resources show retry. Only allow HTTPS Tencent sticker hosts, including redirects; forbid credentials and explicit ports.
- Invalid key/padding, incorrect MD5, non-image bodies, oversized downloads/pixel dimensions/frame counts and HTTP errors must not become a displayed image.
- Animated GIF must animate, not silently render only frame zero. View reuse/cancellation must not display a previous message's sticker.
- Successful full resources persist in a private bounded disk cache without storing URLs/keys. Corrupt cache entries are discarded; thumbnail fallback must not permanently mask a recovered original.
- Acceptance: compile production loader into a standalone integration runner, validate the user's exact bounded message through live HTTPS and a new process/cache-only run. Exercise native view in an isolated acceptance app. Scrub reports; keep private inputs outside tracked paths.
- Installed-app delivery requires a stable legitimate signing identity and a real quit/reopen + automatic reconnection check. Do not replace the installed app using another ad-hoc signature.

## Implementation and live evidence (2026-10-02)

The existing `isSticker`/`[表情]` redaction remains in place. `HistoryRichContent.swift` now extracts an ordered list of original/encrypted/thumbnail candidates while keeping `previewURLs` compatible with existing callers. The loader enforces HTTPS allowlisted hosts on initial requests and redirects, 8 MiB responses, bounded frame count/pixel area, MD5 when supplied, and cancellation. Encrypted emoji uses AES-128-CBC with the decoded 16-byte key also used as the IV and PKCS#7 padding; this was verified against the exact requested resource, not assumed from the separate WeChat image protocol.

Original resources are retained for up to 30 days in a private 32 MiB cache. Thumbnail cache entries expire after five minutes so a temporary original failure does not permanently downgrade the message. Cache filenames hash the resource identity; they do not store raw URLs or keys. Invalid cache entries are ignored/removed and recover via download. GIF uses AppKit's animated NSImageView instead of flattening frame zero. SwiftUI tasks reset and cancel on resource/attempt changes.

Observed via a bounded GreenBubbles CLI query to the single screenshot conversation (50 messages, one matching sticker); no raw database access and no WeChat UI operation:

- Original HTTPS: 96,758 bytes, 16 frames, image decoded, XML hidden — PASS.
- Original address removed from private fixture: encrypted fallback decrypts to the same MD5 and 16-frame GIF — PASS.
- Separate process with networking disabled: original cache hit, same bytes/frames — PASS.
- 12 CLI integration journeys, including encrypted cache restart, thumbnail fallback, malformed/entity XML, disallowed host/userinfo, invalid key, wrong digest, corrupt-cache rejection and redownload — PASS.
- Debug/release build and diff whitespace check — PASS.
- Installed replacement/restart: NOT_RUN. `/Applications/GreenBubbles.app` remains the existing build. No valid signing identity was available. Main installation chat owns the combined delivery and signing decision.

Scrubbed receipts are in `docs/acceptance/sticker-recovery/`. Private message XML and downloaded test resources are under ignored `.tmp/sticker-acceptance/`, mode 0600; do not copy them into reports.

## Repeat

From this repository with an authorized private typed-message JSON file:

```sh
scripts/sticker-acceptance/run.sh /absolute/private/message.json .tmp/sticker-acceptance/cache docs/acceptance/sticker-recovery/live.json
.tmp/sticker-acceptance/runner /absolute/private/message.json .tmp/sticker-acceptance/cache docs/acceptance/sticker-recovery/restart-cache.json --cache-only
python3 scripts/sticker-acceptance/failure-journeys.py /absolute/private/message.json
scripts/sticker-acceptance/package-native.sh /absolute/private/message.json
```

For `failure-journeys.py`, use a sticker with available original, encrypted and thumbnail URLs. The runner primes an encrypted cache, then starts a separate cache-only process. The native app is `.tmp/GreenBubbles Sticker Acceptance.app`; it uses actual production parser/loader/view and has no credentials or WeChat connection. It does not replace either colleague's preview app. The missing/invalid examples must show fallback and retry; the real example must animate within its 160-point bounds.

## Final native follow-up

Production `HistoryStickerView` in the isolated native acceptance app: PASS. Two screenshots show distinct GIF frames (cat sitting, then lying down with caption), within the fixed 160-point bounds, with labels unobscured. Missing-resource fallback and invalid-resource Retry were exercised. Native Cmd-Q terminated the process; native reopening displayed the sticker again. `native-e2e.json` records screenshot hashes. This is the isolated sticker view, not the installed full-history app or remembered-connection acceptance.

Haiku independent review found no confirmed security/correctness defect in supplied sources and reports, and declined unsupported product UI/journey scores. Its then-pending native layout observation is resolved by the final screenshots. Its statement that actor fetches necessarily queue serially is inaccurate: Swift actors are reentrant across network `await` points; no throughput claim is made. Review remains in `independent-review.md` unaltered.
