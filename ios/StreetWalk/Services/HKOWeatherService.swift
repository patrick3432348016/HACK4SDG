import Foundation

/// 拉香港天文台开放数据（本港地区天气、警告、九天预报）。只发请求，不带任何位置；最近测站在手机上挑。
/// 屋企喺香港以外（例如深圳）就改用 Open-Meteo 天气预报（OpenMeteo.swift），只送约 10 公里精度嘅位置。
/// 失败就保留上一份，但读数超过 75 分钟（rhrread 每小时更新）就作废，离线时 report 为 nil，不显示假天气。
@MainActor
@Observable
final class HKOWeatherService {
    private(set) var report: HKOReport?
    /// 演示菜单 / 脚本手动选了天气：之后不再用实时数据覆盖，直到重置演示。
    var demoOverride = false
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// 上次拉嘅系唔系香港：搬咗去深圳要即刻换来源，唔好等 10 分钟。
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

    /// 10 分钟内拉过就不再拉。成功或失败都返回当前可用的报告。
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
        // 读数太旧就唔好再讲"而家"
        if let old = report, Date().timeIntervalSince(old.updated ?? fetchedAt ?? .distantPast) > Self.maxAge { report = nil }
        return report
    }

    /// 前台时每 15 分钟拉一次（拉之前 onTick 会调 refresh）；退到后台就停。
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
