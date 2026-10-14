import XCTest
@testable import RemoteMate

@MainActor
final class UUKeepAliveTests: XCTestCase {
    func testKeepAliveRequiresRemoteModeAndBothUUPreferences() async {
        var client = false
        var requests: [Bool] = []
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { true }, isClientRunning: { client },
            isBackgroundRunning: { true }, open: { activate in
                requests.append(activate)
                client = true
            }
        ))
        defer { monitor.updateUUKeepAlive(remoteModeOn: false, launchUU: false, keepAlive: true) }

        for (mode, preference, keepAlive) in [(false, false, false), (false, false, true), (false, true, false), (false, true, true), (true, false, false), (true, false, true), (true, true, false)] {
            monitor.updateUUKeepAlive(remoteModeOn: mode, launchUU: preference, keepAlive: keepAlive)
            XCTAssertFalse(monitor.isUUKeepAliveEnabled)
            XCTAssertNil(monitor.uuLaunchTask)
        }
        monitor.updateUUKeepAlive(remoteModeOn: true, launchUU: true, keepAlive: true)
        await monitor.uuLaunchTask?.value
        XCTAssertTrue(monitor.isUUKeepAliveEnabled)
        XCTAssertEqual(requests, [false], "Keep-alive must start the client without stealing focus")

        monitor.updateUUKeepAlive(remoteModeOn: false, launchUU: true, keepAlive: true)
        XCTAssertFalse(monitor.isUUKeepAliveEnabled)
        XCTAssertTrue(client, "Stopping keep-alive must leave the running client alone")
        monitor.updateUUKeepAlive(remoteModeOn: true, launchUU: true, keepAlive: true)
        monitor.updateUUKeepAlive(remoteModeOn: true, launchUU: false, keepAlive: true)
        XCTAssertFalse(monitor.isUUKeepAliveEnabled)
        XCTAssertEqual(requests.count, 1, "A running client must not be launched again")
    }

    func testPeriodicRecoveryContinuesWithPanelClosed() async {
        var client = true
        let relaunched = expectation(description: "Client restarted after quitting")
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { true }, isClientRunning: { client },
            isBackgroundRunning: { true }, open: { activate in
                XCTAssertFalse(activate)
                client = true
                relaunched.fulfill()
            }
        ), uuKeepAliveInterval: 0.02)
        defer { monitor.updateUUKeepAlive(remoteModeOn: false, launchUU: false, keepAlive: true) }
        monitor.updateUUKeepAlive(remoteModeOn: true, launchUU: true, keepAlive: true)
        monitor.stopAutoRefresh()
        client = false
        await fulfillment(of: [relaunched], timeout: 2)
        await monitor.uuLaunchTask?.value
        XCTAssertEqual(monitor.uuStatus, .running)
    }

    func testFailureRetriesOnNextTickWithoutOverlappingLaunches() async {
        var client = false
        var attempts = 0
        var inFlight = 0
        let recovered = expectation(description: "Failed launch retried")
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { true }, isClientRunning: { client },
            isBackgroundRunning: { true }, open: { _ in
                attempts += 1
                inFlight += 1
                defer { inFlight -= 1 }
                XCTAssertEqual(inFlight, 1)
                // Multiple timer ticks occur while the launch is pending.
                try await Task.sleep(nanoseconds: 70_000_000)
                if attempts == 1 { throw NSError(domain: "UUKeepAliveTests", code: 1) }
                client = true
                recovered.fulfill()
            }
        ), uuKeepAliveInterval: 0.02)
        defer { monitor.updateUUKeepAlive(remoteModeOn: false, launchUU: false, keepAlive: true) }
        monitor.updateUUKeepAlive(remoteModeOn: true, launchUU: true, keepAlive: true)
        await fulfillment(of: [recovered], timeout: 2)
        await monitor.uuLaunchTask?.value
        XCTAssertEqual(attempts, 2)
        XCTAssertNil(monitor.lastError)
    }

    func testDisablingAnyConditionCancelsQueuedAutomaticLaunch() async {
        for (mode, preference, keepAlive) in [(false, true, true), (true, false, true), (true, true, false)] {
            let monitor = NetworkMonitor(uuEnvironment: .init(
                isInstalled: { true }, isClientRunning: { false },
                isBackgroundRunning: { true }, open: { _ in
                    XCTFail("A disabled keep-alive must not execute its queued launch")
                }
            ), uuKeepAliveInterval: 0.01)
            monitor.updateUUKeepAlive(remoteModeOn: true, launchUU: true, keepAlive: true)
            monitor.updateUUKeepAlive(remoteModeOn: mode, launchUU: preference, keepAlive: keepAlive)
            await monitor.uuLaunchTask?.value
            try? await Task.sleep(nanoseconds: 60_000_000)
            XCTAssertFalse(monitor.isLaunchingUU)
            XCTAssertNil(monitor.lastError)
        }
    }

    func testStoppingKeepAliveDoesNotCancelManualOpen() async {
        var client = false
        var requests: [Bool] = []
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { true }, isClientRunning: { client },
            isBackgroundRunning: { true }, open: { activate in
                requests.append(activate)
                client = true
            }
        ))
        monitor.openUU(activate: true)
        monitor.updateUUKeepAlive(remoteModeOn: true, launchUU: true, keepAlive: true)
        monitor.updateUUKeepAlive(remoteModeOn: false, launchUU: true, keepAlive: true)
        await monitor.uuLaunchTask?.value
        XCTAssertEqual(requests, [true])
        XCTAssertEqual(monitor.uuStatus, .running)
    }

    func testStoppingDuringLaunchDoesNotReportCancellationAsFailure() async {
        var continuation: CheckedContinuation<Void, Never>?
        var client = false
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { true }, isClientRunning: { client },
            isBackgroundRunning: { true }, open: { _ in
                await withCheckedContinuation { continuation = $0 }
                client = true // The OS may finish a request already submitted before cancellation.
            }
        ))
        monitor.updateUUKeepAlive(remoteModeOn: true, launchUU: true, keepAlive: true)
        while continuation == nil { await Task.yield() }
        monitor.updateUUKeepAlive(remoteModeOn: false, launchUU: true, keepAlive: true)
        continuation?.resume()
        await monitor.uuLaunchTask?.value
        XCTAssertTrue(client)
        XCTAssertEqual(monitor.uuStatus, .running)
        XCTAssertFalse(monitor.isLaunchingUU)
        XCTAssertFalse(monitor.isUUKeepAliveEnabled)
        XCTAssertNil(monitor.lastError)
    }

    func testMissingApplicationIsNotLaunchedByKeepAlive() async {
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { false }, isClientRunning: { false },
            isBackgroundRunning: { false }, open: { _ in XCTFail("App is not installed") }
        ), uuKeepAliveInterval: 0.01)
        defer { monitor.updateUUKeepAlive(remoteModeOn: false, launchUU: false, keepAlive: true) }
        monitor.updateUUKeepAlive(remoteModeOn: true, launchUU: true, keepAlive: true)
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertNil(monitor.uuLaunchTask)
        XCTAssertEqual(monitor.uuStatus, .notInstalled)
        XCTAssertFalse(monitor.isUUKeepAliveEnabled)
        XCTAssertNotNil(monitor.lastError)
    }

    func testSlowBackgroundLaunchDoesNotLeaveManualRetryError() async {
        var client = false
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { true }, isClientRunning: { client },
            isBackgroundRunning: { true }, open: { _ in }
        ))
        defer { monitor.updateUUKeepAlive(remoteModeOn: false, launchUU: false, keepAlive: false) }
        monitor.updateUUKeepAlive(remoteModeOn: true, launchUU: true, keepAlive: true)
        await monitor.uuLaunchTask?.value // Client is still cold-starting after the 2-second check.
        XCTAssertNil(monitor.lastError)
        XCTAssertEqual(monitor.uuStatus, .backgroundOnly)
        client = true
        monitor.refreshUUStatus()
        XCTAssertEqual(monitor.uuStatus, .running)
        XCTAssertNil(monitor.lastError)
    }

    func testManualForegroundRequestSurvivesBackgroundLaunchAndCancellation() async {
        for stopKeepAlive in [false, true] {
            var continuation: CheckedContinuation<Void, Never>?
            var requests: [Bool] = []
            var client = false
            let monitor = NetworkMonitor(uuEnvironment: .init(
                isInstalled: { true }, isClientRunning: { client },
                isBackgroundRunning: { true }, open: { activate in
                    requests.append(activate)
                    if requests.count == 1 { await withCheckedContinuation { continuation = $0 } }
                    client = true
                }
            ))
            defer { monitor.updateUUKeepAlive(remoteModeOn: false, launchUU: false, keepAlive: false) }
            monitor.updateUUKeepAlive(remoteModeOn: true, launchUU: true, keepAlive: true)
            while continuation == nil { await Task.yield() }
            let backgroundLaunch = monitor.uuLaunchTask
            for _ in 0..<3 { monitor.openUU(activate: true) }
            XCTAssertEqual(requests, [false], "Foreground clicks must not start overlapping requests")
            if stopKeepAlive { monitor.updateUUKeepAlive(remoteModeOn: false, launchUU: true, keepAlive: true) }
            continuation?.resume()
            await backgroundLaunch?.value
            await monitor.uuLaunchTask?.value
            XCTAssertEqual(requests, [false, true], "Repeated clicks become one foreground request")
            XCTAssertEqual(monitor.uuStatus, .running)
            XCTAssertFalse(monitor.isLaunchingUU)
            XCTAssertNil(monitor.lastError)
        }
    }

    func testCancelledLaunchRefreshesStatusEvenIfOpenThrowsAnotherError() async {
        var continuation: CheckedContinuation<Void, Never>?
        var client = false
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { true }, isClientRunning: { client },
            isBackgroundRunning: { true }, open: { _ in
                await withCheckedContinuation { continuation = $0 }
                client = true
                throw NSError(domain: "UUKeepAliveTests", code: 2)
            }
        ))
        monitor.updateUUKeepAlive(remoteModeOn: true, launchUU: true, keepAlive: true)
        while continuation == nil { await Task.yield() }
        monitor.updateUUKeepAlive(remoteModeOn: false, launchUU: true, keepAlive: true)
        continuation?.resume()
        await monitor.uuLaunchTask?.value
        XCTAssertEqual(monitor.uuStatus, .running)
        XCTAssertFalse(monitor.isLaunchingUU)
        XCTAssertNil(monitor.lastError)
    }

    func testRemovingUUStopsKeepAlive() async {
        var installed = true
        var client = true
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { installed }, isClientRunning: { client },
            isBackgroundRunning: { false }, open: { _ in XCTFail("No launch is needed") }
        ), uuKeepAliveInterval: 0.01)
        defer { monitor.updateUUKeepAlive(remoteModeOn: false, launchUU: false, keepAlive: false) }
        monitor.updateUUKeepAlive(remoteModeOn: true, launchUU: true, keepAlive: true)
        XCTAssertTrue(monitor.isUUKeepAliveEnabled)
        installed = false
        for _ in 0..<100 {
            if !monitor.isUUKeepAliveEnabled { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(monitor.isUUKeepAliveEnabled)
        XCTAssertEqual(monitor.uuStatus, .notInstalled)
        XCTAssertNotNil(monitor.lastError)
        // Reinstalling must not revive the timer that was stopped on removal.
        installed = true
        client = false
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertFalse(monitor.isUUKeepAliveEnabled)
        XCTAssertNil(monitor.uuLaunchTask)
    }
}
