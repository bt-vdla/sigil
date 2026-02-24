#!/usr/bin/env bash
# scripts/make-dmg.sh — Build Sigil.app (Release) and package it into a DMG.
#
# Prerequisites:
#   • Xcode command-line tools (xcodebuild must be on PATH)
#   • Development Team set in Xcode, or pass TEAM_ID below for ad-hoc builds
#   • Optional: brew install create-dmg  (for a polished DMG with background)
#
# Usage:
#   ./scripts/make-dmg.sh              # default — uses signing identity from Xcode
#   ./scripts/make-dmg.sh --unsigned   # skip code signing (for local testing only)

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
SCHEME="Sigil"
CONFIGURATION="Release"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/dist"
DERIVED_DATA="$BUILD_DIR/DerivedData"
ARCHIVE_PATH="$BUILD_DIR/Sigil.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/Sigil.dmg"
APP_NAME="Sigil.app"

UNSIGNED=false
for arg in "$@"; do
  [[ "$arg" == "--unsigned" ]] && UNSIGNED=true
done

# ── Clean previous artifacts ──────────────────────────────────────────────────
echo "🧹  Cleaning dist/…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Archive ───────────────────────────────────────────────────────────────────
echo "🔨  Archiving $SCHEME ($CONFIGURATION)…"

if $UNSIGNED; then
  # Ad-hoc signing — no Developer ID required
  xcodebuild archive \
    -project "$PROJECT_ROOT/Sigil.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="" \
    | xcpretty 2>/dev/null || true
else
  # Automatic signing with Developer ID
  xcodebuild archive \
    -project "$PROJECT_ROOT/Sigil.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Automatic \
    | xcpretty 2>/dev/null || true
fi

# ── Export ────────────────────────────────────────────────────────────────────
echo "📦  Exporting archive…"

if $UNSIGNED; then
  # Ad-hoc export — no Developer ID required; Gatekeeper will block on other Macs
  cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>mac-application</string>
    <key>signingStyle</key><string>manual</string>
    <key>stripSwiftSymbols</key><true/>
</dict>
</plist>
PLIST
else
  # Developer ID export — requires Apple Developer account + Developer ID cert
  cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>automatic</string>
    <key>stripSwiftSymbols</key><true/>
</dict>
</plist>
PLIST
fi

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  | xcpretty 2>/dev/null || true

APP_PATH="$EXPORT_PATH/$APP_NAME"

if [[ ! -d "$APP_PATH" ]]; then
  echo "❌  Export failed — $APP_PATH not found"
  exit 1
fi

# ── Create DMG ────────────────────────────────────────────────────────────────
echo "💿  Creating DMG…"

if command -v create-dmg &>/dev/null; then
  # Polished DMG with custom layout (brew install create-dmg)
  create-dmg \
    --volname "Sigil" \
    --window-pos 200 120 \
    --window-size 540 380 \
    --icon-size 128 \
    --icon "$APP_NAME" 130 190 \
    --hide-extension "$APP_NAME" \
    --app-drop-link 400 190 \
    "$DMG_PATH" \
    "$APP_PATH"
else
  # Fallback: plain DMG via hdiutil
  STAGING="$BUILD_DIR/dmg-staging"
  mkdir -p "$STAGING"
  cp -R "$APP_PATH" "$STAGING/"
  ln -sf /Applications "$STAGING/Applications"

  hdiutil create \
    -volname "Sigil" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

  rm -rf "$STAGING"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✅  Done! DMG at:"
echo "    $DMG_PATH"
echo ""

if $UNSIGNED; then
  echo "⚠️  Built without Developer ID signing."
  echo "   Gatekeeper will block this on other Macs."
  echo "   For distribution, set up a Developer ID cert and run without --unsigned."
fi
