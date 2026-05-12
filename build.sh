#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeUsageWidget"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
BIN_DIR="$CONTENTS_DIR/MacOS"
RES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$BIN_DIR" "$RES_DIR"

echo "→ Compiling Swift…"
swiftc -O -parse-as-library -o "$BIN_DIR/$APP_NAME" Sources/main.swift -framework Cocoa

echo "→ Copying localization bundles…"
for lproj in Resources/*.lproj; do
  cp -R "$lproj" "$RES_DIR/"
done

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClaudeUsageWidget</string>
  <key>CFBundleDisplayName</key><string>Claude Usage</string>
  <key>CFBundleIdentifier</key><string>app.claude-usage-widget</string>
  <key>CFBundleVersion</key><string>1.0.0</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleExecutable</key><string>ClaudeUsageWidget</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>tr</string>
    <string>de</string>
    <string>es</string>
    <string>fr</string>
  </array>
</dict>
</plist>
PLIST

echo "✓ Built: $APP_DIR"
echo "  Run:   open $APP_DIR"
