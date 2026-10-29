#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/MusicBar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -Onone -target "$(uname -m)-apple-macos13.0" Source/*.swift -o "$APP/Contents/MacOS/MusicBar" -framework AppKit -framework CoreAudio
cp Source/Info.plist "$APP/Contents/Info.plist"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/MusicBar" --self-test
