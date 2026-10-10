import Foundation

/// 向后端交一次性码，配上为止（NeighborLinking.swift 嘅约定：未配上返回 nil，每 1–2 秒再问）。
/// 碰一碰（NearbyBumpService）同二维码（AppStore+Bump）共用。
@MainActor
enum LinkPolling {
    /// 每 interval 秒问一次：配上返回对方；够钟都未配上返回 nil；中途网络出错唔即刻放弃，
    /// 够钟时如果最后一次係出错就抛返嗰个错（界面讲「網絡有問題」）。Task 被取消就抛 CancellationError。
    static func poll(_ linker: NeighborLinker, code: String,
                     interval: TimeInterval = BumpTuning.linkInterval,
                     timeout: TimeInterval = BumpTuning.linkTimeout) async throws -> LinkedPeer? {
        let start = Date()
        var lastError: Error?
        while true {
            try Task.checkCancellation()
            do {
                if let peer = try await linker.link(code: code) { return peer }
                lastError = nil
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
            try Task.checkCancellation()
            guard Date().timeIntervalSince(start) + interval <= timeout else { break }
            try await Task.sleep(for: .seconds(interval))
        }
        if let lastError { throw lastError }
        return nil
    }
}

#if DEBUG
/// 【只限 Debug】未接后端时假扮伺服器同对方，等碰一碰 / 二维码喺模拟器、单部手机都试得到成个流程。
/// 同一个码第一次交返 nil（等紧对方），过咗 delay 秒就返回一个「測試街坊」（由码推出，两部手机见到同一个）。
/// 启动参数：`-testLinkerDelay 秒`（默认 3）、`-testLinkerNever`（永远配唔上，试超时）、`-testLinkerError`（试网络出错）。
/// 【整合】接咗后端（社区服务实现 NeighborLinker）就唔会再用呢个，见 AppStore+Bump 嘅 linker。
@MainActor
final class LocalTestLinker: NeighborLinker {
    static let shared = LocalTestLinker()

    var delay: TimeInterval = LaunchArgs.value("-testLinkerDelay").flatMap(Double.init) ?? 3
    var never = LaunchArgs.has("-testLinkerNever")
    var failing = LaunchArgs.has("-testLinkerError")
    private(set) var submitted: [String] = []
    private var firstSeen: [String: Date] = [:]

    struct TestError: Error {}

    func link(code: String) async throws -> LinkedPeer? {
        try await Task.sleep(for: .milliseconds(150))   // 扮网络来回
        if failing { throw TestError() }
        submitted.append(code)
        let t0 = firstSeen[code] ?? Date()
        firstSeen[code] = t0
        guard !never, Date().timeIntervalSince(t0) >= delay else { return nil }
        return Self.peer(for: code)
    }

    static func peer(for code: String) -> LinkedPeer {
        let n = code.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let names = ["何太", "林伯", "周生", "馬太", "葉姨", "孫伯"]
        return LinkedPeer(id: "test-" + code.prefix(8), nickname: "測試" + names[n % names.count],
                          mobility: Mobility.allCases[n % Mobility.allCases.count],
                          colorIndex: n % 6, skinTone: n % 3, ageGroup: .elder,
                          block: nil, floor: 2 + n % 28)
    }
}
#endif
