import Foundation
import AppKit
import NoSleepCore
import os

/// Checks GitHub for a newer stable NoSleep and offers it to the user.
///
/// Deliberately NOT a silent self-installer: the pkg needs admin rights to
/// install and the app is ad-hoc signed, so a background swap of a running
/// /Applications bundle would be both prompt-happy and untrustworthy. Instead
/// this downloads the official installer and hands it to the system installer,
/// with the user in the loop for the one admin prompt they'd expect anyway.
final class UpdateController {
    static let feedURL = URL(string: "https://api.github.com/repos/99Darius/NoSleep/releases/latest")!

    private let log = Logger(subsystem: "com.nosleep", category: "update")
    private let defaults = UserDefaults.standard
    private var checking = false

    /// Latest release found that is newer than the running build, if any.
    private(set) var available: ReleaseInfo?

    /// Called when `available` changes so the menu can re-render.
    var onAvailableChanged: (() -> Void)?

    var automaticChecksEnabled: Bool {
        get { defaults.object(forKey: "autoUpdateCheck") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoUpdateCheck") }
    }

    private var lastCheck: Date? {
        get {
            let t = defaults.double(forKey: "lastUpdateCheck")
            return t == 0 ? nil : Date(timeIntervalSince1970: t)
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "lastUpdateCheck") }
    }

    /// Version the user asked not to be nagged about again.
    private var skippedVersion: String? {
        get { defaults.string(forKey: "skippedUpdateVersion") }
        set { defaults.set(newValue, forKey: "skippedUpdateVersion") }
    }

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    // MARK: - Checking

    /// Daily background check. Silent when up to date or offline.
    func checkInBackgroundIfDue() {
        guard automaticChecksEnabled,
              UpdateCheck.shouldCheck(now: Date(), lastCheck: lastCheck) else { return }
        check(userInitiated: false)
    }

    /// "Check for Updates…" menu item: always checks, always reports.
    func checkNow() {
        check(userInitiated: true)
    }

    private func check(userInitiated: Bool) {
        guard !checking else { return }
        checking = true
        lastCheck = Date()
        var request = URLRequest(url: Self.feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NoSleep/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                guard let data, error == nil,
                      let release = UpdateCheck.parseGitHubRelease(data) else {
                    self.log.info("update check failed: \(error?.localizedDescription ?? "bad payload", privacy: .public)")
                    if userInitiated { self.showCheckFailed() }
                    return
                }
                self.handle(release, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func handle(_ release: ReleaseInfo, userInitiated: Bool) {
        guard UpdateCheck.isNewer(release.version, than: currentVersion) else {
            log.info("up to date at \(self.currentVersion, privacy: .public)")
            available = nil
            onAvailableChanged?()
            if userInitiated { showUpToDate() }
            return
        }
        available = release
        onAvailableChanged?()
        log.info("update available: \(release.version, privacy: .public)")
        // Respect "Skip This Version" for automatic checks only — an explicit
        // "Check for Updates…" always shows what's out there.
        if !userInitiated && skippedVersion == release.version { return }
        promptToUpdate(release, userInitiated: userInitiated)
    }

    // MARK: - UI

    func promptToUpdate(_ release: ReleaseInfo, userInitiated: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "NoSleep \(release.version) is available"
        var body = "You have \(currentVersion)."
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            body += "\n\n" + String(notes.prefix(600))
        }
        alert.informativeText = body
        alert.addButton(withTitle: release.pkgURL != nil ? "Download & Install" : "Open Release Page")
        alert.addButton(withTitle: "Later")
        if !userInitiated { alert.addButton(withTitle: "Skip This Version") }
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let pkg = release.pkgURL {
                download(pkg, version: release.version)
            } else if let page = release.pageURL {
                NSWorkspace.shared.open(page)
            }
        case .alertThirdButtonReturn:
            skippedVersion = release.version
        default:
            break
        }
    }

    /// Download the installer to ~/Downloads and open it. Quarantine is
    /// stripped so Gatekeeper doesn't block the unsigned pkg the user
    /// explicitly asked for — same file the website hands out.
    private func download(_ url: URL, version: String) {
        let dest = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NoSleep-Installer-\(version).pkg")
        guard let dest else { return }
        URLSession.shared.downloadTask(with: url) { [weak self] tmp, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let tmp, error == nil,
                      (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
                    self.showDownloadFailed(url)
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: tmp, to: dest)
                } catch {
                    self.showDownloadFailed(url)
                    return
                }
                Self.stripQuarantine(dest)
                // Reveal + open the installer. NoSleep keeps running; the
                // installer replaces the app and relaunches it.
                NSWorkspace.shared.open(dest)
            }
        }.resume()
    }

    private static func stripQuarantine(_ path: URL) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        proc.arguments = ["-d", "com.apple.quarantine", path.path]
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }

    private func showUpToDate() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "You're up to date"
        alert.informativeText = "NoSleep \(currentVersion) is the latest version."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showCheckFailed() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = "NoSleep couldn't reach GitHub. Check your connection and try again."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showDownloadFailed(_ url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Download failed"
        alert.informativeText = "NoSleep couldn't download the installer. You can get it from the release page instead."
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(url)
        }
    }
}
