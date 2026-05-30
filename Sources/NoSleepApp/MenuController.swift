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
    /// Supplies the live state so the menu can re-render (e.g. countdown) when opened.
    var currentState: (() -> NoSleepState)?

    override init() {
        super.init()
        // Persist the icon's menu bar position once the user ⌘-drags it.
        // (macOS has no API to force right-most; system items always stay rightmost.)
        statusItem.autosaveName = "NoSleepStatusItem"
        build()
    }

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

        let shortcut = NSMenuItem(title: "Change Shortcut…", action: #selector(changeShortcutTapped), keyEquivalent: "")
        shortcut.target = self
        menu.addItem(shortcut)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(loginTapped), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

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
        statusItem.button?.image = Self.icon(crossed: state.isActive)
        statusItem.button?.image?.accessibilityDescription =
            state.isActive ? "NoSleep active" : "NoSleep inactive"
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
    @objc private func changeShortcutTapped() { onChangeShortcut?() }
    @objc private func uninstallTapped() { onUninstall?() }
    @objc private func quitTapped() { onQuit?() }
}
