#!/bin/zsh
# Build notchshelf.app into the repo root. Used by install.sh and by CI.
#
# Xcode builds unsigned; this script signs afterwards, inside-out, the way
# Sparkle's docs prescribe for its nested XPC services and helper app.
set -e
cd "$(dirname "$0")/.."

source ./sign-identity.sh

xcodegen generate --quiet

xcodebuild build \
  -project notchshelf.xcodeproj \
  -scheme notchshelf \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  -quiet

rm -rf notchshelf.app
cp -R build/DerivedData/Build/Products/Release/notchshelf.app .

APP=notchshelf.app
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign() { codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$@"; }
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --entitlements notchshelf.entitlements "$APP"

codesign --verify --deep --strict "$APP"
echo "built $APP (signed by: $IDENTITY)"
