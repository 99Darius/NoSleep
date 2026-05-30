# NoSleep — Design

**Date:** 2026-05-30
**Status:** Approved design, ready for implementation

## Summary

NoSleep is a lightweight macOS menu bar utility that prevents the Mac from
going to sleep on demand. It keeps the **system** awake (downloads, builds,
long-running tasks) while still allowing the **display** to sleep. It is
controlled three ways — a menu bar item, a global hotkey (`⌃⌘Z`), and a CLI
(`nosleep`) — all kept in sync through a single source of truth.

## Goals

- One-click / one-keystroke toggle between normal sleep and "stay awake".
- System-only awake (screen may still sleep) to save power.
- Optional auto-off timers so it is never left on by accident.
- A CLI that drives the same running agent (no divergent state).
- Launch at login by default, starting in the inactive (normal-sleep) state.

## Non-goals (YAGNI)

- Keeping the **display** awake (cut: system-only is the chosen scope).
- Preventing forced sleep (lid close, Apple menu → Sleep). Idle sleep only.
- Cross-platform support. macOS native only.
- Scheduling/rules engine, multiple profiles, analytics.

## Hotkey

`⌃⌘Z` (Control + Command + Z). Z = "zzz". Adding Control avoids any clash with
`⌘Z` (undo) because a global hotkey registration matches the full modifier set.
Triple-modifier combos are very rarely claimed by other apps.

## Two states

- `yes-sleep` (inactive) — no power assertion held; Mac sleeps normally.
  Default at launch.
- `no-sleep` (active) — holds `kIOPMAssertionTypePreventUserIdleSystemSleep`;
  display still allowed to sleep.

## Architecture

Single app bundle, menu bar agent is the single source of truth. It holds the
one IOKit power assertion. Hotkey, menu, and CLI all funnel into the same
`AssertionManager`. The CLI never holds its own assertion.

```
NoSleep.app
├─ Menu bar agent (LSUIElement=true, no Dock icon)
│   ├─ AssertionManager  → IOKit PreventUserIdleSystemSleep
│   ├─ HotkeyManager     → global ⌃⌘Z (Carbon RegisterEventHotKey)
│   ├─ TimerController    → auto-off presets
│   └─ MenuController     → NSStatusItem + menu
└─ nosleep (CLI)          → sends commands via IPC, reads shared state
```

## Components

### AssertionManager
- `activate()` → `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionLevelOn, "NoSleep active", &id)`; store `IOPMAssertionID`.
- `deactivate()` → `IOPMAssertionRelease(id)`; clear id.
- `isActive` derived from whether an id is held.
- Idempotent: activating while active reuses the existing id (no leaks).
- Always writes shared state + refreshes the menu on any change.
- Real IOKit impl sits behind a `SleepBlocking` protocol so logic is testable
  against a fake.

### HotkeyManager
- Carbon `RegisterEventHotKey` with `kVK_ANSI_Z` + `cmdKey | controlKey`
  (only reliable in-process global hotkey needing no Accessibility permission).
- Fires → `toggle()`.
- Registration failure (combo taken) → one-time menu warning; app still works
  via menu/CLI. Never crash.

### TimerController
- Presets: 15m / 1h / 2h / until-off.
- Timed activate starts a `DispatchSourceTimer`; on fire → `deactivate()` +
  reset menu.
- Owns exactly one active timer: always cancel-before-set. Manual off cancels
  any pending timer; selecting a new duration replaces the old one.

### MenuController
- `NSStatusItem`. Icon reflects state: outline `moon` when inactive,
  filled/slashed icon when active.
- Menu: toggle line (state + remaining time), duration submenu,
  "Launch at Login" checkbox, Quit.

### CLI (`nosleep`)
- Subcommands: `on`, `off`, `toggle`, `status`, `timer <dur>`.
- Sends command to the agent, prints resulting state.

## IPC & data flow

**Command channel (CLI → agent):** `DistributedNotificationCenter`.
- CLI posts `com.nosleep.cmd` with userInfo, e.g. `{action:"toggle"}` or
  `{action:"timer", seconds:3600}`.
- Agent observes and routes to `AssertionManager` / `TimerController`.
- No entitlement/Accessibility needed; works across same-user processes.

**State channel (agent → CLI):** shared `UserDefaults` suite
(`com.nosleep.shared`).
- Agent writes `{active: Bool, expiresAt: Date?, pid: Int}` on every change.
- CLI `status` reads it directly → prints `active (1h2m left)` or `inactive`.

**Agent-running detection:** CLI checks `NSRunningApplication` by bundle id
and/or the written pid.
- `on` / `toggle` / `timer` while agent is dead → `open -b com.nosleep`, wait
  briefly for heartbeat, then post.
- `off` / `status` on a dead agent → report `inactive` (nothing is holding
  sleep anyway).

**Sync guarantee:** every entry point mutates state only through
`AssertionManager`, which always writes shared defaults + refreshes the menu.
One path, no divergence.

### Example — `nosleep timer 1h`
1. CLI checks agent running; launches it if needed.
2. CLI posts `{action:timer, seconds:3600}`.
3. Agent activates assertion, starts 1h timer, writes state, updates icon.
4. CLI reads shared state → prints `active (1h left)`.

## Launch at login
- `SMAppService.mainApp.register()` (modern API, no helper bundle).
- Default enabled; starts inactive.
- Menu checkbox toggles register/unregister; surface failures in the menu.

## Edge cases
- **Assertion leaks:** guard on stored id; release on
  `applicationWillTerminate`. macOS auto-releases on process death (safety net).
- **Stale shared state:** if state says `active` but no agent pid is alive, CLI
  treats it as `inactive` (the assertion died with the process).
- **Idle-only:** `PreventUserIdleSystemSleep` blocks idle sleep only. Lid close
  and Apple menu → Sleep still sleep. Documented, not a bug.
- **Display sleep:** by design the screen still sleeps. Expected.

## Build & packaging
- Swift Package Manager. Two products: `NoSleepApp` (executable → `.app`) and
  `nosleep` (CLI executable).
- `make bundle` assembles `NoSleep.app`: Info.plist (`LSUIElement=true`,
  bundle id `com.nosleep`), copies `nosleep` into `Contents/MacOS/`, symlinks to
  `/usr/local/bin/nosleep`.
- Ad-hoc sign for local use. Document Developer ID + notarization for
  distribution. Carbon hotkey + IOKit need no special entitlements.

## Testing
- **Unit:** AssertionManager (activate→active, double-activate no leak,
  deactivate→inactive); TimerController (fire→deactivate, replace cancels old,
  manual-off cancels); CLI arg parsing; duration formatting.
- **Integration:** post DistributedNotification → assert shared-defaults flips;
  CLI `status` reads correctly; agent-not-running launch path.
- **Manual smoke checklist:** menu/hotkey/CLI toggles all sync; `pmset -g
  assertions` shows/clears `PreventUserIdleSystemSleep`; timer auto-reverts;
  launch-at-login persists across reboot.
