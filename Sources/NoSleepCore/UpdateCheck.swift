import Foundation

/// A release found on the update feed.
public struct ReleaseInfo: Equatable {
    public let version: String       // "1.1.8" (no leading v)
    public let pkgURL: URL?          // installer asset, if the release has one
    public let pageURL: URL?         // human-readable release page
    public let notes: String

    public init(version: String, pkgURL: URL?, pageURL: URL?, notes: String = "") {
        self.version = version
        self.pkgURL = pkgURL
        self.pageURL = pageURL
        self.notes = notes
    }
}

/// Pure logic behind "is there a newer NoSleep?" — version comparison, feed
/// parsing, and the once-a-day throttle. Networking lives in the app layer.
public enum UpdateCheck {
    /// Semantic-ish compare of dotted numeric versions ("1.1.10" > "1.1.9").
    /// A leading "v" and any pre-release suffix are ignored.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parts(candidate), let b = parts(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Dotted numeric components, or nil if the string isn't a version at all.
    private static func parts(_ raw: String) -> [Int]? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        // Drop any pre-release/build suffix ("1.2.0-beta.1" → "1.2.0").
        text = text.components(separatedBy: CharacterSet(charactersIn: "-+")).first ?? text
        let comps = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !comps.isEmpty else { return nil }
        var out: [Int] = []
        for c in comps {
            guard let n = Int(c), n >= 0 else { return nil }
            out.append(n)
        }
        return out
    }

    /// Parse the GitHub "latest release" JSON payload.
    public static func parseGitHubRelease(_ data: Data) -> ReleaseInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = root["tag_name"] as? String,
              parts(tag) != nil
        else { return nil }
        // Stable channel only: never offer drafts or pre-releases.
        if root["draft"] as? Bool == true || root["prerelease"] as? Bool == true { return nil }

        var version = tag
        if version.hasPrefix("v") || version.hasPrefix("V") { version.removeFirst() }

        var pkg: URL?
        if let assets = root["assets"] as? [[String: Any]] {
            for a in assets {
                guard let name = a["name"] as? String, name.hasSuffix(".pkg"),
                      let urlText = a["browser_download_url"] as? String,
                      let url = URL(string: urlText) else { continue }
                pkg = url
                break
            }
        }
        let page = (root["html_url"] as? String).flatMap(URL.init(string:))
        let notes = (root["body"] as? String) ?? ""
        return ReleaseInfo(version: version, pkgURL: pkg, pageURL: page, notes: notes)
    }

    /// Throttle: check at most once per `interval` (default 24h).
    public static func shouldCheck(now: Date, lastCheck: Date?,
                                   interval: TimeInterval = 86_400) -> Bool {
        guard let last = lastCheck else { return true }
        let elapsed = now.timeIntervalSince(last)
        // A future timestamp (clock change) must not block checks forever.
        return elapsed >= interval || elapsed < 0
    }
}
