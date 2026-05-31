#!/bin/bash
# Build the branded NoSleep .pkg installer (welcome/license/background +
# auto-launch on install) and drop it in ~/Downloads.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
# Stage in a throwaway temp dir (avoids stuck/again-read-only leftovers in-repo).
BUILD=$(mktemp -d /tmp/nosleep_pkg.XXXXXX)
trap 'rm -rf "$BUILD" 2>/dev/null || true' EXIT
mkdir -p "$BUILD/pkgroot/Applications"

# 1. Fresh app bundle.
make bundle >/dev/null

# 2. Stage the app at its install location (/Applications).
ditto "$ROOT/NoSleep.app" "$BUILD/pkgroot/Applications/NoSleep.app"

# 3. Installer assets (background image + license copy).
swift "$ROOT/tools/make_installer_bg.swift" "$ROOT/installer/resources/background.png"
swift "$ROOT/tools/make_installer_bg.swift" "$ROOT/installer/resources/background-dark.png" dark
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
# Publish: the landing page (site/) links to the pkg as a GitHub Release asset,
# so after building, upload it with:
#   gh release upload <tag> "$HOME/Downloads/NoSleep-Installer.pkg" --clobber

# 7. Sidecar install instructions. The pkg is unsigned/unnotarized, so macOS
#    Gatekeeper blocks a plain double-click BEFORE the installer's own welcome
#    screen can ever show. These instructions must live OUTSIDE the pkg.
cat > "$HOME/Downloads/How to Install NoSleep.txt" <<'TXT'
HOW TO INSTALL NOSLEEP
======================

NoSleep is open-source and safe, but it is not signed with a paid Apple
Developer certificate. So the first time you open it, macOS shows a warning
like:

  "Apple could not verify NoSleep.pkg is free of malware..."

This is normal for unsigned apps. To install:

  1. In Finder, go to your Downloads folder.
  2. RIGHT-CLICK (or Control-click) "NoSleep-Installer.pkg".
  3. Choose "Open" from the menu.
  4. In the warning dialog, click "Open" (this button only appears via
     right-click → Open, not a normal double-click).
  5. Follow the installer. NoSleep launches automatically when it finishes.

You only need to do this once.

--------------------------------------------------------------------
Alternative (Terminal): remove the quarantine flag, then double-click:

  xattr -d com.apple.quarantine ~/Downloads/NoSleep-Installer.pkg

--------------------------------------------------------------------
USING NOSLEEP
  - Press  Control-Command-S  to toggle Sleep / No-Sleep.
  - Or click the "S" icon in your menu bar for timers and options.
  - The first time you keep the lid closed, macOS asks for your
    password once to allow it. After that it is silent.
  - To uninstall, choose "Uninstall NoSleep..." from the menu.
TXT

echo "Installer:    ~/Downloads/NoSleep-Installer.pkg"
echo "Instructions: ~/Downloads/How to Install NoSleep.txt"
