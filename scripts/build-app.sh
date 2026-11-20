#!/bin/sh
# Builds Freeroom.app (menu bar app + embedded freeroom CLI) into ./build.
# Usage: scripts/build-app.sh [--install]   (--install copies it to ~/Applications)
set -eu
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/FreeroomCore/Version.swift)
APP=build/Freeroom.app

swift build -c release --product FreeroomApp
swift build -c release --product freeroom
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/FreeroomApp" "$APP/Contents/MacOS/Freeroom"
cp "$BIN/freeroom" "$APP/Contents/Helpers/freeroom"

# Brand logos (Simple Icons, CC0) used by the icon resolver; bundled so nothing is fetched at runtime.
mkdir -p "$APP/Contents/Resources/BrandIcons"
cp design/catalog-icons/*.svg design/catalog-icons/LICENSE-simple-icons.md "$APP/Contents/Resources/BrandIcons/"

# App icon from the design master
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size design/assets/freeroom-icon-light.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double design/assets/freeroom-icon-light.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Freeroom</string>
  <key>CFBundleDisplayName</key><string>Freeroom</string>
  <key>CFBundleIdentifier</key><string>co.hblabs.freeroom</string>
  <key>CFBundleExecutable</key><string>Freeroom</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 hblabs · MIT License</string>
</dict>
</plist>
PLIST

# Ad-hoc signature for local use. Releases are signed with a Developer ID and notarized.
codesign --force --sign - "$APP/Contents/Helpers/freeroom"
codesign --force --sign - "$APP"

echo "Built $APP ($VERSION)"
if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Freeroom.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to ~/Applications/Freeroom.app"
fi
