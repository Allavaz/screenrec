#!/bin/bash
# Builds ScreenRec and wraps it in a minimal .app bundle so macOS grants
# screen recording permission to the app itself (not to Terminal).
set -euo pipefail
cd "$(dirname "$0")"

echo "Building (release)…"
swift build -c release

APP="build/ScreenRec.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ScreenRec "$APP/Contents/MacOS/ScreenRec"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ScreenRec</string>
    <key>CFBundleDisplayName</key>
    <string>ScreenRec</string>
    <key>CFBundleIdentifier</key>
    <string>com.david.screenrec</string>
    <key>CFBundleExecutable</key>
    <string>ScreenRec</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc signature so TCC (Privacy & Security) identifies the bundle cleanly.
codesign --force --sign - "$APP"

echo "✅ Built $APP"
echo "   Run it with: open $APP"
