#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${1:-dev}
ARCH=$(uname -m)
RELEASE_DIR="$ROOT_DIR/dist/release"
ARCHIVE_NAME="AMBH-${VERSION}-${ARCH}.zip"
ARCHIVE_PATH="$RELEASE_DIR/$ARCHIVE_NAME"

if [ ! -d "$ROOT_DIR/dist/AMBH.app" ]; then
    echo "dist/AMBH.app does not exist; run scripts/build-app.sh first." >&2
    exit 1
fi

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
ditto -c -k --sequesterRsrc --keepParent "$ROOT_DIR/dist/AMBH.app" "$ARCHIVE_PATH"

cd "$RELEASE_DIR"
shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"

echo "Packaged $ARCHIVE_PATH"
