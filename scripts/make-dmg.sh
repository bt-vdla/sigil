#!/usr/bin/env bash
# scripts/make-dmg.sh — Build Sigil.app (Release) and write Sigil.dmg to the repo root.
#
# Needs Xcode. Uses create-dmg (npm i -g create-dmg) for the polished layout when
# it's installed, and falls back to a plain hdiutil image.
#
# Usage:
#   ./scripts/make-dmg.sh             # Developer ID signed; needs that certificate
#   ./scripts/make-dmg.sh --unsigned  # ad-hoc signed; Gatekeeper warns on other Macs

set -euo pipefail

SCHEME="Sigil"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Outside the repo: iCloud-synced folders add attributes that make code signing fail
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
ARCHIVE_PATH="$BUILD_DIR/Sigil.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_PATH="$PROJECT_ROOT/Sigil.dmg"

UNSIGNED=false
for arg in "$@"; do
  [[ "$arg" == "--unsigned" ]] && UNSIGNED=true
done

mkdir -p "$EXPORT_PATH"

echo "Archiving $SCHEME…"
SIGNING=(CODE_SIGN_STYLE=Automatic)
if $UNSIGNED; then
  SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi
xcodebuild archive \
  -project "$PROJECT_ROOT/Sigil.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -quiet \
  "${SIGNING[@]}"

if $UNSIGNED; then
  cp -R "$ARCHIVE_PATH/Products/Applications/Sigil.app" "$EXPORT_PATH/"
else
  cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -quiet
fi

APP_PATH="$EXPORT_PATH/Sigil.app"
rm -f "$DMG_PATH"

echo "Creating DMG…"
if command -v create-dmg &>/dev/null; then
  DMG_ARGS=(--overwrite --dmg-title "Sigil")
  $UNSIGNED && DMG_ARGS+=(--no-code-sign)
  # create-dmg can exit non-zero over signing alone, so check for the image instead
  create-dmg "${DMG_ARGS[@]}" "$APP_PATH" "$BUILD_DIR" || true
  mv "$BUILD_DIR"/Sigil*.dmg "$DMG_PATH"
else
  STAGING="$BUILD_DIR/dmg-staging"
  mkdir -p "$STAGING"
  cp -R "$APP_PATH" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "Sigil" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
fi

echo "Done: $DMG_PATH"
if $UNSIGNED; then
  echo "Ad-hoc signed: Gatekeeper asks people to approve it in System Settings the first time."
fi
