#!/usr/bin/env bash
set -euo pipefail

APP_NAME="WorktreeDesk"
BUNDLE_ID="com.gtsifrikas.worktreedesk"
VERSION="0.1.0"
DEST_APP_PATH="${1:-/Applications/${APP_NAME}.app}"
APP_ICON_NAME="AppIcon"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ICON_SCRIPT="$SCRIPT_DIR/build_app_icon.sh"
ICON_ICNS_PATH="$REPO_ROOT/assets/${APP_ICON_NAME}.icns"

printf "Building %s (release)...\n" "$APP_NAME"
swift build -c release --package-path "$REPO_ROOT"

BINARY_PATH=""
for candidate in \
  "$REPO_ROOT/.build/arm64-apple-macosx/release/$APP_NAME" \
  "$REPO_ROOT/.build/x86_64-apple-macosx/release/$APP_NAME"; do
  if [[ -x "$candidate" ]]; then
    BINARY_PATH="$candidate"
    break
  fi
done

if [[ -z "$BINARY_PATH" ]]; then
  BINARY_PATH="$(find "$REPO_ROOT/.build" -type f -path "*/release/${APP_NAME}" -print -quit 2>/dev/null || true)"
fi

if [[ -z "$BINARY_PATH" || ! -x "$BINARY_PATH" ]]; then
  echo "Could not locate release binary for ${APP_NAME}."
  exit 1
fi

DIST_DIR="$REPO_ROOT/.dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ -x "$ICON_SCRIPT" ]]; then
  printf "Generating app icon...\n"
  "$ICON_SCRIPT"
fi

if [[ -f "$ICON_ICNS_PATH" ]]; then
  cp "$ICON_ICNS_PATH" "$APP_BUNDLE/Contents/Resources/${APP_ICON_NAME}.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>${APP_ICON_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

printf "Installing %s to %s ...\n" "$APP_NAME" "$DEST_APP_PATH"
mkdir -p "$(dirname "$DEST_APP_PATH")"
rm -rf "$DEST_APP_PATH"
ditto "$APP_BUNDLE" "$DEST_APP_PATH"

printf "Installed: %s\n" "$DEST_APP_PATH"
open "$DEST_APP_PATH"
