import Foundation

/// Fetch Observatory observations/warnings/nine-day forecasts without location parameters; select the nearest station locally.
/// Outside Hong Kong, use Open-Meteo and send only a location rounded to roughly ten-kilometre precision.
/// Retain the previous report after fetch failure, but invalidate observations older than 75 minutes; nil means no valid report, not fabricated weather.
@MainActor
@Observable
final class HKOWeatherService {
    private(set) var report: HKOReport?
    /// A manually selected demo/script weather override remains until demo reset.
    var demoOverride = false
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// Track the previous source region; moving outside Hong Kong switches immediately without waiting ten minutes.
    @ObservationIgnored private var lastInHK: Bool?

    static let maxAge: TimeInterval = 75 * 60

    static let base = "https://data.weather.gov.hk/weatherAPI/opendata/weather.php"

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.timeoutIntervalForResource = 12
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    /// Skip a fetch if attempted within ten minutes; return the currently valid report on success or failure.
    func refresh(near p: GeoPoint, force: Bool = false) async -> HKOReport? {
        if LaunchArgs.has("-offline") { report = nil; return nil }
        if loading { return report }
        let inHK = HongKongArea.contains(p)
        if lastInHK != inHK { report = nil; fetchedAt = nil; lastInHK = inHK }
        if !force, let t = fetchedAt, Date().timeIntervalSince(t) < 600 { return report }
        loading = true
        defer { loading = false }
        guard inHK else {
            if let url = OpenMeteo.url(near: p), let data = await fetch(url), let parsed = HKOReport.parseOpenMeteo(data) {
                report = parsed
                fetchedAt = Date()
            }
            if let old = report, Date().timeIntervalSince(old.updated ?? fetchedAt ?? .distantPast) > Self.maxAge { report = nil }
            return report
        }
        async let now = get("rhrread")
        async let warn = get("warnsum")
        async let fnd = get("fnd")
        let (r, w, f) = await (now, warn, fnd)
        if let r, let parsed = HKOReport.parse(rhrread: r, warnsum: w, fnd: f, near: p, today: Date()) {
            report = parsed
            fetchedAt = Date()
        }
        // Do not call an old reading current.
        if let old = report, Date().timeIntervalSince(old.updated ?? fetchedAt ?? .distantPast) > Self.maxAge { report = nil }
        return report
    }

    /// Refresh every 15 minutes in foreground through onTick; stop in background.
    func keepFresh(_ on: Bool, onTick: @escaping @MainActor () -> Void) {
        loop?.cancel()
        loop = nil
        guard on else { return }
        loop = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                if Task.isCancelled { return }
                onTick()
            }
        }
    }

    private func get(_ type: String) async -> Data? {
        guard let url = URL(string: "\(Self.base)?dataType=\(type)&lang=tc") else { return nil }
        return await fetch(url)
    }

    private func fetch(_ url: URL) async -> Data? {
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
