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

/// Ground areas rendered from bottom to top by drawOrder.
enum AreaKind: String, Codable, CaseIterable {
    case urban, residential, school, military, farmland, grass, wood, park, playground, pitch, water, parking, plaza

    var drawOrder: Int { AreaKind.allCases.firstIndex(of: self) ?? 0 }
}

struct Area: Codable {
    var kind: AreaKind
    var outline: [Vec2]
    var name: String?
    /// OSM identity: positive way IDs, negative relation IDs. Used for landmark IDs by LandmarkDeriver.
    var osmID: Int64?
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
    /// Original OSM building tag. Treat building=yes as potentially residential only for tall buildings; see markHomeCandidates.
    var tag: String? = nil

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

/// All map features for one grid: live fetch covers 720 m, bundled example 560 m. Coordinates are metres from the grid centre.
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
    /// Counterclockwise map rotation aligning building edges with the base; subtract it from sun bearing.
    var rotation: Double = 0
    /// Preserve the whole-grid place name after cropping to a smaller base, which may contain fewer named buildings.
    var areaName: String?

    /// Convert the true sun position to the rotated map's coordinates.
    func localSun(_ s: SolarPosition) -> SolarPosition {
        SolarPosition(elevation: s.elevation, azimuth: s.azimuth - rotation * 180 / .pi)
    }

    var half: Double { size / 2 }

    /// Display-area name retained from the home-based crop, such as Queen's Hill Estate.
    var placeName: String { areaName ?? placeName(near: .zero) }

    /// Estate-name priority near home p: containing residential land, then nearby buildings bearing an estate name.
    /// Then the nearest named residential building within 100 m, otherwise nearby. Exclude names of toilets/malls and similar non-residential facilities.
    /// A residential-name anchor must be close; showing an invisible distant building as the user's home would mislead.
    func placeName(near p: Vec2) -> String {
        if let a = areas.first(where: { $0.kind == .residential && !($0.name ?? "").isEmpty && Polygon.contains($0.outline, p) }) {
            return a.name!
        }
        func nearest(_ list: [Building]) -> String? { list.min { $0.centroid.distance(to: p) < $1.centroid.distance(to: p) }?.name }
        if let estate = nearest(buildings.filter { ($0.name ?? "").hasSuffix("邨") && $0.centroid.distance(to: p) < 250 }) { return estate }
        let r = Self.dioramaSize / 2
        if let block = nearest(buildings.filter { $0.kind == .residential && $0.name != nil
            && abs($0.centroid.x - p.x) <= r && abs($0.centroid.y - p.y) <= r }) { return block }
        return L.t("你附近", "你附近")
    }

    /// Settings home-building label: identify a placeholder explicitly; for unnamed buildings, use the area name.
    func homeLabel(_ id: Int64) -> String? {
        Self.placeholderPos(id) != nil ? L.t("示意樓", "示意楼") : building(id: id)?.name
    }

    func building(id: Int64) -> Building? { buildings.first { $0.id == id } }

    /// Scene base width: retain only the 200 m around home.
    static let dioramaSize = 200.0

    /// Crop a square of width size around c, rebase coordinates to c, and simplify:
    /// Remove small sheds/canopies, tiny areas, steps, and cycleways. Retain paving, greenery, sports areas, and water.
    /// When maxResidential is set, limit residential and other buildings separately for home selection.
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
        out.areaName = areaName ?? placeName(near: c)

