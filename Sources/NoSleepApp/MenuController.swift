import AppKit
import NoSleepCore

final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var onToggle: (() -> Void)?
    var onTimer: ((TimeInterval) -> Void)?
    var onToggleLoginItem: (() -> Void)?
    var onChangeShortcut: (() -> Void)?
    var onUninstall: (() -> Void)?
    var onQuit: (() -> Void)?
    var onSelectMode: ((KeepAwakeMode) -> Void)?
    var onSelectGrace: ((Int) -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onToggleAutoUpdate: (() -> Void)?
    /// Supplies the pending update (if any) plus whether auto-checking is on.
    var currentUpdate: (() -> (available: String?, autoEnabled: Bool))?
    /// Supplies the live state so the menu can re-render (e.g. countdown) when opened.
    var currentState: (() -> NoSleepState)?
    /// Supplies the persisted mode + grace minutes for menu checkmarks.
    var currentMode: (() -> (KeepAwakeMode, Int))?

    private var toggleItem: NSMenuItem?
    private var loginItem: NSMenuItem?
    private var smartModeItem: NSMenuItem?
    private var absoluteModeItem: NSMenuItem?
    private var graceParentItem: NSMenuItem?
    private var graceItems: [NSMenuItem] = []
    private var updateItem: NSMenuItem?
    private var autoUpdateItem: NSMenuItem?

    override init() {
        super.init()
        // Persist the icon's menu bar position once the user ⌘-drags it.
        // (macOS has no API to force right-most; system items always stay rightmost.)
        statusItem.autosaveName = "NoSleepStatusItem"
        build()
    }

    private func build() {
        let menu = NSMenu()

        // Prominent, non-clickable reminder of the global shortcut.
        let hint = NSMenuItem(title: "Press  ⌃⌘S  to toggle Sleep / No-Sleep", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        // The toggle item also displays "⌃⌘S" next to it as a constant reminder.
        let toggle = NSMenuItem(title: "Enable NoSleep", action: #selector(toggleTapped), keyEquivalent: "s")
        toggle.keyEquivalentModifierMask = [.command, .control]
        toggle.target = self
        menu.addItem(toggle)
        toggleItem = toggle
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

        // Keep-awake mode: Smart (default) sleeps once coding agents go idle;
        // Absolute never sleeps until turned off.
        let smart = NSMenuItem(title: "Smart NoSleep — sleep when agents finish",
                               action: #selector(smartModeTapped), keyEquivalent: "")
        smart.target = self
        menu.addItem(smart)
        smartModeItem = smart

        let absolute = NSMenuItem(title: "Absolute NoSleep — never sleep",
                                  action: #selector(absoluteModeTapped), keyEquivalent: "")
        absolute.target = self
        menu.addItem(absolute)
        absoluteModeItem = absolute

        let graceMenu = NSMenu()
        for minutes in [5, 15, 30, 60] {
            let item = NSMenuItem(title: "\(minutes) minutes",
                                  action: #selector(graceTapped(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
            graceMenu.addItem(item)
            graceItems.append(item)
        }
        let graceParent = NSMenuItem(title: "Sleep after agents idle for…", action: nil, keyEquivalent: "")
        graceParent.submenu = graceMenu
        menu.addItem(graceParent)
        graceParentItem = graceParent
        menu.addItem(.separator())

        let shortcut = NSMenuItem(title: "Change Shortcut…", action: #selector(changeShortcutTapped), keyEquivalent: "")
        shortcut.target = self
        menu.addItem(shortcut)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(loginTapped), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        loginItem = login

        menu.addItem(.separator())

        let update = NSMenuItem(title: "Check for Updates…", action: #selector(checkUpdatesTapped), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        updateItem = update

        let autoUpdate = NSMenuItem(title: "Check Automatically", action: #selector(toggleAutoUpdateTapped), keyEquivalent: "")
        autoUpdate.target = self
        menu.addItem(autoUpdate)
        autoUpdateItem = autoUpdate

        menu.addItem(.separator())
        let uninstall = NSMenuItem(title: "Uninstall NoSleep…", action: #selector(uninstallTapped), keyEquivalent: "")
        uninstall.target = self
        menu.addItem(uninstall)

        let quit = NSMenuItem(title: "Quit NoSleep", action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        statusItem.menu = menu
        render(state: .inactive)
    }

    /// Refresh the countdown/labels each time the menu is shown so a running
    /// timer's "(Xm left)" text stays current.
    func menuWillOpen(_ menu: NSMenu) {
        if let state = currentState?() {
            render(state: state)
        }
        if let update = currentUpdate?() {
            updateItem?.title = update.available.map { "Update to \($0)…" } ?? "Check for Updates…"
            autoUpdateItem?.state = update.autoEnabled ? .on : .off
        }
    }

    /// Menu bar icon: an "S" (Sleep) in a rounded box. When active (no-sleep),
    /// the S is struck through. Rendered as a template image so the menu bar
    /// tints it for light/dark automatically.
    private static func icon(crossed: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.set()

        // Rounded square box.
        let inset: CGFloat = 1.5
        let rect = NSRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
        let box = NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5)
        box.lineWidth = 1.5
        box.stroke()

        // Centered "S".
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: para,
        ]
        let s = NSAttributedString(string: "S", attributes: attrs)
        let sHeight = s.size().height
        s.draw(in: NSRect(x: 0, y: (size.height - sHeight) / 2, width: size.width, height: sHeight))

        // Diagonal strike when active (no-sleep).
        if crossed {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: inset + 1, y: inset + 1))
            line.line(to: NSPoint(x: size.width - inset - 1, y: size.height - inset - 1))
            line.lineWidth = 1.8
            line.lineCapStyle = .round
            line.stroke()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// Update icon + toggle label/remaining time.
    func render(state: NoSleepState) {
        let dozing = state.dozing == true
        // The icon shows whether the MODE is on (engaged or dozing), not
        // whether the block is currently held — an uncrossed icon while
        // dozing read as "it switched itself off".
        statusItem.button?.image = Self.icon(crossed: state.isActive || dozing)
        statusItem.button?.image?.accessibilityDescription =
            state.isActive ? "NoSleep active" : (dozing ? "NoSleep dozing" : "NoSleep inactive")
        statusItem.button?.toolTip = "NoSleep — press ⌃⌘S to toggle Sleep / No-Sleep"
        guard let toggle = toggleItem else { return }
        if state.isActive {
            if let exp = state.expiresAt {
                let left = max(0, exp.timeIntervalSinceNow)
                toggle.title = "Disable NoSleep (\(formatDuration(seconds: left)) left)"
            } else {
                toggle.title = "Disable NoSleep"
            }
        } else if dozing {
            toggle.title = "Disable NoSleep (dozing — re-arms when agents run)"
        } else {
            toggle.title = "Enable NoSleep"
        }
        loginItem?.state = LoginItem.isEnabled ? .on : .off

        if let (mode, grace) = currentMode?() {
            smartModeItem?.state = mode == .smart ? .on : .off
            absoluteModeItem?.state = mode == .absolute ? .on : .off
            for item in graceItems {
                item.state = (item.representedObject as? Int) == grace ? .on : .off
            }
        }
    }

    @objc private func toggleTapped() { onToggle?() }
    @objc private func timerTapped(_ sender: NSMenuItem) {
        if let secs = sender.representedObject as? TimeInterval { onTimer?(secs) }
    }
    @objc private func loginTapped() { onToggleLoginItem?() }
    @objc private func smartModeTapped() { onSelectMode?(.smart) }
    @objc private func absoluteModeTapped() { onSelectMode?(.absolute) }
    @objc private func graceTapped(_ sender: NSMenuItem) {
        if let minutes = sender.representedObject as? Int { onSelectGrace?(minutes) }
    }
    @objc private func checkUpdatesTapped() { onCheckForUpdates?() }
    @objc private func toggleAutoUpdateTapped() { onToggleAutoUpdate?() }
    @objc private func changeShortcutTapped() { onChangeShortcut?() }
    @objc private func uninstallTapped() { onUninstall?() }
    @objc private func quitTapped() { onQuit?() }
}
