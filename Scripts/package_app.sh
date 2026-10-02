#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Codex-Usage"
EXEC_NAME="CodexUsage"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="${CODEX_USAGE_OUTPUT_DIR:-$ROOT_DIR}/$APP_NAME.app"
ICON_PATH="$ROOT_DIR/Assets/AppIcon.icns"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$EXEC_NAME" "$APP_DIR/Contents/MacOS/$EXEC_NAME"
cp "$ICON_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp -R "$BUILD_DIR/Codex-Usage_CodexUsageAutomation.bundle" "$APP_DIR/Contents/Resources/"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexUsage</string>
  <key>CFBundleIdentifier</key>
  <string>dev.codex-usage.app</string>
  <key>CFBundleName</key>
  <string>Codex-Usage</string>
  <key>CFBundleDisplayName</key>
  <string>Codex-Usage</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>0.4.0</string>
  <key>CFBundleVersion</key>
  <string>12</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --sign "${CODEX_USAGE_SIGN_IDENTITY:--}" "$APP_DIR"
echo "Built $APP_DIR"
