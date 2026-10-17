import Foundation

enum RoadKind: String, Codable {
    case major, minor, residential, service, footway, cycleway, steps
}

struct Road: Codable {
    var kind: RoadKind
    var points: [Vec2]
    var width: Double
    var name: String?
    /// OSM name:en（英文界面用；冇就用 name）。
    var nameEn: String? = nil
    /// OSM lit=yes/no（有冇路灯）；冇标就 nil。
    var lit: Bool? = nil

    var shownName: String? { L.isEn ? (nameEn ?? name) : name }
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
    /// OSM 编号（way 为正、relation 为负）。地标 id 用它，见 LandmarkDeriver。
    var osmID: Int64?
    /// OSM name:en（英文界面用；冇就用 name）。
    var nameEn: String? = nil

    var shownName: String? { L.isEn ? (nameEn ?? name) : name }
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
    /// OSM building= 的原值（yes、industrial……）。只标 yes 的高楼才当可能是住宅，见 markHomeCandidates。
    var tag: String? = nil
    /// OSM name:en（英文界面用；冇就用 name），例如「皇滙樓 Wong Wui House」嘅 Wong Wui House。
    var nameEn: String? = nil

    /// 画面显示嘅楼名：英文界面有英文名就用英文，冇就照用中文名。
    var shownName: String? { L.isEn ? (nameEn ?? name) : name }
    var centroid: Vec2 { Polygon.centroid(outline) }
    var isTower: Bool { height >= 25 }
    /// 似住宅：住宅楼，加上只标 building=yes、10 层以上的楼（香港不少私人楼只这样标）。
    var looksLikeHome: Bool { kind == .residential || (kind == .other && tag == "yes" && levels >= 10) }
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
    /// OSM name:en（英文界面用；冇就用 name），例如「大快活」嘅 Fairwood。
    var nameEn: String? = nil

    var shownName: String? { L.isEn ? (nameEn ?? name) : name }
}

