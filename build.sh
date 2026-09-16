#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeUsageWidget"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
BIN_DIR="$CONTENTS_DIR/MacOS"
RES_DIR="$CONTENTS_DIR/Resources"

# Version comes from the release tag (CI) or the latest git tag (local builds),
# so the in-app update checker compares against the real version.
if [[ "${GITHUB_REF_NAME:-}" == v* ]]; then
  VERSION="$GITHUB_REF_NAME"
else
  VERSION="$(git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)"
fi
VERSION="${VERSION#v}"

rm -rf "$APP_DIR"
mkdir -p "$BIN_DIR" "$RES_DIR"

echo "→ Compiling Swift…"
swiftc -O -parse-as-library -o "$BIN_DIR/$APP_NAME" Sources/*.swift -framework Cocoa -framework UserNotifications -framework Carbon

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
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
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

# Stable signature: ad-hoc cdhash changes every build, so macOS privacy grants
# (Full Disk Access / App Data) would be lost after each rebuild.
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | sed -E 's/.*"(.*)"/\1/' || true)
if [[ -n "$IDENTITY" ]]; then
  echo "→ Signing with: $IDENTITY"
  codesign --force --deep --options runtime --sign "$IDENTITY" "$APP_DIR"
fi

echo "✓ Built: $APP_DIR"
echo "  Run:   open $APP_DIR"
