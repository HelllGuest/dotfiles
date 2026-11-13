#!/usr/bin/env bash
# First-boot SDK bootstrap (skipped when already present).
set -euo pipefail
if [[ ! -x /opt/flutter/bin/flutter ]]; then
  echo "lab-android: cloning Flutter stable into /opt/flutter (one-time)..."
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git /opt/flutter
fi
if [[ ! -d /opt/android-sdk/cmdline-tools/latest ]]; then
  echo "lab-android: Android cmdline-tools not present — install manually:"
  echo "  sdkmanager --install 'platform-tools' 'platforms;android-35' 'build-tools;35.0.0'"
fi
exec "$@"
