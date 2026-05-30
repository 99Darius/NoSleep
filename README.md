# NoSleep

A tiny macOS menu bar agent (`NoSleep.app`) plus a `nosleep` CLI that keep your
Mac awake on demand. A single menu bar agent owns one IOKit power assertion and
is the source of truth; the menu, a global hotkey, and the CLI all drive that
one shared state.

## Build

```bash
make bundle
```

This runs `swift build -c release`, assembles `NoSleep.app`, and ad-hoc
codesigns it.

## Install

```bash
# Copy the app into /Applications
cp -R NoSleep.app /Applications/

# Symlink the bundled CLI onto your PATH
ln -sf /Applications/NoSleep.app/Contents/MacOS/nosleep /usr/local/bin/nosleep
```

Launch it once with `open /Applications/NoSleep.app`. An "S" icon appears in the
menu bar (no Dock icon) — struck through when keep-awake is active. "Launch at
Login" is enabled by default.

## Hotkey

Press **⌃⌘S** (Control-Command-S) anywhere to toggle keep-awake on/off.

To rebind it, open the menu bar item → **Change Shortcut…**, click the field,
and press your new combination ("Reset to ⌃⌘S" restores the default). Powered by
[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).

## CLI

```bash
nosleep on                 # keep awake until turned off
nosleep off                # allow sleep again
nosleep toggle             # flip the current state
nosleep status             # print "active" / "active (Nm left)" / "inactive"
nosleep timer 15m          # keep awake for 15 minutes, then auto-off
nosleep timer 1h           # 1 hour
nosleep timer 2h           # 2 hours
nosleep timer 90s          # 90 seconds
```

Durations accept `s`, `m`, and `h` suffixes. Any command other than `status`/`off`
will launch the menu bar agent automatically if it isn't already running, and the
CLI stays in sync with the menu since both talk to the same agent.

## Uninstall

Easiest: open the menu bar item → **Uninstall NoSleep…** → confirm. That turns off
keep-awake, removes the Launch at Login item, deletes NoSleep's settings and
shortcut, removes the `nosleep` CLI symlink, and moves `NoSleep.app` to the Trash.

To do it manually instead:

```bash
osascript -e 'tell application id "com.nosleep" to quit'   # or quit from the menu
rm -rf /Applications/NoSleep.app                            # wherever you put it
rm -f /usr/local/bin/nosleep                                # if you symlinked the CLI
defaults delete com.nosleep.shared 2>/dev/null              # saved state
# Launch at Login is cleared automatically on quit/removal.
```

## Caveats

NoSleep blocks **idle system sleep only** (`PreventUserIdleSystemSleep`). It is
deliberately minimal:

- **Closing the lid still sleeps the Mac.** Clamshell sleep is a hardware/OS
  behavior that an idle-sleep assertion does not override.
- **Apple menu → Sleep still sleeps the Mac.** Explicit user-requested sleep is
  always honored.
- **The display still sleeps / dims by design.** NoSleep keeps the *system*
  awake (e.g. for downloads or builds), not the screen.
