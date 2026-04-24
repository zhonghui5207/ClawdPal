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

cp "$BIN_DIR/ClawdPetApp" "$MACOS_DIR/ClawdPetApp"
cp "$BIN_DIR/ClawdPetHooks" "$MACOS_DIR/ClawdPetHooks"
cp "$BIN_DIR/ClawdPetSetup" "$MACOS_DIR/ClawdPetSetup"

if [ -d "$BIN_DIR/ClawdPet_ClawdPetApp.bundle" ]; then
  cp -R "$BIN_DIR/ClawdPet_ClawdPetApp.bundle" "$APP_DIR/ClawdPet_ClawdPetApp.bundle"
  cp -R "$BIN_DIR/ClawdPet_ClawdPetApp.bundle/Resources" "$RESOURCES_DIR/ClawdPetResources"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>ClawdPetApp</string>
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

chmod +x "$MACOS_DIR/ClawdPetApp" "$MACOS_DIR/ClawdPetHooks" "$MACOS_DIR/ClawdPetSetup"

echo "Built $APP_DIR"
