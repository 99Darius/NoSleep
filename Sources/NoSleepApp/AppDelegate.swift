import AppKit
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
    private var hotkey: HotkeyManager!
    private var currentExpiry: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        manager.onChange = { [weak self] in self?.persistAndRender() }

        menu.onToggle = { [weak self] in self?.handleToggle() }
        menu.onTimer = { [weak self] secs in self?.handleTimer(secs) }
        menu.onToggleLoginItem = { LoginItem.setEnabled(!LoginItem.isEnabled) }
        menu.onQuit = { NSApp.terminate(nil) }

        hotkey = HotkeyManager { [weak self] in self?.handleToggle() }
        if !hotkey.register() {
            // Hotkey unavailable; app still works via menu/CLI. (Could surface in menu.)
        }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleCommand(_:)),
            name: AppDelegate.commandNotification, object: nil)

        // Default-on login item on first launch.
        if !UserDefaults.standard.bool(forKey: "didSetDefaultLoginItem") {
            LoginItem.setEnabled(true)
            UserDefaults.standard.set(true, forKey: "didSetDefaultLoginItem")
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

    private func persistAndRender() {
        if !manager.isActive { currentExpiry = nil }
        let state = NoSleepState(isActive: manager.isActive, expiresAt: currentExpiry)
        store.save(state, pid: ProcessInfo.processInfo.processIdentifier)
        menu.render(state: state)
    }

    @objc private func handleCommand(_ note: Notification) {
        guard let cmd = Command(userInfo: note.userInfo) else { return }
        switch cmd {
        case .on: timer.cancel(); currentExpiry = nil; manager.activate()
        case .off: timer.cancel(); currentExpiry = nil; manager.deactivate()
        case .toggle: handleToggle()
        case .timer(let s): handleTimer(s)
        case .status: persistAndRender()   // ensure store is fresh
        }
    }
}
