#!/bin/bash
set -euo pipefail

# Find git commit count
if [ -n "${SRCROOT:-}" ] && [ -d "$SRCROOT/.git" ]; then
    BUILD_NUMBER=$(git -C "$SRCROOT" rev-list --count HEAD 2>/dev/null || echo "1")
else
    BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
fi

# Target Info.plist in built products
INFOPLIST_TARGET="${BUILT_PRODUCTS_DIR:-}/${INFOPLIST_PATH:-}"

if [ -n "${INFOPLIST_TARGET}" ] && [ -f "${INFOPLIST_TARGET}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${INFOPLIST_TARGET}" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD_NUMBER}" "${INFOPLIST_TARGET}" 2>/dev/null
    echo "Updated CFBundleVersion to ${BUILD_NUMBER} in ${INFOPLIST_TARGET}"
else
    echo "Info.plist target not found at '${INFOPLIST_TARGET}'. Skipping plist update."
fi
