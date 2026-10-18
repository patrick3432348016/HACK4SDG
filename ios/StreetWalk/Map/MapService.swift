import CoreLocation
import Foundation

/// Location → grid → cache/Overpass → stale cache → bundled Queen's Hill example as the final fallback.
/// For map requests, transmit grid bounds rather than the precise user position.
@MainActor
final class MapService: NSObject, CLLocationManagerDelegate {
    enum Source: String {
        case live = "實時", cache = "快取", fallback = "示例"
        /// Display label.
        var label: String {
            switch self {
            case .live: return L.t("實時", "实时", "Live")
            case .cache: return L.t("地圖", "地图", "Map")   // Do not expose cache terminology to users (UX finding 16).
            case .fallback: return L.t("示例", "示例", "Sample")
            }
        }
    }

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<GeoPoint?, Never>?
    private var locationTimer: DispatchWorkItem?

    /// Mac measurements on 10-18 using a 720-m Kowloon City query and estate.overpassql:
    /// openstreetmap.fr took about 3 s; overpass-api.de took 26–38 s to first byte, often exceeding the previous 30-s limit.
    /// private.coffee failed full-grid queries with 500, kumi.systems with 500, and mail.ru with 504. Race endpoints and accept the first valid data.
    nonisolated static let endpoints = [
        "https://overpass.openstreetmap.fr/api/interpreter",
        "https://overpass-api.de/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    ]
    /// Live fetch width exceeds the 400-m grid so a 200-m home-centred base still fits when home is near a grid edge.
    /// Bundled example width remains 560 m (TileKey.plinthSize).
    nonisolated static let fetchSize = 720.0
    /// Allow 75 seconds per fetch round because a busy endpoint can take over 30 seconds. AppStore.scheduleMapRetry retries later.
    nonisolated static let fetchTimeout = 75.0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Location

    /// Last locally obtained location, used for background map retries while showing the example estate.
    var lastLocation: GeoPoint?

    /// Current-location marker follows GPS while the map is visible; displayed locally, not uploaded by this path.
    let here = HereTracker()

    /// One-shot location override for repicking home after confirming a move; clear after use.
    var pinnedLocation: GeoPoint?

    /// Whether location permission has never been requested; explain its purpose before showing the system prompt.
    var locationUndetermined: Bool {
        pinnedLocation == nil && !LaunchArgs.has("-offline") && manager.authorizationStatus == .notDetermined
    }

    /// Call only for initial/repeated home selection. Start the timeout after the permission prompt is answered, allowing time to read it.
    func currentLocation(timeout: TimeInterval = 8) async -> GeoPoint? {
        if let p = pinnedLocation { pinnedLocation = nil; return p }
        if LaunchArgs.has("-offline") { return nil }
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted { return nil }
        return await withCheckedContinuation { cont in
            // Resolve any previous pending request with nil before starting another, avoiding a hung continuation.
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
            // CLLocationManager invokes a callback on creation; request location only when a caller is waiting.
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

    // MARK: - Map

    func load(tile: TileKey) async -> (MapModel, Source) {
        if !LaunchArgs.has("-offline") {
            if let c = TileCache.read(tile), let m = try? OSMParser.parse(c.data, tile: tile, size: c.size, source: "cache") { return (m, .cache) }
            if let data = await fetch(tile), let m = try? OSMParser.parse(data, tile: tile, size: Self.fetchSize, source: "live") {
                TileCache.write(tile, data)
                return (m, .live)
            }
            // Stale local-area cache is preferable to an unrelated example estate when fetching fails.
            if let c = TileCache.read(tile, maxAge: .infinity), let m = try? OSMParser.parse(c.data, tile: tile, size: c.size, source: "cache") { return (m, .cache) }
        }
        return (Self.fallback(), .fallback)
    }

    /// Retry a tile while showing example data. Cache a successfully parsed response and return true so load(tile:) can use it.
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

    /// Overpass bounds in south,west,north,east order, centred on the grid with width size; no precise user coordinate.
    nonisolated static func bbox(_ t: TileKey, size: Double = fetchSize) -> String {
        let proj = LocalProjection(origin: t.center)
        let h = size / 2
        let sw = proj.toGeo(Vec2(x: -h, y: -h)), ne = proj.toGeo(Vec2(x: h, y: h))
        return String(format: "%.7f,%.7f,%.7f,%.7f", sw.lat, sw.lon, ne.lat, ne.lon)
    }

    private enum FetchResult: Sendable { case data(Data), failed, timeout }

    /// Race servers with slightly staggered starts and accept the first valid response within fetchTimeout.
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

    /// Require nonempty elements and reject partial runtime-error responses or endpoints with no local coverage.
    nonisolated static func usable(_ data: Data) -> Bool {
        data.count > 200 && data.range(of: Data("\"elements\"".utf8)) != nil && data.range(of: Data("\"type\"".utf8)) != nil
            && data.range(of: Data("runtime error".utf8)) == nil
    }

    /// Retry fast endpoint failures (502/504/429) after three seconds until the deadline.
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

/// Track the local current-location marker only while Today/home-selection maps are visible, using existing permission without a new prompt.
/// Screenshot check: -hereAt lat,lon supplies a simulated GPS position.
@MainActor
final class HereTracker: NSObject, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private(set) var last: GeoPoint?
    var onUpdate: ((GeoPoint?) -> Void)?
    private var users = Set<String>()

    /// Track consumers by screen; stop only when no screen needs the marker.
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

/// Cache raw Overpass responses per grid for 30 days; permit older data when the network is unavailable.
/// v2 fetches 720 m per grid. Retain old 560-m v1 only as fallback and remove it once v2 is written for that grid.
enum TileCache {
    /// Both cache versions live under tiles/. Demo regeneration clears the entire root so old v1 data cannot reappear offline.
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
