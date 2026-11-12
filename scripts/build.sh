#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app="build/Mac Proxy Switcher.app"
executable="$app/Contents/MacOS/MacProxySwitcher"
mkdir -p "$app/Contents/MacOS"
cp Resources/Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"

sdk="$(xcrun --sdk macosx --show-sdk-path)"
for architecture in arm64 x86_64; do
    xcrun swiftc -sdk "$sdk" -target "$architecture-apple-macos13.0" \
        -swift-version 5 -O -parse-as-library Sources/*.swift \
        -o "build/MacProxySwitcher-$architecture"
done

xcrun lipo -create build/MacProxySwitcher-arm64 build/MacProxySwitcher-x86_64 -output "$executable"
xcrun lipo "$executable" -verify_arch arm64 x86_64
codesign --force --sign - "$app"
codesign --verify --strict --verbose=2 "$app"

(
    cd build
    ditto -c -k --keepParent "Mac Proxy Switcher.app" Mac-Proxy-Switcher-macOS-universal.zip
    shasum -a 256 Mac-Proxy-Switcher-macOS-universal.zip > SHA256SUMS.txt
)
