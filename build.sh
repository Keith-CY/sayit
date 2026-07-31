#!/bin/bash

# SayIt source build helper.
#
# Usage:
#   ./build.sh                    # Debug build
#   ./build.sh incremental        # Debug incremental build
#   ./build.sh release            # Release build
#   LAUNCH_APP=1 ./build.sh       # Build and open the result

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE="${1:-${BUILD_PROFILE:-dev}}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${PROJECT_DIR}/.build/xcode}"

case "${PROFILE}" in
    dev|debug|incremental|fast)
        CONFIGURATION="${CONFIGURATION:-Debug}"
        ;;
    release|full)
        CONFIGURATION="${CONFIGURATION:-Release}"
        ;;
    *)
        echo "Unknown build profile: ${PROFILE}"
        echo "Valid profiles: dev, debug, incremental, fast, release, full"
        exit 1
        ;;
esac

mkdir -p "${DERIVED_DATA_PATH}"

XCODEBUILD_ARGS=(
    -project "${PROJECT_DIR}/SayIt.xcodeproj"
    -scheme SayIt
    -configuration "${CONFIGURATION}"
    -destination "platform=macOS"
    -derivedDataPath "${DERIVED_DATA_PATH}"
    -onlyUsePackageVersionsFromResolvedFile
)

if [[ -n "${CLONED_SOURCE_PACKAGES_PATH:-}" ]]; then
    XCODEBUILD_ARGS+=(-clonedSourcePackagesDirPath "${CLONED_SOURCE_PACKAGES_PATH}")
fi

xcodebuild "${XCODEBUILD_ARGS[@]}" \
    CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
    COMPILER_INDEX_STORE_ENABLE="${COMPILER_INDEX_STORE_ENABLE:-NO}" \
    build

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/SayIt.app"
echo "Built ${APP_PATH}"

if [[ "${LAUNCH_APP:-0}" == "1" ]]; then
    open "${APP_PATH}"
fi
