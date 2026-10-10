import Foundation

enum LandmarkKind: String, Codable {
    case busTerminus, busStop, park, playground, pitch, shelter, bench, mall, market, community, lobby, food
}

/// 自动选出的地标候选，名字由 AIService.nameLandmark 决定。
struct LandmarkCandidate: Codable, Hashable {
    var id: String
    var kind: LandmarkKind
    var pos: Vec2
    var osmName: String?
    var hasSeat: Bool
}

struct Landmark: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: LandmarkKind
    var pos: Vec2
    var hasSeat: Bool
}

/// 从地图标签里挑 3–4 个间隔够远、居民会用来约见面的地方。
enum LandmarkDeriver {
    /// 底座的地标：先按常用地方挑；不够 3 个（村屋、资料未齐的新屋邨）就加上各座楼（包括我屋企）的楼下再挑；
    /// 还不够（村屋太密，楼下都贴着别的屋）就逐个补，放得下就要；最后用底座外面不远的巴士站、车路出底座的路口（都放在底座边）。
    static func derive(in map: MapModel, home: Int64? = nil) -> [LandmarkCandidate] {
        let main = candidates(in: map)
        let first = settle(pick(main), in: map)
        guard first.count < 3 else { return first }
        let ids = Set(main.map(\.id))
        let extra = lobbyFallbacks(in: map, home: home).filter { !ids.contains($0.id) }
        let second = settle(pick(main + extra), in: map)
        var best = second.count > first.count ? second : first
        for c in main + extra + edgeFallbacks(in: map) + roadExits(in: map) where best.count < 3 && !best.contains(where: { $0.id == c.id }) {
            if genericKinds.contains(c.kind) && !c.id.hasPrefix("road-") && best.contains(where: { $0.kind == c.kind }) { continue }
            let s = settle(best + [c], in: map)
            if s.count == best.count + 1 { best = s }
        }
        return best
    }

