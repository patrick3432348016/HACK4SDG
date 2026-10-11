import CoreLocation
import Foundation

/// 取当前位置 → 吸附到格子 → 读缓存 / 请求 Overpass → 失败就用旧缓存，再不行才用内置皇后山邨。
/// 只有格子范围会发给地图服务，精确位置不离开手机。
@MainActor
final class MapService: NSObject, CLLocationManagerDelegate {
    enum Source: String {
        case live = "實時", cache = "快取", fallback = "示例"
        /// 显示用。
        var label: String {
            switch self {
            case .live: return L.t("實時", "实时")
            case .cache: return L.t("快取", "缓存")
            case .fallback: return L.t("示例", "示例")
            }
        }
    }

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<GeoPoint?, Never>?
    private var locationTimer: DispatchWorkItem?

    /// overpass.private.coffee 已失效（2026-10 起一律回 500），不再用。
    nonisolated static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    ]
    /// 实时拉取的边长（米）。比 400 m 格子大：屋企在格边（离格心约 200 m）时，以它为中心的 200 m 底座仍在资料范围内。
    /// 内置示例屋邨仍然是 560 m（TileKey.plinthSize）。
    nonisolated static let fetchSize = 720.0
    /// 拉地图最多等几耐（秒）。两个服务器同时问，边个先答到就用边个。
    nonisolated static let fetchTimeout = 30.0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - 位置

    /// 下一次 currentLocation 直接用呢个位置（「你係咪搬咗屋」按「係」：喺过夜嘅地方重新揀樓）。用一次就清。
    var pinnedLocation: GeoPoint?

    /// 只在首次选楼 / 重新选楼时调用。权限框未回答前不计时（长者看权限框可能要很久），回答后才等 timeout 秒。
    func currentLocation(timeout: TimeInterval = 8) async -> GeoPoint? {
        if let p = pinnedLocation { pinnedLocation = nil; return p }
        if LaunchArgs.has("-offline") { return nil }
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted { return nil }
        return await withCheckedContinuation { cont in
            // 上一次还在等（例如连按两次重新选楼）：先给它 nil，不要挂住。
            finishLocation(nil)
            locationContinuation = cont
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
                armTimeout(120)
            } else {
                manager.requestLocation()
                armTimeout(timeout)
            }
        }
    }

    private func armTimeout(_ seconds: TimeInterval) {
        locationTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.finishLocation(nil) }
        locationTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func finishLocation(_ p: GeoPoint?) {
        locationTimer?.cancel()
        locationTimer = nil
        locationContinuation?.resume(returning: p)
        locationContinuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            // 建 CLLocationManager 时系统也会回调一次：没人在等位置就不取（F1：只在需要时开定位）。
            guard self.locationContinuation != nil else { return }
            switch m.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                m.requestLocation()
                self.armTimeout(8)
            case .denied, .restricted: self.finishLocation(nil)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let p = GeoPoint(lat: l.coordinate.latitude, lon: l.coordinate.longitude)
        Task { @MainActor in self.finishLocation(p) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishLocation(nil) }
    }

    // MARK: - 地图

    func load(tile: TileKey) async -> (MapModel, Source) {
        if !LaunchArgs.has("-offline") {
            if let c = TileCache.read(tile), let m = try? OSMParser.parse(c.data, tile: tile, size: c.size, source: "cache") { return (m, .cache) }
            if let data = await fetch(tile), let m = try? OSMParser.parse(data, tile: tile, size: Self.fetchSize, source: "live") {
                TileCache.write(tile, data)
                return (m, .live)
            }
            // 拉不到：过期的旧缓存也比示例屋邨好（至少是你屋企附近）。
            if let c = TileCache.read(tile, maxAge: .infinity), let m = try? OSMParser.parse(c.data, tile: tile, size: c.size, source: "cache") { return (m, .cache) }
        }
        return (Self.fallback(), .fallback)
    }

    static func fallback() -> MapModel {
        let url = Bundle.main.url(forResource: "fallback_queenshill", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        return try! OSMParser.parse(data, tile: TileKey(ix: 0, iy: 0), source: "fallback")
    }

    /// Overpass 用的 south,west,north,east（以格心为中心、边长 size，仍然按格子对齐，不含精确位置）。
    nonisolated static func bbox(_ t: TileKey, size: Double = fetchSize) -> String {
        let proj = LocalProjection(origin: t.center)
        let h = size / 2
        let sw = proj.toGeo(Vec2(x: -h, y: -h)), ne = proj.toGeo(Vec2(x: h, y: h))
        return String(format: "%.7f,%.7f,%.7f,%.7f", sw.lat, sw.lon, ne.lat, ne.lon)
    }

    private enum FetchResult: Sendable { case data(Data), failed, timeout }

    /// 两个服务器同时问，边个先答到就用边个；总共最多等 fetchTimeout 秒。
    private func fetch(_ tile: TileKey) async -> Data? {
        guard let qURL = Bundle.main.url(forResource: "estate", withExtension: "overpassql"),
              let template = try? String(contentsOf: qURL, encoding: .utf8) else { return nil }
        let query = template.replacingOccurrences(of: "{{bbox}}", with: Self.bbox(tile))
        let body = Data(("data=" + (query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")).utf8)
        let deadline = Date().addingTimeInterval(Self.fetchTimeout)
        return await withTaskGroup(of: FetchResult.self) { group in
            for endpoint in Self.endpoints {
                group.addTask { await Self.post(endpoint, body: body, until: deadline) }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(Self.fetchTimeout))
                return .timeout
            }
            var failed = 0
            for await r in group {
                switch r {
                case .data(let d): group.cancelAll(); return d
                case .timeout: group.cancelAll(); return nil
                case .failed:
                    failed += 1
                    if failed == Self.endpoints.count { group.cancelAll(); return nil }
                }
            }
            return nil
        }
    }

    /// 问一个服务器；好快就失败（504 / 429）就隔 2 秒再试，直到限期。
    private nonisolated static func post(_ endpoint: String, body: Data, until deadline: Date) async -> FetchResult {
        while !Task.isCancelled {
            let left = deadline.timeIntervalSinceNow
            guard left > 3 else { break }
            var req = URLRequest(url: URL(string: endpoint)!, timeoutInterval: min(30, left))
            req.httpMethod = "POST"
            req.setValue("hack4sdg-streetwalk/0.1 (iOS prototype)", forHTTPHeaderField: "User-Agent")
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 200 {
                return .data(data)
            }
            guard deadline.timeIntervalSinceNow > 5 else { break }
            try? await Task.sleep(for: .seconds(2))
        }
        return .failed
    }
}

/// 解析前的原始 Overpass 响应按格子存在 Caches 里，保留 30 天；拉不到时再旧也照用。
/// v2 起每格拉 720 m（MapService.fetchSize）；v1 是以前 560 m 的，只在拉不到时兜底，同一格写了 v2 就删掉。
enum TileCache {
    /// 缓存根目录 tiles/（v1、v2 都在里面）。演示「重新生成」用的 clear() 删的就是它，旧的 v1 不会在离线时又被读出来。
    static var dir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("tiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func folder(_ v: String) -> URL {
        let d = dir.appendingPathComponent(v, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func read(_ t: TileKey, maxAge: TimeInterval = 30 * 86400) -> (data: Data, size: Double)? {
        let sources: [(URL, Double)] = maxAge.isFinite ? [(folder("v2"), MapService.fetchSize)]
            : [(folder("v2"), MapService.fetchSize), (folder("v1"), TileKey.plinthSize)]
        for (d, size) in sources {
            let url = d.appendingPathComponent("\(t).json")
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < maxAge,
                  let data = try? Data(contentsOf: url) else { continue }
            return (data, size)
        }
        return nil
    }

    static func write(_ t: TileKey, _ data: Data) {
        guard (try? data.write(to: folder("v2").appendingPathComponent("\(t).json"))) != nil else { return }
        try? FileManager.default.removeItem(at: folder("v1").appendingPathComponent("\(t).json"))
    }
}
