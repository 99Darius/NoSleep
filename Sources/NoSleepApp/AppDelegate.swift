import AppKit
import KeyboardShortcuts
import NoSleepCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let commandNotification = Notification.Name("com.nosleep.cmd")

    private let blocker = PMSetSleepBlocker()
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
        menu.onUninstall = { Uninstaller.run() }

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
        reconcileLeftoverSleepBlock()
    }

    /// NoSleep always starts inactive. If the system still has sleep disabled,
    /// it was left on by a previous force-quit — offer to restore normal sleep.
    private func reconcileLeftoverSleepBlock() {
        guard PMSetSleepBlocker.systemSleepDisabled() else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Turn sleep back on?"
        alert.informativeText = """
        NoSleep is currently keeping your Mac awake from a previous session. \
        Want to switch back to normal sleep?
        """
        alert.addButton(withTitle: "Turn Sleep Back On")
        alert.addButton(withTitle: "Keep Awake")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            blocker.forceRestoreSleep()   // admin prompt → disablesleep 0
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.deactivate()   // never leak the assertion
    }

    private func handleToggle() {
        if manager.isActive {
            timer.cancel(); currentExpiry = nil
            manager.deactivate()        // pmset disablesleep 0 (admin prompt)
        } else {
            activateClosedLid()
        }
    }

    private func handleTimer(_ seconds: TimeInterval) {
        currentExpiry = Date().addingTimeInterval(seconds)
        timer.start(seconds: seconds)
        activateClosedLid()
        // If the user cancelled the admin prompt, don't leave a dangling timer.
        if !manager.isActive { timer.cancel(); currentExpiry = nil }
        persistAndRender()
    }

    /// Turn on closed-lid keep-awake, showing the heat/lid warning the first time.
    private func activateClosedLid() {
        guard confirmClosedLidIfNeeded() else { return }
        manager.activate()              // triggers the admin prompt via PMSetSleepBlocker
    }

    /// One-time warning about closed-lid behavior, admin auth, and heat.
    private func confirmClosedLidIfNeeded() -> Bool {
        if UserDefaults.standard.bool(forKey: "didShowClosedLidWarning") { return true }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Keep your Mac awake — even with the lid closed"
        alert.informativeText = """
        Your Mac will stay awake until you turn NoSleep off, so music, \
        downloads, and other tasks keep going even if you close the lid.

        • macOS will ask for your password once to allow this.
        • The lid blocks airflow, so give your Mac some room to breathe while \
        charging.

        Turn it off anytime from the menu or with ⌃⌘S.
        """
        alert.addButton(withTitle: "Keep Awake")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        UserDefaults.standard.set(true, forKey: "didShowClosedLidWarning")
        return true
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
            case .on: self.timer.cancel(); self.currentExpiry = nil; self.activateClosedLid()
            case .off: self.timer.cancel(); self.currentExpiry = nil; self.manager.deactivate()
            case .toggle: self.handleToggle()
            case .timer(let s): self.handleTimer(s)
            case .status: self.persistAndRender()   // ensure store is fresh
            }
        }
    }
}
