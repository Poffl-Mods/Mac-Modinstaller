#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="$PWD/dist/Mac-ModInstaller.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/RogueModInstaller "$APP/Contents/MacOS/RogueModInstaller"
# SwiftPM resource bundle, when supplied by ZIPFoundation.
for bundle in .build/release/*.bundle; do
  if [ -d "$bundle" ]; then cp -R "$bundle" "$APP/Contents/Resources/"; fi
done
if [ -f "$APP/Contents/Resources/ZIPFoundation-LICENSE.txt" ]; then chmod u+w "$APP/Contents/Resources/ZIPFoundation-LICENSE.txt"; fi
cp .build/checkouts/ZIPFoundation/LICENSE "$APP/Contents/Resources/ZIPFoundation-LICENSE.txt"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RogueModInstaller</string>
<key>CFBundleIdentifier</key><string>de.poffl.roguemods</string>
<key>CFBundleName</key><string>Mac-ModInstaller</string>
<key>CFBundleDisplayName</key><string>Mac-ModInstaller</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>de</string><string>fr</string><string>es</string><string>ru</string><string>zh-Hans</string></array>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>Mod ZIP</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>LSItemContentTypes</key><array><string>public.zip-archive</string></array>
</dict></array>
</dict></plist>
PLIST
if [ -f AppIcon.icns ]; then cp AppIcon.icns "$APP/Contents/Resources/"; fi
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$APP"
