#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT_DIR/.build/direct"
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
TARGET_ARCH=$(uname -m)
TARGET="$TARGET_ARCH-apple-macosx13.0"

"$ROOT_DIR/scripts/build-direct.sh" >/dev/null

swiftc \
    -parse-as-library \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    -I "$BUILD_DIR" \
    -I "$ROOT_DIR/Sources/CCurlShim/include" \
    "$ROOT_DIR/DirectTests/main.swift" \
    "$BUILD_DIR/AMBHCore.o" \
    "$BUILD_DIR/curl_shim.o" \
    -lcurl \
    -o "$BUILD_DIR/AMBHCoreDirectTests"

"$BUILD_DIR/AMBHCoreDirectTests"