        // Prioritize style: rectangularize aligned building bounds, inset edges for gaps, and compress heights aesthetically.
        // Exempt home from area/dimension filters; small village houses retain at least an 8×8-m footprint.
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
            // Turn nearly square towers into slabs by preserving the long side and reducing the short side to 45%, matching the reference style.
            // Do not thin buildings shorter than 20 m; they would become narrow slivers.
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
        // Remove overlaps introduced by rectangularization, first accepted wins; prioritize homes during home selection.
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
        // Render greenery/water as at most three regular rectangular patches, choosing the largest areas.
        // Shrink bounding rectangles around their centres to avoid exceeding the original area or 20% of the base per patch.
        // Do not render rectangularized water over home, which would visually strand the building and block walking.
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
            return Area(kind: kind, outline: rect, name: a.name, osmID: a.osmID)
        }.sorted { Polygon.area($0.outline) > Polygon.area($1.outline) }.prefix(3)).sorted { $0.kind.drawOrder < $1.kind.drawOrder }
        out.roads = roads.flatMap { r -> [Road] in
            // Draw only vehicle roads as pale broad bands; omit footpaths, cycleways, and steps from this simplified rendering.
            guard r.kind == .major || r.kind == .minor || r.kind == .residential else { return [] }
            let kind = r.kind
            return Polygon.clipPolyline(r.points.map(shift), half: h).map { Road(kind: kind, points: $0, width: r.width, name: r.name) }
        }
        // Retain bus stops up to 80 m outside the base for edge fallback landmarks (LandmarkDeriver.edgeFallbacks).
        out.pois = pois.compactMap { p in
            var np = p
            np.pos = shift(p.pos)
            let reach = p.kind == .busStop || p.kind == .busStation ? h + 80 : h
            return abs(np.pos.x) <= reach && abs(np.pos.y) <= reach ? np : nil
        }
        out.trees = []
        return out
    }

    /// Determine the rotation that aligns dominant building edges near c with the base.
    func turn(around c: Vec2, size: Double) -> Double {
        -Polygon.dominantAngle(buildings.filter { $0.kind != .small && $0.centroid.distance(to: c) < size }.map(\.outline))
    }

    /// Allow at most 10% of the rotated 200-m home-centred base outside the fetched data area.
    /// Use area rather than edge distance: a 20-m strip differs from a small 60-m corner triangle; reject excessive spill across two edges.
    func dioramaFits(at c: Vec2) -> Bool {
        let r = Self.dioramaSize / 2, m = max(abs(c.x), abs(c.y))
        if m + r * 2.0.squareRoot() <= half { return true }   // Entire base fits regardless of rotation; no direction calculation needed.
        guard m - r < half else { return false }
        let a = -turn(around: c, size: Self.dioramaSize)        // Base orientation in the original map.
        let ca = cos(a), sa = sin(a)
        let square = [(-r, -r), (r, -r), (r, r), (-r, r)].map { Vec2(x: c.x + $0.0 * ca - $0.1 * sa, y: c.y + $0.0 * sa + $0.1 * ca) }
        return Polygon.area(Polygon.clip(square, half: half)) >= 0.9 * Self.dioramaSize * Self.dioramaSize
    }

    /// Home-selection viewport width in metres.
    static let pickSize = 300.0

    /// When location is known, show 300 m centred on the user, retaining up to ten selectable and three other buildings; always include the containing/nearest building.
    /// If no home candidate lies within 300 m, centre on the nearest candidate instead of showing the whole 720-m grid with untappable tiny buildings.
    /// Without user location, show the full grid and retain every selectable building.
    /// Mark candidates as residential for orange highlighting/hit testing; render others normally. See markHomeCandidates.
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

    /// Whether the home-selection scene contains selectable buildings.
    var hasHomeCandidate: Bool { buildings.contains { $0.kind == .residential } }

    /// Home candidates include explicit residences and building=yes with at least ten floors, excluding industry, warehouses, and parking.
    /// If none exist in the requested 300-m area/full grid, allow general buildings for village houses or incompletely mapped new estates.
    /// Exclude homes whose base would extend too far beyond fetched data; see dioramaFits.
    private func markHomeCandidates(around c: Vec2?) -> [Building] {
        let r = Self.pickSize / 2
        func local(_ b: Building) -> Bool { c.map { abs(b.centroid.x - $0.x) <= r && abs(b.centroid.y - $0.y) <= r } ?? true }
        func homeLike(_ b: Building) -> Bool { b.kind == .residential || (b.kind == .other && b.tag == "yes" && b.levels >= 10) }
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

    // MARK: - Placeholder building: allow onboarding when no building data exists nearby

    /// Negative placeholder ID encodes rounded metre coordinates so its position can be restored on restart.
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

    /// Add one 16×12-m, 30-floor placeholder resembling a new estate block, unless already present.
    /// If it overlaps water/buildings, move deterministically to the nearest free space.
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

    /// Whether a point lies inside any building, excluding canopies.
    func isInsideBuilding(_ p: Vec2) -> Bool {
        buildings.contains { $0.kind != .canopy && Polygon.contains($0.outline, p) }
    }
}
