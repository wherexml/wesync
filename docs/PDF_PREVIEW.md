# PDF attachment preview

## Failure matrix (written before implementation)

- Only document/app subtype 6 messages with a PDF filename become PDF cards; ordinary text mentioning a PDF remains text.
- Resolve through bounded GreenBubbles attachment inspect/materialize, never scan the account folder from Swift.
- Missing local downloads show an honest error with retry; no implicit network download.
- Reject oversized, changed, wrong-kind, mismatched digest/size, malformed and locked PDF files.
- Cancelled work/source changes discard temporary files; closing the preview removes its private copy. An explicit system-open action uses a separate private copy retained for 24 hours.
- Preserve the document extension, but never use message filenames as paths.
- Preview supports page navigation, zoom and completion; system-open errors remain visible.
- Offline E2E exercises production CLI transport, integrity, PDFKit decoding, missing/retry and native UI. It does not prove that the screenshot's real PDF is downloaded.
- Installed-app restart and real attachment acceptance require preserving its signing/permission identity; no ad-hoc overwrite as a routine update.

## In-progress handoff (2026-10-02)

PDF implementation is in the shared working tree. Native isolated Preview UI has verified file card → PDFKit first/second pages → zoom/fit → system Preview application (2-page synthetic file) → close back to chat. Evidence: `docs/acceptance/pdf-preview-20261002/`. Initial combined harness exposed unrelated icon fixture size/parallel packaging issues; the shared script now scales the icon to 128px. Full combined rerun pending in this chat. Installed app not modified; signing blocker remains.

Steve added a request to make the welcome page and all downstream views understandable Chinese. This chat is actively changing presentation strings in HistoryViews, HistoryDirectViews, HistoryDetailViews, HistorySnapshotCreationSheet, LiveMediaAccessView, HistoryBrowserModel, GreenBubblesHistoryApp plus HistoryChinesePresentation.swift and displayName-only changes in HistoryDirectQueryClient/HistorySnapshotCreationClient. Preserve existing input/menu/category changes. No changes to the owned sticker implementation. Do not install until combined build and native acceptance are complete.

## Latest handoff

PDF and Chinese UI work is ready in the shared tree. The independent Chinese Preview passed 49/49 combined E2E on 2026-10-02 16:46 Singapore time, then actual quit/process-absence/reopen without credential input, then PDF open again. See `docs/acceptance/chinese-ui-20261002/` and `docs/CHINESE_UI.md`. Haiku bounded review saved in PDF evidence; decoded-size error classification repaired. The card is keyed by conversation+message, and preview dismissal on source disappearance is intentional. Original review process stalled and was superseded by the completed bounded review.

No production installation performed. Install coordinator must preserve Chinese Info.plist declarations documented in CHINESE_UI.md along with all menu/input/sticker changes. No further shared production code edits planned by this task after final release compilation.
