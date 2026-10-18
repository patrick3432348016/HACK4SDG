import Foundation

/// Submit a one-time code until paired. NeighborLinking.swift defines nil as pending, with polling every 1–2 seconds.
/// Shared by NearbyBumpService and QR pairing in AppStore+Bump.
@MainActor
enum LinkPolling {
    /// Poll every interval seconds. Return the peer on success or nil on timeout; tolerate transient network errors during the wait.
    /// At timeout, rethrow the last error if present so the UI can explain network failure. Task cancellation throws CancellationError.
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
/// Debug only: simulate the server/peer for a complete bump/QR flow on a simulator or one phone before backend integration.
/// First submission returns nil; after delay, return a test neighbor deterministically derived from the code.
/// Launch options: -testLinkerDelay seconds (default 3), -testLinkerNever for timeout, and -testLinkerError for network failure.
/// Once CommunityService implements NeighborLinker, this test implementation is unused; see AppStore+Bump.linker.
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
        try await Task.sleep(for: .milliseconds(150))   // Simulate network round-trip time.
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
