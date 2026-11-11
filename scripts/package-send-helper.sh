#!/bin/bash
# Builds, assembles, signs, notarizes, and staples the we-sync application
# together with its privilege-separated input helper.
#
# The send path is a Developer-ID direct distribution only: the helper needs
# cross-application control, which the App Sandbox forbids and the Mac App Store
# does not accept. Every bundled executable is built here or pinned in SwiftPM;
# full application updates use the signed GitHub feed, never separate send code.
#
# Required environment:
#   GREENBUBBLES_SIGNING_IDENTITY   Developer ID Application certificate name
#   GREENBUBBLES_TEAM_IDENTIFIER    Apple team identifier (pinned by the helper's
#                                   XPC code-signing requirement)
# Optional environment:
#   GREENBUBBLES_VERSION             Bundle marketing version. Defaults to the
#                                   root Rust package version.
#   GREENBUBBLES_BUILD               Monotonic bundle build. Defaults to git commit count.
#   GREENBUBBLES_SKIP_BUILD          Set to 1 when verified release binaries
#                                   were already built before credentials were
#                                   imported into an ephemeral CI keychain.
#   GREENBUBBLES_SEND_RELEASE_PUBLIC_KEYS
#                                   Comma-separated hexadecimal Ed25519 public
#                                   keys pinned into this build. Omitting it
#                                   ships a binary that trusts no release
#                                   calibration profile, so the send path can
#                                   never leave the dry-run stage. That is the
#                                   safe default, not an oversight.
#   GREENBUBBLES_NOTARY_PROFILE     `notarytool` keychain profile for the app and
#                                   disk image; when unset only signing runs.
#   GREENBUBBLES_OUTPUT_DIRECTORY   Where to write the bundle, SBOM, and DMG.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

signing_identity="${GREENBUBBLES_SIGNING_IDENTITY:-}"
team_identifier="${GREENBUBBLES_TEAM_IDENTIFIER:-}"
version="${GREENBUBBLES_VERSION:-$(awk -F '"' '/^version[[:space:]]*=/ { print $2; exit }' Native/GreenBubbles/Cargo.toml)}"
build="${GREENBUBBLES_BUILD:-$(git rev-list --count HEAD)}"
skip_build="${GREENBUBBLES_SKIP_BUILD:-0}"
release_public_keys="${GREENBUBBLES_SEND_RELEASE_PUBLIC_KEYS:-}"
notary_profile="${GREENBUBBLES_NOTARY_PROFILE:-}"
output_directory="${GREENBUBBLES_OUTPUT_DIRECTORY:-$repository_root/.build/package}"
app_bundle="$output_directory/we-sync.app"
helper_bundle="$app_bundle/Contents/Library/LoginItems/GreenBubblesInputHelper.app"
trust_source="Sources/GreenBubblesSendKit/SendReleaseTrust.swift"

fail() {
  echo "error: $*" >&2
  exit 1
}

notarize_and_staple() {
  local payload="$1" artifact="$2" receipt="$3" submission attempt
  xcrun notarytool submit "$payload" --keychain-profile "$notary_profile" \
    --output-format json >"$receipt.submit.json"
  submission=$(/usr/bin/plutil -extract id raw "$receipt.submit.json")
  echo "==> Apple submission: $submission"
  xcrun notarytool wait "$submission" --keychain-profile "$notary_profile" \
    --timeout 25m --output-format json >"$receipt.json"
  if [ "$(/usr/bin/plutil -extract status raw "$receipt.json")" != "Accepted" ]; then
    xcrun notarytool log "$submission" "$receipt.log.json" \
      --keychain-profile "$notary_profile"
    fail "notarization was not Accepted for $artifact"
  fi
  for attempt in $(seq 1 12); do
    if xcrun stapler staple "$artifact"; then
      xcrun stapler validate "$artifact"
      return
    fi
    [ "$attempt" -lt 12 ] && sleep 10
  done
  fail "could not staple the accepted ticket for $artifact"
}

[ -n "$signing_identity" ] || fail "set GREENBUBBLES_SIGNING_IDENTITY to a Developer ID Application identity"
[ -n "$team_identifier" ] || fail "set GREENBUBBLES_TEAM_IDENTIFIER to the Apple team identifier"
[[ "$build" =~ ^[1-9][0-9]*$ ]] || fail "GREENBUBBLES_BUILD must be a positive integer"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
  || fail "GREENBUBBLES_VERSION must be a semantic version"
[[ "$skip_build" == "0" || "$skip_build" == "1" ]] \
  || fail "GREENBUBBLES_SKIP_BUILD must be 0 or 1"

# The release verifying keys are pinned into the binary rather than read from
# disk at run time, so a profile can only be trusted if this build says so. The
# substitution is temporary and always reverted, including on failure.
restore_trust_source() {
  if [ -f "$trust_source.packaging-backup" ]; then
    mv "$trust_source.packaging-backup" "$trust_source"
  fi
}
trap restore_trust_source EXIT

