#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-.build/message-timestamps-acceptance}"
mkdir -p "$out"
cat Sources/GreenBubblesHistoryApp/HistoryMessageTimestamp.swift scripts/verify-message-timestamps.swift > "$out/main.swift"
swiftc "$out/main.swift" -o "$out/render-timeline"
"$out/render-timeline" "$out"
