Independent review of supplied sources and scrubbed reports only. No tools, no code changes, no installed-app delivery claim.

## Non-claims

- Stable signing identity is absent; `docs/acceptance/sticker-recovery/failure-journeys.json` has `"installedApp": "NOT_RUN"`. Installed quit/reopen/reconnect was not evidenced.
- Native GIF was seen, but the first capture was oversized. `sizeThatFits` + `.clipped()` exist in source; native follow-up is pending. That is not a verified UI fix.

## Security (confirmed)

No confirmed allowlist/XXE/redirect/cache bypass in the supplied code.

`HistoryRichContent.swift` (`sticker`, `stickerURL`, `allowedStickerHost`, `StickerXMLReader`): 256 KiB cap; rejects `<!DOCTYPE` / `<!ENTITY`; `shouldResolveExternalEntities = false`; depth abort at 32; https-only after upgrade; exact host allowlist; rejects userinfo and port. Encrypted resources are dropped if `aeskey` is not 16-byte hex.

`HistoryStickerLoader.swift` (`StickerRedirectPolicy`, `download`, `decrypt`, `validate`, `cached`): ephemeral session, no cookies/credentials/URLCache; redirects re-checked with the same URL policy; 8 MiB cap (Content-Length and stream); AES-128-CBC PKCS7 with key-as-IV (matches the passing encrypted fixture); optional MD5 of plaintext; ImageIO complete + frame/pixel bounds; cache names are SHA-256 (no URL/key in the filename); 0o700/0o600; corrupt cache deleted on validate failure.

Those controls match the passing bounded checks: `entity-rejected`, `host-rejected`, `userinfo-rejected`, `invalid-key`, `wrong-digest`, `corrupt-cache-rejected`, `corrupt-cache-recovers`.

Residual (not scored as bugs): MD5 is skipped when missing/invalid (`stickerHex` → `nil`) and always skipped for thumbnails; ImageIO is not restricted to raster UTIs; decrypted bytes sit in the user cache.

## Correctness

No confirmed functional defect against the bounded reports: `live.json`, `encrypted.json`, and `restart-cache.json` all `passed` with 96758 bytes, 16 frames, `imageDecoded: true`. Failure journeys listed above also `passed`.

Open, not verified:

- `HistoryStickerView.swift` `AnimatedStickerImage`: SwiftUI `.frame(160).clipped()` does not set `NSImageView.clipsToBounds`. AppKit drawing often ignores SwiftUI clip. First native capture was oversized; post-fix native evidence is absent. Treat layout as **unfixed in production UI** until follow-up.
- `HistoryStickerLoader` is an `actor` (`shared.load`). All sticker fetches queue on one actor; a thread of stickers will load serially. Not contradicted by a single-GIF capture.

## Acceptance vs delivery

Bounded CLI/native-fixture recovery is evidenced. That is not installed-app E2E (quit, native reopen, remembered connection, sticker in the real UI after restart).

## Scores

| Axis | Score | Evidence |
|------|--------|----------|
| UI | **NOT_SCORED** | GIF seen but first capture oversized; `sizeThatFits`/`.clipped()` not re-captured natively |
| Journey (installed / reconnect) | **NOT_SCORED** | `installedApp: NOT_RUN`; no stable signing identity |
| Bounded sticker recovery | **NOT_SCORED as ≥95 product score** | `live` / `encrypted` / `restart-cache` / `failure-journeys` passed; those reports do not cover installed UI |

Do not treat this as delivered. Native size follow-up and installed restart are still required before any UI/journey score.