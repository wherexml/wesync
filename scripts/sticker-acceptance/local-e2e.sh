#!/bin/zsh
set -eu
cd "${0:A:h}/../.."
swift build --product greenbubbles-history
emoji_products=$(swift build --show-bin-path)
if [[ -f "$emoji_products/GreenBubblesHistory.o" ]]; then
  emoji_objects=("$emoji_products/GreenBubblesHistory.o")
  emoji_modules="$emoji_products"
else
  emoji_objects=("$emoji_products"/GreenBubblesHistory.build/*.o)
  emoji_modules="$emoji_products/Modules"
fi
mkdir -p .tmp/emoji-fix docs/acceptance/emoji-fix-20261002
swiftc -parse-as-library -I "$emoji_modules" scripts/sticker-acceptance/local-e2e.swift "${emoji_objects[@]}" -lsqlite3 -o .tmp/emoji-fix/local-e2e
.tmp/emoji-fix/local-e2e docs/acceptance/emoji-fix-20261002/synthetic.json
