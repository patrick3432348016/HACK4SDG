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

    /// 点是否落在任何建筑里（不含遮蓬）。
    func isInsideBuilding(_ p: Vec2) -> Bool {
        buildings.contains { $0.kind != .canopy && Polygon.contains($0.outline, p) }
    }
}
