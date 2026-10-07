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

/// 从地图标签里挑 5–8 个间隔够远、居民会用来约见面的地方。
enum LandmarkDeriver {
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

        for (i, a) in map.areas.enumerated() {
            let c = interiorPoint(a.outline)
            guard inside(c) else { continue }
            switch a.kind {
            case .park where Polygon.area(a.outline) > 300:
                raw.append((LandmarkCandidate(id: "park-\(i)", kind: .park, pos: c, osmName: a.name, hasSeat: true), 9))
            case .playground:
                raw.append((LandmarkCandidate(id: "play-a\(i)", kind: .playground, pos: c, osmName: a.name, hasSeat: true), 6))
            case .pitch where Polygon.area(a.outline) > 200:
                raw.append((LandmarkCandidate(id: "pitch-\(i)", kind: .pitch, pos: edgePoint(a.outline, toward: .zero), osmName: a.name, hasSeat: false), 5))
            default: break
            }
        }

        // 有名字的住宅大楼：楼下大堂。
        for b in map.buildings where b.kind == .residential && b.levels >= 10 && b.name != nil {
            let lobby = nearestRoadPoint(to: b.centroid, in: map, maxDistance: 50) ?? edgePoint(b.outline, toward: .zero)
            guard inside(lobby) else { continue }
            raw.append((LandmarkCandidate(id: "lobby-\(b.id)", kind: .lobby, pos: lobby, osmName: b.name, hasSeat: false), 4))
        }

        return raw.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.pos.length < $1.0.pos.length }.map(\.0)
    }

    /// 贪心挑选：间隔至少 minSpacing 米，每类最多 2 个，最多 maxCount 个；不够 5 个就放宽间隔再挑。
    static func pick(_ cands: [LandmarkCandidate], maxCount: Int = 4) -> [LandmarkCandidate] {
        for spacing in [55.0, 40.0, 30.0] {
            var chosen: [LandmarkCandidate] = []
            var perKind: [LandmarkKind: Int] = [:]
            for c in cands {
                if chosen.count >= maxCount { break }
                if perKind[c.kind, default: 0] >= 2 { continue }
                if chosen.contains(where: { $0.pos.distance(to: c.pos) < spacing }) { continue }
                chosen.append(c)
                perKind[c.kind, default: 0] += 1
            }
            if chosen.count >= 3 || spacing == 30 { return chosen }
        }
        return []
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
