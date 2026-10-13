import XCTest
@testable import RemoteMate

@MainActor
final class UUApplicationTests: XCTestCase {
    func testStatusDistinguishesClientAndBackgroundServices() async {
        var installed = true
        var client = false
        var background = true
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { installed }, isClientRunning: { client },
            isBackgroundRunning: { background }, open: { _ in }
        ))
        XCTAssertEqual(monitor.uuStatus, .backgroundOnly)
        XCTAssertTrue(monitor.uuStatus.canLaunch)
        client = true
        monitor.refreshUUStatus()
        XCTAssertEqual(monitor.uuStatus, .running)
        XCTAssertFalse(monitor.uuStatus.canLaunch)
        client = false
        monitor.refreshUUStatus()
        XCTAssertEqual(monitor.uuStatus, .backgroundOnly)
        background = false
        monitor.refreshUUStatus()
        XCTAssertEqual(monitor.uuStatus, .installedNotRunning)
        installed = false
        monitor.refreshUUStatus()
        XCTAssertEqual(monitor.uuStatus, .notInstalled)
    }

    func testResidentServiceDoesNotPreventAutomaticClientLaunch() async {
        var client = false
        var requests: [Bool] = []
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { true }, isClientRunning: { client },
            isBackgroundRunning: { true }, open: { activate in
                requests.append(activate)
                client = true
            }
        ))
        monitor.launchUUIfNeeded()
        XCTAssertTrue(monitor.isLaunchingUU)
        await monitor.uuLaunchTask?.value
        XCTAssertEqual(requests, [false], "Automatic launch must not steal focus")
        XCTAssertEqual(monitor.uuStatus, .running)
        XCTAssertFalse(monitor.isLaunchingUU)
        XCTAssertNil(monitor.lastError)
        monitor.launchUUIfNeeded()
        XCTAssertEqual(requests.count, 1, "Do not relaunch an already running client")
    }

    func testLaunchFailureIsVisibleAndCanBeRetried() async {
        var fail = true
        var client = false
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { true }, isClientRunning: { client },
            isBackgroundRunning: { true }, open: { _ in
                if fail { throw NSError(domain: "UUApplicationTests", code: 1) }
                client = true
            }
        ))
        monitor.launchUUIfNeeded()
        await monitor.uuLaunchTask?.value
        XCTAssertEqual(monitor.uuStatus, .backgroundOnly)
        XCTAssertNotNil(monitor.lastError)
        XCTAssertFalse(monitor.isLaunchingUU)
        fail = false
        monitor.launchUUIfNeeded()
        await monitor.uuLaunchTask?.value
        XCTAssertEqual(monitor.uuStatus, .running)
        XCTAssertNil(monitor.lastError)
    }

    func testMissingApplicationIsNotLaunched() async {
        var requests = 0
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { false }, isClientRunning: { false },
            isBackgroundRunning: { true }, open: { _ in requests += 1 }
        ))
        monitor.launchUUIfNeeded()
        XCTAssertNil(monitor.uuLaunchTask)
        XCTAssertEqual(requests, 0)
    }

    func testRepeatedRequestsDoNotStartMultipleLaunches() async {
        var continuation: CheckedContinuation<Void, Never>?
        var client = false
        var requests = 0
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { true }, isClientRunning: { client },
            isBackgroundRunning: { true }, open: { _ in
                requests += 1
                await withCheckedContinuation { continuation = $0 }
                client = true
            }
        ))
        monitor.launchUUIfNeeded()
        while continuation == nil { await Task.yield() }
        monitor.launchUUIfNeeded()
        monitor.openUU()
        XCTAssertEqual(requests, 1)
        continuation?.resume()
        await monitor.uuLaunchTask?.value
        XCTAssertEqual(monitor.uuStatus, .running)
    }
}
