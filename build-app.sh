#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building bak-bak (release)..."
swift build -c release

APP_DIR="/Applications/Bak-Bak.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

# Create app bundle structure if needed
mkdir -p "$MACOS" "$CONTENTS/Resources"

# Copy binary, Info.plist, and icon
cp .build/release/bak-bak "$MACOS/bak-bak"
cp Sources/bak-bak/Info.plist "$CONTENTS/Info.plist"
cp Sources/bak-bak/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

# Ad-hoc codesign
codesign -s - -f --deep "$APP_DIR"

echo ""
echo "Installed to: $APP_DIR"
echo ""
echo "To run:"
echo "  open /Applications/Bak-Bak.app"
echo ""
echo "Grant Accessibility permission when prompted (System Settings > Privacy & Security > Accessibility)."
