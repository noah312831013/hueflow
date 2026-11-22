#!/bin/sh
# Builds the native app and its screen saver with swiftc (no Xcode project needed), universal, signed ad hoc:
#   build/Hueflow.app  (contains Resources/Hueflow.saver, installed from the app's screen saver popover)
#   build/Hueflow.zip  (attach to a GitHub release; the website links to the latest one)
# For signed builds set DEVELOPER_ID="Developer ID Application: Name (TEAMID)" and, to notarize,
# NOTARY_PROFILE=<name saved with `xcrun notarytool store-credentials`>. Without them it signs ad hoc: other Macs must
# allow it once in System Settings › Privacy & Security (see README).
set -e
cd "$(dirname "$0")"
IDENTITY="${DEVELOPER_ID:--}"
sign() {
  if [ "$IDENTITY" = "-" ]; then codesign --force --sign - "$1"
  else codesign --force --timestamp --options runtime --sign "$IDENTITY" "$1"; fi
}
OUT=build
APP="$OUT/Hueflow.app"
SAVER="$OUT/Hueflow.saver"
rm -rf "$OUT" && mkdir -p "$OUT/tmp"
SDK=$(xcrun --sdk macosx --show-sdk-path)

for arch in arm64 x86_64; do
  xcrun swiftc -O -sdk "$SDK" -target $arch-apple-macos14.0 -module-name Hueflow \
    Shared/*.swift App/*.swift -o "$OUT/tmp/app-$arch"
  xcrun swiftc -O -sdk "$SDK" -target $arch-apple-macos13.0 -module-name HueflowSaver \
    -emit-library -Xlinker -bundle Shared/*.swift Saver/*.swift -o "$OUT/tmp/saver-$arch"
done

mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"
cp Saver/Info.plist "$SAVER/Contents/"
lipo -create "$OUT"/tmp/saver-* -output "$SAVER/Contents/MacOS/Hueflow"
sign "$SAVER"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp App/Info.plist "$APP/Contents/"
cp App/Hueflow.icns "$APP/Contents/Resources/"
lipo -create "$OUT"/tmp/app-* -output "$APP/Contents/MacOS/Hueflow"
cp -R "$SAVER" "$APP/Contents/Resources/"
sign "$APP"
rm -rf "$OUT/tmp"
ditto -c -k --keepParent "$APP" "$OUT/Hueflow.zip"
if [ -n "$NOTARY_PROFILE" ]; then
  xcrun notarytool submit "$OUT/Hueflow.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$OUT/Hueflow.zip" && ditto -c -k --keepParent "$APP" "$OUT/Hueflow.zip"
fi
echo "built $APP and $OUT/Hueflow.zip"
