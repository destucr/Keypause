#!/bin/bash
# Builds Keypause.app into ./dist (menu bar app, no Dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Keypause"

APP="dist/Keypause.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Keypause"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/lottie/*.json "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Keypause</string>
  <key>CFBundleDisplayName</key><string>Keypause</string>
  <key>CFBundleIdentifier</key><string>com.destucr.Keypause</string>
  <key>CFBundleExecutable</key><string>Keypause</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.2</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>com.destucr.Keypause</string>
    <key>CFBundleURLSchemes</key><array><string>keypause</string></array>
  </dict></array>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Sign with a stable identity when one exists (override with SIGN_IDENTITY=...). A stable identity
# lets macOS keep the Accessibility grant across rebuilds and updates; ad-hoc signing cannot.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID Application/{print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --sign "$IDENTITY" "$APP"
  echo "Signed with identity $IDENTITY"
else
  codesign --force --options runtime --sign - "$APP"
  echo "Ad-hoc signed (no signing identity found; permissions reset on every rebuild)"
fi
echo "Built $APP"
