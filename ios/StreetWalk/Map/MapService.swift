import CoreLocation
import Foundation

/// 取当前位置 → 吸附到格子 → 读缓存 / 请求 Overpass → 失败就用内置皇后山邨。
/// 只有格子范围会发给地图服务，精确位置不离开手机。
@MainActor
final class MapService: NSObject, CLLocationManagerDelegate {
    enum Source: String { case live = "實時", cache = "快取", fallback = "示例" }

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<GeoPoint?, Never>?

    static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
    ]

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - 位置

    func currentLocation(timeout: TimeInterval = 8) async -> GeoPoint? {
        if LaunchArgs.has("-offline") { return nil }
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted { return nil }
        return await withCheckedContinuation { cont in
            locationContinuation = cont
            if status == .notDetermined { manager.requestWhenInUseAuthorization() } else { manager.requestLocation() }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finishLocation(nil) }
        }
    }

    private func finishLocation(_ p: GeoPoint?) {
        locationContinuation?.resume(returning: p)
        locationContinuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            switch m.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse: m.requestLocation()
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
            if let data = TileCache.read(tile), let m = try? OSMParser.parse(data, tile: tile, source: "cache") { return (m, .cache) }
            if let data = await fetch(tile), let m = try? OSMParser.parse(data, tile: tile, source: "live") {
                TileCache.write(tile, data)
                return (m, .live)
            }
        }
        return (Self.fallback(), .fallback)
    }

    static func fallback() -> MapModel {
        let url = Bundle.main.url(forResource: "fallback_queenshill", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        return try! OSMParser.parse(data, tile: TileKey(ix: 0, iy: 0), source: "fallback")
    }

    private func fetch(_ tile: TileKey) async -> Data? {
        guard let qURL = Bundle.main.url(forResource: "estate", withExtension: "overpassql"),
              let template = try? String(contentsOf: qURL, encoding: .utf8) else { return nil }
        let query = template.replacingOccurrences(of: "{{bbox}}", with: tile.bboxString)
        let body = "data=" + (query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        for (i, endpoint) in Self.endpoints.enumerated() {
            for attempt in 0..<2 {
                var req = URLRequest(url: URL(string: endpoint)!, timeoutInterval: 20)
                req.httpMethod = "POST"
                req.setValue("hack4sdg-streetwalk/0.1 (iOS prototype)", forHTTPHeaderField: "User-Agent")
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                req.httpBody = body.data(using: .utf8)
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 200 {
                    return data
                }
                try? await Task.sleep(for: .seconds(attempt == 0 ? 2 : 4))
            }
            if i == 0 { continue }
        }
        return nil
    }
}

/// 解析前的原始 Overpass 响应按格子存在 Caches 里，保留 30 天。
enum TileCache {
    static var dir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("tiles/v1", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func read(_ t: TileKey) -> Data? {
        let url = dir.appendingPathComponent("\(t).json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < 30 * 86400 else { return nil }
        return try? Data(contentsOf: url)
    }

    static func write(_ t: TileKey, _ data: Data) {
        try? data.write(to: dir.appendingPathComponent("\(t).json"))
    }
}
