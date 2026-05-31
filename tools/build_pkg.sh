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

# 1. Build the app bundle straight into the staging pkgroot at its install
#    location (APP= overrides the Makefile's default). We deliberately do NOT
#    create NoSleep.app in the repo: a stale, root-owned bundle there (e.g. left
#    by an aborted run) would make `make bundle`'s `rm -rf` fail and block every
#    future build.
APP_DST="$BUILD/pkgroot/Applications/NoSleep.app"
make bundle APP="$APP_DST" >/dev/null

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

On recent macOS (Sequoia and later) the old "right-click -> Open" trick no
longer offers an Open button — you only get Done / Move to Bin. Use Terminal
instead:

  1. Open the Terminal app (Applications > Utilities > Terminal).
  2. Copy-paste this line and press Return:

       xattr -d com.apple.quarantine ~/Downloads/NoSleep-Installer.pkg

     (If it says "No such xattr", run:  xattr -c ~/Downloads/NoSleep-Installer.pkg )
  3. Now double-click NoSleep-Installer.pkg in Downloads. It opens normally.
  4. Follow the installer. NoSleep launches automatically when it finishes.

You only need to do this once.

--------------------------------------------------------------------
USING NOSLEEP
  - Press  Control-Command-S  to toggle Sleep / No-Sleep.
  - Or click the menu bar icon for timers and options.
  - The first time you keep the lid closed, macOS asks for your
    password once to allow it. After that it is silent.
  - To uninstall, choose "Uninstall NoSleep..." from the menu.
TXT

echo "Installer:    ~/Downloads/NoSleep-Installer.pkg"
echo "Instructions: ~/Downloads/How to Install NoSleep.txt"
