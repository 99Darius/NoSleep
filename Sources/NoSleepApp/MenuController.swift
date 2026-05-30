import AppKit
import NoSleepCore

final class MenuController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var onToggle: (() -> Void)?
    var onTimer: ((TimeInterval) -> Void)?
    var onToggleLoginItem: (() -> Void)?
    var onQuit: (() -> Void)?

    init() { build() }

    private func build() {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Enable NoSleep", action: #selector(toggleTapped), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        let durations: [(String, TimeInterval)] = [("15 minutes", 900), ("1 hour", 3600), ("2 hours", 7200)]
        let timerMenu = NSMenu()
        for (title, secs) in durations {
            let item = NSMenuItem(title: title, action: #selector(timerTapped(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = secs
            timerMenu.addItem(item)
        }
        let timerParent = NSMenuItem(title: "Stay awake for…", action: nil, keyEquivalent: "")
        timerParent.submenu = timerMenu
        menu.addItem(timerParent)
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(loginTapped), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Quit NoSleep", action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        render(state: .inactive)
    }

    /// Update icon + toggle label/remaining time.
    func render(state: NoSleepState) {
        let symbol = state.isActive ? "moon.zzz.fill" : "moon"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "NoSleep")
        guard let toggle = statusItem.menu?.items.first else { return }
        if state.isActive {
            if let exp = state.expiresAt {
                let left = max(0, exp.timeIntervalSinceNow)
                toggle.title = "Disable NoSleep (\(formatDuration(seconds: left)) left)"
            } else {
                toggle.title = "Disable NoSleep"
            }
        } else {
            toggle.title = "Enable NoSleep"
        }
        statusItem.menu?.items.first(where: { $0.title == "Launch at Login" })?.state =
            LoginItem.isEnabled ? .on : .off
    }

    @objc private func toggleTapped() { onToggle?() }
    @objc private func timerTapped(_ sender: NSMenuItem) {
        if let secs = sender.representedObject as? TimeInterval { onTimer?(secs) }
    }
    @objc private func loginTapped() { onToggleLoginItem?() }
    @objc private func quitTapped() { onQuit?() }
}
