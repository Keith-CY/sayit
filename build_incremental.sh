#!/bin/bash

# SayIt fast Debug build wrapper.
#
# Use LAUNCH_APP=1 to open the built app after a successful build.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

exec "${PROJECT_DIR}/build.sh" incremental
