# NoSleep

A tiny macOS menu bar agent (`NoSleep.app`) plus a `nosleep` CLI that keep your
Mac awake on demand — **even with the lid closed**, no external display needed.

When you turn NoSleep on it sets `pmset disablesleep 1`, the one setting that
overrides clamshell (lid-close) sleep; turning it off restores
`disablesleep 0`. Because that setting is system-wide it needs root, so macOS
asks for your **administrator password** when you toggle it. A single menu bar
agent is the source of truth; the menu, a global hotkey, and the CLI all drive
that one shared state.

> 💡 The lid blocks airflow, so give your Mac some room to breathe while
> charging. NoSleep restores normal sleep automatically when you turn it off or
> quit — and if it was ever left on (e.g. after a force-quit), it offers to
> switch sleep back on the next time it launches.

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

## Smart NoSleep vs Absolute NoSleep

NoSleep's main job is keeping your Mac awake while coding agents (Claude Code,
Codex, aider, Ollama, …) work — often overnight with the lid closed. Two modes,
picked from the menu:

- **Smart NoSleep** (default) — stays awake while your agents are working.
  Once every watched agent has been idle for the grace period (default
  15 minutes, configurable 5/15/30/60), NoSleep turns itself off so the Mac can
  sleep — saving battery and heat. You get a notification when that happens.
- **Absolute NoSleep** — never sleeps until you turn it off (or a timer fires).

Smart mode watches CPU activity of known agent processes (`claude`, `codex`,
`aider`, `ollama`, `gemini`, `cursor-agent`, `copilot`, ChatGPT). Override the
list with:

```bash
defaults write com.nosleep agentWatchlist -array claude ollama my-agent
```

For an exact signal, any tool can also run `nosleep ping` as a heartbeat — e.g.
a Claude Code `PostToolUse`/`Stop` hook. A ping counts as agent activity and
resets the idle window.

> Heads-up: an agent that only waits on a remote machine (SSH, cloud session)
> looks idle locally — use Absolute mode for those runs.

## CLI

```bash
nosleep on                 # keep awake until turned off
nosleep off                # allow sleep again
nosleep toggle             # flip the current state
nosleep status             # print "active" / "active (Nm left)" / "inactive"
nosleep ping               # agent-activity heartbeat for Smart NoSleep (silent)
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

## Good to know

NoSleep uses `pmset disablesleep`, which keeps the whole system awake while it's on:

- **Asks for your password** when you toggle it — it changes a system-wide power
  setting. macOS remembers the authorization for a little while.
- **Give it airflow:** with the lid closed there's no ventilation, so keep your
  Mac somewhere open while charging.
- **It stays fully awake** while on — idle, lid-close, and even Apple menu →
  Sleep are all held off. Turn NoSleep off (or quit it) for normal sleep again.
- **The screen can still turn off** to save power; the system keeps running
  behind it (music plays, downloads continue).
- **Never get stuck:** if NoSleep is ever left on after a force-quit, it notices
  on its next launch and offers to switch sleep back on — no Terminal needed.
  (If you ever want to do it by hand: `sudo pmset -a disablesleep 0`.)
