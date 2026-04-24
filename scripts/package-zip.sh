#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="ClawdPal.app"
ZIP_PATH="$DIST_DIR/ClawdPal.zip"
BUILT_APP="$ROOT_DIR/.build/$APP_NAME"

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/build-app.sh"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

ditto -c -k --sequesterRsrc --keepParent "$BUILT_APP" "$ZIP_PATH"

echo "Packaged $ZIP_PATH"