/// 一个格子（实时拉取 720 m、内置示例 560 m）里的全部地图要素，坐标是以格子中心为原点的米。
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
    /// 同上，英文名（OSM name:en；冇就 nil，英文界面照用 areaName）。
    var areaNameEn: String?

    /// 真实太阳位置 → 这张（转过的）地图里的太阳位置。
    func localSun(_ s: SolarPosition) -> SolarPosition {
        SolarPosition(elevation: s.elevation, azimuth: s.azimuth - rotation * 180 / .pi)
    }

    var half: Double { size / 2 }

    /// 显示用的地名，例如"皇后山邨"。裁成底座后沿用裁切时按我屋企算好的名。
    /// 注意：placeName 一律系中文原名（上传服务器做圈名 communityName，两部手机要对得上），画面显示用 shownPlaceName。
    var placeName: String { areaName ?? placeSource(near: .zero)?.zh ?? "你附近" }

    /// 画面显示嘅地名：英文界面有英文名（OSM name:en）就用英文，冇就照用中文名。
    var shownPlaceName: String {
        guard L.isEn else { return placeName == "你附近" ? L.t("你附近", "你附近", "Near you") : placeName }
        if areaName != nil { return areaNameEn ?? (areaName == "你附近" ? "Near you" : areaName!) }
        return placeName(near: .zero)
    }

    /// p（我屋企）附近的屋苑名：所在住宅用地的名 → 附近叫"X邨"的建筑（公屋常把邨名标在巴士站、商场上）
    /// → 底座范围内（离 p 100 m 内）最近的有名住宅楼 → "你附近"。公厕、商场这类建筑的名不用。
    /// 有名住宅楼不能太远：示意楼的名会显示成"住喺 X"，用一座看不到的楼会误导。
    func placeName(near p: Vec2) -> String {
        guard let src = placeSource(near: p) else { return L.t("你附近", "你附近", "Near you") }   // 显示用；上传用 placeName
        return L.isEn ? (src.en ?? src.zh) : src.zh
    }

    /// placeName 嘅来源：中文名 + 英文名（OSM name:en，可能冇）。
    func placeSource(near p: Vec2) -> (zh: String, en: String?)? {
        if let a = areas.first(where: { $0.kind == .residential && !($0.name ?? "").isEmpty && Polygon.contains($0.outline, p) }) {
            return (a.name!, a.nameEn)
        }
        func nearest(_ list: [Building]) -> Building? { list.min { $0.centroid.distance(to: p) < $1.centroid.distance(to: p) } }
        if let estate = nearest(buildings.filter { ($0.name ?? "").hasSuffix("邨") && $0.centroid.distance(to: p) < 250 }) { return (estate.name!, estate.nameEn) }
        let r = Self.dioramaSize / 2
        if let block = nearest(buildings.filter { $0.kind == .residential && $0.name != nil
            && abs($0.centroid.x - p.x) <= r && abs($0.centroid.y - p.y) <= r }) { return (block.name!, block.nameEn) }
        return nil
    }

    /// 注意：上传服务器（blockShort）用呢个，英文界面都系中文原名（AppStore+Backend 对住「示意樓」判断）；画面显示用 Settings 嘅 homeBlockShown。
    /// 设定页"住喺"显示的楼名：示意楼叫"示意樓"，没有名的楼不显示（用地名）。
    func homeLabel(_ id: Int64) -> String? {
        Self.placeholderPos(id) != nil ? L.t("示意樓", "示意楼", "示意樓") : building(id: id)?.name
    }

    func building(id: Int64) -> Building? { buildings.first { $0.id == id } }

    /// 场景用的底座边长：做减法，只留我屋企周围 200 米。
    static let dioramaSize = 200.0

    /// 以 c 为中心裁出 size 见方的一块（坐标重新以 c 为原点），并做减法：
    /// 去掉小屋和遮蓬、太小的面、楼梯和单车径；地面只留铺地 / 绿 / 球场 / 水。
    /// maxResidential 设了的话，住宅楼按它限、其他楼按 maxBuildings 限（首次选楼用）。
    func simplified(around c: Vec2, size: Double = MapModel.dioramaSize, home: Int64? = nil,
                    maxBuildings: Int? = 6, maxResidential: Int? = nil) -> MapModel {
        let h = size / 2
        let phi = turn(around: c, size: size)
        let cs = cos(phi), sn = sin(phi)
        func shift(_ v: Vec2) -> Vec2 { let d = v - c; return Vec2(x: d.x * cs - d.y * sn, y: d.x * sn + d.y * cs) }
        var out = self
        out.size = size
        out.center = LocalProjection(origin: center).toGeo(c)
        out.rotation = rotation + phi
        if areaName == nil {
            let src = placeSource(near: c)
            out.areaName = src?.zh ?? "你附近"
            out.areaNameEn = src?.en
        }

        // 画风优先：楼改成规整长方体（转正后的外接矩形，四边内缩留缝），高度按美学比例压缩。
        // 我屋企不受面积、尺寸门槛限制（村屋可能只有 8×10 m），最少保留 8×8 m 占地。
        var blocks: [Building] = buildings.compactMap { b in
            let isHome = b.id == home
            guard isHome || (b.kind != .small && b.kind != .canopy && Polygon.area(b.outline) >= 60) else { return nil }
            let pts = b.outline.map(shift)
            let xs = pts.map(\.x), ys = pts.map(\.y)
            let inset = 2.5
            var x0 = xs.min()! + inset, x1 = xs.max()! - inset, y0 = ys.min()! + inset, y1 = ys.max()! - inset
            let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
            if isHome {
                if x1 - x0 < 8 { x0 = cx - 4; x1 = cx + 4 }
                if y1 - y0 < 8 { y0 = cy - 4; y1 = cy + 4 }
            }
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
        // 改成矩形后盖住我屋企的水面不画（楼盖在水上不像样，人也走不出去）。
        let maxArea = size * size * 0.2
        let homeBox = placed.first { $0.id == home }.map { b -> (Vec2, Vec2) in
            let xs = b.outline.map(\.x), ys = b.outline.map(\.y)
            return (Vec2(x: xs.min()!, y: ys.min()!), Vec2(x: xs.max()!, y: ys.max()!))
        }
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
            if kind == .water, let (lo, hi) = homeBox,
               mid.x - hw < hi.x, mid.x + hw > lo.x, mid.y - hd < hi.y, mid.y + hd > lo.y { return nil }
            return Area(kind: kind, outline: rect, name: a.name, osmID: a.osmID, nameEn: a.nameEn)
        }.sorted { Polygon.area($0.outline) > Polygon.area($1.outline) }.prefix(3)).sorted { $0.kind.drawOrder < $1.kind.drawOrder }
        out.roads = roads.flatMap { r -> [Road] in
            // 只留车路（淡色宽带）；行人路、单车径、楼梯都不画。
            guard r.kind == .major || r.kind == .minor || r.kind == .residential else { return [] }
            let kind = r.kind
            return Polygon.clipPolyline(r.points.map(shift), half: h).map { Road(kind: kind, points: $0, width: r.width, name: r.name, nameEn: r.nameEn) }
        }
        // 巴士站多留底座外 80 m 内的：地标不够时放在底座边（见 LandmarkDeriver.edgeFallbacks）。
        out.pois = pois.compactMap { p in
            var np = p
            np.pos = shift(p.pos)
            let reach = p.kind == .busStop || p.kind == .busStation ? h + 80 : h
            return abs(np.pos.x) <= reach && abs(np.pos.y) <= reach ? np : nil
        }
        out.trees = []
        return out
    }

    /// 转正：取 c 附近楼宇的主方向，整块地图要转多少弧度，楼边才和底座边平行。
    func turn(around c: Vec2, size: Double) -> Double {
        -Polygon.dominantAngle(buildings.filter { $0.kind != .small && $0.centroid.distance(to: c) < size }.map(\.outline))
    }

    /// 以 c 为中心、转正后的 200 m 底座，落在已拉取资料外面的部分最多 10%（那里没有楼和路）。
    /// 按面积算：不转时等于一边出界 20 m 一条窄边；转 45° 时一角出界约 60 m 也只是个小三角；近格角两边都出界的会被挡下。
    func dioramaFits(at c: Vec2) -> Bool {
        let r = Self.dioramaSize / 2, m = max(abs(c.x), abs(c.y))
        if m + r * 2.0.squareRoot() <= half { return true }   // 怎样转都在资料内，不用算方向
        guard m - r < half else { return false }
        let a = -turn(around: c, size: Self.dioramaSize)        // 底座在原图里的方向
        let ca = cos(a), sa = sin(a)
        let square = [(-r, -r), (r, -r), (r, r), (-r, r)].map { Vec2(x: c.x + $0.0 * ca - $0.1 * sa, y: c.y + $0.0 * sa + $0.1 * ca) }
        return Polygon.area(Polygon.clip(square, half: half)) >= 0.9 * Self.dioramaSize * Self.dioramaSize
    }

    /// 首次选楼画面的边长（米）。
    static let pickSize = 300.0

    /// 首次选楼用的画面。知道我在哪：以我为中心看 300 m，可选的楼最多 10 座、其他楼 3 座，我脚下（或最近）的楼一定留着；
    /// 附近 300 m 一座可选的楼都没有，就看离我最近那座可选的楼周围 300 m（不看整格：720 m 一格，楼细到点不到）。
    /// 不知道我在哪：看整格、可选的楼全留，哪座都选得到。
    /// 画面里可选的楼一律标成住宅楼（亮橙色、点得到），其余当普通楼，见 markHomeCandidates。
    func pickView(near me: Vec2?) -> MapModel {
        guard let me else {
            var src = self
            src.buildings = markHomeCandidates(around: nil)
            return src.simplified(around: .zero, size: size, maxBuildings: 3, maxResidential: .max)
        }
        let lim = half - Self.pickSize / 2
        func clamp(_ p: Vec2) -> Vec2 { Vec2(x: max(-lim, min(lim, p.x)), y: max(-lim, min(lim, p.y))) }
        func view(_ src: MapModel, at p: Vec2) -> MapModel {
            let homes = src.buildings.filter { $0.kind == .residential }
            let guess = (homes.first { Polygon.contains($0.outline, p) } ?? homes.min { $0.centroid.distance(to: p) < $1.centroid.distance(to: p) })?.id
            return src.simplified(around: clamp(p), size: Self.pickSize, home: guess, maxBuildings: 3, maxResidential: 10)
        }
        var near = self
        near.buildings = markHomeCandidates(around: clamp(me))
        let v = view(near, at: me)
        if v.hasHomeCandidate { return v }
        var all = self
        all.buildings = markHomeCandidates(around: nil)
        guard let target = all.buildings.filter({ $0.kind == .residential }).min(by: { $0.centroid.distance(to: me) < $1.centroid.distance(to: me) })
        else { return v }
        return view(all, at: target.centroid)
    }

    /// 选楼画面里有没有可选的楼。
    var hasHomeCandidate: Bool { buildings.contains { $0.kind == .residential } }

    /// 可以选做"我屋企"的楼：住宅楼，加上只标 building=yes、10 层以上的楼（香港不少私人楼只这样标；工厦、货仓、停车场不算）。
    /// around 附近（选楼画面的 300 m，不给就是整格）一座都没有，就放宽到那里的一般建筑（村屋、资料不全的新屋邨）。
    /// 做屋企时底座会超出已拉取资料太多的楼不给选，见 dioramaFits。
    private func markHomeCandidates(around c: Vec2?) -> [Building] {
        let r = Self.pickSize / 2
        func local(_ b: Building) -> Bool { c.map { abs(b.centroid.x - $0.x) <= r && abs(b.centroid.y - $0.y) <= r } ?? true }
        func homeLike(_ b: Building) -> Bool { b.looksLikeHome }
        func general(_ b: Building) -> Bool { b.kind == .other || b.kind == .commercial }
        var fitCache: [Int64: Bool] = [:]
        func fits(_ b: Building) -> Bool {
            if let f = fitCache[b.id] { return f }
            let f = dioramaFits(at: b.centroid)
            fitCache[b.id] = f
            return f
        }
        let hasHomes = buildings.contains { homeLike($0) && local($0) && fits($0) }
        return buildings.map { b in
            var b = b
            let pickable = Self.placeholderPos(b.id) != nil
                || (homeLike(b) || (!hasHomes && local(b) && general(b))) && fits(b)
            if pickable { b.kind = .residential } else if b.kind == .residential { b.kind = .other }
            return b
        }
    }

    // MARK: - 示意楼（附近完全没有楼宇资料时，在我的位置放一座，让首次使用能走完）

    /// 示意楼的 id 是负数，把位置（米，取整）编进去，下次启动按 id 放回同一个位置。
    static func placeholderID(at p: Vec2) -> Int64 {
        let x = Int64(max(-49_999, min(49_999, p.x.rounded()))) + 50_000
        let y = Int64(max(-49_999, min(49_999, p.y.rounded()))) + 50_000
        return -(1_000_000_000_000 + x * 100_000 + y)
    }

    static func placeholderPos(_ id: Int64) -> Vec2? {
        guard id <= -1_000_000_000_000 else { return nil }
        let v = -id - 1_000_000_000_000
        return Vec2(x: Double(v / 100_000 - 50_000), y: Double(v % 100_000 - 50_000))
    }

    /// 加一座示意楼（16×12 m、30 层，和北都新屋邨差不多）。已经有就不再加。
    /// 位置落在水面或别的楼里，就挪去最近的空地（同一份地图每次挪到同一个位置）。
    func addingPlaceholderHome(at p: Vec2) -> (map: MapModel, id: Int64) {
        let id = Self.placeholderID(at: p)
        guard building(id: id) == nil else { return (self, id) }
        var m = self
        let water = areas.filter { $0.kind == .water }.map(\.outline)
        func rect(_ c: Vec2) -> [Vec2] { [Vec2(x: c.x - 8, y: c.y - 6), Vec2(x: c.x + 8, y: c.y - 6), Vec2(x: c.x + 8, y: c.y + 6), Vec2(x: c.x - 8, y: c.y + 6)] }
        func free(_ c: Vec2) -> Bool {
            let r = rect(c) + [c]
            return !r.contains { q in water.contains { Polygon.contains($0, q) } || isInsideBuilding(q) }
        }
        var q = Self.placeholderPos(id)!
        search: for r in stride(from: 0.0, through: 120, by: 6) where !free(q) {
            for k in 0..<16 {
                let a = Double(k) * .pi / 8
                let c = Self.placeholderPos(id)! + Vec2(x: cos(a) * r, y: sin(a) * r)
                if free(c) { q = c; break search }
            }
        }
        let outline = rect(q)
        m.buildings.append(Building(id: id, name: nil, outline: outline, minHeight: 0, height: 92, levels: 30, kind: .residential))
        return (m, id)
    }

    /// 点是否落在任何建筑里（不含遮蓬）。
    func isInsideBuilding(_ p: Vec2) -> Bool {
        buildings.contains { $0.kind != .canopy && Polygon.contains($0.outline, p) }
    }
}
