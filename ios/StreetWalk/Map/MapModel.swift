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
    /// 裁切前整格的地名。裁成小底座后楼少了，地名要沿用整格的（例如"皇后山邨"）。
    var areaName: String?

    /// 真实太阳位置 → 这张（转过的）地图里的太阳位置。
    func localSun(_ s: SolarPosition) -> SolarPosition {
        SolarPosition(elevation: s.elevation, azimuth: s.azimuth - rotation * 180 / .pi)
    }

    var half: Double { size / 2 }

    /// 显示用的地名：附近有名字的住宅楼或建筑，例如"皇后山邨"。
    var placeName: String {
        if let areaName { return areaName }
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
    /// maxResidential 设了的话，住宅楼按它限、其他楼按 maxBuildings 限（首次选楼用）。
    func simplified(around c: Vec2, size: Double = MapModel.dioramaSize, home: Int64? = nil,
                    maxBuildings: Int? = 6, maxResidential: Int? = nil) -> MapModel {
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
        out.areaName = placeName

        // 画风优先：楼改成规整长方体（转正后的外接矩形，四边内缩留缝），高度按美学比例压缩。
        var blocks: [Building] = buildings.compactMap { b in
            guard b.kind != .small, b.kind != .canopy, Polygon.area(b.outline) >= 60 else { return nil }
            let pts = b.outline.map(shift)
            let xs = pts.map(\.x), ys = pts.map(\.y)
            let inset = 2.5
            var x0 = xs.min()! + inset, x1 = xs.max()! - inset, y0 = ys.min()! + inset, y1 = ys.max()! - inset
            let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
            guard abs(cx) <= h - 6, abs(cy) <= h - 6, x1 - x0 > 4, y1 - y0 > 4 else { return nil }
            x0 = max(x0, -h + 4); x1 = min(x1, h - 4); y0 = max(y0, -h + 4); y1 = min(y1, h - 4)
            // 接近正方形的（十字形塔楼）改成板楼：长边不变，短边收到长边的 45%，看起来像参考图里的薄板。
            // 小屋（长边不到 20 m）不改，免得压成一条细片。
            let w = x1 - x0, d = y1 - y0
            if max(w, d) >= 20, max(w, d) / min(w, d) < 1.8 {
                if (b.id % 2 == 0) == (w >= d) {
                    let nd = w * 0.45; y0 = cy - nd / 2; y1 = cy + nd / 2
                } else {
                    let nw = d * 0.45; x0 = cx - nw / 2; x1 = cx + nw / 2
                }
            }
            var nb = b
            nb.outline = [Vec2(x: x0, y: y0), Vec2(x: x1, y: y0), Vec2(x: x1, y: y1), Vec2(x: x0, y: y1)]
            nb.minHeight = 0
            nb.height = b.height <= 20 ? max(b.height, 9) : 20 + (b.height - 20) * 0.38
            return nb
        }
        func nearest(_ list: [Building], _ n: Int) -> [Building] {
            Array(list.sorted { a, b in
                if a.id == home { return true }
                if b.id == home { return false }
                return a.centroid.length < b.centroid.length
            }.prefix(n))
        }
        if let maxResidential {
            blocks = nearest(blocks.filter { $0.kind == .residential }, maxResidential)
                + nearest(blocks.filter { $0.kind != .residential }, maxBuildings ?? .max)
        } else if let maxBuildings {
            blocks = nearest(blocks, maxBuildings)
        }
        // 去掉和别的楼重叠的（矩形化后可能相交），先到先得；选楼时住宅楼优先。
        func rank(_ b: Building) -> Int { b.id == home ? 0 : (maxResidential != nil && b.kind != .residential ? 2 : 1) }
        var placed: [Building] = []
        for b in blocks.sorted(by: { (rank($0), $0.centroid.length) < (rank($1), $1.centroid.length) }) {
            let r = b.outline
            let overlaps = placed.contains { p in
                let q = p.outline
                return !(r[1].x + 2 < q[0].x || q[1].x + 2 < r[0].x || r[2].y + 2 < q[0].y || q[2].y + 2 < r[0].y)
            }
            if !overlaps { placed.append(b) }
        }
        out.buildings = placed
        // 地面：绿地 / 水改成规整矩形色块，最多 3 块（取面积大的）。
        // 外接矩形会比原来的面大很多：绕中心缩小到不超过原面积，单块也不超过底座的 20%。
        let maxArea = size * size * 0.2
        out.areas = Array(areas.compactMap { a -> Area? in
            let kind: AreaKind
            switch a.kind {
            case .grass, .wood, .park, .farmland, .pitch, .playground: kind = .park
            case .water: kind = .water
            default: return nil
            }
            let ring = Polygon.clip(a.outline.map(shift), half: h - 4)
            guard ring.count >= 3, Polygon.area(ring) >= 400 else { return nil }
            let xs = ring.map(\.x), ys = ring.map(\.y)
            let w = xs.max()! - xs.min()!, d = ys.max()! - ys.min()!
            let k = min(1, (min(Polygon.area(ring), maxArea) / (w * d)).squareRoot())
            let mid = Vec2(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
            let hw = w * k / 2, hd = d * k / 2
            let rect = [Vec2(x: mid.x - hw, y: mid.y - hd), Vec2(x: mid.x + hw, y: mid.y - hd), Vec2(x: mid.x + hw, y: mid.y + hd), Vec2(x: mid.x - hw, y: mid.y + hd)]
            return Area(kind: kind, outline: rect, name: a.name)
        }.sorted { Polygon.area($0.outline) > Polygon.area($1.outline) }.prefix(3)).sorted { $0.kind.drawOrder < $1.kind.drawOrder }
        out.roads = roads.flatMap { r -> [Road] in
            // 只留车路（淡色宽带）；行人路、单车径、楼梯都不画。
            guard r.kind == .major || r.kind == .minor || r.kind == .residential else { return [] }
            let kind = r.kind
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

    /// 首次选楼用的画面。知道我在哪：以我为中心看 300 m，住宅楼最多 10 座、其他楼 3 座，
    /// 我脚下（或最近）的住宅楼一定留着；不知道：看整格、住宅楼全留，哪座都选得到。
    func pickView(near me: Vec2?) -> MapModel {
        guard let me else { return simplified(around: .zero, size: size, maxBuildings: 3, maxResidential: .max) }
        let homes = buildings.filter { $0.kind == .residential }
        let guess = (homes.first { Polygon.contains($0.outline, me) } ?? homes.min { $0.centroid.distance(to: me) < $1.centroid.distance(to: me) })?.id
        let lim = half - 150
        let c = Vec2(x: max(-lim, min(lim, me.x)), y: max(-lim, min(lim, me.y)))
        return simplified(around: c, size: 300, home: guess, maxBuildings: 3, maxResidential: 10)
    }

    /// 点是否落在任何建筑里（不含遮蓬）。
    func isInsideBuilding(_ p: Vec2) -> Bool {
        buildings.contains { $0.kind != .canopy && Polygon.contains($0.outline, p) }
    }
}
