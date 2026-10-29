#!/bin/zsh
# Builds Redline.app (Apple Silicon + Intel) and a drag-to-install DMG in dist/.
#   ./build.sh           build app + DMG
#   ./build.sh install   also install to /Applications and launch
set -euo pipefail
cd "${0:A:h}"

VERSION=1.0
APP=build/Redline.app
rm -rf build dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist

# Universal binary: compile per architecture, then merge.
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library \
    -target "$arch-apple-macos14.0" \
    -import-objc-header Sources/Bridge.h \
    Sources/*.swift \
    -framework IOKit \
    -o "build/Redline-$arch"
done
lipo -create build/Redline-arm64 build/Redline-x86_64 -output "$APP/Contents/MacOS/Redline"

# App icon from the 1024px master.
ICONSET=build/Redline.iconset
mkdir -p "$ICONSET"
for px in 16 32 128 256 512; do
  sips -z $px $px Resources/icon-1024.png --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
  sips -z $((px * 2)) $((px * 2)) Resources/icon-1024.png --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Redline</string>
  <key>CFBundleDisplayName</key><string>Redline</string>
  <key>CFBundleIdentifier</key><string>com.nik.redline</string>
  <key>CFBundleExecutable</key><string>Redline</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

# DMG with an Applications shortcut to drag onto.
STAGE=build/dmg
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Redline" -srcfolder "$STAGE" -ov -format UDZO "dist/Redline-$VERSION.dmg"
echo "Built dist/Redline-$VERSION.dmg"

if [[ "${1:-}" == "install" ]]; then
  pkill -x Redline 2>/dev/null || true
  rm -rf /Applications/Redline.app
  cp -R "$APP" /Applications/
  open /Applications/Redline.app
  echo "Installed /Applications/Redline.app"
fi
