#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64
APP=build/Kurenai.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Kurenai" "$APP/Contents/MacOS/Kurenai"
cp Icon/Kurenai.icns "$APP/Contents/Resources/Kurenai.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.clippo</string>
  <key>CFBundleName</key><string>Kurenai</string>
  <key>CFBundleExecutable</key><string>Kurenai</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>Kurenai</string>
  <key>CFBundleShortVersionString</key><string>0.4.0</string>
  <key>CFBundleVersion</key><string>10</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string><string>zh-Hans</string></array>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Kurenai contributors. MIT License.</string>
</dict></plist>
PLIST
# A stable self-signed identity keeps the Accessibility grant across rebuilds; without one, sign ad-hoc
# (then macOS asks for Accessibility again after every build).
IDENTITY="Clipo Local Signing"
security find-identity -p codesigning | grep -q "\"$IDENTITY\"" || IDENTITY="-"
codesign --force --sign "$IDENTITY" --identifier app.clippo "$APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x Kurenai || true
  pkill -x Clippo || true
  pkill -x Clipo || true
  rm -rf /Applications/Kurenai.app /Applications/Clippo.app /Applications/Clipo.app # old names
  ditto "$APP" /Applications/Kurenai.app
  open /Applications/Kurenai.app
fi

if [[ "${1:-}" == "zip" ]]; then
  ditto -c -k --keepParent "$APP" build/Kurenai.zip
  # Clippo 0.3.x looks for Clippo.zip with Clippo.app inside; the new app renames itself on first launch.
  rm -rf build/legacy && mkdir -p build/legacy && ditto "$APP" build/legacy/Clippo.app
  ditto -c -k --keepParent build/legacy/Clippo.app build/Clippo.zip
  echo "build/Kurenai.zip build/Clippo.zip"
fi
