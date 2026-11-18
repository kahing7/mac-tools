#!/bin/zsh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/PerfBar.app"
# 自动探测可用工具链：优先正式版 Xcode，其次 Xcode-beta，最后回退 CLT
if [ -d "/Applications/Xcode.app" ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
elif [ -d "/Applications/Xcode-beta.app" ]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 应用图标（如存在 Resources/AppIcon.icns 则打包）
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

xcrun --sdk macosx swiftc -O \
  "$ROOT"/Sources/Metrics.swift \
  "$ROOT"/Sources/Sparkline.swift \
  "$ROOT"/Sources/BarPanel.swift \
  "$ROOT"/Sources/AppDelegate.swift \
  "$ROOT"/Sources/main.swift \
  -o "$APP/Contents/MacOS/PerfBar" \
  -framework AppKit -framework IOKit

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.local.perfbar</string>
    <key>CFBundleName</key>
    <string>PerfBar</string>
    <key>CFBundleDisplayName</key>
    <string>PerfBar</string>
    <key>CFBundleExecutable</key>
    <string>PerfBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force -s - "$APP"
echo "Build OK: $APP"
