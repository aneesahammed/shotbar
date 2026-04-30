#!/usr/bin/env bash
set -euo pipefail

PROFILE_NAME="${NOTARY_KEYCHAIN_PROFILE:-shotbar-notary}"
TEAM_ID="${DEVELOPMENT_TEAM:-9B5T2H5SA7}"

APPLE_ID="$(osascript \
    -e 'display dialog "Apple ID email for notarization" default answer "" buttons {"Cancel", "Continue"} default button "Continue"' \
    -e 'text returned of result')"

APP_PASSWORD="$(osascript \
    -e 'display dialog "App-specific password for this Apple ID, not your normal account password" default answer "" with hidden answer buttons {"Cancel", "Store"} default button "Store"' \
    -e 'text returned of result')"

xcrun notarytool store-credentials "${PROFILE_NAME}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${TEAM_ID}" \
    --password "${APP_PASSWORD}" \
    --validate

unset APP_PASSWORD APPLE_ID

echo "Stored notarization profile: ${PROFILE_NAME}"
