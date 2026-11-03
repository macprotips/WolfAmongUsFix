#!/bin/bash
# Builds "Wolf Among Us Trail Fix.app" (and a zip of it) into ./build.
#
#   ./build-app.sh
#   VERSION=1.1 ./build-app.sh
#   SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=notary VERSION=1.1 ./build-app.sh   (release)
#
# NOTARY_PROFILE is a `xcrun notarytool store-credentials` keychain profile: the zip is sent to
# Apple's notary service, and the ticket stapled to the app before it's zipped again.
#
# Apple Silicon only, like D3DMetal. The fix's d3d11.dll comes from ../prebuilt (built from ../fix by ../build.sh). No game files go in the app.
set -euo pipefail
cd "$(dirname "$0")"
FIX="$(cd .. && pwd)"

VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

echo "==> Testing"
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
"$FIX/tests/run.sh"

echo "==> Building release binary"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Wolf Among Us Trail Fix.app"
echo "==> Assembling $APP"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/payload"
cp "$BIN_DIR/WolfFix" "$APP/Contents/MacOS/WolfFix"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
(cd "$FIX/prebuilt" && shasum -a 256 -c d3d11.dll.sha256)
cp "$FIX/prebuilt/d3d11.dll" "$APP/Contents/Resources/payload/"
cp "$FIX/LICENSE" "$APP/Contents/Resources/LICENSE.txt"

echo "==> Signing"
SIGN=(--force --sign -)   # ad-hoc
[[ -n "${SIGN_IDENTITY:-}" ]] && SIGN=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")
codesign "${SIGN[@]}" "$APP"
codesign --verify --strict "$APP"
"$APP/Contents/MacOS/WolfFix" --selftest

ZIP="build/Wolf-Among-Us-Trail-Fix.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    [[ -n "${SIGN_IDENTITY:-}" ]] || { echo "Notarizing needs SIGN_IDENTITY (a Developer ID Application identity)." >&2; exit 1; }
    echo "==> Notarizing (a few minutes)"
    OUT="$(xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"
    echo "$OUT"
    grep -q "status: Accepted" <<< "$OUT" || { echo "Notarization failed (see above)." >&2; exit 1; }
    xcrun stapler staple "$APP"
    rm "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
fi
echo "==> Done: $APP ($ZIP)"
