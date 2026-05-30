# NoSleep Manual Smoke Checklist

Run after `make bundle` and `open NoSleep.app`.

- [ ] Moon icon appears in the menu bar (no Dock icon).
- [ ] Click "Enable NoSleep" → icon becomes filled; `pmset -g assertions`
      shows `PreventUserIdleSystemSleep` held by NoSleep.
- [ ] Click "Disable NoSleep" → assertion clears from `pmset -g assertions`.
- [ ] Press ⌃⌘Z → toggles state; menu label updates.
- [ ] `nosleep on` → icon active; `nosleep status` prints `active`.
- [ ] `nosleep off` → `nosleep status` prints `inactive`.
- [ ] `nosleep toggle` flips state and stays in sync with the menu.
- [ ] `nosleep timer 15m` → active with countdown in menu; assertion auto-clears
      at expiry.
- [ ] Quit the app while a CLI command runs → `nosleep on` relaunches it.
- [ ] "Launch at Login" checked by default; survives reboot, starts inactive.
- [ ] Quit app → `pmset -g assertions` no longer lists NoSleep (no leak).
