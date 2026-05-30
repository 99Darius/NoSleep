import AppKit
import KeyboardShortcuts
import NoSleepCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let commandNotification = Notification.Name("com.nosleep.cmd")

    private let blocker = IOKitSleepBlocker()
    private lazy var manager = AssertionManager(blocker: blocker)
    private lazy var timer = TimerController(scheduler: DispatchTimerScheduler()) { [weak self] in
        self?.manager.deactivate()
    }
    private let menu = MenuController()
    private let store = StateStore.shared()
    private let shortcutSettings = ShortcutSettingsWindowController()
    private var currentExpiry: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        manager.onChange = { [weak self] in self?.persistAndRender() }

        menu.onToggle = { [weak self] in self?.handleToggle() }
        menu.onTimer = { [weak self] secs in self?.handleTimer(secs) }
        menu.onToggleLoginItem = { [weak self] in self?.toggleLoginItem() }
        menu.onQuit = { NSApp.terminate(nil) }
        menu.currentState = { [weak self] in
            guard let self else { return .inactive }
            return NoSleepState(isActive: self.manager.isActive, expiresAt: self.currentExpiry)
        }
        menu.onChangeShortcut = { [weak self] in self?.shortcutSettings.show() }

        // Global hotkey (default ⌃⌘S, user-rebindable). KeyboardShortcuts registers
        // the persisted shortcut and delivers callbacks on the main thread.
        KeyboardShortcuts.onKeyDown(for: .toggle) { [weak self] in self?.handleToggle() }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleCommand(_:)),
            name: AppDelegate.commandNotification, object: nil)

        // Default-on login item on first launch. Only mark as done if it succeeded,
        // so a failure retries on the next launch.
        if !UserDefaults.standard.bool(forKey: "didSetDefaultLoginItem") {
            if LoginItem.setEnabled(true) {
                UserDefaults.standard.set(true, forKey: "didSetDefaultLoginItem")
            }
        }

        persistAndRender()   // start inactive
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.deactivate()   // never leak the assertion
    }

    private func handleToggle() {
        if manager.isActive { timer.cancel(); currentExpiry = nil }
        manager.toggle()
    }

    private func handleTimer(_ seconds: TimeInterval) {
        currentExpiry = Date().addingTimeInterval(seconds)
        timer.start(seconds: seconds)
        manager.activate()
        persistAndRender()
    }

    private func toggleLoginItem() {
        let desired = !LoginItem.isEnabled
        if !LoginItem.setEnabled(desired) {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = desired ? "Couldn't enable Launch at Login"
                                        : "Couldn't disable Launch at Login"
            alert.informativeText = "NoSleep was unable to update the Launch at Login setting. Please try again."
            alert.runModal()
        }
        // The next render re-reads LoginItem.isEnabled, so the checkmark stays truthful.
        menu.render(state: NoSleepState(isActive: manager.isActive, expiresAt: currentExpiry))
    }

    private func persistAndRender() {
        if !manager.isActive { currentExpiry = nil }
        let state = NoSleepState(isActive: manager.isActive, expiresAt: currentExpiry)
        store.save(state, pid: ProcessInfo.processInfo.processIdentifier)
        menu.render(state: state)
    }

    @objc private func handleCommand(_ note: Notification) {
        // DistributedNotificationCenter may deliver off the main thread; hop to main
        // so all manager/timer/menu/currentExpiry touches honor the concurrency model.
        let userInfo = note.userInfo
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let cmd = Command(userInfo: userInfo) else { return }
            switch cmd {
            case .on: self.timer.cancel(); self.currentExpiry = nil; self.manager.activate()
            case .off: self.timer.cancel(); self.currentExpiry = nil; self.manager.deactivate()
            case .toggle: self.handleToggle()
            case .timer(let s): self.handleTimer(s)
            case .status: self.persistAndRender()   // ensure store is fresh
            }
        }
    }
}
