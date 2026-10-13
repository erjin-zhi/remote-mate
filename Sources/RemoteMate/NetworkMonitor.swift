import AppKit
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    enum Level { case good, fair, bad, unknown }

    struct Probe: Equatable {
        var level: Level = .unknown
        var value = "检测中…"
        var detail = ""
    }

    enum UUStatus: Equatable {
        case running
        case backgroundOnly
        case installedNotRunning
        case notInstalled

        var canLaunch: Bool {
            self == .installedNotRunning || self == .backgroundOnly
        }
    }

    static let uuAppPath = "/Applications/UURemote.app"
    static let uuServiceHost = "api.nrd.nie.163.com"
    static let wanHost = "223.5.5.5"

    @Published private(set) var interfaceText = "网络未知"
    @Published private(set) var isOnline = true
    @Published private(set) var proxyTUN = false
    @Published private(set) var lan = Probe()
    @Published private(set) var wan = Probe()
    @Published private(set) var uuService = Probe()
    @Published private(set) var uuStatus: UUStatus = .notInstalled
    @Published private(set) var isLaunchingUU = false
    @Published var lastError: String?
    private(set) var uuLaunchTask: Task<Void, Never>?
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?

    private let pathMonitor = NWPathMonitor()
    private var timer: Timer?
    private var uuStatusTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private let uuEnvironment: UUApplicationEnvironment

    init(uuEnvironment: UUApplicationEnvironment? = nil) {
        self.uuEnvironment = uuEnvironment ?? .live
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.update(path: path) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "remotemate.path"))
        refreshUUStatus()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == UUApplicationEnvironment.bundleIdentifier else { return }
                Task { @MainActor [weak self] in self?.refreshUUStatus() }
            })
        }
    }

    deinit {
        timer?.invalidate()
        uuStatusTimer?.invalidate()
        pathMonitor.cancel()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// 面板打开时周期刷新，关闭后停止，避免后台持续 ping。
    func startAutoRefresh() {
        refreshUUStatus()
        uuStatusTimer?.invalidate()
        uuStatusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshUUStatus() }
        }
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
        uuStatusTimer?.invalidate()
        uuStatusTimer = nil
    }

    func refresh() {
        guard !isChecking else { return }
        isChecking = true
        refreshUUStatus()
        Task {
            let routes = await Self.readRoutes()
            proxyTUN = routes.tun
            async let lanResult = Self.ping(routes.gateway, interface: routes.interface)
            async let wanResult = Self.ping(Self.wanHost, interface: routes.interface)
            async let uuResult = Self.https(Self.uuServiceHost)
            let (l, w, u) = await (lanResult, wanResult, uuResult)
            lan = l.map { Self.probe(latency: $0.ms, loss: $0.loss, good: 10, fair: 50, detail: "网关 \(routes.gateway ?? "")") }
                ?? Probe(level: .bad, value: routes.gateway == nil ? "无网关" : "不可达", detail: "网关 \(routes.gateway ?? "-")")
            wan = w.map { Self.probe(latency: $0.ms, loss: $0.loss, good: 60, fair: 150, detail: "Ping \(Self.wanHost)") }
                ?? Probe(level: .bad, value: "不可达", detail: "Ping \(Self.wanHost)")
            uuService = u.map { Self.probe(latency: $0, loss: 0, good: 300, fair: 800, detail: "HTTPS \(Self.uuServiceHost)") }
                ?? Probe(level: .bad, value: "不可达", detail: "HTTPS \(Self.uuServiceHost)")
            refreshUUStatus()
            lastChecked = Date()
            isChecking = false
        }
    }

    func openUU(activate: Bool = true) {
        guard !isLaunchingUU else { return }
        refreshUUStatus()
        guard uuStatus != .notInstalled else {
            lastError = "未找到 UU 远程，请先将其安装到应用程序文件夹。"
            return
        }
        lastError = nil
        isLaunchingUU = true
        uuLaunchTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isLaunchingUU = false }
            do {
                try await self.uuEnvironment.open(activate)
                // 启动回调与 Workspace 主程序列表的更新可能相差片刻。
                for _ in 0..<10 {
                    self.refreshUUStatus()
                    if self.uuStatus == .running { return }
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                self.refreshUUStatus()
                if self.uuStatus != .running {
                    self.lastError = "已请求启动 UU 远程，但尚未检测到主程序，请重试。"
                }
            } catch {
                self.refreshUUStatus()
                self.lastError = "启动 UU 远程失败：\(error.localizedDescription)"
            }
        }
    }

    /// 后台守护服务不代表客户端已启动；仅后台服务运行时也应拉起主程序。
    func launchUUIfNeeded() {
        refreshUUStatus()
        guard uuStatus.canLaunch else { return }
        openUU(activate: false)
    }

    // MARK: - 内部

    private func update(path: NWPath) {
        isOnline = path.status == .satisfied
        let type: String
        if !isOnline {
            type = "无网络"
        } else if path.usesInterfaceType(.wiredEthernet) {
            type = "有线"
        } else if path.usesInterfaceType(.wifi) {
            type = "Wi‑Fi"
        } else if path.usesInterfaceType(.cellular) {
            type = "蜂窝"
        } else {
            type = "已联网"
        }
        interfaceText = type
    }

    func refreshUUStatus() {
        if !uuEnvironment.isInstalled() {
            uuStatus = .notInstalled
        } else if uuEnvironment.isClientRunning() {
            uuStatus = .running
        } else if uuEnvironment.isBackgroundRunning() {
            uuStatus = .backgroundOnly
        } else {
            uuStatus = .installedNotRunning
        }
    }

    private static func probe(latency: Double, loss: Double, good: Double, fair: Double, detail: String) -> Probe {
        let level: Level
        if loss >= 50 { level = .bad }
        else if latency <= good && loss == 0 { level = .good }
        else if latency <= fair { level = .fair }
        else { level = .bad }
        var value = "\(Int(latency.rounded())) ms"
        if loss > 0 { value += " · 丢包\(Int(loss))%" }
        return Probe(level: level, value: value, detail: detail)
    }

    /// 从路由表找物理网卡的网关（代理 TUN 接管默认路由时仍能找到真实网关）。
    private static func readRoutes() async -> (gateway: String?, interface: String?, tun: Bool) {
        let output = await Shell.runAsync("/usr/sbin/netstat", ["-rn", "-f", "inet"]).output
        var gateway: String?
        var interface: String?
        var tun = false
        var firstDefault = true
        for line in output.split(separator: "\n") {
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard cols.count >= 4, cols[0] == "default" else { continue }
            let iface = String(cols[3])
            if firstDefault && iface.hasPrefix("utun") { tun = true }
            firstDefault = false
            let gw = String(cols[1])
            if gateway == nil, !iface.hasPrefix("utun"), gw.split(separator: ".").count == 4 {
                gateway = gw
                interface = iface
            }
        }
        return (gateway, interface, tun)
    }

    /// 绑定物理网卡发包，绕开代理 TUN（否则内网地址会被 TUN 吞掉）。
    private static func ping(_ host: String?, interface: String?) async -> (ms: Double, loss: Double)? {
        guard let host else { return nil }
        var args = ["-c", "3", "-i", "0.2", "-t", "3", "-q"]
        if let interface { args += ["-b", interface] }
        let output = await Shell.runAsync("/sbin/ping", args + [host]).output
        var loss = 100.0
        if let range = output.range(of: #"([\d.]+)% packet loss"#, options: .regularExpression) {
            loss = Double(output[range].split(separator: "%").first ?? "") ?? 100
        }
        // round-trip min/avg/max/stddev = 39.9/40.9/42.0/1.0 ms
        guard loss < 100,
              let line = output.split(separator: "\n").first(where: { $0.contains("min/avg/max") }),
              let stats = line.split(separator: "=").last?.trimmingCharacters(in: .whitespaces) else { return nil }
        let parts = stats.split(separator: "/")
        guard parts.count >= 2, let avg = Double(parts[1]) else { return nil }
        return (avg, loss)
    }

    /// HTTPS 请求耗时（含 DNS/TCP/TLS），收到任意 HTTP 响应即视为服务可达。
    private static func https(_ host: String) async -> Double? {
        guard let url = URL(string: "https://\(host)/") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 5)
        request.httpMethod = "HEAD"
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let start = Date()
        do {
            let (_, response) = try await session.data(for: request)
            guard response is HTTPURLResponse else { return nil }
            return Date().timeIntervalSince(start) * 1000
        } catch {
            return nil
        }
    }
}
