#!/bin/bash
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:${PATH:-}"

# Resolve project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SRCROOT:-"$(cd "$SCRIPT_DIR/.." && pwd)"}"
SRC_PLIST="$PROJECT_DIR/MistiaInfo.plist"

# Find git commit count
if [ -d "$PROJECT_DIR/.git" ]; then
    BUILD_NUMBER=$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null || echo "")
else
    BUILD_NUMBER=""
fi

if [ -z "$BUILD_NUMBER" ] || [ "$BUILD_NUMBER" = "0" ]; then
    if [ -f "$SRC_PLIST" ]; then
        BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$SRC_PLIST" 2>/dev/null || echo "1")
    else
        BUILD_NUMBER="1"
    fi
fi

echo "Calculated Git Build Number: ${BUILD_NUMBER}"

# 1. Update source MistiaInfo.plist if available
if [ -f "$SRC_PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$SRC_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD_NUMBER}" "$SRC_PLIST" 2>/dev/null
    echo "Updated source MistiaInfo.plist CFBundleVersion to ${BUILD_NUMBER}"
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
