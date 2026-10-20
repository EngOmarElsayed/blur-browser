#!/bin/bash
# Build Blur-Browser (Release), sign it with your Developer ID Application
# certificate and install it to /Applications.
#
# 1Password only trusts browsers signed with Developer ID (or App Store)
# certificates, so the copy you use day to day should come from here.
# See docs/extensions.md › 1Password.
set -euo pipefail
cd "$(dirname "$0")/.."

identity=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
if [[ -z "$identity" ]]; then
  echo "No 'Developer ID Application' certificate in your keychain." >&2
  echo "Create one in Xcode › Settings › Accounts › (your team) › Manage Certificates… › + › Developer ID Application." >&2
  exit 1
fi
echo "Signing with: $identity"

xcodebuild -project Blur-Browser.xcodeproj -scheme Blur-Browser -configuration Release \
  -derivedDataPath build/DerivedData \
  BLUR_SIGN_IDENTITY_Release="$identity" \
  build | grep -E "error:|warning: .*sign|BUILD" || true

app=build/DerivedData/Build/Products/Release/Blur-Browser.app
codesign --verify --strict "$app"
codesign -dv "$app" 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier"

# Quit the running copy (lets it save its session), then replace it.
bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist")
osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
sleep 2
rm -rf /Applications/Blur-Browser.app
ditto "$app" /Applications/Blur-Browser.app
open /Applications/Blur-Browser.app
echo "Installed /Applications/Blur-Browser.app"
