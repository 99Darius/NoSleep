# NoSleep Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS menu bar utility (`NoSleep.app`) plus a `nosleep` CLI that toggle a system-only keep-awake state, controlled by menu, global hotkey `⌃⌘Z`, and CLI, all synced through one agent.

**Architecture:** A single Swift Package with two executable products. The menu bar agent owns one IOKit power assertion and is the single source of truth. The CLI sends commands via `DistributedNotificationCenter` and reads state from a shared `UserDefaults` suite. All testable logic sits behind protocols (`SleepBlocking`, a clock/timer abstraction, a state store) so it can be tested without real IOKit/Carbon/UI.

**Tech Stack:** Swift 5.9+, Swift Package Manager, AppKit, IOKit (`IOPMAssertion`), Carbon (`RegisterEventHotKey`), `SMAppService`, XCTest.

---

## Conventions

- **TDD throughout:** write the failing test, run it (confirm it fails for the right reason), write minimal code, run it (confirm pass), commit.
- **Run tests with:** `swift test` (whole suite) or `swift test --filter <TestClass>/<testName>` (one test).
- **Build with:** `swift build`.
- **Commit after every green step.** Conventional commit messages.
- Platform-gated code (`IOKit`, `AppKit`, `Carbon`) only in the real implementations, never in the pure-logic types — that keeps `swift test` runnable and the logic portable.

---

## Project Layout (target end state)

```
NoSleep/
├─ Package.swift
├─ Makefile
├─ Sources/
│  ├─ NoSleepCore/            # pure logic, no UI/IOKit — fully unit-tested
│  │  ├─ NoSleepState.swift
│  │  ├─ SleepBlocking.swift
│  │  ├─ AssertionManager.swift
│  │  ├─ TimerController.swift
│  │  ├─ StateStore.swift
│  │  └─ Command.swift
│  ├─ NoSleepApp/             # menu bar agent (AppKit, IOKit, Carbon)
│  │  ├─ main.swift
│  │  ├─ AppDelegate.swift
│  │  ├─ IOKitSleepBlocker.swift
│  │  ├─ HotkeyManager.swift
│  │  ├─ MenuController.swift
│  │  └─ LoginItem.swift
│  └─ nosleep/                # CLI
│     └─ main.swift
├─ Tests/
│  └─ NoSleepCoreTests/
│     ├─ AssertionManagerTests.swift
│     ├─ TimerControllerTests.swift
│     ├─ StateStoreTests.swift
│     └─ CommandTests.swift
└─ Resources/
   └─ Info.plist
```

---

## Task 1: Project scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/NoSleepCore/Placeholder.swift`
- Create: `Tests/NoSleepCoreTests/ScaffoldTests.swift`

**Step 1: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NoSleep",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "NoSleepCore"),
        .executableTarget(
            name: "NoSleepApp",
            dependencies: ["NoSleepCore"]
        ),
        .executableTarget(
            name: "nosleep",
            dependencies: ["NoSleepCore"]
        ),
        .testTarget(
            name: "NoSleepCoreTests",
            dependencies: ["NoSleepCore"]
        ),
    ]
)
```

`.macOS(.v13)` is required for `SMAppService`.

**Step 2: Add a placeholder so the core target compiles**

`Sources/NoSleepCore/Placeholder.swift`:
```swift
enum NoSleepCore {}
```

**Step 3: Write a trivial test**

`Tests/NoSleepCoreTests/ScaffoldTests.swift`:
```swift
import XCTest
@testable import NoSleepCore

final class ScaffoldTests: XCTestCase {
    func testScaffoldBuilds() {
        XCTAssertTrue(true)
    }
}
```

**Step 4: Run**

Run: `swift test`
Expected: builds and passes (1 test).

**Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore: scaffold Swift package with core/app/cli targets"
```

---

## Task 2: NoSleepState model

A small value type capturing the two states plus optional expiry.

**Files:**
- Create: `Sources/NoSleepCore/NoSleepState.swift`
- Test: `Tests/NoSleepCoreTests/StateStoreTests.swift` (start the file here; reused in Task 6)

