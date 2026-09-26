#!/bin/bash
set -euo pipefail

APP_PATH="${1:?Usage: verify-app-bundle.sh /path/to/SayIt.app}"
APP_BINARY="${APP_PATH}/Contents/MacOS/SayIt"
METAL_LIBRARY="${APP_PATH}/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"

test -s "${APP_PATH}/Contents/Info.plist"
test -x "${APP_BINARY}"
test -d "${APP_PATH}/Contents/Frameworks/Sparkle.framework"

if [[ ! -s "${METAL_LIBRARY}" ]]; then
    echo "Missing MLX Metal library: Qwen cannot run in this app bundle."
    exit 1
fi

/usr/bin/lipo "${APP_BINARY}" -verify_arch arm64
if ! LC_ALL=C /usr/bin/grep -a -q -F 'mlx-community/Qwen3-ASR-1.7B-8bit' "${APP_BINARY}"; then
    echo "The app binary does not contain the expected Qwen model integration."
    exit 1
fi

echo "Verified Apple Silicon app, Qwen model integration, MLX Metal resources, and Sparkle."
