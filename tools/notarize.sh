#!/bin/bash
# Shared by the release script and its tests. Credentials stay in Keychain.
ip_notarize_and_wait() {
    local artifact="$1" report="$2"
    local command_status=0 status submission_id
    xcrun notarytool submit "$artifact" --keychain-profile "$IP_NOTARY_PROFILE" \
        --wait --output-format json > "$report" || command_status=$?
    status="$(plutil -extract status raw -o - "$report" 2>/dev/null || true)"
    submission_id="$(plutil -extract id raw -o - "$report" 2>/dev/null || true)"
    if [[ "$command_status" -eq 0 && "$status" == Accepted ]]; then
        printf 'Notarization accepted: %s\n' "$submission_id"
        return 0
    fi
    printf 'Notarization did not succeed (status: %s, exit: %s).\nResponse: %s\n' \
        "${status:-unknown}" "$command_status" "$report" >&2
    if [[ "$submission_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
        if xcrun notarytool log "$submission_id" --keychain-profile "$IP_NOTARY_PROFILE" "$report.log.json"; then
            printf 'Apple validation log: %s\n' "$report.log.json" >&2
            cat "$report.log.json" >&2
        fi
    fi
    return 1
}
