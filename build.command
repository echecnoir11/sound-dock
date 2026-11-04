#!/bin/zsh
set -eu
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swift build -c release --disable-sandbox --build-system native
app="$PWD/outputs/++sound@dock.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/SoundDock "$app/Contents/MacOS/SoundDock"
cp -R Resources/ "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SoundDock</string>
<key>CFBundleIdentifier</key><string>audio.sounddock.ennuienoir</string>
<key>CFBundleName</key><string>++sound@dock</string>
<key>CFBundleDisplayName</key><string>++sound@dock</string>
<key>CFBundleIconFile</key><string>SoundDock.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>11</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>++sound@dock reçoit uniquement le flux du périphérique virtuel BlackHole pour appliquer les effets en direct. Aucun enregistrement n’est effectué.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$app"
codesign --force --sign - "$app"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$PWD/outputs/++sound@dock-V2.0-macOS.zip"
printf '\nApplication créée : %s\n' "$app"