**Step 1: Write the failing test**

`Tests/NoSleepCoreTests/StateStoreTests.swift`:
```swift
import XCTest
@testable import NoSleepCore

final class NoSleepStateTests: XCTestCase {
    func testInactiveByDefault() {
        let s = NoSleepState.inactive
        XCTAssertFalse(s.isActive)
        XCTAssertNil(s.expiresAt)
    }

    func testActiveWithExpiry() {
        let when = Date(timeIntervalSince1970: 1000)
        let s = NoSleepState(isActive: true, expiresAt: when)
        XCTAssertTrue(s.isActive)
        XCTAssertEqual(s.expiresAt, when)
    }
}
```

**Step 2: Run to verify it fails**

Run: `swift test --filter NoSleepCoreTests.NoSleepStateTests`
Expected: FAIL — `NoSleepState` undefined.

**Step 3: Minimal implementation**

`Sources/NoSleepCore/NoSleepState.swift`:
```swift
import Foundation

public struct NoSleepState: Equatable, Codable {
    public var isActive: Bool
    public var expiresAt: Date?

    public init(isActive: Bool, expiresAt: Date? = nil) {
        self.isActive = isActive
        self.expiresAt = expiresAt
    }

    public static let inactive = NoSleepState(isActive: false, expiresAt: nil)
}
```

**Step 4: Run to verify pass**

Run: `swift test --filter NoSleepCoreTests.NoSleepStateTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/NoSleepCore/NoSleepState.swift Tests/NoSleepCoreTests/StateStoreTests.swift
git commit -m "feat(core): add NoSleepState model"
```

---

## Task 3: SleepBlocking protocol + AssertionManager

`AssertionManager` is pure logic. The real IOKit call hides behind `SleepBlocking`; tests use a fake that counts begin/end calls so we can prove idempotency and no leaks.

**Files:**
- Create: `Sources/NoSleepCore/SleepBlocking.swift`
- Create: `Sources/NoSleepCore/AssertionManager.swift`
- Test: `Tests/NoSleepCoreTests/AssertionManagerTests.swift`

**Step 1: Write the failing tests**

`Tests/NoSleepCoreTests/AssertionManagerTests.swift`:
```swift
import XCTest
@testable import NoSleepCore

final class FakeSleepBlocker: SleepBlocking {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    var heldToken: Int? = nil

    func begin(reason: String) -> Int {
        beginCount += 1
        heldToken = beginCount
        return beginCount
    }
    func end(token: Int) {
        endCount += 1
        heldToken = nil
    }
}

final class AssertionManagerTests: XCTestCase {
    func testActivateHoldsAssertion() {
        let fake = FakeSleepBlocker()
        let m = AssertionManager(blocker: fake)
        m.activate()
        XCTAssertTrue(m.isActive)
        XCTAssertEqual(fake.beginCount, 1)
    }

    func testDoubleActivateDoesNotLeak() {
        let fake = FakeSleepBlocker()
        let m = AssertionManager(blocker: fake)
        m.activate()
        m.activate()
        XCTAssertEqual(fake.beginCount, 1, "second activate must be a no-op")
    }

    func testDeactivateReleases() {
        let fake = FakeSleepBlocker()
        let m = AssertionManager(blocker: fake)
        m.activate()
        m.deactivate()
        XCTAssertFalse(m.isActive)
        XCTAssertEqual(fake.endCount, 1)
    }

    func testDeactivateWhenInactiveIsNoOp() {
        let fake = FakeSleepBlocker()
        let m = AssertionManager(blocker: fake)
        m.deactivate()
        XCTAssertEqual(fake.endCount, 0)
    }

    func testToggleFlips() {
        let fake = FakeSleepBlocker()
        let m = AssertionManager(blocker: fake)
        m.toggle()
        XCTAssertTrue(m.isActive)
        m.toggle()
        XCTAssertFalse(m.isActive)
    }
}
```

