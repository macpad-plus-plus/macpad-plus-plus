#!/bin/bash
# Builds MacPad++ in Release and packages it as a DMG in dist/.
#
#   scripts/build-dmg.sh
#
# Optional environment:
#   BUILD_NUMBER                 CURRENT_PROJECT_VERSION override (CI uses the run number)
#   DEVELOPER_ID_APPLICATION     e.g. "Developer ID Application: Name (TEAMID)"; without it the
#                                app is ad-hoc signed and Gatekeeper will warn on first launch
#   DEVELOPMENT_TEAM             Team ID for Developer ID signing
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
#                                notarize and staple the DMG (requires DEVELOPER_ID_APPLICATION)
#   NPM_REGISTRY                 registry for create-dmg (default: the public npm registry)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CREATE_DMG_VERSION="8.1.0"

VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9][0-9.]*\)"\{0,1\}.*/\1/p' project.yml | head -1)"
[[ -n "$VERSION" ]] || { echo "error: MARKETING_VERSION not found in project.yml" >&2; exit 1; }

# DerivedData must live outside iCloud-synced folders, or code signing fails.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/macpad-release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "==> MacPad++ $VERSION"
xcodegen generate --quiet

BUILD_SETTINGS=()
[[ -n "${BUILD_NUMBER:-}" ]] && BUILD_SETTINGS+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "==> Signing with $DEVELOPER_ID_APPLICATION"
    BUILD_SETTINGS+=(
        "CODE_SIGN_IDENTITY=$DEVELOPER_ID_APPLICATION"
        "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM:-}"
        "CODE_SIGN_STYLE=Manual"
        "OTHER_CODE_SIGN_FLAGS=--timestamp"
    )
else
    echo "==> No DEVELOPER_ID_APPLICATION: ad-hoc signing (Gatekeeper will warn on first launch)"
fi

echo "==> Building"
# Generic destination: a universal binary for Apple silicon and Intel.
xcodebuild -project MacPad.xcodeproj -scheme MacPad -configuration Release \
    -destination "generic/platform=macOS" ONLY_ACTIVE_ARCH=NO \
    -derivedDataPath "$WORK/DerivedData" ${BUILD_SETTINGS[@]+"${BUILD_SETTINGS[@]}"} \
    build | grep -E "^(\*\*|.*error:)" || true
APP="$WORK/DerivedData/Build/Products/Release/MacPad++.app"
[[ -d "$APP" ]] || { echo "error: build failed, see xcodebuild output" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
lipo -info "$APP/Contents/MacOS/MacPad++"

echo "==> Creating DMG"
mkdir -p "$ROOT/dist"
# Run from the work directory: create-dmg turns a license.txt in the
# current directory into a click-through agreement. Signing happens below,
# after the background is replaced.
(cd "$WORK" && npx --yes --registry "${NPM_REGISTRY:-https://registry.npmjs.org}" \
    "create-dmg@$CREATE_DMG_VERSION" --overwrite --dmg-title="MacPad++ $VERSION" \
    --no-code-sign "$APP" "$WORK") || true
CREATED="$(ls "$WORK"/*.dmg 2>/dev/null | head -1)"
[[ -n "$CREATED" ]] || { echo "error: create-dmg produced no DMG" >&2; exit 1; }

# create-dmg has no background option: swap in ours (same 660x400 layout,
# drawn by scripts/render-dmg-background.swift) inside a writable copy.
BACKGROUND="$ROOT/AppIcon/dmg/dmg-background.tiff"
if [[ -f "$BACKGROUND" ]]; then
    echo "==> Adding the axolotl background"
    FORMAT="$(hdiutil imageinfo -format "$CREATED")"
    hdiutil convert "$CREATED" -format UDRW -o "$WORK/rw.dmg" -quiet
    MOUNT="$(hdiutil attach "$WORK/rw.dmg" -readwrite -nobrowse -noautoopen | tail -1 | cut -f3-)"
    cp "$BACKGROUND" "$MOUNT/.background/dmg-background.tiff"
    hdiutil detach "$MOUNT" -quiet
    rm -f "$CREATED"
    hdiutil convert "$WORK/rw.dmg" -format "$FORMAT" -o "$CREATED" -quiet
fi

DMG="$ROOT/dist/MacPad++-$VERSION.dmg"
mv -f "$CREATED" "$DMG"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    codesign --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG"
fi

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" && -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$DMG" --apple-id "$APPLE_ID" --team-id "${APPLE_TEAM_ID:-$DEVELOPMENT_TEAM}" \
        --password "$APPLE_APP_PASSWORD" --wait
    xcrun stapler staple "$DMG"
fi

(cd "$ROOT/dist" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "==> $DMG"
cat "$DMG.sha256"
