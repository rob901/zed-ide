#!/bin/zsh
# Builds the customized Zed and packages it as "Zed Tabs.app", a separate
# application that can run side by side with the regular Zed install.
#
#   script/build-zed-tabs.sh            build + package + install to /Applications
#   script/build-zed-tabs.sh --no-build package the existing release binary only
#
# The app uses Zed's "dev" release channel: its own bundle id
# (dev.zed.Zed-Dev) and its own workspace/thread database, separate from
# regular Zed. Settings (~/.config/zed), keymaps and installed extensions
# are shared with the regular install.
set -euo pipefail

ZED_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Zed Tabs"
INSTALL_DIR="/Applications"
APP="$INSTALL_DIR/$APP_NAME.app"
CARGO="$HOME/.cargo/bin/cargo"

cd "$ZED_DIR"

if [[ "${1:-}" != "--no-build" ]]; then
  # runtime_shaders compiles Metal shaders at launch, so full Xcode isn't needed.
  "$CARGO" build --release -p zed --features gpui_platform/runtime_shaders
fi

BIN="$ZED_DIR/target/release/zed"
[[ -x "$BIN" ]] || { echo "missing $BIN" >&2; exit 1; }

STAGE="$(mktemp -d)/$APP_NAME.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/zed"
cp crates/zed/resources/Document.icns "$STAGE/Contents/Resources/Document.icns"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size crates/zed/resources/app-icon-dev@2x.png \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) crates/zed/resources/app-icon-dev@2x.png \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$STAGE/Contents/Resources/AppIcon.icns"

VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' crates/zed/Cargo.toml | head -1)"
cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>zed</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>dev.zed.Zed-Dev</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
$(cat crates/zed/resources/info/Permissions.plist)
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$STAGE" >/dev/null 2>&1

if [[ -d "$APP" ]]; then
  # Only ever replace our own custom bundle, never the regular Zed.app.
  [[ "$(defaults read "$APP/Contents/Info" CFBundleName)" == "$APP_NAME" ]] \
    || { echo "refusing to overwrite $APP" >&2; exit 1; }
  rm -rf "$APP"
fi
mv "$STAGE" "$APP"
echo "Installed $APP"