**Step 2: Run to verify it fails**

Run: `swift test --filter NoSleepCoreTests.AssertionManagerTests`
Expected: FAIL — `SleepBlocking` / `AssertionManager` undefined.

**Step 3: Minimal implementation**

`Sources/NoSleepCore/SleepBlocking.swift`:
```swift
import Foundation

/// Abstraction over the OS sleep-prevention mechanism so logic is testable.
public protocol SleepBlocking: AnyObject {
    /// Begin blocking idle system sleep. Returns an opaque token to release later.
    func begin(reason: String) -> Int
    /// Release a previously acquired block.
    func end(token: Int)
}
```

`Sources/NoSleepCore/AssertionManager.swift`:
```swift
import Foundation

/// Single source of truth for the keep-awake state. Holds at most one block.
public final class AssertionManager {
    private let blocker: SleepBlocking
    private var token: Int?

    /// Called after every state change so the UI/store can refresh.
    public var onChange: (() -> Void)?

    public init(blocker: SleepBlocking) {
        self.blocker = blocker
    }

    public var isActive: Bool { token != nil }

    public func activate() {
        guard token == nil else { return }            // idempotent: no leak
        token = blocker.begin(reason: "NoSleep active")
        onChange?()
    }

    public func deactivate() {
        guard let t = token else { return }            // no-op when inactive
        blocker.end(token: t)
        token = nil
        onChange?()
    }

    public func toggle() {
        isActive ? deactivate() : activate()
    }
}
```

**Step 4: Run to verify pass**

Run: `swift test --filter NoSleepCoreTests.AssertionManagerTests`
Expected: PASS (5 tests).

**Step 5: Commit**

```bash
git add Sources/NoSleepCore/SleepBlocking.swift Sources/NoSleepCore/AssertionManager.swift Tests/NoSleepCoreTests/AssertionManagerTests.swift
git commit -m "feat(core): add SleepBlocking protocol and AssertionManager"
```

---

## Task 4: TimerController

Owns at most one auto-off timer. Uses an injected scheduler so tests fire timers deterministically (no real waiting).

**Files:**
- Create: `Sources/NoSleepCore/TimerController.swift`
- Test: `Tests/NoSleepCoreTests/TimerControllerTests.swift`

**Step 1: Write the failing tests**

`Tests/NoSleepCoreTests/TimerControllerTests.swift`:
```swift
import XCTest
@testable import NoSleepCore

/// Manual scheduler: records the last scheduled work and fires it on demand.
final class ManualScheduler: TimerScheduling {
    private var work: (() -> Void)?
    private(set) var scheduleCount = 0
    private(set) var cancelCount = 0

    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) {
        scheduleCount += 1
        self.work = work
    }
    func cancel() {
        if work != nil { cancelCount += 1 }
        work = nil
    }
    func fire() {
        let w = work
        work = nil
        w?()
    }
    var hasPending: Bool { work != nil }
}

final class TimerControllerTests: XCTestCase {
    func testFiringCallsExpire() {
        let sched = ManualScheduler()
        var expired = false
        let tc = TimerController(scheduler: sched, onExpire: { expired = true })
        tc.start(seconds: 3600)
        XCTAssertEqual(sched.scheduleCount, 1)
        sched.fire()
        XCTAssertTrue(expired)
    }

    func testStartingNewTimerCancelsOld() {
        let sched = ManualScheduler()
        let tc = TimerController(scheduler: sched, onExpire: {})
        tc.start(seconds: 60)
        tc.start(seconds: 120)
        XCTAssertEqual(sched.cancelCount, 1, "old timer must be cancelled")
        XCTAssertEqual(sched.scheduleCount, 2)
    }

    func testCancelStopsPending() {
        let sched = ManualScheduler()
        var expired = false
        let tc = TimerController(scheduler: sched, onExpire: { expired = true })
        tc.start(seconds: 60)
        tc.cancel()
        XCTAssertFalse(sched.hasPending)
        sched.fire()
        XCTAssertFalse(expired)
    }
}
```

