#!/bin/zsh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/PerfBar.app"
# 用 Xcode-beta 工具链（CLT 的 SDK 与编译器版本不匹配）
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

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
    <key>CFBundleExecutable</key>
    <string>PerfBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force -s - "$APP"
echo "Build OK: $APP"
