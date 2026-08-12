#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT_DIR/.build/direct"
APP_DIR="$ROOT_DIR/dist/AMBH.app"
CONTENTS_DIR="$APP_DIR/Contents"
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
TARGET_ARCH=$(uname -m)
TARGET="$TARGET_ARCH-apple-macosx13.0"

mkdir -p "$BUILD_DIR"

clang -c "$ROOT_DIR/Sources/CCurlShim/curl_shim.c" \
    -I "$ROOT_DIR/Sources/CCurlShim/include" \
    -isysroot "$SDK_PATH" \
    -mmacosx-version-min=13.0 \
    -o "$BUILD_DIR/curl_shim.o"

swiftc -parse-as-library -O -whole-module-optimization -emit-module -emit-object \
    -module-name AMBHCore \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    -I "$ROOT_DIR/Sources/CCurlShim/include" \
    -emit-module-path "$BUILD_DIR/AMBHCore.swiftmodule" \
    -o "$BUILD_DIR/AMBHCore.o" \
    "$ROOT_DIR"/Sources/AMBHCore/*.swift

swiftc \
    -O \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    -I "$BUILD_DIR" \
    -I "$ROOT_DIR/Sources/CCurlShim/include" \
    "$ROOT_DIR"/Sources/AMBH/*.swift \
    "$BUILD_DIR/AMBHCore.o" \
    "$BUILD_DIR/curl_shim.o" \
    -lcurl \
    -o "$BUILD_DIR/AMBH"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BUILD_DIR/AMBH" "$CONTENTS_DIR/MacOS/AMBH"
cp "$ROOT_DIR/support/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$CONTENTS_DIR/MacOS/AMBH"
codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR using direct compiler fallback"