**Step 2: Run to verify it fails**

Run: `swift test --filter NoSleepCoreTests.TimerControllerTests`
Expected: FAIL — `TimerScheduling` / `TimerController` undefined.

**Step 3: Minimal implementation**

`Sources/NoSleepCore/TimerController.swift`:
```swift
import Foundation

public protocol TimerScheduling: AnyObject {
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void)
    func cancel()
}

public final class TimerController {
    private let scheduler: TimerScheduling
    private let onExpire: () -> Void

    public init(scheduler: TimerScheduling, onExpire: @escaping () -> Void) {
        self.scheduler = scheduler
        self.onExpire = onExpire
    }

    /// Replaces any pending timer (cancel-before-set).
    public func start(seconds: TimeInterval) {
        scheduler.cancel()
        scheduler.schedule(after: seconds) { [weak self] in
            self?.onExpire()
        }
    }

    public func cancel() {
        scheduler.cancel()
    }
}
```

**Step 4: Run to verify pass**

Run: `swift test --filter NoSleepCoreTests.TimerControllerTests`
Expected: PASS (3 tests).

**Step 5: Commit**

```bash
git add Sources/NoSleepCore/TimerController.swift Tests/NoSleepCoreTests/TimerControllerTests.swift
git commit -m "feat(core): add TimerController with injectable scheduler"
```

---

## Task 5: Command parsing

Maps CLI args and notification payloads to a `Command` enum. Pure, fully tested.

**Files:**
- Create: `Sources/NoSleepCore/Command.swift`
- Test: `Tests/NoSleepCoreTests/CommandTests.swift`

**Step 1: Write the failing tests**

`Tests/NoSleepCoreTests/CommandTests.swift`:
```swift
import XCTest
@testable import NoSleepCore

final class CommandTests: XCTestCase {
    func testParseSimple() {
        XCTAssertEqual(Command.parse(["on"]), .on)
        XCTAssertEqual(Command.parse(["off"]), .off)
        XCTAssertEqual(Command.parse(["toggle"]), .toggle)
        XCTAssertEqual(Command.parse(["status"]), .status)
    }

    func testParseTimerDurations() {
        XCTAssertEqual(Command.parse(["timer", "15m"]), .timer(900))
        XCTAssertEqual(Command.parse(["timer", "1h"]), .timer(3600))
        XCTAssertEqual(Command.parse(["timer", "2h"]), .timer(7200))
        XCTAssertEqual(Command.parse(["timer", "90s"]), .timer(90))
    }

    func testParseInvalid() {
        XCTAssertNil(Command.parse([]))
        XCTAssertNil(Command.parse(["bogus"]))
        XCTAssertNil(Command.parse(["timer"]))
        XCTAssertNil(Command.parse(["timer", "abc"]))
    }

    func testRoundTripViaUserInfo() {
        for c in [Command.on, .off, .toggle, .status, .timer(3600)] {
            let info = c.userInfo
            XCTAssertEqual(Command(userInfo: info), c)
        }
    }

    func testFormatDuration() {
        XCTAssertEqual(formatDuration(seconds: 0), "0s")
        XCTAssertEqual(formatDuration(seconds: 90), "1m30s")
        XCTAssertEqual(formatDuration(seconds: 3600), "1h")
        XCTAssertEqual(formatDuration(seconds: 3720), "1h2m")
    }
}
```

**Step 2: Run to verify it fails**

Run: `swift test --filter NoSleepCoreTests.CommandTests`
Expected: FAIL — `Command` undefined.

**Step 3: Minimal implementation**