if [ -n "$release_public_keys" ]; then
  cp "$trust_source" "$trust_source.packaging-backup"
  literal=$(printf '%s' "$release_public_keys" | tr ',' '\n' | sed 's/^ *//; s/ *$//' \
    | awk 'NF { printf "\"%s\", ", $0 }' | sed 's/, $//')
  /usr/bin/sed -i '' \
    "s|static let generatedReleasePublicKeys: \[String\] = \[\]|static let generatedReleasePublicKeys: [String] = [$literal]|" \
    "$trust_source"
  grep -q "$(printf '%s' "$release_public_keys" | cut -d, -f1)" "$trust_source" \
    || fail "release trust-root injection did not take effect"
  echo "pinned release verifying keys into $trust_source"
else
  echo "no release verifying key supplied: this build trusts no release calibration profile"
fi

if [ "$skip_build" == "1" ]; then
  echo "==> using prebuilt release binaries"
  for executable in \
    .build/release/greenbubbles-history \
    .build/release/greenbubbles-send \
    .build/release/greenbubbles-input-helper \
    Native/GreenBubbles/target/release/greenbubbles; do
    [ -x "$executable" ] || fail "prebuilt executable is missing: $executable"
  done
else
  echo "==> building release binaries"
  swift build -c release --product greenbubbles-history
  swift build -c release --product greenbubbles-send
  swift build -c release --product greenbubbles-input-helper
  (
    cd Native/GreenBubbles
    if [ -n "$release_public_keys" ]; then
      GREENBUBBLES_SEND_RELEASE_PUBLIC_KEYS="$release_public_keys" cargo build --locked --release
    else
      cargo build --locked --release
    fi
  )
fi

echo "==> assembling $app_bundle"
rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" \
  "$app_bundle/Contents/Resources" \
  "$app_bundle/Contents/Library/LaunchAgents" \
  "$helper_bundle/Contents/MacOS" \
  "$helper_bundle/Contents/Resources"
cp Packaging/GreenBubbles/Info.plist "$app_bundle/Contents/Info.plist"
cp Packaging/GreenBubblesInputHelper/Info.plist "$helper_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" \
  "$app_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" \
  "$helper_bundle/Contents/Info.plist"
for bundle in "$app_bundle" "$helper_bundle"; do
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$bundle/Contents/Info.plist"
done
cp Packaging/GreenBubblesInputHelper/me.greenbubbles.InputHelper.plist \
  "$app_bundle/Contents/Library/LaunchAgents/"
cp .build/release/greenbubbles-history "$app_bundle/Contents/MacOS/"
cp .build/release/greenbubbles-send "$app_bundle/Contents/MacOS/"
cp Native/GreenBubbles/target/release/greenbubbles "$app_bundle/Contents/MacOS/"
cp Native/GreenBubbles/target/release/greenbubbles "$app_bundle/Contents/MacOS/greenbubbles-sticker-query"
cp .build/release/greenbubbles-input-helper "$helper_bundle/Contents/MacOS/"
cp LICENSE NOTICE.md THIRD_PARTY_NOTICES.md "$app_bundle/Contents/Resources/"

echo "==> generating the application icon"
icon_source="assets/greenbubbles-icon.svg"
icon_base="$output_directory/GreenBubbles-icon-1024.png"
iconset="$output_directory/GreenBubbles.iconset"
[ -f "$icon_source" ] || fail "application icon source is missing: $icon_source"
rm -f "$icon_base"
rm -rf "$iconset"
mkdir -p "$iconset"
/usr/bin/sips -s format png -z 1024 1024 "$icon_source" --out "$icon_base" >/dev/null
for size in 16 32 128 256 512; do
  double_size=$((size * 2))
  /usr/bin/sips -z "$size" "$size" "$icon_base" \
    --out "$iconset/icon_${size}x${size}.png" >/dev/null
  /usr/bin/sips -z "$double_size" "$double_size" "$icon_base" \
    --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" \
  -o "$app_bundle/Contents/Resources/GreenBubbles.icns"
rm -f "$icon_base"
rm -rf "$iconset"

echo "==> generating the menu bar template"
/usr/bin/sips -s format png -z 44 44 assets/greenbubbles-menubar.svg \
  --out "$app_bundle/Contents/Resources/GreenBubbles-black.png" >/dev/null

