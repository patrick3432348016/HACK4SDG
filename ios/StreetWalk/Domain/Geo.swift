import Foundation

/// 本地平面坐标（米）。x 向东，y 向北，原点是格子中心。
struct Vec2: Codable, Hashable {
    var x: Double
    var y: Double

    static let zero = Vec2(x: 0, y: 0)

    static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Vec2, s: Double) -> Vec2 { Vec2(x: a.x * s, y: a.y * s) }

    var length: Double { (x * x + y * y).squareRoot() }
    func distance(to o: Vec2) -> Double { (self - o).length }
    var normalized: Vec2 { let l = length; return l > 1e-9 ? Vec2(x: x / l, y: y / l) : .zero }
    func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    func cross(_ o: Vec2) -> Double { x * o.y - y * o.x }
}

struct GeoPoint: Codable, Hashable {
    var lat: Double
    var lon: Double
}

/// 经纬度与本地米坐标互转（等距近似，几百米范围内误差可忽略）。
struct LocalProjection {
    let origin: GeoPoint
    let metersPerDegLat: Double
    let metersPerDegLon: Double

    init(origin: GeoPoint) {
        self.origin = origin
        let φ = origin.lat * .pi / 180
        metersPerDegLat = 111_132.92 - 559.82 * cos(2 * φ) + 1.175 * cos(4 * φ) - 0.0023 * cos(6 * φ)
        metersPerDegLon = 111_412.84 * cos(φ) - 93.5 * cos(3 * φ) + 0.118 * cos(5 * φ)
    }

    func toLocal(_ p: GeoPoint) -> Vec2 {
        Vec2(x: (p.lon - origin.lon) * metersPerDegLon, y: (p.lat - origin.lat) * metersPerDegLat)
    }

    func toGeo(_ v: Vec2) -> GeoPoint {
        GeoPoint(lat: origin.lat + v.y / metersPerDegLat, lon: origin.lon + v.x / metersPerDegLon)
    }
}

/// 400 米网格上的一格。网格原点设在皇后山邨，让示例屋邨正好是 0_0 格居中。
/// 只有格子范围会发给地图服务，不发精确位置。
struct TileKey: Codable, Hashable, CustomStringConvertible {
    var ix: Int
    var iy: Int

    static let gridOrigin = GeoPoint(lat: 22.5044, lon: 114.1563)
    static let cellSize = 400.0
    /// 底座边长（米）。比格子大，保证用户在格子边缘时周围也有内容。
    static let plinthSize = 560.0

    var description: String { "\(ix)_\(iy)" }

    static func snap(_ p: GeoPoint) -> TileKey {
        let v = LocalProjection(origin: gridOrigin).toLocal(p)
        return TileKey(ix: Int((v.x / cellSize).rounded()), iy: Int((v.y / cellSize).rounded()))
    }

    var center: GeoPoint {
        LocalProjection(origin: Self.gridOrigin).toGeo(Vec2(x: Double(ix) * Self.cellSize, y: Double(iy) * Self.cellSize))
    }

    /// Overpass 用的 south,west,north,east。
    var bboxString: String {
        let proj = LocalProjection(origin: center)
        let h = Self.plinthSize / 2
        let sw = proj.toGeo(Vec2(x: -h, y: -h)), ne = proj.toGeo(Vec2(x: h, y: h))
        return String(format: "%.7f,%.7f,%.7f,%.7f", sw.lat, sw.lon, ne.lat, ne.lon)
    }
}
