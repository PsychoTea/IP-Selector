#!/bin/bash
# Build and sign a local test copy. Does not install or register the helper.
set -euo pipefail
cd "$(dirname "$0")/.."
task_root="$PWD"
identity="${IP_LOCAL_SIGN_IDENTITY:-IP Selector Local Test}"
if [[ "$identity" == '-' || -z "$identity" ]]; then
    printf 'Use a certificate identity, not an ad-hoc signature. See docs/LOCAL_TEST.md.\n' >&2
    exit 1
fi
if ! security find-certificate -c "$identity" >/dev/null 2>&1; then
    printf 'Certificate not found: %s\nCreate it with Keychain Access as described in docs/LOCAL_TEST.md.\n' "$identity" >&2
    exit 1
fi
xcodebuild -project IPSelector.xcodeproj -scheme IPSelector -configuration LocalTest \
    -derivedDataPath "$task_root/build/local-derived" build CODE_SIGNING_ALLOWED=NO
app_path="$task_root/build/local-derived/Build/Products/LocalTest/IP Selector (Local Test).app"
helper_path="$app_path/Contents/Library/HelperTools/IPSelectorHelper"
codesign --force --options runtime --timestamp=none --sign "$identity" \
    --identifier org.ipselector.IPSelector.LocalTest.Helper "$helper_path"
codesign --force --options runtime --timestamp=none --sign "$identity" \
    --identifier org.ipselector.IPSelector.LocalTest "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
check_dir="$(mktemp -d "$task_root/build/local-derived/signature-check.XXXXXX")"
codesign --display --extract-certificates="$check_dir/app-" "$app_path"
codesign --display --extract-certificates="$check_dir/helper-" "$helper_path"
cmp "$check_dir/app-0" "$check_dir/helper-0"
fingerprint="$(/usr/bin/openssl x509 -inform DER -in "$check_dir/app-0" -noout -fingerprint -sha1 | /usr/bin/awk -F= '{print $2}' | /usr/bin/tr -d ':')"
if [[ ${#fingerprint} -ne 40 ]]; then
    printf 'Cannot read the signing certificate fingerprint.\n' >&2
    exit 1
fi
codesign --verify --strict -R "=identifier \"org.ipselector.IPSelector.LocalTest\" and certificate leaf = H\"$fingerprint\"" "$app_path"
codesign --verify --strict -R "=identifier \"org.ipselector.IPSelector.LocalTest.Helper\" and certificate leaf = H\"$fingerprint\"" "$helper_path"
printf '\nSigned local test app: %s\n' "$app_path"
printf 'Copy it to /Applications and open it. First launch starts helper setup; use Open System Settings in the approval window. Use Approve Helper in the menu to return to setup.\n'
