#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build

BIN_DIR="$(swift build --show-bin-path)"
APP_DIR="$ROOT_DIR/.build/ClawdPal.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/ClawdPalApp" "$MACOS_DIR/ClawdPalApp"
cp "$BIN_DIR/ClawdPalHooks" "$MACOS_DIR/ClawdPalHooks"
cp "$BIN_DIR/ClawdPalSetup" "$MACOS_DIR/ClawdPalSetup"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>ClawdPalApp</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>studio.lovexai.ClawdPal</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>ClawdPal</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/ClawdPalApp" "$MACOS_DIR/ClawdPalHooks" "$MACOS_DIR/ClawdPalSetup"

APP_REQUIREMENT='=designated => identifier "studio.lovexai.ClawdPal"'
HOOKS_REQUIREMENT='=designated => identifier "studio.lovexai.ClawdPal.Hooks"'
SETUP_REQUIREMENT='=designated => identifier "studio.lovexai.ClawdPal.Setup"'

codesign --force --sign - --identifier studio.lovexai.ClawdPal --requirements "$APP_REQUIREMENT" "$MACOS_DIR/ClawdPalApp" >/dev/null 2>&1 || true
codesign --force --sign - --identifier studio.lovexai.ClawdPal.Hooks --requirements "$HOOKS_REQUIREMENT" "$MACOS_DIR/ClawdPalHooks" >/dev/null 2>&1 || true
codesign --force --sign - --identifier studio.lovexai.ClawdPal.Setup --requirements "$SETUP_REQUIREMENT" "$MACOS_DIR/ClawdPalSetup" >/dev/null 2>&1 || true

if [ -d "$BIN_DIR/ClawdPal_ClawdPalApp.bundle" ]; then
  cp -R "$BIN_DIR/ClawdPal_ClawdPalApp.bundle" "$APP_DIR/ClawdPal_ClawdPalApp.bundle"
  cp -R "$BIN_DIR/ClawdPal_ClawdPalApp.bundle/Resources" "$RESOURCES_DIR/ClawdPalResources"
fi

cp "$ROOT_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

codesign --force --sign - --identifier studio.lovexai.ClawdPal --requirements "$APP_REQUIREMENT" "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR"
