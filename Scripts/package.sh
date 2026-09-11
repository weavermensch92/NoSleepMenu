#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT_DIR/VERSION")"
bash "$ROOT_DIR/Scripts/build-app.sh"
APP_DIR="$ROOT_DIR/build/NoSleepMenu.app"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nosleepmenu-package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
mkdir -p "$DIST_DIR" "$STAGING_DIR/dmg" "$STAGING_DIR/pkg/Applications"
ditto "$APP_DIR" "$STAGING_DIR/dmg/NoSleepMenu.app"
ditto "$APP_DIR" "$STAGING_DIR/pkg/Applications/NoSleepMenu.app"
ln -s /Applications "$STAGING_DIR/dmg/Applications"
cp "$ROOT_DIR/docs/INSTALL.txt" "$STAGING_DIR/dmg/INSTALL.txt"
PKG="$DIST_DIR/NoSleepMenu-$VERSION.pkg"
DMG="$DIST_DIR/NoSleepMenu-$VERSION.dmg"
# No installer scripts, bundled credentials, login items, or power-setting changes.
/usr/bin/pkgbuild --analyze --root "$STAGING_DIR/pkg" "$STAGING_DIR/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$STAGING_DIR/components.plist"
/usr/bin/pkgbuild --root "$STAGING_DIR/pkg" --component-plist "$STAGING_DIR/components.plist" --identifier io.github.nosleepmenu.installer --version "$VERSION" --install-location / "$STAGING_DIR/unsigned.pkg"
if [[ -n "${DEVELOPER_ID_INSTALLER:-}" ]]; then
  /usr/bin/productsign --sign "$DEVELOPER_ID_INSTALLER" "$STAGING_DIR/unsigned.pkg" "$PKG"
else
  cp "$STAGING_DIR/unsigned.pkg" "$PKG"
fi
/usr/bin/hdiutil create -ov -volname NoSleepMenu -srcfolder "$STAGING_DIR/dmg" -format UDZO "$DMG"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${DEVELOPER_ID_APPLICATION:-}" || -z "${DEVELOPER_ID_INSTALLER:-}" ]]; then
    echo 'Notarization requires Developer ID Application and Installer identities.' >&2
    exit 1
  fi
  for ARTIFACT in "$PKG" "$DMG"; do
    xcrun notarytool submit "$ARTIFACT" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$ARTIFACT"
  done
fi
(cd "$DIST_DIR" && shasum -a 256 "NoSleepMenu-$VERSION.pkg" "NoSleepMenu-$VERSION.dmg" > SHA256SUMS)
echo "Packages: $DIST_DIR"
