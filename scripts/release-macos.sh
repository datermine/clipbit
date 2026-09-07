#!/bin/bash
# Release ClipBit to App Store Connect.
#
#   scripts/release-macos.sh              archive, export, and upload
#   scripts/release-macos.sh --dry-run    archive and export a local .pkg, skip upload
#   SKIP_TESTS=1 scripts/release-macos.sh skip the unit tests
#
# Prereqs: the App ID and app record must exist in App Store Connect (one-time
# setup), and the API key .p8 must be in one of the search locations below.
# Signing is automatic: with the API key, xcodebuild creates the Mac App
# Distribution / Mac Installer Distribution certificates and the App Store
# provisioning profile on demand.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="Clipbit"
SCHEME="Clipbit"
PRODUCT_NAME="ClipBit"
CONFIGURATION="Release"
TEAM_ID="39M246A2UR"

# App Store Connect API credentials. The .p8 is the secret, but the key and issuer IDs
# are account identifiers that don't belong in a public repo either, so both come from
# the environment or from an untracked .release.env at the repo root:
#   ASC_KEY_ID=XXXXXXXXXX
#   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
if [ -f "$ROOT_DIR/.release.env" ]; then
  # shellcheck disable=SC1091
  . "$ROOT_DIR/.release.env"
fi
API_KEY_ID="${ASC_KEY_ID:-}"
API_ISSUER_ID="${ASC_ISSUER_ID:-}"
if [ -z "$API_KEY_ID" ] || [ -z "$API_ISSUER_ID" ]; then
  echo "Error: ASC_KEY_ID and ASC_ISSUER_ID must be set (environment or .release.env)." >&2
  exit 1
fi
# App Store Connect API key .p8 file — searched in these locations:
#   1. ~/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8
#   2. ~/.private_keys/AuthKey_${API_KEY_ID}.p8
#   3. ./private_keys/AuthKey_${API_KEY_ID}.p8

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
fi

ARCHIVE_PATH="$ROOT_DIR/build/${PRODUCT_NAME}.xcarchive"
EXPORT_PATH="$ROOT_DIR/build/export"
EXPORT_OPTIONS_PLIST="$(mktemp "/tmp/${PRODUCT_NAME}-export-options.XXXXXX.plist")"

cleanup() {
  rm -f "$EXPORT_OPTIONS_PLIST"
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: missing required command: $1" >&2
    exit 1
  fi
}

require_command xcodegen
require_command xcodebuild
require_command xcrun

find_api_key() {
  local key_file="AuthKey_${API_KEY_ID}.p8"
  local search_dirs=(
    "$HOME/.appstoreconnect/private_keys"
    "$HOME/.private_keys"
    "$ROOT_DIR/private_keys"
  )
  for dir in "${search_dirs[@]}"; do
    if [ -f "$dir/$key_file" ]; then
      echo "$dir/$key_file"
      return 0
    fi
  done
  return 1
}

if ! API_KEY_PATH=$(find_api_key); then
  echo "Error: App Store Connect API key AuthKey_${API_KEY_ID}.p8 not found." >&2
  echo "Place it in one of:" >&2
  echo "  ~/.appstoreconnect/private_keys/" >&2
  echo "  ~/.private_keys/" >&2
  echo "  ./private_keys/" >&2
  exit 1
fi
echo "Found API key at $API_KEY_PATH"

cd "$ROOT_DIR"

# Version/build come from project.yml (MARKETING_VERSION / CURRENT_PROJECT_VERSION);
# Info.plist just references them. The archive is re-verified below.
VERSION=$(grep -E '^[[:space:]]*MARKETING_VERSION:' project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')
BUILD=$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')
if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
  echo "Error: could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml" >&2
  exit 1
fi
echo "Releasing ${PRODUCT_NAME} v${VERSION} (${BUILD})"

echo ""
echo "==> Generating Xcode project..."
xcodegen generate

if [ "${SKIP_TESTS:-0}" != "1" ]; then
  echo ""
  echo "==> Running unit tests..."
  xcodebuild \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -derivedDataPath "$ROOT_DIR/build" \
    -quiet \
    test
fi

echo ""
echo "==> Cleaning previous archive output..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"

if [ "$DRY_RUN" = "1" ]; then
  DESTINATION="export"
else
  DESTINATION="upload"
fi

cat >"$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>${DESTINATION}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>uploadSymbols</key>
  <true/>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
</dict>
</plist>
PLIST

echo ""
echo "==> Archiving ${PRODUCT_NAME}..."
xcodebuild \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$ROOT_DIR/build" \
  -archivePath "$ARCHIVE_PATH" \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID" \
  -allowProvisioningUpdates \
  -quiet \
  archive

if [ ! -d "$ARCHIVE_PATH" ]; then
  echo "Error: archive not found at $ARCHIVE_PATH" >&2
  exit 1
fi

# Verify the archive really carries the version we think we're shipping.
ARCHIVE_PLIST="$ARCHIVE_PATH/Products/Applications/${PRODUCT_NAME}.app/Contents/Info.plist"
ARCHIVE_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ARCHIVE_PLIST")
ARCHIVE_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ARCHIVE_PLIST")
if [ "$ARCHIVE_VERSION" != "$VERSION" ] || [ "$ARCHIVE_BUILD" != "$BUILD" ]; then
  echo "Error: archive version mismatch!" >&2
  echo "  project.yml: ${VERSION} (${BUILD})" >&2
  echo "  archive:     ${ARCHIVE_VERSION} (${ARCHIVE_BUILD})" >&2
  exit 1
fi

echo ""
if [ "$DRY_RUN" = "1" ]; then
  echo "==> [dry run] Exporting .pkg locally (no upload)..."
else
  echo "==> Exporting and uploading to App Store Connect..."
fi
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID" \
  -allowProvisioningUpdates

echo ""
if [ "$DRY_RUN" = "1" ]; then
  PKG_PATH="$(find "$EXPORT_PATH" -name '*.pkg' -print -quit)"
  echo "Dry run complete: ${PRODUCT_NAME} v${VERSION} (${BUILD})"
  echo "Package: ${PKG_PATH:-<not found>}"
else
  echo "Done! ${PRODUCT_NAME} v${VERSION} (${BUILD}) uploaded to App Store Connect."
  echo "Next: tag the release —  git tag v${VERSION} && git push --tags"
fi
