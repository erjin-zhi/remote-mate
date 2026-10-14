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
        XCTAssertFalse(monitor.isUUKeepAliveEnabled, "One-shot launch must not enable keep-alive")
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
                if requests == 1 { await withCheckedContinuation { continuation = $0 } }
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
        await monitor.uuLaunchTask?.value // The queued foreground request follows the background launch.
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(monitor.uuStatus, .running)
    }

    func testMissingApplicationSkipsProcessAndServiceChecks() async {
        var serviceRequests = 0
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { false },
            isClientRunning: { XCTFail("Uninstalled app must not query client processes"); return false },
            isBackgroundRunning: { XCTFail("Uninstalled app must not query services"); return false },
            open: { _ in XCTFail("Uninstalled app must not launch") }
        ))
        let result = await monitor.probeUUService { _ in serviceRequests += 1; return 20 }
        XCTAssertNil(result)
        XCTAssertEqual(serviceRequests, 0)
        XCTAssertFalse(monitor.isUUInstalled)
    }

    func testInstalledApplicationProbesServiceAndDropsResultIfUninstalled() async {
        var installed = true
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { installed }, isClientRunning: { false },
            isBackgroundRunning: { false }, open: { _ in }
        ))
        var serviceRequests = 0
        let success = await monitor.probeUUService { _ in serviceRequests += 1; return 20 }
        XCTAssertEqual(serviceRequests, 1)
        XCTAssertEqual(success?.value, "20 ms")
        let removed = await monitor.probeUUService { _ in installed = false; return 30 }
        XCTAssertNil(removed)
        monitor.refreshUUStatus()
        XCTAssertFalse(monitor.isUUInstalled)
        XCTAssertEqual(monitor.uuService.value, "未检测")
    }

    func testClickAlreadyRunningClientRequestsForegroundActivation() async {
        var requests: [Bool] = []
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { true }, isClientRunning: { true },
            isBackgroundRunning: { true }, open: { activate in requests.append(activate) }
        ))
        monitor.openUU(activate: true)
        await monitor.uuLaunchTask?.value
        XCTAssertEqual(requests, [true])
        XCTAssertNil(monitor.lastError)
    }

    func testManualLaunchStillReportsUnconfirmedStartup() async {
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { true }, isClientRunning: { false },
            isBackgroundRunning: { true }, open: { _ in }
        ))
        monitor.openUU()
        await monitor.uuLaunchTask?.value
        XCTAssertNotNil(monitor.lastError)
        XCTAssertFalse(monitor.isLaunchingUU)
    }


    func testOneClickRechecksActualClientInsteadOfStaleDisplayedStatus() async {
        var client = true
        var requests = 0
        let monitor = NetworkMonitor(uuEnvironment: .init(
            isInstalled: { true }, isClientRunning: { client },
            isBackgroundRunning: { true }, open: { _ in requests += 1; client = true }
        ))
        XCTAssertEqual(monitor.uuStatus, .running)
        client = false // Client quits before the panel receives a refresh.
        monitor.launchUUIfNeeded()
        await monitor.uuLaunchTask?.value
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(monitor.uuStatus, .running)

        client = false
        monitor.refreshUUStatus()
        XCTAssertEqual(monitor.uuStatus, .backgroundOnly)
        client = true // Client starts while the panel still shows background-only.
        monitor.launchUUIfNeeded()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(monitor.uuStatus, .running)
    }

}