    /// 底座外 80 m 内的巴士站（同名合并），挪到底座边上。只在地标不够时用。
    static func edgeFallbacks(in map: MapModel) -> [LandmarkCandidate] {
        let inner = map.half - 20, edge = map.half - 14
        var byName: [String: [POI]] = [:]
        for p in map.pois where p.kind == .busStop || p.kind == .busStation {
            byName[p.name ?? "巴士站#\(p.id)", default: []].append(p)
        }
        return byName.compactMap { name, stops -> (LandmarkCandidate, Double)? in
            let c = stops.map(\.pos).reduce(Vec2.zero, +) * (1.0 / Double(stops.count))
            let out = max(abs(c.x), abs(c.y))
            guard out > inner else { return nil }   // 底座里面的已在 candidates
            let terminus = name.contains("總站") || stops.contains { $0.kind == .busStation }
            let pos = Vec2(x: max(-edge, min(edge, c.x)), y: max(-edge, min(edge, c.y)))
            return (LandmarkCandidate(id: "bus-\(stops[0].id)", kind: terminus ? .busTerminus : .busStop, pos: pos, osmName: name,
                                      hasSeat: terminus || stops.contains { $0.hasShelter || $0.hasBench }), out)
        }.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.id < $1.0.id }.map(\.0)
    }

    /// 车路出底座的地方，放在底座边（"X路口"，名字见 uniqueNames）。有名、大路的先。
    /// 没有"路口"这一类，借用涼亭类（只影响模板起名，uniqueNames 按 id 改名），不当有座位。
    static func roadExits(in map: MapModel) -> [LandmarkCandidate] {
        let edge = map.half - 14
        var seen = Set<String>()
        return map.roads.flatMap { r -> [(LandmarkCandidate, Int)] in
            let rank = (r.name == nil ? 3 : 0) + (r.kind == .major ? 0 : r.kind == .minor ? 1 : 2)
            return [r.points.first, r.points.last].compactMap { $0 }.filter { max(abs($0.x), abs($0.y)) > map.half - 2 }.map { e in
                let p = Vec2(x: max(-edge, min(edge, e.x)), y: max(-edge, min(edge, e.y)))
                return (LandmarkCandidate(id: "road-\(Int((p.x / 5).rounded()))_\(Int((p.y / 5).rounded()))", kind: .shelter, pos: p, osmName: r.name, hasSeat: false), rank)
            }
        }.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.id < $1.0.id }.map(\.0).filter { seen.insert($0.id).inserted }
    }

    /// 后备地标：我屋企楼下（我屋企可能只标 building=yes）→ 任何高度、有没有名字的住宅楼楼下 → 其他有名的楼（商场、学校）楼下 → 其他楼。
    static func lobbyFallbacks(in map: MapModel, home: Int64?) -> [LandmarkCandidate] {
        let limit = map.half - 20
        func rank(_ b: Building) -> Int { b.id == home ? 0 : b.kind == .residential ? 1 : b.name != nil ? 2 : 3 }
        return map.buildings.filter { $0.kind != .small && $0.kind != .canopy && $0.kind != .construction }
            .sorted { (rank($0), $0.centroid.length) < (rank($1), $1.centroid.length) }
            .compactMap { b in
                let lobby = nearestRoadPoint(to: b.centroid, in: map, maxDistance: 50) ?? edgePoint(b.outline, toward: .zero)
                guard abs(lobby.x) <= limit, abs(lobby.y) <= limit else { return nil }
                return LandmarkCandidate(id: "lobby-\(b.id)", kind: .lobby, pos: lobby, osmName: b.name, hasSeat: false)
            }
    }

    static func candidates(in map: MapModel) -> [LandmarkCandidate] {
        var raw: [(LandmarkCandidate, Int)] = []
        let limit = map.half - 20
        func inside(_ p: Vec2) -> Bool { abs(p.x) <= limit && abs(p.y) <= limit }

        // 巴士站：同名的站合并成一个。
        var stopsByName: [String: [POI]] = [:]
        for p in map.pois where p.kind == .busStop || p.kind == .busStation {
            stopsByName[p.name ?? "巴士站#\(p.id)", default: []].append(p)
        }
        for (name, stops) in stopsByName {
            let c = stops.map(\.pos).reduce(Vec2.zero, +) * (1.0 / Double(stops.count))
            guard inside(c) else { continue }
            let terminus = name.contains("總站") || stops.contains { $0.kind == .busStation }
            let seat = terminus || stops.contains { $0.hasShelter || $0.hasBench }
            raw.append((LandmarkCandidate(id: "bus-\(stops[0].id)", kind: terminus ? .busTerminus : .busStop,
                                          pos: c, osmName: name, hasSeat: seat), terminus ? 10 : 6))
        }

        for p in map.pois where inside(p.pos) {
            switch p.kind {
            case .shelter: raw.append((LandmarkCandidate(id: "shelter-\(p.id)", kind: .shelter, pos: p.pos, osmName: p.name, hasSeat: true), 9))
            case .bench: raw.append((LandmarkCandidate(id: "bench-\(p.id)", kind: .bench, pos: p.pos, osmName: p.name, hasSeat: true), 7))
            case .market: raw.append((LandmarkCandidate(id: "market-\(p.id)", kind: .market, pos: p.pos, osmName: p.name, hasSeat: false), 9))
            case .mall:
                let door = nearestRoadPoint(to: p.pos, in: map, maxDistance: 60) ?? p.pos
                raw.append((LandmarkCandidate(id: "mall-\(p.id)", kind: .mall, pos: door, osmName: p.name, hasSeat: false), 8))
            case .community: raw.append((LandmarkCandidate(id: "community-\(p.id)", kind: .community, pos: p.pos, osmName: p.name, hasSeat: true), 6))
            case .playground: raw.append((LandmarkCandidate(id: "play-\(p.id)", kind: .playground, pos: p.pos, osmName: p.name, hasSeat: true), 6))
            case .food: raw.append((LandmarkCandidate(id: "food-\(p.id)", kind: .food, pos: p.pos, osmName: p.name, hasSeat: false), 3))
            default: break
            }
        }

        // 面状地标的 id 用 OSM 编号（不用裁切后数组的下标）：换楼、缓存刷新后同一块地仍然是同一个 id。
        for (i, a) in map.areas.enumerated() {
            let c = interiorPoint(a.outline)
            guard inside(c) else { continue }
            let key = a.osmID.map { "\($0)" } ?? "i\(i)"
            switch a.kind {
            case .park where Polygon.area(a.outline) > 300:
                raw.append((LandmarkCandidate(id: "park-\(key)", kind: .park, pos: c, osmName: a.name, hasSeat: true), 9))
            case .playground:
                raw.append((LandmarkCandidate(id: "play-a\(key)", kind: .playground, pos: c, osmName: a.name, hasSeat: true), 6))
            case .pitch where Polygon.area(a.outline) > 200:
                raw.append((LandmarkCandidate(id: "pitch-\(key)", kind: .pitch, pos: edgePoint(a.outline, toward: .zero), osmName: a.name, hasSeat: false), 5))
            default: break
            }
        }

        // 有名字的住宅大楼：楼下大堂。
        for b in map.buildings where b.kind == .residential && b.levels >= 10 && b.name != nil {
            let lobby = nearestRoadPoint(to: b.centroid, in: map, maxDistance: 50) ?? edgePoint(b.outline, toward: .zero)
            guard inside(lobby) else { continue }
            raw.append((LandmarkCandidate(id: "lobby-\(b.id)", kind: .lobby, pos: lobby, osmName: b.name, hasSeat: false), 4))
        }

        // 同一个 OSM 要素可能出几块（relation 多个外环）：id 重复的只留第一个。
        var seen = Set<String>()
        return raw.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.pos.length < $1.0.pos.length }.map(\.0)
            .filter { seen.insert($0.id).inserted }
    }

    /// 泛称地标（模板会叫做"公園櫈仔""涼亭"之类）：每类最多 1 个，免得两个同名。
    static let genericKinds: Set<LandmarkKind> = [.park, .playground, .shelter, .bench, .pitch]

    /// 贪心挑选：间隔至少 spacing 米，泛称每类 1 个、其他每类 2 个，最多 maxCount 个；不够 3 个就放宽间隔再挑，
    /// 还不够就用楼下补（各座楼名不同）。
    static func pick(_ cands: [LandmarkCandidate], maxCount: Int = 4) -> [LandmarkCandidate] {
        var best: [LandmarkCandidate] = []
        for spacing in [55.0, 40.0, 30.0] {
            var chosen: [LandmarkCandidate] = []
            var perKind: [LandmarkKind: Int] = [:]
            func far(_ c: LandmarkCandidate) -> Bool { !chosen.contains { $0.pos.distance(to: c.pos) < spacing } }
            for c in cands {
                if chosen.count >= maxCount { break }
                if perKind[c.kind, default: 0] >= (genericKinds.contains(c.kind) ? 1 : 2) { continue }
                if !far(c) { continue }
                chosen.append(c)
                perKind[c.kind, default: 0] += 1
            }
            for c in cands where chosen.count < 3 && c.kind == .lobby && !chosen.contains(c) && far(c) { chosen.append(c) }
            if chosen.count >= 3 { return chosen }
            if chosen.count > best.count { best = chosen }
        }
        return best
    }

    /// 名字不能重复（语音、约会都靠名字分辨）：重名的加上最近的有名楼宇（"皇滙樓旁公園櫈仔"），还不行就加编号。
    /// 没有名的楼的楼下（模板叫"大堂"，长者分不出是哪座）：我屋企叫"你屋企樓下"；其他按附近有名的楼、店、路叫"21座旁"，
    /// 都没有就按在我屋企哪个方向叫"東邊嗰座樓下"。底座边的路口叫"X路口"（模板当涼亭，这里改名）。
    static func uniqueNames(_ list: [Landmark], in map: MapModel, home: Int64? = nil) -> [Landmark] {
        var out = list
        var used = Set<String>()
        let named = map.buildings.filter { $0.name != nil && $0.kind != .small }
        func roadDistance(_ r: Road, _ p: Vec2) -> Double {
            (0..<max(r.points.count - 1, 0)).map { closestPoint(on: r.points[$0], r.points[$0 + 1], to: p).distance(to: p) }.min() ?? .infinity
        }
        func namedRoads(near p: Vec2, within d: Double) -> [String] {
            map.roads.compactMap { r -> (String, Double)? in
                guard let n = r.name, !n.isEmpty else { return nil }
                let x = roadDistance(r, p)
                return x < d ? (n, x) : nil
            }.sorted { $0.1 < $1.1 }.map(\.0)
        }
        for i in out.indices {
            let p = out[i].pos
            let taken = Set(out.enumerated().filter { $0.offset != i }.map(\.element.name))
            if out[i].id.hasPrefix("road-") {
                out[i].name = namedRoads(near: p, within: 20).map { $0.hasSuffix("口") ? $0 : "\($0)口" }.first { !taken.contains($0) } ?? "路口"
                continue
            }
            guard out[i].kind == .lobby, let id = Int64(out[i].id.dropFirst("lobby-".count)),
                  let b = map.building(id: id), b.name == nil else { continue }
            if id == home { out[i].name = "你屋企樓下"; continue }
            let byBuilding = named.filter { $0.id != id && distance(from: p, to: $0.outline) < 60 }
                .sorted { distance(from: p, to: $0.outline) < distance(from: p, to: $1.outline) }.map { $0.name! }
            // 店名太长（"Win East Sanitary Ware Co., Ltd"）不好讲，只用 6 个字以内的。
            let byPOI = map.pois.filter { $0.kind != .busStop && $0.kind != .busStation && (1...6).contains($0.name?.count ?? 0) && $0.pos.distance(to: p) < 50 }
                .sorted { $0.pos.distance(to: p) < $1.pos.distance(to: p) }.map { $0.name! }
            // 方向按真北：底座转过 rotation（逆时针），转回去再算方位角。
            let c = b.centroid, cr = cos(-map.rotation), sr = sin(-map.rotation)
            let bearing = atan2(c.x * cr - c.y * sr, c.x * sr + c.y * cr) * 180 / .pi
            let dir = ["北", "東北", "東", "東南", "南", "西南", "西", "西北"][Int(((bearing + 382.5).truncatingRemainder(dividingBy: 360)) / 45) % 8]
            let options = (byBuilding + byPOI + namedRoads(near: p, within: 80)).map { "\($0)旁" } + ["\(dir)邊嗰座樓下"]
            if let n = options.first(where: { !taken.contains($0) }) { out[i].name = n }
        }
        for i in out.indices {
            guard used.contains(out[i].name) else { used.insert(out[i].name); continue }
            let base = out[i].name, p = out[i].pos
            var name = named.filter { distance(from: p, to: $0.outline) < 60 && !base.contains($0.name!) }
                .min { distance(from: p, to: $0.outline) < distance(from: p, to: $1.outline) }
                .map { "\($0.name!)旁\(base)" }
            if let n = name, used.contains(n) { name = nil }
            let name2 = name ?? ["二", "三", "四", "五", "六", "七"].map { "\(base)（\($0)）" }.first { !used.contains($0) } ?? "\(base)\(i + 1)"
            out[i].name = name2
            used.insert(name2)
        }
        return out
    }

    /// 楼改成规整矩形后，地标可能压在楼上或贴着墙：挪到楼外、不在水里、底座内的最近位置，尽量少动。
    /// clearance 是地标中心到楼的距离（小凉亭半宽约 4.75 m，8 m 即亭边离楼约 3 m）；地标之间仍保持 spacing。
    /// 60 m 内都找不到合适位置的就不要了。
    static func settle(_ picked: [LandmarkCandidate], in map: MapModel, clearance: Double = 8, spacing: Double = 30) -> [LandmarkCandidate] {
        let limit = map.half - 10
        let water = map.areas.filter { $0.kind == .water }.map(\.outline)
        func ok(_ p: Vec2, _ placed: [LandmarkCandidate]) -> Bool {
            abs(p.x) <= limit && abs(p.y) <= limit
                && map.buildings.allSatisfy { $0.kind == .canopy || distance(from: p, to: $0.outline) >= clearance }
                && !water.contains { Polygon.contains($0, p) }
                && placed.allSatisfy { $0.pos.distance(to: p) >= spacing }
        }
        func spot(near q: Vec2, _ placed: [LandmarkCandidate]) -> Vec2? {
            if ok(q, placed) { return q }
            // 由近到远一圈圈找：半径每次加 2 m，每圈 24 个方向。
            for r in stride(from: 2.0, through: 60, by: 2) {
                for k in 0..<24 {
                    let a = Double(k) * .pi / 12
                    let p = q + Vec2(x: cos(a) * r, y: sin(a) * r)
                    if ok(p, placed) { return p }
                }
            }
            return nil
        }
        var out: [LandmarkCandidate] = []
        for var c in picked {
            guard let p = spot(near: c.pos, out) else { continue }
            c.pos = p
            out.append(c)
        }
        return out
    }

    // MARK: - 几何

    /// 点到多边形的距离（在里面算 0）。
    static func distance(from p: Vec2, to poly: [Vec2]) -> Double {
        if Polygon.contains(poly, p) { return 0 }
        return (0..<poly.count).map { closestPoint(on: poly[$0], poly[($0 + 1) % poly.count], to: p).distance(to: p) }.min() ?? .infinity
    }

    static func nearestRoadPoint(to p: Vec2, in map: MapModel, maxDistance: Double) -> Vec2? {
        var best: (Vec2, Double)?
        for r in map.roads where r.kind == .footway || r.kind == .service || r.kind == .residential || r.kind == .minor {
            for i in 0..<max(r.points.count - 1, 0) {
                let q = closestPoint(on: r.points[i], r.points[i + 1], to: p)
                let d = q.distance(to: p)
                if d < maxDistance, best == nil || d < best!.1 { best = (q, d) }
            }
        }
        return best?.0
    }

    static func closestPoint(on a: Vec2, _ b: Vec2, to p: Vec2) -> Vec2 {
        let ab = b - a
        let t = max(0, min(1, (p - a).dot(ab) / max(ab.dot(ab), 1e-9)))
        return a + ab * t
    }

    /// 质心落在多边形外（凹形）时，退而求其次取最靠近质心的内部点。
    static func interiorPoint(_ poly: [Vec2]) -> Vec2 {
        let c = Polygon.centroid(poly)
        if Polygon.contains(poly, c) { return c }
        let tris = Polygon.triangulate(poly)
        var best = poly[0], bestD = Double.infinity
        var i = 0
        while i + 2 < tris.count {
            let m = (poly[tris[i]] + poly[tris[i + 1]] + poly[tris[i + 2]]) * (1.0 / 3)
            let d = m.distance(to: c)
            if d < bestD { bestD = d; best = m }
            i += 3
        }
        return best
    }

    static func edgePoint(_ poly: [Vec2], toward target: Vec2) -> Vec2 {
        var best = poly[0], bestD = Double.infinity
        for i in 0..<poly.count {
            let q = closestPoint(on: poly[i], poly[(i + 1) % poly.count], to: target)
            let d = q.distance(to: target)
            if d < bestD { bestD = d; best = q }
        }
        return best
    }
}