`Sources/NoSleepCore/Command.swift`:
```swift
import Foundation

public enum Command: Equatable {
    case on
    case off
    case toggle
    case status
    case timer(TimeInterval)

    /// Parse from CLI argv (excluding the program name).
    public static func parse(_ args: [String]) -> Command? {
        guard let first = args.first else { return nil }
        switch first {
        case "on": return .on
        case "off": return .off
        case "toggle": return .toggle
        case "status": return .status
        case "timer":
            guard args.count >= 2, let secs = parseDuration(args[1]) else { return nil }
            return .timer(secs)
        default: return nil
        }
    }

    // MARK: - Notification payload encoding

    public var userInfo: [String: Any] {
        switch self {
        case .on: return ["action": "on"]
        case .off: return ["action": "off"]
        case .toggle: return ["action": "toggle"]
        case .status: return ["action": "status"]
        case .timer(let s): return ["action": "timer", "seconds": s]
        }
    }

    public init?(userInfo: [AnyHashable: Any]?) {
        guard let action = userInfo?["action"] as? String else { return nil }
        switch action {
        case "on": self = .on
        case "off": self = .off
        case "toggle": self = .toggle
        case "status": self = .status
        case "timer":
            guard let s = userInfo?["seconds"] as? TimeInterval else { return nil }
            self = .timer(s)
        default: return nil
        }
    }
}

/// Parse durations like "90s", "15m", "1h", "2h".
public func parseDuration(_ text: String) -> TimeInterval? {
    guard let unit = text.last, let value = Double(text.dropLast()) else { return nil }
    switch unit {
    case "s": return value
    case "m": return value * 60
    case "h": return value * 3600
    default: return nil
    }
}

/// Format seconds compactly: 3720 -> "1h2m".
public func formatDuration(seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    var out = ""
    if h > 0 { out += "\(h)h" }
    if m > 0 { out += "\(m)m" }
    if s > 0 || out.isEmpty { out += "\(s)s" }
    return out
}
```

**Step 4: Run to verify pass**

Run: `swift test --filter NoSleepCoreTests.CommandTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/NoSleepCore/Command.swift Tests/NoSleepCoreTests/CommandTests.swift
git commit -m "feat(core): add Command parsing and duration helpers"
```

---

## Task 6: StateStore (shared UserDefaults)

Reads/writes `NoSleepState` to a shared suite. Inject a `UserDefaults(suiteName:)` so the test uses a throwaway suite.

**Files:**
- Create: `Sources/NoSleepCore/StateStore.swift`
- Test: append to `Tests/NoSleepCoreTests/StateStoreTests.swift`

**Step 1: Write the failing tests** (append to existing file)

```swift
final class StateStoreTests: XCTestCase {
    private func makeStore() -> (StateStore, UserDefaults) {
        let suite = "com.nosleep.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (StateStore(defaults: defaults), defaults)
    }

    func testDefaultsToInactive() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.load(), .inactive)
    }

    func testRoundTrip() {
        let (store, _) = makeStore()
        let when = Date(timeIntervalSince1970: 5000)
        let state = NoSleepState(isActive: true, expiresAt: when)
        store.save(state, pid: 4321)
        XCTAssertEqual(store.load(), state)
        XCTAssertEqual(store.loadPID(), 4321)
    }
}
```

**Step 2: Run to verify it fails**

Run: `swift test --filter NoSleepCoreTests.StateStoreTests`
Expected: FAIL — `StateStore` undefined.

**Step 3: Minimal implementation**

`Sources/NoSleepCore/StateStore.swift`:
```swift
import Foundation

public final class StateStore {
    public static let suiteName = "com.nosleep.shared"

    private let defaults: UserDefaults
    private let stateKey = "state"
    private let pidKey = "pid"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Convenience for production use against the shared suite.
    public static func shared() -> StateStore {
        StateStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    public func save(_ state: NoSleepState, pid: Int32) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: stateKey)
        }
        defaults.set(Int(pid), forKey: pidKey)
    }

    public func load() -> NoSleepState {
        guard let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(NoSleepState.self, from: data)
        else { return .inactive }
        return state
    }

    public func loadPID() -> Int? {
        let p = defaults.integer(forKey: pidKey)
        return p == 0 ? nil : p
    }
}
```

**Step 4: Run to verify pass**

