#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${CLAWDPAL_INSTALL_DIR:-$HOME/Applications}"
APP_NAME="ClawdPal.app"
BUILT_APP="$ROOT_DIR/.build/$APP_NAME"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"
SETUP_BIN="$INSTALLED_APP/Contents/MacOS/ClawdPalSetup"
HOOK_BIN="$INSTALLED_APP/Contents/MacOS/ClawdPalHooks"

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/build-app.sh"

mkdir -p "$INSTALL_DIR"

pkill -x ClawdPalApp >/dev/null 2>&1 || true
rm -rf "$INSTALLED_APP"
ditto "$BUILT_APP" "$INSTALLED_APP"

"$SETUP_BIN" install-all --hook "$HOOK_BIN"

open "$INSTALLED_APP"

echo "Installed $INSTALLED_APP"
