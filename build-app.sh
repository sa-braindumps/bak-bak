#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building bak-bak..."
swift build

APP_DIR=".build/bak-bak.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

# Create app bundle structure
mkdir -p "$MACOS" "$CONTENTS/Resources"

# Copy binary
cp .build/debug/bak-bak "$MACOS/bak-bak"

# Copy Info.plist
cp Sources/bak-bak/Info.plist "$CONTENTS/Info.plist"

echo ""
echo "App bundle created at: $APP_DIR"
echo ""
echo "To install and run:"
echo "  rm -rf /Applications/Bak-Bak.app"
echo "  cp -r $APP_DIR /Applications/Bak-Bak.app"
echo "  open /Applications/Bak-Bak.app"
echo ""
echo "Then grant permissions when prompted."
