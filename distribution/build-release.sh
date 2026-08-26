#!/bin/zsh
#
# Builds a distributable macOS .app.
#
#   ./distribution/build-release.sh            # auto-detects which signing you have
#   ./distribution/build-release.sh developer-id
#   ./distribution/build-release.sh development
#
# Output lands in ./build/export/MangoAccounting.app
#
# Notarisation is a separate step; see distribution/README.md.

set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="MangoAccounting.xcodeproj"
SCHEME="MangoAccounting"
TEAM="LUR83WQX7W"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/MangoAccounting.xcarchive"

mode="${1:-auto}"

if [[ "$mode" == "auto" ]]; then
  if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    mode="developer-id"
  elif security find-identity -v -p codesigning | grep -q "Apple Development"; then
    mode="development"
  else
    print -u2 "No code-signing identity found."
    print -u2 "Open Xcode > Settings > Accounts and add your Apple ID, then re-run."
    exit 1
  fi
fi

case "$mode" in
  developer-id) options="distribution/ExportOptions-DeveloperID.plist" ;;
  development)  options="distribution/ExportOptions-Development.plist" ;;
  *) print -u2 "Unknown mode: $mode (expected developer-id or development)"; exit 2 ;;
esac

print "Signing mode: $mode"
rm -rf "$ARCHIVE" "$BUILD_DIR/export"
mkdir -p "$BUILD_DIR"

# Universal binary, matching what has been shipped before.
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  ARCHS="x86_64 arm64" \
  ONLY_ACTIVE_ARCH=NO

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$options" \
  -exportPath "$BUILD_DIR/export" \
  -allowProvisioningUpdates

APP="$BUILD_DIR/export/MangoAccounting.app"
print "\n--- signature ---"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier|flags|Sealed'
print "\n--- version ---"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" | sed 's/^/  short: /'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" | sed 's/^/  build: /'
print "\n--- architectures ---"
lipo -archs "$APP/Contents/MacOS/MangoAccounting" | sed 's/^/  /'

# Zip with ditto, not the Finder or `zip`: it preserves the extended attributes
# the code signature depends on, so the app still validates after transfer.
ZIP="$BUILD_DIR/MangoAccounting-$( /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" ).zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

print "\nBuilt: $APP"
print "Send:  $ZIP"
if [[ "$mode" == "development" ]]; then
  print "\nNOTE: development-signed. Users must right-click the app and choose Open"
  print "the first time, because it is not notarised."
fi
