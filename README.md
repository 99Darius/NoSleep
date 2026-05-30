# NoSleep

A tiny macOS menu bar agent (`NoSleep.app`) plus a `nosleep` CLI that keep your
Mac awake on demand — **even with the lid closed**, no external display needed.

When you turn NoSleep on it sets `pmset disablesleep 1`, the one setting that
overrides clamshell (lid-close) sleep; turning it off restores
`disablesleep 0`. Because that setting is system-wide it needs root, so macOS
asks for your **administrator password** when you toggle it. A single menu bar
agent is the source of truth; the menu, a global hotkey, and the CLI all drive
that one shared state.

> ⚠️ With the lid closed there's no airflow — your Mac can get warm, especially
> while charging. Keep it somewhere ventilated. NoSleep restores normal sleep
> when you disable it or quit. If it's ever force-quit while active, run
> `sudo pmset -a disablesleep 0` to restore sleep.

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

NoSleep uses `pmset disablesleep`, which fully disables system sleep while it's on:

- **Requires your admin password** each time you toggle it (it changes a
  system-wide power setting). The authorization is cached briefly by macOS.
- **Heat:** with the lid closed there's no airflow — the Mac can get warm,
  especially while charging. Use it somewhere ventilated.
- **It really doesn't sleep.** While active, idle sleep, lid-close (clamshell)
  sleep, and even Apple menu → Sleep are all suppressed. Turn NoSleep off (or
  quit it) to get normal sleep back.
- **The display may still turn off** to save power; the *system* stays awake
  behind it (audio keeps playing, downloads keep running).
- **If force-quit while active**, the setting persists — restore sleep with
  `sudo pmset -a disablesleep 0`.
