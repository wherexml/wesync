#!/bin/zsh
set -eu
cd "${0:A:h}/../.."
swift build --product greenbubbles-history
mkdir -p .tmp/sticker-acceptance
products=$(swift build --show-bin-path)
if [[ -f "$products/GreenBubblesHistory.o" ]]; then
  objects=("$products/GreenBubblesHistory.o")
  sticker_modules="$products"
else
  objects=("$products"/GreenBubblesHistory.build/*.o)
  sticker_modules="$products/Modules"
fi
swiftc -parse-as-library -I "$sticker_modules" scripts/sticker-acceptance/run.swift Sources/GreenBubblesHistoryApp/HistoryStickerLoader.swift "${objects[@]}" -lsqlite3 -o .tmp/sticker-acceptance/runner
.tmp/sticker-acceptance/runner "$@"
