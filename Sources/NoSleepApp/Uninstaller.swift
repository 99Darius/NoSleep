import AppKit
import ServiceManagement
import KeyboardShortcuts
import NoSleepCore

/// Removes everything NoSleep installs, then moves the app to the Trash and quits.
enum Uninstaller {
    static func run() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall NoSleep?"
        alert.informativeText = """
        This will:
        • turn off keep-awake
        • remove the Launch at Login item
        • delete NoSleep's saved settings and shortcut
        • remove the `nosleep` command-line symlink (if present)
        • move NoSleep.app to the Trash

        NoSleep will then quit.
        """
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // 1. Login item.
        try? SMAppService.mainApp.unregister()

        // 2. Persisted settings: shared state suite, first-launch flag, shortcut override.
        UserDefaults.standard.removeObject(forKey: "didSetDefaultLoginItem")
        UserDefaults.standard.removePersistentDomain(forName: StateStore.suiteName)
        KeyboardShortcuts.reset(.toggle)

        // 3. CLI symlink (best effort; /usr/local/bin may not be writable).
        try? FileManager.default.removeItem(atPath: "/usr/local/bin/nosleep")

        // 4. Trash the app bundle (allowed while running), then quit.
        try? FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)

        NSApp.terminate(nil)
    }
}
