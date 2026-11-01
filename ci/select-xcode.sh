#!/bin/bash
# Picks the newest non-beta Xcode on the runner and fails unless it is >= 26.4
# (DAT 1.0.x needs Xcode 26.4+ / Swift 6.3+).
set -euo pipefail

echo "Xcodes on this runner:"
ls -d /Applications/Xcode*.app

XCODE=$(ls -d /Applications/Xcode_*.app | grep -iv beta | sort -V | tail -1)
sudo xcode-select -s "$XCODE"
xcodebuild -version
swift --version

VERSION=$(xcodebuild -version | head -1 | awk '{print $2}')
MAJOR=$(echo "$VERSION" | cut -d. -f1)
MINOR=$(echo "$VERSION" | cut -d. -f2)
if [ "$MAJOR" -lt 26 ] || { [ "$MAJOR" -eq 26 ] && [ "${MINOR:-0}" -lt 4 ]; }; then
  echo "::error::Selected $XCODE ($VERSION) but DAT needs Xcode 26.4 or newer."
  exit 1
fi
