#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/AMBH.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$ROOT_DIR"
if ! swift package dump-package >/dev/null 2>&1; then
    echo "SwiftPM is unavailable; using the direct compiler fallback." >&2
    exec "$ROOT_DIR/scripts/build-direct.sh"
fi
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BUILD_DIR/AMBH" "$CONTENTS_DIR/MacOS/AMBH"
cp "$ROOT_DIR/support/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$CONTENTS_DIR/MacOS/AMBH"
codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
