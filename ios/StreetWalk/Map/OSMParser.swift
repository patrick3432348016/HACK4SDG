import Foundation

/// Parse Overpass out-geom JSON into MapModel for both live and bundled data.
enum OSMParser {
    struct Response: Decodable { let elements: [Element] }
    struct LatLon: Decodable { let lat: Double; let lon: Double }
    struct Member: Decodable {
        let type: String
        let role: String?
        let geometry: [LatLon?]?
    }
    struct Element: Decodable {
        let type: String
        let id: Int64
        let lat: Double?
        let lon: Double?
        let tags: [String: String]?
        let geometry: [LatLon?]?
        let members: [Member]?
    }

    enum ParseError: Error { case empty }

    /// size is the source fetch width (720 m live, 560 m bundled); clip features beyond it.
    static func parse(_ data: Data, tile: TileKey, size: Double = TileKey.plinthSize, source: String) throws -> MapModel {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let center = tile.center
        let proj = LocalProjection(origin: center)
        let half = size / 2

        var buildings: [Building] = []
        var roads: [Road] = []
        var areas: [Area] = []
        var pois: [POI] = []
        var trees: [Vec2] = []

        func local(_ g: [LatLon?]?) -> [Vec2] {
            (g ?? []).compactMap { $0 }.map { proj.toLocal(GeoPoint(lat: $0.lat, lon: $0.lon)) }
        }

        for e in response.elements {
            let tags = e.tags ?? [:]
            let name = displayName(tags)

            if e.type == "node", let lat = e.lat, let lon = e.lon {
                let p = proj.toLocal(GeoPoint(lat: lat, lon: lon))
                guard abs(p.x) <= half, abs(p.y) <= half else { continue }
                if tags["natural"] == "tree" { trees.append(p); continue }
                if let kind = poiKind(tags) {
                    pois.append(POI(id: e.id, kind: kind, name: name, pos: p,
                                    hasShelter: tags["shelter"] == "yes" || tags["covered"] == "yes",
                                    hasBench: tags["bench"] == "yes"))
                }
                continue
            }

            // For ways/relations, use outer rings.
            var rings: [[Vec2]] = []
            if e.type == "way" {
                rings = [local(e.geometry)]
            } else if e.type == "relation" {
                let outers = (e.members ?? []).filter { $0.type == "way" && ($0.role ?? "outer") != "inner" }.map { local($0.geometry) }
                rings = joinRings(outers)
            }

            for raw in rings where raw.count >= 2 {
                let closed = raw.count >= 4 && raw.first!.distance(to: raw.last!) < 0.5

                if let b = tags["building"], closed {
                    let outline = Polygon.normalized(Polygon.clip(Polygon.normalized(raw), half: half))
                    guard outline.count >= 3, Polygon.area(outline) >= 4 else { continue }
                    buildings.append(makeBuilding(id: e.id, type: b, tags: tags, name: name, outline: outline))
                    continue
                }

                if let hw = tags["highway"], tags["area"] != "yes" {
                    guard let (kind, width) = roadKind(hw, tags) else { continue }
                    for seg in Polygon.clipPolyline(raw, half: half) {
                        roads.append(Road(kind: kind, points: seg, width: width, name: name))
                    }
                    continue
                }

                if tags["natural"] == "tree_row" {
                    trees += resample(raw, every: 8).filter { abs($0.x) <= half && abs($0.y) <= half }
                    continue
                }

                if closed, let kind = areaKind(tags) {
                    let outline = Polygon.normalized(Polygon.clip(Polygon.normalized(raw), half: half))
                    guard outline.count >= 3, Polygon.area(outline) >= 10 else { continue }
                    // Preserve OSM identity across crops/cache refreshes; negative relation IDs avoid collisions with ways.
                    areas.append(Area(kind: kind, outline: outline, name: name, osmID: e.type == "relation" ? -e.id : e.id))
                    // Area bus terminals, malls, and markets also become points of interest.
                    if let pk = poiKind(tags) {
                        let c = Polygon.centroid(outline)
                        pois.append(POI(id: e.id, kind: pk, name: name, pos: c))
                    }
                    continue
                }

                if closed, let pk = poiKind(tags) {
                    let outline = Polygon.normalized(raw)
                    let c = Polygon.centroid(outline)
                    if abs(c.x) <= half, abs(c.y) <= half {
                        pois.append(POI(id: e.id, kind: pk, name: name, pos: c))
                    }
                }
            }
        }

        // Named buildings such as malls also become points of interest.
        for b in buildings where b.kind == .commercial && b.name != nil {
            pois.append(POI(id: b.id, kind: .mall, name: b.name, pos: b.centroid))
        }

        areas.sort { $0.kind.drawOrder < $1.kind.drawOrder }
        guard !buildings.isEmpty || !roads.isEmpty else { throw ParseError.empty }
        return MapModel(tile: tile, center: center, size: size, buildings: buildings, roads: roads,
                        areas: areas, pois: pois, trees: trees, fetchedAt: Date(), source: source)
    }

