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

        // 0. Restore sleep in case closed-lid mode is active, and remove the
        //    passwordless sudoers drop-in we installed. Both happen in one admin
        //    prompt (best effort).
        let cleanup = "/usr/bin/pmset -a disablesleep 0; /bin/rm -f /etc/sudoers.d/nosleep"
        if let script = NSAppleScript(source: "do shell script \"\(cleanup)\" with administrator privileges") {
            var err: NSDictionary?
            script.executeAndReturnError(&err)
        }

        // 1. Login item.
        try? SMAppService.mainApp.unregister()

        // 2. Persisted settings: shared state suite, first-launch flag, shortcut override.
        UserDefaults.standard.removeObject(forKey: "didSetDefaultLoginItem")
        UserDefaults.standard.removePersistentDomain(forName: StateStore.suiteName)
        KeyboardShortcuts.reset(.toggle)

        // 3. CLI symlink (best effort; /usr/local/bin may not be writable).
        try? FileManager.default.removeItem(atPath: "/usr/local/bin/nosleep")

        // 4. Trash the app bundle (allowed while running), then quit. Trashing
        //    /Applications needs write access there, which a standard user does
        //    not have — swallowing that failure told people NoSleep was gone
        //    while it stayed installed and came back at the next login.
        let bundle = Bundle.main.bundleURL
        do {
            try FileManager.default.trashItem(at: bundle, resultingItemURL: nil)
        } catch {
            let failed = NSAlert()
            failed.alertStyle = .warning
            failed.messageText = "Couldn't move NoSleep to the Trash"
            failed.informativeText = """
            Normal sleep and your settings have been restored, but NoSleep.app \
            couldn't be removed — you may not have permission to change that \
            folder. Drag it to the Trash yourself:

            \(bundle.path)
            """
            failed.addButton(withTitle: "Show in Finder")
            failed.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            if failed.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([bundle])
            }
        }

        NSApp.terminate(nil)
    }
}
