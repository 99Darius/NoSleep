import XCTest
@testable import NoSleepCore

final class UpdateCheckVersionTests: XCTestCase {
    func testNewerVersionsAreDetected() {
        XCTAssertTrue(UpdateCheck.isNewer("1.1.8", than: "1.1.7"))
        XCTAssertTrue(UpdateCheck.isNewer("1.2.0", than: "1.1.9"))
        XCTAssertTrue(UpdateCheck.isNewer("1.1.10", than: "1.1.9"))
        XCTAssertTrue(UpdateCheck.isNewer("v1.1.8", than: "1.1.7"))
        XCTAssertTrue(UpdateCheck.isNewer("1.2.1", than: "1.2"))
    }

    func testSameOrOlderOrUnparseableIsNotNewer() {
        XCTAssertFalse(UpdateCheck.isNewer("1.1.7", than: "1.1.7"))
        XCTAssertFalse(UpdateCheck.isNewer("1.1.6", than: "1.1.7"))
        XCTAssertFalse(UpdateCheck.isNewer("1.2", than: "1.2.0"))
        XCTAssertFalse(UpdateCheck.isNewer("garbage", than: "1.1.7"))
    }
}

final class UpdateCheckFeedTests: XCTestCase {
    private let stable = """
    {"tag_name":"v1.1.8","html_url":"https://github.com/99Darius/NoSleep/releases/tag/v1.1.8",
     "body":"Fixes things.","draft":false,"prerelease":false,
     "assets":[{"name":"NoSleep-Installer-1.1.8.pkg",
                "browser_download_url":"https://github.com/99Darius/NoSleep/releases/download/v1.1.8/NoSleep-Installer-1.1.8.pkg"}]}
    """

    func testParsesStableRelease() {
        let info = UpdateCheck.parseGitHubRelease(Data(stable.utf8))
        XCTAssertEqual(info?.version, "1.1.8")
        XCTAssertEqual(info?.pkgURL?.lastPathComponent, "NoSleep-Installer-1.1.8.pkg")
        XCTAssertEqual(info?.notes, "Fixes things.")
        XCTAssertTrue(info?.pageURL?.absoluteString.hasSuffix("/tag/v1.1.8") == true)
    }

    func testDraftsPrereleasesAndGarbageAreIgnored() {
        XCTAssertNil(UpdateCheck.parseGitHubRelease(
            Data(#"{"tag_name":"v1.2.0","draft":true,"prerelease":false,"assets":[]}"#.utf8)))
        XCTAssertNil(UpdateCheck.parseGitHubRelease(
            Data(#"{"tag_name":"v1.2.0","draft":false,"prerelease":true,"assets":[]}"#.utf8)))
        XCTAssertNil(UpdateCheck.parseGitHubRelease(Data("not json".utf8)))
    }

    func testReleaseWithoutPkgAssetStillReportsVersion() {
        let json = #"{"tag_name":"v1.2.0","html_url":"https://x/y","draft":false,"prerelease":false,"assets":[]}"#
        let info = UpdateCheck.parseGitHubRelease(Data(json.utf8))
        XCTAssertEqual(info?.version, "1.2.0")
        XCTAssertNil(info?.pkgURL)
    }
}

final class UpdateCheckThrottleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testFirstRunChecksAndIntervalIsRespected() {
        XCTAssertTrue(UpdateCheck.shouldCheck(now: now, lastCheck: nil))
        XCTAssertFalse(UpdateCheck.shouldCheck(now: now, lastCheck: now.addingTimeInterval(-3600)))
        XCTAssertTrue(UpdateCheck.shouldCheck(now: now, lastCheck: now.addingTimeInterval(-90_000)))
    }

    func testFutureTimestampDoesNotWedgeChecksForever() {
        XCTAssertTrue(UpdateCheck.shouldCheck(now: now, lastCheck: now.addingTimeInterval(86_400)))
    }
}
