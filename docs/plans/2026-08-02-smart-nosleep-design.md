# Smart NoSleep — sleep automatically once your coding agents finish

**Date:** 2026-08-02
**Status:** validated with user (approach A + B, mode model confirmed)

## Problem

NoSleep's primary use is keeping a Mac awake (lid closed) while coding agents
(Claude Code, Codex, aider, Ollama, desktop AI apps) work overnight. When the
agents finish, the machine stays hot and drains battery until the user manually
turns NoSleep off.

## Product model (per user)

Two keep-awake modes; **Smart NoSleep is the default**:

- **Smart NoSleep** — don't sleep while an agent is running; once agents go
  idle, release the block and let the Mac sleep.
- **Absolute NoSleep** — never sleep, no matter what (previous behavior).

Mode is a persisted setting, chosen in the menu; the hotkey/CLI/menu toggle
turns keep-awake on/off in whichever mode is selected.

## Key facts (verified 2026-08-02)

- `/etc/sudoers.d/nosleep` (installed by `PMSetSleepBlocker`) already grants
  passwordless `pmset -a disablesleep 0|1`, so the agent can release the sleep
  block unattended — no admin prompt when nobody is at the keyboard.
- Releasing `disablesleep` with the lid closed triggers clamshell sleep
  immediately; lid open falls back to the normal macOS idle-sleep timer.
- Process existence is not a usable signal: Claude Desktop keeps ~6 Electron
  helpers alive while idle, and idle `claude` CLI sessions sit at a shell
  prompt indefinitely.
- CPU activity separates cleanly: idle `claude` CLI ≈ 0.1–0.2% CPU; an active
  session ≈ 2.3%+. Sampling CPU-time deltas per polling tick (not `pcpu`,
  which is a decaying average) gives a robust activity measure.

## Design

Two complementary activity signals feed one idle decision:

### A. CPU-activity monitor (zero-config, covers every agent)

- `AgentActivityMonitor` (NoSleepApp) polls every 60 s while keep-awake is
  active **and** mode is Smart.
- Each tick: enumerate processes whose name/args match the watchlist, read
  cumulative CPU time (`proc_pid_rusage`), compute the delta since the last
  tick. Tick is "busy" if any watched process used ≥ 1.0 s of CPU during the
  interval.
- Default watchlist (user-overridable via UserDefaults key `agentWatchlist`):
  `claude`, `codex`, `aider`, `ollama`, `gemini`, `cursor-agent`, `copilot`,
  `Claude Helper`, `ChatGPT`.

### B. Heartbeat — `nosleep ping` (exact, opt-in per tool)

- New CLI verb `ping` → distributed notification to the agent, which stamps
  `lastHeartbeat` in the shared UserDefaults suite.
- A heartbeat younger than the grace window counts as a busy tick.
- Intended use: Claude Code `PostToolUse`/`Stop` hooks run `nosleep ping`.

### Idle decision (NoSleepCore, pure logic, unit-tested)

- `IdleDetector`: consumes a busy/idle bool per tick; after `graceWindow`
  (default 15 min) of consecutive idle ticks → fires `onIdle`. Any busy tick
  resets the counter. Hysteresis lives here, not in the sampler.
- On idle: post a user notification ("No agent activity for 15 min — allowing
  sleep"), then call the existing `manager.deactivate()` path so
  `disablesleep 0`, shared-store state, and the menu icon all stay truthful.

### UI

- Menu gains a mode picker: "Smart NoSleep (sleep when agents finish)" /
  "Absolute NoSleep (never sleep)". Default Smart. Persisted key `mode`.
- Grace period submenu 5 m / 15 m / 30 m / 60 m under Smart.
- Mode survives across on/off toggles; the monitor starts/stops with the
  keep-awake assertion.

### Testability

- New seam `ProcessActivitySampling` (protocol) with a fake for tests, same
  pattern as `SleepBlocking` / `TimerScheduling`.
- `IdleDetector` + watchlist matching live in NoSleepCore with XCTests; the
  real `proc_pid_rusage` sampler stays thin inside NoSleepApp.

## Website changes (same request)

- Email capture before download: form gates the Download button; on submit
  POST `/api/subscribe` (Vercel serverless function) → Resend Audiences REST
  API using `RESEND_API_KEY` + `RESEND_AUDIENCE_ID` env vars. Download always
  proceeds even if the API call fails — collection is best-effort, never a
  hard wall. `localStorage` remembers a submitted email so returning visitors
  skip the form.
- Open-source (GitHub repo) link surfaced prominently near the download CTA
  (already present in footer).

## Out of scope / rejected

- `nosleep run -- <cmd>` wrapper: interactive agents never exit; YAGNI.
- Network-traffic sampling (`nettop`): more moving parts, CPU delta already
  separates idle vs. active.
- Forcing immediate sleep (`pmset sleepnow`) lid-open: releasing the block and
  letting macOS's own idle timer decide is safer and simpler.

## Known caveats

- Agents running remotely (SSH'd out, cloud sessions) look idle locally; the
  Mac will sleep and drop the connection. Documented, accepted.
- A watched agent that stays "thinking" with ~0 CPU for longer than the grace
  window would trigger sleep; `nosleep ping` from hooks makes Claude Code
  immune, and Absolute mode is one click away.
