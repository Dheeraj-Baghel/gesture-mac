#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/artifacts/macos/Gesture Mac.app"
if [[ ! -x "$APP/Contents/MacOS/GestureMac" ]]; then
    bash build-app.sh
fi
open "$APP"