Run: `swift test --filter NoSleepCoreTests.StateStoreTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/NoSleepCore/StateStore.swift Tests/NoSleepCoreTests/StateStoreTests.swift
git commit -m "feat(core): add StateStore over shared UserDefaults"
```

---

## Task 7: Real IOKit blocker + DispatchTimer scheduler

Thin platform adapters implementing the two protocols. Not unit-tested (verified manually via `pmset`), kept tiny so there's little to get wrong.

**Files:**
- Create: `Sources/NoSleepApp/IOKitSleepBlocker.swift`
- Create: `Sources/NoSleepApp/DispatchTimerScheduler.swift`

**Step 1: Implement `IOKitSleepBlocker`**

```swift
import Foundation
import IOKit.pwr_mgt
import NoSleepCore

final class IOKitSleepBlocker: SleepBlocking {
    private var assertions: [Int: IOPMAssertionID] = [:]
    private var nextKey = 1

    func begin(reason: String) -> Int {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        let key = nextKey; nextKey += 1
        if result == kIOReturnSuccess { assertions[key] = id }
        return key
    }

    func end(token: Int) {
        guard let id = assertions[token] else { return }
        IOPMAssertionRelease(id)
        assertions[token] = nil
    }
}
```

**Step 2: Implement `DispatchTimerScheduler`**

```swift
import Foundation
import NoSleepCore

final class DispatchTimerScheduler: TimerScheduling {
    private var source: DispatchSourceTimer?

    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + seconds)
        t.setEventHandler(handler: work)
        t.resume()
        source = t
    }

    func cancel() {
        source?.cancel()
        source = nil
    }
}
```

**Step 3: Build**

Run: `swift build`
Expected: builds (NoSleepApp has no `main` yet — add a temporary empty `main.swift` if the executable target fails to link, removed in Task 10).

> Note: add `Sources/NoSleepApp/main.swift` containing only `// placeholder` for now so the target links. It is replaced in Task 10.

**Step 4: Commit**

```bash
git add Sources/NoSleepApp
git commit -m "feat(app): add IOKit blocker and dispatch timer scheduler"
```

---

## Task 8: HotkeyManager (Carbon ⌃⌘Z)

Thin wrapper around `RegisterEventHotKey`. Manually verified. Reports registration failure via a callback.

**Files:**
- Create: `Sources/NoSleepApp/HotkeyManager.swift`

**Step 1: Implement**

```swift
import Carbon
import AppKit

final class HotkeyManager {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    /// Returns true on success; false if the combo is already taken.
    @discardableResult
    func register() -> Bool {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ctx in
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(ctx!).takeUnretainedValue()
            mgr.onPress()
            return noErr
        }, 1, &spec, selfPtr, &handler)

        let id = EventHotKeyID(signature: OSType(0x4E534C50), id: 1) // 'NSLP'
        let mods = UInt32(cmdKey | controlKey)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_Z), mods,
                                         id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil; handler = nil
    }
}
```

**Step 2: Build**

Run: `swift build`
Expected: builds.

**Step 3: Commit**

```bash
git add Sources/NoSleepApp/HotkeyManager.swift
git commit -m "feat(app): add Carbon global hotkey manager (Ctrl+Cmd+Z)"
```

---

## Task 9: LoginItem (SMAppService)

**Files:**
- Create: `Sources/NoSleepApp/LoginItem.swift`

**Step 1: Implement**

```swift
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            return false
        }
    }
}
```

**Step 2: Build**

Run: `swift build`
Expected: builds.

**Step 3: Commit**

```bash
git add Sources/NoSleepApp/LoginItem.swift
git commit -m "feat(app): add login-item helper via SMAppService"
```

---

## Task 10: MenuController + AppDelegate wiring

The agent: status item, menu, observers, and the glue connecting hotkey/menu/CLI commands into `AssertionManager` + `TimerController`, persisting to `StateStore` on every change.

**Files:**
- Create: `Sources/NoSleepApp/MenuController.swift`
- Create: `Sources/NoSleepApp/AppDelegate.swift`
- Replace: `Sources/NoSleepApp/main.swift`

