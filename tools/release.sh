#!/bin/bash

# Build and notarize a release

set -euo pipefail
: "${IP_SIGN_IDENTITY:?Set IP_SIGN_IDENTITY to your Developer ID Application identity}"
: "${IP_TEAM_ID:?Set IP_TEAM_ID to your Apple Developer team ID}"
: "${IP_NOTARY_PROFILE:?Set IP_NOTARY_PROFILE to a notarytool Keychain profile}"
cd "$(dirname "$0")/.."
task_root="$PWD"
source "$task_root/tools/notarize.sh"
release_dir="$task_root/build/release"
logs_dir="$task_root/build/release-logs"
mkdir -p "$release_dir" "$logs_dir"
work_dir="$(mktemp -d "$task_root/build/release-work.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

xcodebuild -project IPSelector.xcodeproj -scheme IPSelector -configuration Release \
    -derivedDataPath "$task_root/build/release-derived" build \
    "ARCHS=arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    "DEVELOPMENT_TEAM=$IP_TEAM_ID" "CODE_SIGN_IDENTITY=$IP_SIGN_IDENTITY" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    'OTHER_CODE_SIGN_FLAGS=--timestamp'
app_path="$task_root/build/release-derived/Build/Products/Release/IP Selector.app"
codesign --verify --deep --strict --verbose=2 "$app_path"
staging_dir="$work_dir/staging"
mkdir -p "$staging_dir"
ditto "$app_path" "$staging_dir/IP Selector.app"
ditto -c -k --keepParent "$staging_dir/IP Selector.app" "$staging_dir/notarize.zip"
ip_notarize_and_wait "$staging_dir/notarize.zip" "$logs_dir/app-notarization.json"
xcrun stapler staple "$staging_dir/IP Selector.app"
xcrun stapler validate "$staging_dir/IP Selector.app"

image_dir="$work_dir/image"
mkdir -p "$image_dir"
ditto "$staging_dir/IP Selector.app" "$image_dir/IP Selector.app"
ln -s /Applications "$image_dir/Applications"
dmg_path="$work_dir/IP-Selector.dmg"
hdiutil create -volname 'IP Selector' -srcfolder "$image_dir" -format UDZO "$dmg_path"
codesign --sign "$IP_SIGN_IDENTITY" --timestamp "$dmg_path"
ip_notarize_and_wait "$dmg_path" "$logs_dir/dmg-notarization.json"
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"

# Replace the last release only after the new image passes notarization and validation.
mv -f "$dmg_path" "$release_dir/IP-Selector.dmg"
printf 'Release created: %s\n' "$release_dir/IP-Selector.dmg"
