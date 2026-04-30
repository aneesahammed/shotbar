#!/usr/bin/env bash
set -euo pipefail

# Build, sign, and package ShotBarApp for distribution.
# Notarization is required by default for release builds:
#   Scripts/store_notary_credentials.sh
#   ./create_dmg.sh
#
# For local packaging smoke tests only:
#   SKIP_NOTARIZATION=1 ./create_dmg.sh

APP_NAME="ShotBarApp"
PROJECT="ShotBarApp.xcodeproj"
SCHEME="ShotBarApp"
CONFIGURATION="Release"
DERIVED_DATA="./build/ReleaseDmg"
DIST_DIR="./dist"
DMG_DIR="./dmg_temp"

build_setting() {
    local key="$1"
    xcodebuild \
        -project "${PROJECT}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -showBuildSettings 2>/dev/null |
        awk -F= -v key="${key}" '
            $1 ~ key {
                gsub(/^[ \t]+|[ \t]+$/, "", $2)
                print $2
                exit
            }
        '
}

VERSION="${VERSION:-$(build_setting MARKETING_VERSION)}"
DMG_NAME="${DMG_NAME:-ShotBarApp-v${VERSION}}"
BUILT_APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
DIST_APP="${DIST_DIR}/${APP_NAME}.app"
DMG_PATH="${DMG_NAME}.dmg"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-shotbar-notary}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-1}"

if [[ "${SKIP_NOTARIZATION:-0}" == "1" ]]; then
    REQUIRE_NOTARIZATION=0
fi

echo "Building signed ${CONFIGURATION} app..."
xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "platform=macOS" \
    -derivedDataPath "${DERIVED_DATA}" \
    build

echo "Preparing distribution app..."
rm -rf "${DIST_DIR}" "${DMG_DIR}" "${DMG_PATH}"
mkdir -p "${DIST_DIR}" "${DMG_DIR}"
cp -R "${BUILT_APP}" "${DIST_APP}"

echo "Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "${DIST_APP}"

echo "Preparing DMG contents..."
cp -R "${DIST_APP}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

cat > "${DMG_DIR}/README.txt" << 'EOF'
ShotBarApp - macOS Screenshot Utility
=====================================

INSTALLATION:
1. Drag ShotBarApp.app to the Applications folder
2. Open ShotBarApp from Applications
3. Grant Screen Recording permission when prompted
4. Configure hotkeys in preferences (default: F1-F3)

USAGE:
- F1: Selection capture (drag to select area)
- F2: Active window capture
- F3: Full screen capture
- Access preferences via menu bar icon

NOTE:
Public release DMGs are signed and notarized.
Local smoke-test builds that skip notarization may show a macOS security warning.
EOF

echo "Creating DMG..."
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "${DMG_PATH}"

rm -rf "${DMG_DIR}"

echo "Signing DMG..."
codesign --force --sign "Developer ID Application" --timestamp "${DMG_PATH}"
codesign --verify --verbose=2 "${DMG_PATH}"

if xcrun notarytool history --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" --output-format json >/dev/null 2>&1; then
    echo "Submitting DMG for notarization..."
    xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" \
        --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"

    echo "Checking Gatekeeper assessment..."
    spctl -a -vv -t open --context context:primary-signature "${DMG_PATH}"
elif [[ "${REQUIRE_NOTARIZATION}" == "0" ]]; then
    echo "Skipping notarization because REQUIRE_NOTARIZATION=0."
else
    echo "Notarization is required but no valid notary profile was found: ${NOTARY_KEYCHAIN_PROFILE}" >&2
    echo "Run Scripts/store_notary_credentials.sh, or set SKIP_NOTARIZATION=1 for local smoke tests only." >&2
    exit 1
fi

echo "DMG created: ${DMG_PATH}"
echo "Size: $(du -h "${DMG_PATH}" | cut -f1)"
