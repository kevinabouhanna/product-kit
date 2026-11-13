#!/bin/bash
# Builds the test app for the iPhone and iPad simulator with swiftc alone, no Xcode project:
# build.sh <folder> writes <folder>/ShotsTest.app (#43).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="${1:?usage: build.sh <folder>}/ShotsTest.app"
rm -rf "$out"
mkdir -p "$out/en.lproj" "$out/ar.lproj"
xcrun --sdk iphonesimulator swiftc -parse-as-library -target "$(uname -m)-apple-ios17.0-simulator" \
  "$here/App.swift" -o "$out/ShotsTest"
cat >"$out/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.example.ShotsTest</string>
  <key>CFBundleExecutable</key><string>ShotsTest</string>
  <key>CFBundleName</key><string>ShotsTest</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ar</string></array>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>UILaunchScreen</key><dict/>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><true/></dict>
</dict></plist>
EOF
printf '"Home" = "Home";\n"Sync" = "Sync";\n"Items" = "Items";\n"Item" = "Item";\n' >"$out/en.lproj/Localizable.strings"
printf '"Home" = "الرئيسية";\n"Sync" = "مزامنة";\n"Items" = "العناصر";\n"Item" = "عنصر";\n' >"$out/ar.lproj/Localizable.strings"
codesign -s - --force "$out" >/dev/null 2>&1
echo "$out"
