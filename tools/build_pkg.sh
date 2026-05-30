#!/bin/bash
# Build the branded NoSleep .pkg installer (welcome/license/background +
# auto-launch on install) and drop it in ~/Downloads.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BUILD="$ROOT/build/pkg"
rm -rf "$BUILD"
mkdir -p "$BUILD/pkgroot/Applications"

# 1. Fresh app bundle.
make bundle >/dev/null

# 2. Stage the app at its install location (/Applications).
ditto "$ROOT/NoSleep.app" "$BUILD/pkgroot/Applications/NoSleep.app"

# 3. Installer assets (background image + license copy).
swift "$ROOT/tools/make_installer_bg.swift" "$ROOT/installer/resources/background.png"
cp "$ROOT/LICENSE" "$ROOT/installer/resources/LICENSE.txt"
chmod +x "$ROOT/installer/scripts/postinstall"

# 4. Component package: installs NoSleep.app, runs postinstall (auto-launch).
pkgbuild --root "$BUILD/pkgroot" \
         --identifier com.nosleep.pkg \
         --version 1.0 \
         --install-location / \
         --scripts "$ROOT/installer/scripts" \
         "$BUILD/NoSleep-component.pkg"

# 5. Product (distribution) package: the pretty wizard around the component.
productbuild --distribution "$ROOT/installer/distribution.xml" \
             --resources "$ROOT/installer/resources" \
             --package-path "$BUILD" \
             "$BUILD/NoSleep-Installer.pkg"

# 6. Deliver to Downloads.
cp "$BUILD/NoSleep-Installer.pkg" "$HOME/Downloads/NoSleep-Installer.pkg"
echo "Installer: ~/Downloads/NoSleep-Installer.pkg"
