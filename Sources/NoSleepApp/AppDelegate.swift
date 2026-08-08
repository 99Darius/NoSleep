import AppKit
import KeyboardShortcuts
import NoSleepCore
import UserNotifications

/// Persisted Smart NoSleep settings.
enum SmartSettings {
    static var mode: KeepAwakeMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "keepAwakeMode") ?? ""
            return KeepAwakeMode(rawValue: raw) ?? .smart   // Smart is the default
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "keepAwakeMode") }
    }

    static var graceMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "smartGraceMinutes")
            return v > 0 ? v : 15
        }
        set { UserDefaults.standard.set(newValue, forKey: "smartGraceMinutes") }
    }

    static var watchlist: AgentWatchlist {
        if let patterns = UserDefaults.standard.stringArray(forKey: "agentWatchlist"),
           !patterns.isEmpty {
            return AgentWatchlist(patterns: patterns)
        }
        return .default
    }
}

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
    private lazy var monitor = AgentActivityMonitor(sampler: AgentProcessSampler(),
                                                    presence: SystemUserPresence(),
                                                    store: store)

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
        menu.currentMode = { (SmartSettings.mode, SmartSettings.graceMinutes) }
        menu.onSelectMode = { [weak self] mode in
            SmartSettings.mode = mode
            self?.syncMonitor()
            self?.persistAndRender()
        }
        menu.onSelectGrace = { [weak self] minutes in
            SmartSettings.graceMinutes = minutes
            self?.syncMonitor(restart: true)
            self?.persistAndRender()
        }
        monitor.onIdle = { [weak self] in self?.handleAgentsIdle() }

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
        Your Mac will stay awake so music, downloads, and coding agents keep \
        going even if you close the lid.

        • Smart NoSleep (default): once your coding agents finish working, \
        NoSleep lets the Mac sleep again to save battery and heat.
        • Absolute NoSleep: stays awake until you turn it off.
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
        syncMonitor()
    }

    /// The agent-activity monitor runs exactly while keep-awake is active in
    /// Smart mode. `restart` forces a fresh grace window (e.g. after the user
    /// changes the grace period).
    private func syncMonitor(restart: Bool = false) {
        let shouldRun = manager.isActive && SmartSettings.mode == .smart
        if shouldRun {
            if restart || !monitor.isRunning {
                monitor.start(graceMinutes: SmartSettings.graceMinutes,
                              watchlist: SmartSettings.watchlist)
                // Ask for notification permission NOW, while the user is at
                // the keyboard — at fire time (3 AM, lid closed) the auth
                // prompt would never be seen.
                requestNotificationAuthOnce()
            }
        } else {
            monitor.stop()
        }
    }

    private var didRequestNotificationAuth = false
    private func requestNotificationAuthOnce() {
        guard !didRequestNotificationAuth, Bundle.main.bundleIdentifier != nil else { return }
        didRequestNotificationAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    /// Smart NoSleep verdict: agents idle for the whole grace window.
    /// Release the sleep block (passwordless sudo rule → no prompt needed
    /// while unattended) and tell the user why.
    private func handleAgentsIdle() {
        guard manager.isActive else { return }
        notifyAgentsIdle(graceMinutes: SmartSettings.graceMinutes,
                         lastAgents: monitor.lastBusyAgents,
                         lastActivity: monitor.lastBusyDate)
        timer.cancel()
        currentExpiry = nil
        manager.deactivate()
    }

    /// Rich "went to sleep" toast. With the lid closed it lands in
    /// Notification Center, so the user sees the full story on wake:
    /// when Smart NoSleep released the block, how long agents were idle,
    /// and what was running before.
    private func notifyAgentsIdle(graceMinutes: Int, lastAgents: [String], lastActivity: Date?) {
        let timeFmt = DateFormatter()
        timeFmt.timeStyle = .short
        timeFmt.dateStyle = .none
        let now = timeFmt.string(from: Date())

        var body = "Smart NoSleep let your Mac sleep at \(now) — no agents working and no one using the Mac for \(graceMinutes) min."
        if !lastAgents.isEmpty {
            let names = lastAgents.joined(separator: ", ")
            if let seen = lastActivity {
                body += " Last running: \(names) (until \(timeFmt.string(from: seen)))."
            } else {
                body += " Last running: \(names)."
            }
        } else {
            body += " No coding agents were seen running."
        }

        let title = "NoSleep turned itself off"
        // UNUserNotificationCenter traps in un-bundled dev runs (swift run):
        // go straight to the in-app toast there.
        guard Bundle.main.bundleIdentifier != nil else {
            ToastPanel.show(title: title, body: body)
            return
        }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                center.add(UNNotificationRequest(identifier: "com.nosleep.agents-idle",
                                                 content: content, trigger: nil))
            } else {
                // Auth denied/never granted (common for ad-hoc-signed builds):
                // fall back to our own floating toast so the user still sees
                // when and why the Mac went to sleep.
                DispatchQueue.main.async {
                    ToastPanel.show(title: title, body: body)
                }
            }
        }
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
            case .ping: break   // heartbeat is written straight to the shared store by the CLI
            }
        }
    }
}
