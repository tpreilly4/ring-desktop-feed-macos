#!/bin/bash
# One-time (and after-pull) setup: fetch the pinned Node runtime, build the
# helper, stage its production bundle, and generate the Xcode project.
set -euo pipefail
cd "$(dirname "$0")/.."

NODE_VERSION=v22.23.3
NODE_SHA256=23b25245dcfb9af7262f8ff142e9e2e0af025368117329e7a7458a51e5922f53
NODE_DIR=vendor/node-$NODE_VERSION

if [ ! -x "$NODE_DIR/bin/node" ]; then
  echo "Fetching Node $NODE_VERSION…"
  mkdir -p vendor
  tarball=vendor/node.tar.gz
  curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-darwin-arm64.tar.gz" -o "$tarball"
  echo "$NODE_SHA256  $tarball" | shasum -a 256 -c -
  mkdir -p "$NODE_DIR"
  tar -xzf "$tarball" -C "$NODE_DIR" --strip-components 1
  rm "$tarball"
fi
ln -sfn "node-$NODE_VERSION" vendor/node

export PATH="$PWD/vendor/node/bin:$PATH"

echo "Building helper…"
(cd helper && npm ci && npm run build)

echo "Staging helper bundle…"
rm -rf build/helper
mkdir -p build/helper
cp -R helper/dist helper/player helper/package.json helper/package-lock.json build/helper/
(cd build/helper && npm ci --omit=dev --ignore-scripts)

if [ ! -f Local.xcconfig ]; then
  cp Local.xcconfig.example Local.xcconfig
  echo "Created Local.xcconfig — add your DEVELOPMENT_TEAM there."
fi

xcodegen generate
echo "Done. Open RingDesktopFeed.xcodeproj or run scripts/build.sh."
