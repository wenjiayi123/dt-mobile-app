#!/usr/bin/env bash
set -euo pipefail

BUILDER_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$BUILDER_DIR/.build"
TARGET_APP="${PORT_DEMO_APP_PATH:-$HOME/Desktop/港航演示中心.app}"
SYSTEMS_DIR="$TARGET_APP/Contents/Resources/Systems"
BUILD_VERSION="${PORT_DEMO_BUILD_VERSION:-$(date +%Y%m%d%H%M%S)}"

mkdir -p "$BUILD_DIR"
/usr/bin/swiftc -O -framework Cocoa -framework WebKit "$BUILDER_DIR/ManagedProcessRuntime.swift" "$BUILDER_DIR/SystemShell.swift" -o "$BUILD_DIR/SystemShell"
/usr/bin/swiftc -O -framework Cocoa "$BUILDER_DIR/ManagedProcessRuntime.swift" "$BUILDER_DIR/ApplicationFreshness.swift" "$BUILDER_DIR/Launcher.swift" -o "$BUILD_DIR/Launcher"
/usr/bin/swiftc -O -framework AppKit "$BUILDER_DIR/IconMaker.swift" -o "$BUILD_DIR/IconMaker"

if [[ -d "$TARGET_APP" ]]; then
  current_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET_APP/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$current_id" != "com.wenjiayi.portdemo.launcher" ]]; then
    echo "Refusing to replace an unrelated app at $TARGET_APP" >&2
    exit 2
  fi
  rm -rf "$TARGET_APP"
fi

mkdir -p "$TARGET_APP/Contents/MacOS" "$TARGET_APP/Contents/Resources" "$SYSTEMS_DIR"
cp "$BUILD_DIR/Launcher" "$TARGET_APP/Contents/MacOS/Launcher"
cp "$BUILDER_DIR/AppInfo.plist" "$TARGET_APP/Contents/Info.plist"
cp "$BUILDER_DIR/使用说明.txt" "$TARGET_APP/Contents/Resources/使用说明.txt"
/usr/bin/plutil -replace CFBundleIdentifier -string "com.wenjiayi.portdemo.launcher" "$TARGET_APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleDisplayName -string "港航演示中心" "$TARGET_APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleName -string "港航演示中心" "$TARGET_APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleExecutable -string "Launcher" "$TARGET_APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$BUILD_VERSION" "$TARGET_APP/Contents/Info.plist"

make_icon() {
  local output="$1"
  local symbol="$2"
  local red="$3"
  local green="$4"
  local blue="$5"
  "$BUILD_DIR/IconMaker" "$output" "$symbol" "$red" "$green" "$blue"
}

make_system() {
  local app_name="$1"
  local bundle_id="$2"
  local config_name="$3"
  local symbol="$4"
  local red="$5"
  local green="$6"
  local blue="$7"
  local app_path="$SYSTEMS_DIR/$app_name.app"
  local url_scheme="xianyi-launch-${config_name}"
  mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
  cp "$BUILD_DIR/SystemShell" "$app_path/Contents/MacOS/SystemShell"
  cp "$BUILDER_DIR/configs/$config_name.json" "$app_path/Contents/Resources/system.json"
  cp "$BUILDER_DIR/AppInfo.plist" "$app_path/Contents/Info.plist"
  /usr/bin/plutil -replace CFBundleIdentifier -string "$bundle_id" "$app_path/Contents/Info.plist"
  /usr/bin/plutil -replace CFBundleDisplayName -string "$app_name" "$app_path/Contents/Info.plist"
  /usr/bin/plutil -replace CFBundleName -string "$app_name" "$app_path/Contents/Info.plist"
  /usr/bin/plutil -replace CFBundleExecutable -string "SystemShell" "$app_path/Contents/Info.plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$BUILD_VERSION" "$app_path/Contents/Info.plist"
  if [[ "$config_name" == "mobile" ]]; then
    /usr/bin/plutil -replace displayURL -string "http://127.0.0.1:8765/?native_build=$BUILD_VERSION" "$app_path/Contents/Resources/system.json"
  fi
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$app_path/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$app_path/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string ${bundle_id}.launcher" "$app_path/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$app_path/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string ${url_scheme}" "$app_path/Contents/Info.plist"
  make_icon "$app_path/Contents/Resources/AppIcon.icns" "$symbol" "$red" "$green" "$blue"
  /usr/bin/codesign --force --sign - "$app_path" >/dev/null
}

make_icon "$TARGET_APP/Contents/Resources/AppIcon.icns" "square.grid.2x2.fill" 0.10 0.56 0.98
make_system "PortAI移动端" "com.wenjiayi.portdemo.mobile" "mobile" "iphone.gen3" 0.21 0.67 1.0
make_system "港口数字孪生V3.2" "com.wenjiayi.portdemo.digitaltwin" "port" "shippingbox.fill" 0.22 0.83 0.73
make_system "马六甲港口推演" "com.wenjiayi.portdemo.malacca" "malacca" "map.fill" 1.0 0.59 0.24
make_system "航行模拟器" "com.wenjiayi.portdemo.sailing" "sailing" "ferry.fill" 0.47 0.58 1.0
make_system "能碳驾驶舱" "com.wenjiayi.portdemo.energy" "energy" "leaf.fill" 0.42 0.88 0.38
make_system "舷鸥 · GullMate" "com.wenjiayi.portdemo.xiaoyi" "xiaoyi" "sparkles" 0.92 0.43 1.0

/usr/bin/codesign --force --deep --sign - "$TARGET_APP" >/dev/null
/usr/bin/touch "$TARGET_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET_APP" >/dev/null 2>&1 || true
for system_app in "$SYSTEMS_DIR"/*.app; do
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$system_app" >/dev/null 2>&1 || true
done

echo "$TARGET_APP"
