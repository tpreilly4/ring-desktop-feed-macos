#!/bin/bash
# Command-line Debug build into build/DerivedData.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project RingDesktopFeed.xcodeproj -scheme RingDesktopFeed -configuration Debug \
  -derivedDataPath build/DerivedData build | tail -20
echo "App: build/DerivedData/Build/Products/Debug/Ring Desktop Feed.app"
