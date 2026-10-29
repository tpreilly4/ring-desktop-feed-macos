#!/bin/bash
# Xcode build phase: copy the staged helper and the Node runtime into the app.
set -euo pipefail
cd "$SRCROOT"

if [ ! -d build/helper/dist ] || [ ! -x vendor/node/bin/node ]; then
  echo "error: helper not staged. Run scripts/bootstrap.sh first." >&2
  exit 1
fi

dest="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/helper"
rm -rf "$dest"
mkdir -p "$dest"
cp -R build/helper/ "$dest/"
cp vendor/node/bin/node "$dest/node"
