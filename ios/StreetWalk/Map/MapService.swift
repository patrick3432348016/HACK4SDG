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
            case .live: return L.t("實時", "实时", "Live")
            case .cache: return L.t("地圖", "地图", "Map")   // 唔讲「快取」（UX 评审 16）
            case .fallback: return L.t("示例", "示例", "Sample")
            }
        }
    }

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<GeoPoint?, Never>?
    private var locationTimer: DispatchWorkItem?

    /// 10-18 喺 Mac 实测（九龙城 720 m 一格、estate.overpassql）：
    /// openstreetmap.fr 约 3 秒；overpass-api.de 要 26–38 秒先有第一个字节（以前限 30 秒，所以香港测试员次次失败）；
    /// private.coffee 细查询得、成格查询 500；kumi.systems 500；mail.ru 504。全部同时问，边个先答到有效资料就用边个。
    nonisolated static let endpoints = [
        "https://overpass.openstreetmap.fr/api/interpreter",
        "https://overpass-api.de/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    ]
    /// 实时拉取的边长（米）。比 400 m 格子大：屋企在格边（离格心约 200 m）时，以它为中心的 200 m 底座仍在资料范围内。
    /// 内置示例屋邨仍然是 560 m（TileKey.plinthSize）。
    nonisolated static let fetchSize = 720.0
    /// 拉地图一轮最多等几耐（秒）。overpass-api.de 繁忙时要 30 几秒，所以放宽到 75 秒；拉唔到之后 AppStore 喺后台再试（scheduleMapRetry）。
    nonisolated static let fetchTimeout = 75.0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - 位置

    /// 最近一次攞到嘅位置（示例屋邨显示紧时，后台再试拉地图用；只喺本机）。
    var lastLocation: GeoPoint?

    /// 「你喺呢度」：地图开住时跟住 GPS 更新（只喺本机显示，唔上传）。
    let here = HereTracker()

    /// 下一次 currentLocation 直接用呢个位置（「你係咪搬咗屋」按「係」：喺过夜嘅地方重新揀樓）。用一次就清。
    var pinnedLocation: GeoPoint?

    /// 未问过定位（首次使用「屋企」一步要先讲一句点解要定位，再弹系统框）。
    var locationUndetermined: Bool {
        pinnedLocation == nil && !LaunchArgs.has("-offline") && manager.authorizationStatus == .notDetermined
    }

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
        Task { @MainActor in self.lastLocation = p; self.finishLocation(p) }
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

    /// 后台再试一次拉 tile（示例屋邨显示紧时用）：拉到、解析得就写入缓存，返回 true；之后 load(tile:) 会读到缓存。
    func refresh(tile: TileKey) async -> Bool {
        guard !LaunchArgs.has("-offline"), let data = await fetch(tile),
              (try? OSMParser.parse(data, tile: tile, size: Self.fetchSize, source: "live")) != nil else { return false }
        TileCache.write(tile, data)
        return true
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

    /// 几个服务器同时问（后面嘅迟少少先开始），边个先答到有效资料就用边个；总共最多等 fetchTimeout 秒。
    private func fetch(_ tile: TileKey) async -> Data? {
        guard let qURL = Bundle.main.url(forResource: "estate", withExtension: "overpassql"),
              let template = try? String(contentsOf: qURL, encoding: .utf8) else { return nil }
        let query = template.replacingOccurrences(of: "{{bbox}}", with: Self.bbox(tile))
        let body = Data(("data=" + (query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")).utf8)
        let deadline = Date().addingTimeInterval(Self.fetchTimeout)
        return await withTaskGroup(of: FetchResult.self) { group in
            for (i, endpoint) in Self.endpoints.enumerated() {
                group.addTask {
                    if i > 1 { try? await Task.sleep(for: .seconds(Double(i - 1))) }
                    return await Self.post(endpoint, body: body, until: deadline)
                }
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

    /// 有效嘅 Overpass 回覆：有 elements、最少一件嘢（overpass.osm.ch 呢类只有本国资料嘅会回空），唔系「runtime error」半截资料。
    nonisolated static func usable(_ data: Data) -> Bool {
        data.count > 200 && data.range(of: Data("\"elements\"".utf8)) != nil && data.range(of: Data("\"type\"".utf8)) != nil
            && data.range(of: Data("runtime error".utf8)) == nil
    }

    /// 问一个服务器；好快就失败（502 / 504 / 429）就隔 3 秒再试，直到限期。
    private nonisolated static func post(_ endpoint: String, body: Data, until deadline: Date) async -> FetchResult {
        while !Task.isCancelled {
            let left = deadline.timeIntervalSinceNow
            guard left > 3 else { break }
            var req = URLRequest(url: URL(string: endpoint)!, timeoutInterval: min(70, left))
            req.httpMethod = "POST"
            req.setValue("hack4sdg-streetwalk/0.1 (iOS prototype)", forHTTPHeaderField: "User-Agent")
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200, usable(data) {
                return .data(data)
            }
            guard deadline.timeIntervalSinceNow > 5 else { break }
            try? await Task.sleep(for: .seconds(3))
        }
        return .failed
    }
}

/// 「你喺呢度」嘅位置点：地图喺画面上（今日页、选楼）先开，离开就停。只用已有嘅定位权限，唔会弹框；位置唔离开手机。
/// 截图自检：-hereAt lat,lon 当系 GPS 位置。
@MainActor
final class HereTracker: NSObject, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private(set) var last: GeoPoint?
    var onUpdate: ((GeoPoint?) -> Void)?
    private var users = Set<String>()

    /// who：边个画面要（今日页、选楼），全部唔要先停。
    func start(_ who: String) {
        users.insert(who)
        if let s = LaunchArgs.value("-hereAt") {
            let p = s.split(separator: ",").compactMap { Double($0) }
            if p.count == 2 { update(GeoPoint(lat: p[0], lon: p[1])) }
            return
        }
        guard !LaunchArgs.has("-offline") else { return }
        if manager == nil {
            let m = CLLocationManager()
            m.delegate = self
            m.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            m.distanceFilter = 8
            manager = m
        }
        guard let m = manager, m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways else { return }
        m.startUpdatingLocation()
    }

    func stop(_ who: String) {
        users.remove(who)
        guard users.isEmpty else { return }
        manager?.stopUpdatingLocation()
    }

    private func update(_ p: GeoPoint?) {
        last = p
        onUpdate?(p)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            guard !self.users.isEmpty else { return }
            if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways { m.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0, l.horizontalAccuracy < 300 else { return }
        let p = GeoPoint(lat: l.coordinate.latitude, lon: l.coordinate.longitude)
        Task { @MainActor in self.update(p) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
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