**Step 1: `MenuController`**

```swift
import AppKit
import NoSleepCore

final class MenuController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var onToggle: (() -> Void)?
    var onTimer: ((TimeInterval) -> Void)?
    var onToggleLoginItem: (() -> Void)?
    var onQuit: (() -> Void)?

    init() { build() }

    private func build() {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Enable NoSleep", action: #selector(toggleTapped), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        let durations: [(String, TimeInterval)] = [("15 minutes", 900), ("1 hour", 3600), ("2 hours", 7200)]
        let timerMenu = NSMenu()
        for (title, secs) in durations {
            let item = NSMenuItem(title: title, action: #selector(timerTapped(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = secs
            timerMenu.addItem(item)
        }
        let timerParent = NSMenuItem(title: "Stay awake for…", action: nil, keyEquivalent: "")
        timerParent.submenu = timerMenu
        menu.addItem(timerParent)
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(loginTapped), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Quit NoSleep", action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        render(state: .inactive)
    }

    /// Update icon + toggle label/remaining time.
    func render(state: NoSleepState) {
        let symbol = state.isActive ? "moon.zzz.fill" : "moon"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "NoSleep")
        guard let toggle = statusItem.menu?.items.first else { return }
        if state.isActive {
            if let exp = state.expiresAt {
                let left = max(0, exp.timeIntervalSinceNow)
                toggle.title = "Disable NoSleep (\(formatDuration(seconds: left)) left)"
            } else {
                toggle.title = "Disable NoSleep"
            }
        } else {
            toggle.title = "Enable NoSleep"
        }
        statusItem.menu?.items.first(where: { $0.title == "Launch at Login" })?.state =
            LoginItem.isEnabled ? .on : .off
    }

    @objc private func toggleTapped() { onToggle?() }
    @objc private func timerTapped(_ sender: NSMenuItem) {
        if let secs = sender.representedObject as? TimeInterval { onTimer?(secs) }
    }
    @objc private func loginTapped() { onToggleLoginItem?() }
    @objc private func quitTapped() { onQuit?() }
}
```

**Step 2: `AppDelegate`**

```swift
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
```

**Step 3: `main.swift`**

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu bar agent, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

**Step 4: Build**

Run: `swift build`
Expected: builds. (`@testable` core tests still pass: `swift test`.)

**Step 5: Commit**

```bash
git add Sources/NoSleepApp/MenuController.swift Sources/NoSleepApp/AppDelegate.swift Sources/NoSleepApp/main.swift
git commit -m "feat(app): wire menu, hotkey, timer, and IPC into the agent"
```

---

## Task 11: CLI

Sends a command via `DistributedNotificationCenter`, launches the agent if needed, then reads and prints state.

**Files:**
- Create: `Sources/nosleep/main.swift`

**Step 1: Implement**

```swift
import Foundation
import AppKit
import NoSleepCore

let bundleID = "com.nosleep"
let store = StateStore.shared()

func agentRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
}

func launchAgent() {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    proc.arguments = ["-b", bundleID]
    try? proc.run()
    proc.waitUntilExit()
    // brief wait for heartbeat
    for _ in 0..<20 where !agentRunning() { usleep(100_000) }
}

func post(_ cmd: Command) {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.nosleep.cmd"),
        object: nil, userInfo: cmd.userInfo as? [String: Any],
        deliverImmediately: true)
}

func printState() {
    // Treat stale state as inactive when agent is dead.
    let running = agentRunning()
    let state = running ? store.load() : .inactive
    if state.isActive {
        if let exp = state.expiresAt {
            print("active (\(formatDuration(seconds: max(0, exp.timeIntervalSinceNow))) left)")
        } else {
            print("active")
        }
    } else {
        print("inactive")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = Command.parse(args) else {
    FileHandle.standardError.write(Data("usage: nosleep [on|off|toggle|status|timer <15m|1h|2h|90s>]\n".utf8))
    exit(2)
}

switch cmd {
case .status:
    printState()
case .off:
    if agentRunning() { post(.off); usleep(200_000) }
    printState()
default:
    if !agentRunning() { launchAgent() }
    post(cmd)
    usleep(200_000)   // let agent update shared state
    printState()
}
```

