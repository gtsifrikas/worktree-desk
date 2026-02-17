#!/usr/bin/env bash
set -euo pipefail

APP_ICON_NAME="AppIcon"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSET_DIR="$REPO_ROOT/assets"
DIST_DIR="$REPO_ROOT/.dist"

BASE_PNG="$ASSET_DIR/${APP_ICON_NAME}-1024.png"
ICONSET_DIR="$DIST_DIR/${APP_ICON_NAME}.iconset"
ICNS_PATH="$ASSET_DIR/${APP_ICON_NAME}.icns"

mkdir -p "$ASSET_DIR"
mkdir -p "$DIST_DIR"

"$SCRIPT_DIR/generate_app_icon.swift" "$BASE_PNG"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

make_icon() {
  local size="$1"
  local out="$2"
  sips -s format png -z "$size" "$size" "$BASE_PNG" --out "$out" >/dev/null
}

make_icon 16 "$ICONSET_DIR/icon_16x16.png"
make_icon 32 "$ICONSET_DIR/icon_16x16@2x.png"
make_icon 32 "$ICONSET_DIR/icon_32x32.png"
make_icon 64 "$ICONSET_DIR/icon_32x32@2x.png"
make_icon 128 "$ICONSET_DIR/icon_128x128.png"
make_icon 256 "$ICONSET_DIR/icon_128x128@2x.png"
make_icon 256 "$ICONSET_DIR/icon_256x256.png"
make_icon 512 "$ICONSET_DIR/icon_256x256@2x.png"
make_icon 512 "$ICONSET_DIR/icon_512x512.png"
make_icon 1024 "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "Generated icns: $ICNS_PATH"
