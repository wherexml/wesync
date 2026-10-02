**Review (correctness only).** Synthetic PDFKit/Preview E2E does not cover these. Production install still blocked on signing — not complete.

1. **`HistoryPDFCard.onDisappear` kills a live preview**
   `onDisappear` does `task?.cancel(); preview = nil`. In a chat `List`/`LazyVStack`, scrolling the card off-screen (or any parent disappear) dismisses the sheet and `HistoryPDFPreview.deinit` deletes the temp file. Default sheet presentation would have kept it; this explicitly tears it down.

2. **Card identity is not bound to the load**
   `@State` preview/task are not reset on `filename`/`load` change, and the `Task` captures `load` at tap time. If the row is reused for another message, an in-flight result can present the old PDF under the new title. Prefer `.task(id:)` / cancel+clear in `onChange`.

3. **Decoded size > 64 MB is reported as integrity failure**
   Source size uses `PDFPreviewError.tooLarge`. After materialize, `decodedByteCount <= 64MB` sits in the same `guard` as SHA/type/attachment checks, so a too-large decode throws `PresentationError.invalidIntegrity` instead of `tooLarge`.

Not bugs given the stated E2E: PDFView owned by `@State` + empty `updateNSView` (next/prev/zoom already verified); OpenedPDFs 24h retain for Preview; `%PDF-` + `isLocked` + `pageCount` gates.

Disposition: (1) Source/conversation disappearance deliberately dismisses its private preview; sheets block background chat scrolling and native opening/closing passed. (2) Caller sets .id(message.conversationID + message.id) on HistoryPDFCard; this context was omitted from the bounded review, so row identity is explicitly reset. (3) Decoded-size check now reports PDFPreviewError.tooLarge separately. No independent acceptance score claimed.