    // MARK: - Tag interpretation

    /// Prefer Chinese names, removing the English suffix from bilingual names.
    static func displayName(_ tags: [String: String]) -> String? {
        if let n = tags["name:zh-Hant"] ?? tags["name:zh"], !n.isEmpty { return n }
        guard let n = tags["name"], !n.isEmpty else { return nil }
        if n.unicodeScalars.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }) {
            var out = ""
            for ch in n {
                if ch.isASCII && ch.isLetter && out.last == " " { break }
                out.append(ch)
            }
            return out.trimmingCharacters(in: .whitespaces)
        }
        return n
    }

    static func makeBuilding(id: Int64, type: String, tags: [String: String], name: String?, outline: [Vec2]) -> Building {
        let area = Polygon.area(outline)
        var kind: BuildingKind
        var levels: Int
        switch type {
        case "apartments", "residential", "dormitory":
            kind = .residential; levels = area > 900 ? 25 : 4
        case "house", "detached", "terrace", "semidetached_house", "bungalow":
            kind = .residential; levels = 3
        case "school", "university", "college", "kindergarten":
            kind = .school; levels = 6
        // Hotels, hospitals, and government buildings are commercial/public, not residential candidates even when tall.
        case "commercial", "retail", "office", "supermarket", "hotel", "hospital", "public", "civic", "government", "train_station", "transportation":
            kind = .commercial; levels = area > 2000 ? 4 : 5
        // Industry/warehouses remain non-residential even above ten floors; their tag is not building=yes.
        case "industrial", "warehouse":
            kind = .other; levels = 3
        case "construction":
            kind = .construction; levels = 6
        case "roof", "canopy", "carport":
            kind = .canopy; levels = 1
        case "toilets", "kiosk", "hut", "shed", "garage", "garages", "service":
            kind = .small; levels = 1
        default:
            kind = .other; levels = area > 2500 ? 5 : area > 400 ? 3 : 2
        }
        if tags["amenity"] == "school" { kind = .school }
        // A building=yes public toilet is not a general building candidate or an area-name source.
        if tags["amenity"] == "toilets" { kind = .small }
        if let l = tags["building:levels"].flatMap({ Int($0.filter(\.isNumber)) }), l > 0 { levels = l }
        var height = Double(levels) * 3.0 + (levels > 10 ? 2 : 0.6)
        if let h = tags["height"].flatMap(parseMeters) { height = h }
        var minHeight = tags["min_height"].flatMap(parseMeters)
            ?? tags["building:min_level"].flatMap { Double($0).map { $0 * 3 } } ?? 0
        if kind == .canopy {
            minHeight = max(minHeight, 3.2)
            height = max(height, minHeight + 0.6)
            if tags["height"] == nil { height = minHeight + 0.6 }
        }
        return Building(id: id, name: name, outline: outline, minHeight: minHeight, height: height, levels: levels, kind: kind, tag: type)
    }

    static func parseMeters(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: "m", with: "").trimmingCharacters(in: .whitespaces))
    }

    static func roadKind(_ hw: String, _ tags: [String: String]) -> (RoadKind, Double)? {
        switch hw {
        case "motorway", "trunk", "primary", "secondary", "motorway_link", "trunk_link", "primary_link", "secondary_link":
            return (.major, 12)
        case "tertiary", "tertiary_link":
            return (.minor, 9)
        case "residential", "unclassified", "living_street", "road":
            return (.residential, 7)
        case "service":
            return (.service, tags["service"] == "parking_aisle" ? 4 : 5)
        case "footway", "path", "pedestrian", "corridor", "track", "bridleway":
            return (.footway, 3)
        case "cycleway":
            return (.cycleway, 2.5)
        case "steps":
            return (.steps, 2.5)
        default:
            return nil
        }
    }

    static func areaKind(_ t: [String: String]) -> AreaKind? {
        if let l = t["leisure"] {
            switch l {
            case "park", "garden": return .park
            case "pitch", "sports_centre", "track": return .pitch
            case "playground": return .playground
            default: break
            }
        }
        if let n = t["natural"] {
            switch n {
            case "wood": return .wood
            case "scrub", "grassland", "heath", "wetland": return .grass
            case "water": return .water
            default: break
            }
        }
        if t["waterway"] == "riverbank" || t["waterway"] == "dock" { return .water }
        if let l = t["landuse"] {
            switch l {
            case "forest": return .wood
            case "grass", "recreation_ground", "village_green", "meadow", "cemetery": return .grass
            case "farmland", "farmyard", "orchard", "allotments", "greenhouse_horticulture": return .farmland
            case "reservoir", "basin": return .water
            case "residential": return .residential
            case "industrial", "commercial", "retail", "railway", "construction": return .urban
            case "military": return .military
            default: break
            }
        }
        if let a = t["amenity"] {
            switch a {
            case "school", "college", "university", "kindergarten": return .school
            case "parking": return .parking
            default: break
            }
        }
        if t["highway"] == "pedestrian" && t["area"] == "yes" { return .plaza }
        return nil
    }

    static func poiKind(_ t: [String: String]) -> POIKind? {
        if t["highway"] == "bus_stop" { return .busStop }
        if let a = t["amenity"] {
            switch a {
            case "bus_station": return .busStation
            case "bench": return .bench
            case "shelter": return .shelter
            case "toilets": return .toilet
            case "marketplace": return .market
            case "fast_food", "restaurant", "cafe": return .food
            case "community_centre", "social_facility": return .community
            case "recycling": return .recycling
            default: break
            }
        }
        if t["shop"] == "mall" { return .mall }
        if t["shop"] != nil { return .shop }
        if t["leisure"] == "playground" { return .playground }
        if t["entrance"] != nil { return .entrance }
        return nil
    }

    // MARK: - Geometry helpers

    /// Join way fragments end-to-end into rings.
    static func joinRings(_ parts: [[Vec2]]) -> [[Vec2]] {
        var pending = parts.filter { $0.count >= 2 }
        var rings: [[Vec2]] = []
        while var ring = pending.first {
            pending.removeFirst()
            var progressed = true
            while progressed, ring.first!.distance(to: ring.last!) > 0.5 {
                progressed = false
                for (i, p) in pending.enumerated() {
                    if p.first!.distance(to: ring.last!) < 0.5 { ring += p.dropFirst(); pending.remove(at: i); progressed = true; break }
                    if p.last!.distance(to: ring.last!) < 0.5 { ring += p.reversed().dropFirst(); pending.remove(at: i); progressed = true; break }
                }
            }
            rings.append(ring)
        }
        return rings
    }

    static func resample(_ line: [Vec2], every step: Double) -> [Vec2] {
        guard line.count >= 2 else { return line }
        var out: [Vec2] = [line[0]]
        var carry = 0.0
        for i in 0..<(line.count - 1) {
            let a = line[i], b = line[i + 1]
            let len = a.distance(to: b)
            var t = step - carry
            while t <= len {
                out.append(a + (b - a) * (t / len))
                t += step
            }
            carry = len - (t - step)
        }
        return out
    }
}
