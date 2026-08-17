import AppKit
import KeyboardShortcuts
import NoSleepCore
import UserNotifications
import os

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
    /// Smart NoSleep dozing: armed, but the sleep block is released because
    /// agents are idle. Persisted so an app relaunch stays armed. The block
    /// re-engages on the next busy tick (passwordless sudoers rule → silent).
    private var smartDozing: Bool {
        get { UserDefaults.standard.bool(forKey: "smartDozing") }
        set { UserDefaults.standard.set(newValue, forKey: "smartDozing") }
    }
    private let presence = SystemUserPresence()
    private lazy var monitor = AgentActivityMonitor(sampler: AgentProcessSampler(),
                                                    presence: presence,
                                                    store: store)
    private let updater = UpdateController()
    private var updateTimer: Timer?
    private var batteryTimer: Timer?
    /// The sleep block was released because the battery was nearly empty.
    /// Persisted like `smartDozing`: a relaunch must not forget why keep-awake
    /// is off and quietly re-engage it into a dying battery.
    private var batteryHold: Bool {
        get { UserDefaults.standard.bool(forKey: "batteryHold") }
        set { UserDefaults.standard.set(newValue, forKey: "batteryHold") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        manager.onChange = { [weak self] in self?.persistAndRender() }

        menu.onToggle = { [weak self] in self?.handleToggle() }
        menu.onTimer = { [weak self] secs in self?.handleTimer(secs) }
        menu.onToggleLoginItem = { [weak self] in self?.toggleLoginItem() }
        menu.onQuit = { NSApp.terminate(nil) }
        menu.currentState = { [weak self] in
            guard let self else { return .inactive }
            return NoSleepState(isActive: self.manager.isActive,
                                expiresAt: self.currentExpiry,
                                dozing: self.smartDozing ? true : nil)
        }
        menu.onChangeShortcut = { [weak self] in self?.shortcutSettings.show() }
        menu.onCheckForUpdates = { [weak self] in
            guard let self else { return }
            // If a check already found something, go straight to the offer.
            if let pending = self.updater.available {
                self.updater.promptToUpdate(pending, userInitiated: true)
            } else {
                self.updater.checkNow()
            }
        }
        menu.onToggleAutoUpdate = { [weak self] in
            guard let self else { return }
            self.updater.automaticChecksEnabled.toggle()
            if self.updater.automaticChecksEnabled { self.updater.checkInBackgroundIfDue() }
        }
        menu.currentUpdate = { [weak self] in
            (self?.updater.available?.version, self?.updater.automaticChecksEnabled ?? true)
        }
        menu.onUninstall = { Uninstaller.run() }
        menu.currentMode = { (SmartSettings.mode, SmartSettings.graceMinutes) }
        menu.onSelectMode = { [weak self] mode in
            guard let self else { return }
            SmartSettings.mode = mode
            // Mode change is a manual action: dozing (and its queued recap)
            // belongs to Smart mode and must not linger — otherwise switching
            // to Absolute while dozing shows a "dozing" state nothing can
            // ever re-engage.
            self.smartDozing = false
            self.store.clearPendingRecap()
            self.syncMonitor()
            self.persistAndRender()
        }
        menu.onSelectGrace = { [weak self] minutes in
            SmartSettings.graceMinutes = minutes
            self?.syncMonitor(restart: true)
            self?.persistAndRender()
        }
        monitor.onIdle = { [weak self] in self?.handleAgentsIdle() ?? true }
        monitor.onBusy = { [weak self] agents in self?.handleAgentsBusy(agents) }

        // Global hotkey (default ⌃⌘S, user-rebindable). KeyboardShortcuts registers
        // the persisted shortcut and delivers callbacks on the main thread.
        KeyboardShortcuts.onKeyDown(for: .toggle) { [weak self] in self?.handleToggle() }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleCommand(_:)),
            name: AppDelegate.commandNotification, object: nil)

        // Smart auto-off always fires with the screen dark, so its toast is
        // never seen live. Recap it the first time the display wakes instead.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screensDidWake(_:)),
            name: NSWorkspace.screensDidWakeNotification, object: nil)
        // Authoritative screen-dark signal. CGDisplayIsAsleep missed a 4h45m
        // display-off window on 2026-08-16 (Apple Silicon), which kept the
        // countdown frozen and the Mac awake all night.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screensDidSleep(_:)),
            name: NSWorkspace.screensDidSleepNotification, object: nil)

        // Default-on login item on first launch. Only mark as done if it succeeded,
        // so a failure retries on the next launch.
        if !UserDefaults.standard.bool(forKey: "didSetDefaultLoginItem") {
            if LoginItem.setEnabled(true) {
                UserDefaults.standard.set(true, forKey: "didSetDefaultLoginItem")
            }
        }

        // A dozing session survives an app relaunch: stay armed and let the
        // monitor re-engage the block when agents resume. Everything else
        // starts inactive.
        if SmartSettings.mode != .smart {
            smartDozing = false
            store.clearPendingRecap()
        }
        persistAndRender()
        reconcileLeftoverSleepBlock()
        startUpdateChecks()
        startBatteryWatch()
    }

    /// Watches the battery in every mode, not just Smart — Absolute NoSleep can
    /// flatten a Mac just as thoroughly, and did on 2026-08-17. One minute is
    /// fine-grained enough: the last few percent of a battery take far longer
    /// to spend, and the check is a cheap IOKit snapshot.
    private func startBatteryWatch() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkBattery()
        }
        RunLoop.main.add(timer, forMode: .common)
        batteryTimer = timer
        // The battery notice fires in every mode, including Absolute, where the
        // agent monitor never runs to ask for permission.
        requestNotificationAuthOnce()
        checkBattery()
    }

    /// Releases the sleep block on a nearly-empty battery and re-engages it once
    /// the Mac is charging again. This runs underneath every other decision:
    /// whatever the user or the agent monitor wants, a Mac that shuts down from
    /// an empty battery keeps nothing awake.
    private func checkBattery() {
        let state = BatteryGuard.read()
        let log = Logger(subsystem: "com.nosleep", category: "battery")
        if manager.isActive, BatteryGuard.shouldRelease(state) {
            // Unattended path only: this fires with the lid shut and nobody
            // watching, so a failure means "try again in a minute", never a
            // password prompt.
            guard manager.deactivateUnattended() else {
                log.error("battery at \(state?.percent ?? -1)% — release failed, retrying")
                return
            }
            batteryHold = true
            timer.cancel()
            currentExpiry = nil
            log.info("battery at \(state?.percent ?? -1)% — released the sleep block")
            notifyBatteryRelease(percent: state?.percent ?? BatteryGuard.releasePercent)
            persistAndRender()
        } else if batteryHold, BatteryGuard.shouldResume(state) {
            if manager.activateUnattended() {
                batteryHold = false
                log.info("battery recovered — sleep block re-engaged")
            }
            persistAndRender()
        }
    }

    private func notifyBatteryRelease(percent: Int) {
        notify(title: "NoSleep let your Mac sleep to save the battery",
               body: "Your battery was down to \(percent)% on battery power, so NoSleep "
                   + "released the sleep block rather than let the Mac shut down empty. "
                   + "It re-engages by itself once you plug back in.",
               identifier: "com.nosleep.battery-hold")
    }

    /// Daily update check. The first check waits a few seconds so launch isn't
    /// competing with a network round-trip, then repeats hourly — the throttle
    /// inside UpdateController is what enforces "at most once a day", so a Mac
    /// that sleeps through its slot still checks soon after waking.
    private func startUpdateChecks() {
        updater.onAvailableChanged = { [weak self] in self?.persistAndRender() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.updater.checkInBackgroundIfDue()
        }
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            self?.updater.checkInBackgroundIfDue()
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
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
        if manager.isActive || smartDozing {
            timer.cancel(); currentExpiry = nil
            smartDozing = false         // manual off fully disarms
            batteryHold = false
            store.clearPendingRecap()
            manager.deactivate()        // pmset disablesleep 0 (admin prompt)
            persistAndRender()
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
        smartDozing = false             // manual on = fully engaged
        batteryHold = false             // explicit user intent clears the brake
        store.clearPendingRecap()       // user is here and re-arming — no recap needed
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

        • Smart NoSleep (default): once your screen is off and your coding \
        agents finish working, NoSleep lets the Mac sleep to save battery and \
        heat — and re-engages by itself when agents start working again.
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
        // The next render re-reads LoginItem.isEnabled, so the checkmark stays
        // truthful. Full persistAndRender so the dozing flag survives the render.
        persistAndRender()
    }

    private func persistAndRender() {
        if !manager.isActive { currentExpiry = nil }
        let state = NoSleepState(isActive: manager.isActive,
                                 expiresAt: currentExpiry,
                                 dozing: smartDozing ? true : nil)
        store.save(state, pid: ProcessInfo.processInfo.processIdentifier)
        menu.render(state: state)
        syncMonitor()
    }

    /// The agent-activity monitor runs while keep-awake is engaged OR dozing
    /// in Smart mode — dozing needs the ticks to notice agents resuming.
    /// `restart` forces a fresh grace window (e.g. after the user changes the
    /// grace period).
    private func syncMonitor(restart: Bool = false) {
        let shouldRun = (manager.isActive || smartDozing) && SmartSettings.mode == .smart
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

    /// Smart NoSleep verdict: screen off and agents idle for the whole grace
    /// window. Release the sleep block (passwordless sudo rule → no prompt
    /// needed while unattended) but STAY ARMED: the monitor keeps ticking and
    /// re-engages the block when agents resume. Auto-off must never disarm the
    /// mode — that made every fire read as "it switched itself off on me".
    @discardableResult
    private func handleAgentsIdle() -> Bool {
        guard manager.isActive else { return true }
        // Release first, unattended (sudo -n only — never an admin prompt with
        // nobody at the screen). If it fails, the block is still real: stay
        // active, say nothing, and report failure so the monitor retries on the
        // next tick instead of leaving the Mac awake until morning.
        guard manager.deactivateUnattended() else { return false }
        notifyAgentsIdle(graceMinutes: SmartSettings.graceMinutes,
                         lastAgents: monitor.lastBusyAgents,
                         lastActivity: monitor.lastBusyDate)
        store.savePendingRecap(PendingRecap(sleptAt: Date(),
                                            agents: monitor.lastBusyAgents))
        timer.cancel()
        currentExpiry = nil
        smartDozing = true
        persistAndRender()
        return true
    }

    /// Agents resumed while dozing: silently re-engage the sleep block.
    /// No toast — keeping the Mac awake while agents work is just NoSleep
    /// doing its job; announcing it only confused people. Unattended path:
    /// sudo -n only, so a missing sudoers rule means "stay dozing", never a
    /// password prompt looping once per tick at 3 AM.
    private func handleAgentsBusy(_ agents: [String]) {
        // A nearly-empty battery outranks busy agents: re-engaging here would
        // undo the battery release once a minute until the Mac died anyway.
        guard smartDozing, !manager.isActive, !batteryHold else { return }
        if manager.activateUnattended() {
            smartDozing = false
        }
        persistAndRender()
    }

    /// First screen-on after a Smart auto-off: tell the story the user
    /// couldn't see at 1 AM — when the Mac slept and what was last running.
    @objc private func screensDidSleep(_ note: Notification) {
        presence.notifiedDisplayAsleep = true
        Logger(subsystem: "com.nosleep", category: "smart").info("screens slept — countdown can advance")
    }

    @objc private func screensDidWake(_ note: Notification) {
        presence.notifiedDisplayAsleep = false
        Logger(subsystem: "com.nosleep", category: "smart").info("screens woke — countdown held")
        // Small delay so the toast appears after the unlock transition.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.showPendingRecapIfAny()
        }
    }

    private func showPendingRecapIfAny() {
        guard let recap = store.loadPendingRecap() else { return }
        store.clearPendingRecap()
        ToastPanel.show(title: "While you were away",
                        body: SmartRecap.message(sleptAt: recap.sleptAt,
                                                 graceMinutes: SmartSettings.graceMinutes,
                                                 agents: recap.agents),
                        seconds: 45)
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

        var body = "Smart NoSleep let your Mac sleep at \(now) — screen off and no agents working for \(graceMinutes) min."
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
        body += " Still armed — it re-engages when agents work again."

        notify(title: "Smart NoSleep is letting your Mac sleep",
               body: body,
               identifier: "com.nosleep.agents-idle")
    }

    /// System notification with an in-app toast fallback. These fire with the
    /// lid closed, so Notification Center is the only place the user will ever
    /// read them — but auth is denied often enough (ad-hoc-signed builds) that
    /// the toast has to cover for it.
    private func notify(title: String, body: String, identifier: String) {
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
                center.add(UNNotificationRequest(identifier: identifier,
                                                 content: content, trigger: nil))
            } else {
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
            case .off:
                self.timer.cancel(); self.currentExpiry = nil
                self.smartDozing = false
                self.batteryHold = false
                self.store.clearPendingRecap()
                self.manager.deactivate()
                self.persistAndRender()
            case .toggle: self.handleToggle()
            case .timer(let s): self.handleTimer(s)
            case .status: self.persistAndRender()   // ensure store is fresh
            case .ping: break   // heartbeat is written straight to the shared store by the CLI
            }
        }
    }
}