**Step 2: Build**

Run: `swift build`
Expected: builds all three targets.

**Step 3: Commit**

```bash
git add Sources/nosleep/main.swift
git commit -m "feat(cli): add nosleep CLI driving the running agent"
```

---

## Task 12: Info.plist + Makefile bundle

**Files:**
- Create: `Resources/Info.plist`
- Create: `Makefile`

**Step 1: `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>NoSleep</string>
    <key>CFBundleDisplayName</key>     <string>NoSleep</string>
    <key>CFBundleIdentifier</key>      <string>com.nosleep</string>
    <key>CFBundleExecutable</key>      <string>NoSleepApp</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
```

**Step 2: `Makefile`**

```makefile
APP := NoSleep.app
BIN := /usr/local/bin/nosleep

.PHONY: build bundle install clean test

build:
	swift build -c release

test:
	swift test

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/NoSleepApp $(APP)/Contents/MacOS/NoSleepApp
	cp .build/release/nosleep    $(APP)/Contents/MacOS/nosleep
	cp Resources/Info.plist      $(APP)/Contents/Info.plist
	codesign --force --deep --sign - $(APP)

install: bundle
	@echo "Copy $(APP) to /Applications, then symlink the CLI:"
	@echo "  ln -sf /Applications/$(APP)/Contents/MacOS/nosleep $(BIN)"

clean:
	rm -rf .build $(APP)
```

**Step 3: Verify**

Run: `make bundle`
Expected: produces `NoSleep.app`, ad-hoc signed. Launch with `open NoSleep.app` and confirm a menu bar moon icon appears.

**Step 4: Commit**

```bash
git add Resources/Info.plist Makefile
git commit -m "build: add Info.plist and Makefile bundle/install targets"
```

---

## Task 13: Manual smoke checklist + README

**Files:**
- Create: `docs/SMOKE_CHECKLIST.md`
- Create: `README.md`

**Step 1: `docs/SMOKE_CHECKLIST.md`**

```markdown
# NoSleep Manual Smoke Checklist

Run after `make bundle` and `open NoSleep.app`.

- [ ] Moon icon appears in the menu bar (no Dock icon).
- [ ] Click "Enable NoSleep" → icon becomes filled; `pmset -g assertions`
      shows `PreventUserIdleSystemSleep` held by NoSleep.
- [ ] Click "Disable NoSleep" → assertion clears from `pmset -g assertions`.
- [ ] Press ⌃⌘Z → toggles state; menu label updates.
- [ ] `nosleep on` → icon active; `nosleep status` prints `active`.
- [ ] `nosleep off` → `nosleep status` prints `inactive`.
- [ ] `nosleep toggle` flips state and stays in sync with the menu.
- [ ] `nosleep timer 15m` → active with countdown in menu; assertion auto-clears
      at expiry.
- [ ] Quit the app while a CLI command runs → `nosleep on` relaunches it.
- [ ] "Launch at Login" checked by default; survives reboot, starts inactive.
- [ ] Quit app → `pmset -g assertions` no longer lists NoSleep (no leak).
```

**Step 2: `README.md`** — short usage: build (`make bundle`), install, hotkey `⌃⌘Z`, CLI subcommands, the system-only/idle-only caveat (lid close & Apple-menu Sleep still sleep; display still sleeps by design).

**Step 3: Commit**

```bash
git add docs/SMOKE_CHECKLIST.md README.md
git commit -m "docs: add smoke checklist and README"
```

---

## Done criteria

- `swift test` green (core logic: state, assertion, timer, command, store).
- `make bundle` produces a launchable `NoSleep.app`.
- Manual smoke checklist passes end-to-end.
- Menu, hotkey, and CLI all reflect one shared state with no assertion leaks.
```
