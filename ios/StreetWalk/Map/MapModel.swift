import Foundation

enum RoadKind: String, Codable {
    case major, minor, residential, service, footway, cycleway, steps
}

struct Road: Codable {
    var kind: RoadKind
    var points: [Vec2]
    var width: Double
    var name: String?
}

/// 地面上的面，按 drawOrder 从底到顶画。
enum AreaKind: String, Codable, CaseIterable {
    case urban, residential, school, military, farmland, grass, wood, park, playground, pitch, water, parking, plaza

    var drawOrder: Int { AreaKind.allCases.firstIndex(of: self) ?? 0 }
}

struct Area: Codable {
    var kind: AreaKind
    var outline: [Vec2]
    var name: String?
}

enum BuildingKind: String, Codable {
    case residential, commercial, school, construction, canopy, small, other
}

struct Building: Codable, Identifiable {
    var id: Int64
    var name: String?
    var outline: [Vec2]
    var minHeight: Double
    var height: Double
    var levels: Int
    var kind: BuildingKind

    var centroid: Vec2 { Polygon.centroid(outline) }
    var isTower: Bool { height >= 25 }
}

enum POIKind: String, Codable {
    case busStop, busStation, bench, shelter, toilet, shop, mall, food, market, school, community, playground, recycling, entrance, other
}

struct POI: Codable, Identifiable {
    var id: Int64
    var kind: POIKind
    var name: String?
    var pos: Vec2
    var hasShelter = false
    var hasBench = false
}

/// 一个格子（560 m 底座）里的全部地图要素，坐标是以格子中心为原点的米。
struct MapModel: Codable {
    var tile: TileKey
    var center: GeoPoint
    var size: Double
    var buildings: [Building]
    var roads: [Road]
    var areas: [Area]
    var pois: [POI]
    var trees: [Vec2]
    var fetchedAt: Date
    var source: String
    /// 地图被逆时针转了多少弧度（转正后楼边与底座边平行）。太阳方位要减去它。
    var rotation: Double = 0

    /// 真实太阳位置 → 这张（转过的）地图里的太阳位置。
    func localSun(_ s: SolarPosition) -> SolarPosition {
        SolarPosition(elevation: s.elevation, azimuth: s.azimuth - rotation * 180 / .pi)
    }

    var half: Double { size / 2 }

    /// 显示用的地名：附近有名字的住宅楼或建筑，例如"皇后山邨"。
    var placeName: String {
        let named = buildings.compactMap { $0.name }
        if let estate = named.first(where: { $0.hasSuffix("邨") }) { return estate }
        if let block = buildings.filter({ $0.kind == .residential && $0.name != nil }).min(by: { $0.centroid.length < $1.centroid.length })?.name {
            return block
        }
        return named.first ?? "你附近"
    }

    func building(id: Int64) -> Building? { buildings.first { $0.id == id } }

    /// 场景用的底座边长：做减法，只留我屋企周围 300 米。
    static let dioramaSize = 200.0

    /// 以 c 为中心裁出 size 见方的一块（坐标重新以 c 为原点），并做减法：
    /// 去掉小屋和遮蓬、太小的面、楼梯和单车径；地面只留铺地 / 绿 / 球场 / 水。
    func simplified(around c: Vec2, size: Double = MapModel.dioramaSize) -> MapModel {
        let h = size / 2
        // 转正：取附近楼宇的主方向，整块地图绕中心旋转，让楼边和底座边平行。
        let nearby = buildings.filter { $0.kind != .small && $0.centroid.distance(to: c) < size }.map(\.outline)
        let theta = Polygon.dominantAngle(nearby)
        let phi = -theta
        let cs = cos(phi), sn = sin(phi)
        func shift(_ v: Vec2) -> Vec2 { let d = v - c; return Vec2(x: d.x * cs - d.y * sn, y: d.x * sn + d.y * cs) }
        var out = self
        out.size = size
        out.center = LocalProjection(origin: center).toGeo(c)
        out.rotation = rotation + phi

        out.buildings = buildings.compactMap { b in
            guard b.kind != .small, b.kind != .canopy, Polygon.area(b.outline) >= 60 else { return nil }
            let cen = shift(b.centroid)
            guard abs(cen.x) <= h, abs(cen.y) <= h else { return nil }
            let simple = Polygon.simplify(b.outline, tolerance: 1.2)
            let ring = Polygon.normalized(Polygon.clip(simple.map(shift), half: h))
            guard ring.count >= 3, Polygon.area(ring) >= 40 else { return nil }
            var nb = b
            nb.outline = ring
            return nb
        }
        out.areas = areas.compactMap { a in
            let kind: AreaKind
            switch a.kind {
            case .grass, .wood, .park, .farmland: kind = a.kind == .park || a.kind == .wood ? .park : .grass
            case .pitch, .playground: kind = .pitch
            case .water: kind = .water
            default: return nil          // 铺地类不单独上色，统一用底色
            }
            let ring = Polygon.normalized(Polygon.clip(a.outline.map(shift), half: h))
            guard ring.count >= 3, Polygon.area(ring) >= 150 else { return nil }
            return Area(kind: kind, outline: ring, name: a.name)
        }.sorted { $0.kind.drawOrder < $1.kind.drawOrder }
        out.roads = roads.flatMap { r -> [Road] in
            guard r.kind != .steps else { return [] }
            let kind: RoadKind = r.kind == .cycleway ? .footway : r.kind
            return Polygon.clipPolyline(r.points.map(shift), half: h).map { Road(kind: kind, points: $0, width: r.width, name: r.name) }
        }
        out.pois = pois.compactMap { p in
            var np = p
            np.pos = shift(p.pos)
            return abs(np.pos.x) <= h && abs(np.pos.y) <= h ? np : nil
        }
        out.trees = []
        return out
    }

    /// 点是否落在任何建筑里（不含遮蓬）。
    func isInsideBuilding(_ p: Vec2) -> Bool {
        buildings.contains { $0.kind != .canopy && Polygon.contains($0.outline, p) }
    }
}
