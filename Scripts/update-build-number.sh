#!/bin/bash
set -euo pipefail

# Find git commit count
if [ -n "${SRCROOT:-}" ] && [ -d "$SRCROOT/.git" ]; then
    BUILD_NUMBER=$(git -C "$SRCROOT" rev-list --count HEAD 2>/dev/null || echo "1")
    SRC_PLIST="$SRCROOT/MistiaInfo.plist"
else
    BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
    SRC_PLIST="MistiaInfo.plist"
fi

echo "Calculated Git Build Number: ${BUILD_NUMBER}"

# 1. Update source MistiaInfo.plist if available
if [ -f "$SRC_PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$SRC_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD_NUMBER}" "$SRC_PLIST" 2>/dev/null
    echo "Updated source MistiaInfo.plist to ${BUILD_NUMBER}"
fi

# 2. Candidate locations for compiled Info.plist in build products
PLIST_PATHS=(
    "${TARGET_BUILD_DIR:-}/${INFOPLIST_PATH:-}"
    "${BUILT_PRODUCTS_DIR:-}/${INFOPLIST_PATH:-}"
    "${CODESIGNING_FOLDER_PATH:-}/Info.plist"
    "${BUILT_PRODUCTS_DIR:-}/${WRAPPER_NAME:-}/Info.plist"
)

for plist in "${PLIST_PATHS[@]}"; do
    if [ -n "$plist" ] && [ -f "$plist" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD_NUMBER}" "$plist" 2>/dev/null
        echo "Successfully updated compiled Info.plist at $plist"
    fi
done
