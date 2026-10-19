#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/dist/Mac-ModInstaller.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid application version' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/RogueModInstaller")
[[ "$ARCHS" == arm64 ]] || { echo "Expected arm64 build, got $ARCHS" >&2; exit 1; }
STAGE=$(mktemp -d "$PWD/dist/.release-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
NAME="Mac-ModInstaller-$VERSION"
mkdir "$STAGE/$NAME"
ditto --norsrc "$APP" "$STAGE/$NAME/Mac-ModInstaller.app"
cp README.txt LICENSE THIRD-PARTY-NOTICES.txt "$STAGE/$NAME/"
cp -R LICENSES "$STAGE/$NAME/"
ZIP="$PWD/dist/$NAME-macOS-arm64.zip"
ditto -c -k --norsrc --keepParent "$STAGE/$NAME" "$ZIP"
unzip -tq "$ZIP"
(cd dist && shasum -a 256 "$NAME-macOS-arm64.zip" > SHA256SUMS.txt)
printf 'Packaged: %s\n' "$ZIP"
