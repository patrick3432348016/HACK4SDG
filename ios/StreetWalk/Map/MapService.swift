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
            case .live: return L.t("實時", "实时")
            case .cache: return L.t("地圖", "地图")   // Do not expose cache terminology to users (UX finding 16).
            case .fallback: return L.t("示例", "示例")
            }
        }
    }

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<GeoPoint?, Never>?
    private var locationTimer: DispatchWorkItem?

    /// This branch excludes overpass.private.coffee after the team's October 2026 HTTP 500 observations.
    nonisolated static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    ]
    /// Live fetch width exceeds the 400-m grid so a 200-m home-centred base still fits when home is near a grid edge.
    /// Bundled example width remains 560 m (TileKey.plinthSize).
    nonisolated static let fetchSize = 720.0
    /// Map-fetch timeout in seconds. Query two servers concurrently and use the first successful response.
    nonisolated static let fetchTimeout = 30.0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Location

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
        Task { @MainActor in self.finishLocation(p) }
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

    /// Query two servers concurrently and use the first success, within fetchTimeout seconds overall.
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

    /// Query one server; retry fast failures such as 504 or 429 after two seconds until the deadline.
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
