#!/bin/zsh
# Regenerate the app icon from make-icon.swift into the asset catalog.
# The generated PNGs are committed, so a normal build never needs this.
set -e
cd "$(dirname "$0")/.."

BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT

swiftc -O scripts/make-icon.swift -o "$BUILD/make-icon"
"$BUILD/make-icon" "$BUILD/icon-1024.png"

SET="App/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$SET"
cp "$BUILD/icon-1024.png" assets-icon-preview.png 2>/dev/null || true
images=""
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    px=$((size * scale))
    name="icon_${size}x${size}@${scale}x.png"
    sips -z $px $px "$BUILD/icon-1024.png" --out "$SET/$name" >/dev/null
    images+="    { \"idiom\": \"mac\", \"size\": \"${size}x${size}\", \"scale\": \"${scale}x\", \"filename\": \"$name\" },\n"
  done
done
printf '{\n  "images": [\n%b  ],\n  "info": { "author": "xcode", "version": 1 }\n}\n' "${images%,\\n}\n" | sed 's/},\n  ]/}\n  ]/' > "$SET/Contents.json"
printf '{\n  "info": { "author": "xcode", "version": 1 }\n}\n' > App/Assets.xcassets/Contents.json
rm -f assets-icon-preview.png
echo "wrote $SET"