echo "==> recording the build provenance"
git_commit=$(git rev-parse HEAD)
cat >"$app_bundle/Contents/Resources/build-provenance.json" <<PROVENANCE
{
  "formatVersion": 1,
  "version": "$version",
  "gitCommit": "$git_commit",
  "builtAtUnixSeconds": $(date +%s),
  "teamIdentifier": "$team_identifier",
  "releaseTrustRootPinned": $([ -n "$release_public_keys" ] && echo true || echo false),
  "swiftVersion": "$(swift --version 2>&1 | head -1)",
  "rustVersion": "$(rustc --version)",
  "distribution": "developer-id-direct",
  "macAppStore": false,
  "sandboxed": false
}
PROVENANCE

echo "==> generating the software bill of materials"
mkdir -p "$output_directory"
swift scripts/check-distribution-inventory.swift --print \
  >"$output_directory/greenbubbles-sbom.json"
cp "$output_directory/greenbubbles-sbom.json" "$app_bundle/Contents/Resources/sbom.json"

echo "==> signing (Hardened Runtime, library validation on, no sandbox)"
python3 scripts/sparkle_bundle.py --app "$app_bundle" --identity "$signing_identity" --distribution
# Inside out: the helper first, then its enclosing bundle, so every seal is
# computed over already-signed contents.
codesign --force --timestamp --options runtime \
  --entitlements Packaging/GreenBubblesInputHelper.entitlements \
  --identifier me.greenbubbles.InputHelper \
  --sign "$signing_identity" "$helper_bundle"
for executable in greenbubbles-history greenbubbles-send greenbubbles greenbubbles-sticker-query; do
  codesign --force --timestamp --options runtime \
    --entitlements Packaging/GreenBubbles.entitlements \
    --sign "$signing_identity" "$app_bundle/Contents/MacOS/$executable"
done
sticker_query_sha256=$(shasum -a 256 "$app_bundle/Contents/MacOS/greenbubbles-sticker-query" | awk '{print $1}')
/usr/libexec/PlistBuddy -c "Add :GBStickerQuerySHA256 string $sticker_query_sha256" "$app_bundle/Contents/Info.plist"
python3 - "$app_bundle" <<'PY'
import hashlib,json,re,sys
from pathlib import Path
app=Path(sys.argv[1])
prior=json.loads(Path('Packaging/GreenBubbles/ToolPredecessors.json').read_text())['publishedQueryToolSHA256s']
if not prior or any(not re.fullmatch('[0-9a-f]{64}',value) for value in prior):
    raise SystemExit('Invalid published query-tool predecessor inventory')
current=hashlib.sha256((app/'Contents/MacOS/greenbubbles').read_bytes()).hexdigest()
(app/'Contents/Resources/ToolUpdate.json').write_text(json.dumps({'previousSHA256':prior[0],
    'previousSHA256s':sorted(set(prior)),'currentSHA256':current})+'\n')
PY
codesign --force --timestamp --options runtime \
  --entitlements Packaging/GreenBubbles.entitlements \
  --identifier me.greenbubbles.GreenBubbles \
  --sign "$signing_identity" "$app_bundle"

echo "==> verifying the signature"
codesign --verify --deep --strict --verbose=2 "$app_bundle"
codesign --display --entitlements - "$helper_bundle" >/dev/null
# Library validation must remain enabled: the helper links only Apple-signed
# system frameworks and our own same-team-signed code.
if codesign --display --entitlements - "$helper_bundle" 2>&1 |
  grep -q "disable-library-validation"; then
  fail "the helper must not disable library validation"
fi

if [ -n "$notary_profile" ]; then
  echo "==> notarizing and stapling the application"
  app_archive="$output_directory/we-sync-app-notary.zip"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$app_archive"
  notarize_and_staple "$app_archive" "$app_bundle" "$output_directory/app-notary"
  codesign --verify --deep --strict "$app_bundle"
  spctl --assess --type execute --verbose=4 "$app_bundle"
fi

disk_image="$output_directory/we-sync.dmg"
dmg_staging="$output_directory/GreenBubbles-dmg-root"
echo "==> building $disk_image"
rm -f "$disk_image"
rm -rf "$dmg_staging"
mkdir -p "$dmg_staging"
/usr/bin/ditto "$app_bundle" "$dmg_staging/we-sync.app"
/bin/ln -s /Applications "$dmg_staging/Applications"
hdiutil create -quiet -volname we-sync -srcfolder "$dmg_staging" -ov -format UDZO "$disk_image"
rm -rf "$dmg_staging"
codesign --force --timestamp --sign "$signing_identity" "$disk_image"

if [ -n "$notary_profile" ]; then
  echo "==> notarizing and stapling the disk image"
  notarize_and_staple "$disk_image" "$disk_image" "$output_directory/dmg-notary"
  codesign --verify --strict "$disk_image"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$disk_image"
else
  echo "GREENBUBBLES_NOTARY_PROFILE is unset: signed but not notarized"
fi

echo "==> done"
echo "bundle: $app_bundle"
echo "disk image: $disk_image"
echo "sbom: $output_directory/greenbubbles-sbom.json"
