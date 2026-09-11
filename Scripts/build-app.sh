#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT_DIR/VERSION")"
CACHE_DIR="${NOSLEEPMENU_BUILD_CACHE:-$HOME/Library/Caches/NoSleepMenu-release}"
APP_DIR="$ROOT_DIR/build/NoSleepMenu.app"
ARCHS="${NOSLEEPMENU_ARCHS:-arm64 x86_64}"
BINARIES=()
cd "$ROOT_DIR"
for ARCH in $ARCHS; do
  case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
  ARCH_CACHE="$CACHE_DIR/$ARCH"
  swift build --scratch-path "$ARCH_CACHE" -c release --triple "$ARCH-apple-macosx13.0" --product NoSleepMenu
  BIN_DIR="$(swift build --scratch-path "$ARCH_CACHE" -c release --triple "$ARCH-apple-macosx13.0" --show-bin-path)"
  BINARIES+=("$BIN_DIR/NoSleepMenu")
done
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
if [[ ${#BINARIES[@]} -gt 1 ]]; then
  /usr/bin/lipo -create "${BINARIES[@]}" -output "$APP_DIR/Contents/MacOS/NoSleepMenu"
else
  cp "${BINARIES[0]}" "$APP_DIR/Contents/MacOS/NoSleepMenu"
fi
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>NoSleepMenu</string>
<key>CFBundleDisplayName</key><string>NoSleepMenu</string>
<key>CFBundleIdentifier</key><string>io.github.nosleepmenu.NoSleepMenu</string>
<key>CFBundleExecutable</key><string>NoSleepMenu</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>ko</string></array>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp "$ROOT_DIR/LICENSE" "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  /usr/bin/codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_DIR"
else
  /usr/bin/codesign --force --sign - "$APP_DIR"
fi
/usr/bin/codesign --verify --strict "$APP_DIR"
/usr/bin/lipo -info "$APP_DIR/Contents/MacOS/NoSleepMenu"
echo "Created $APP_DIR"
