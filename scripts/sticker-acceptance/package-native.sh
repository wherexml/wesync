#!/bin/zsh
set -eu
cd "${0:A:h}/../.."
swift build --product greenbubbles-history
sticker_products=$(swift build --show-bin-path)
if [[ -f "$sticker_products/GreenBubblesHistory.o" ]]; then
  sticker_objects=("$sticker_products/GreenBubblesHistory.o")
  sticker_modules="$sticker_products"
else
  sticker_objects=("$sticker_products"/GreenBubblesHistory.build/*.o)
  sticker_modules="$sticker_products/Modules"
fi
sticker_app=".tmp/GreenBubbles Sticker Acceptance.app"
mkdir -p "$sticker_app/Contents/MacOS" "$sticker_app/Contents/Resources"
swiftc -parse-as-library -I "$sticker_modules" scripts/sticker-acceptance/native.swift Sources/GreenBubblesHistoryApp/HistoryStickerLoader.swift Sources/GreenBubblesHistoryApp/HistoryStickerView.swift "${sticker_objects[@]}" -lsqlite3 -o "$sticker_app/Contents/MacOS/sticker-acceptance"
cp "$1" "$sticker_app/Contents/Resources/message.json"
chmod 600 "$sticker_app/Contents/Resources/message.json"
python3 - <<'PY'
import plistlib
from pathlib import Path
p=Path('.tmp/GreenBubbles Sticker Acceptance.app/Contents/Info.plist')
p.write_bytes(plistlib.dumps({'CFBundleExecutable':'sticker-acceptance','CFBundleIdentifier':'me.greenbubbles.StickerAcceptance','CFBundleName':'GreenBubbles Sticker Acceptance','CFBundlePackageType':'APPL','NSHighResolutionCapable':True,'LSMinimumSystemVersion':'14.0'}))
PY
codesign --force --sign - "$sticker_app"
