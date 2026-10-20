#!/bin/zsh
# Builds OpenRelay.app for armv7 / iOS 4.3 using the stubbed iPhoneOS 4.3 SDK, packages an IPA.
set -e
cd "$(dirname "$0")"
SDK=/Users/mshukla/ios4sdk/iPhoneOS4.3.sdk
APP=NextTrain
OUT=build
rm -rf "$OUT" && mkdir -p "$OUT/obj" "$OUT/Payload/$APP.app"
CFLAGS=(-target armv7-apple-ios4.3 -isysroot "$SDK" -fobjc-runtime=ios-4.3 -fno-objc-arc -marm -O2 -Wall -Wno-deprecated-declarations -Wno-unused-but-set-variable)
for f in src/*.m; do
  clang "${CFLAGS[@]}" -c "$f" -o "$OUT/obj/$(basename "${f%.m}").o"
done
clang -target armv7-apple-ios4.3 -isysroot "$SDK" "$OUT"/obj/*.o -o "$OUT/Payload/$APP.app/$APP" \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework AudioToolbox -lobjc -lz 2>&1 | grep -v 'no platform load command' || true
test -f "$OUT/Payload/$APP.app/$APP"
cp -R res/Settings.bundle "$OUT/Payload/$APP.app/" 2>/dev/null; cp res/sat-*.jpg "$OUT/Payload/$APP.app/"
cp res/Icon.png res/Icon@2x.png res/tab-*.png res/logo-*.png res/caltrain.json res/bart.json res/muni_stops.json res/bay.json res/track.json res/bart_map.json res/muni_metro.json "$OUT/Payload/$APP.app/"
cat > "$OUT/Payload/$APP.app/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleDisplayName</key><string>Next Train</string>
<key>CFBundleExecutable</key><string>$APP</string>
<key>CFBundleIconFiles</key><array><string>Icon.png</string><string>Icon@2x.png</string></array>
<key>CFBundleIdentifier</key><string>com.mshukla.nexttrain</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>Next Train</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>MinimumOSVersion</key><string>4.3</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UIStatusBarStyle</key><string>UIStatusBarStyleBlackOpaque</string>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
</dict></plist>
PL
plutil -convert binary1 "$OUT/Payload/$APP.app/Info.plist"
ldid -S "$OUT/Payload/$APP.app/$APP"
(cd "$OUT" && rm -f "$APP.ipa" && zip -qr "$APP.ipa" Payload)
ls -la "$OUT/$APP.ipa"
file "$OUT/Payload/$APP.app/$APP"
