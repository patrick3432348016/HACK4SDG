import Foundation
import Testing
@testable import StreetWalk

// Map/scene/shade regressions from the 2026-10-08 audit and 10-09 review: A01 A08 A25 A26 A29 A32 A98 A99 A100.

private func hk(_ s: String) -> Date { SunShadeTests.hk(s) }

private func box(_ id: Int64, _ x: Double, _ y: Double, w: Double = 20, d: Double = 14, name: String? = nil,
                 kind: BuildingKind = .residential, height: Double = 30) -> Building {
    Building(id: id, name: name, outline: [Vec2(x: x - w / 2, y: y - d / 2), Vec2(x: x + w / 2, y: y - d / 2),
                                           Vec2(x: x + w / 2, y: y + d / 2), Vec2(x: x - w / 2, y: y + d / 2)],
             minHeight: 0, height: height, levels: Int(height / 3), kind: kind)
}

private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Vec2] {
    [Vec2(x: x0, y: y0), Vec2(x: x1, y: y0), Vec2(x: x1, y: y1), Vec2(x: x0, y: y1)]
}

private func testMap(_ buildings: [Building], areas: [Area] = [], roads: [Road] = [], size: Double = 560) -> MapModel {
    MapModel(tile: TileKey(ix: 0, iy: 0), center: GeoPoint(lat: 22.5044, lon: 114.1563), size: size, buildings: buildings,
             roads: roads, areas: areas, pois: [], trees: [], fetchedAt: Date(), source: "t")
}

@MainActor
struct ShadeHourTests {
    let full = MapService.fallback()

    func service() -> (ShadeService, Landmark) {
        let home = full.buildings.filter { $0.kind == .residential }.min { $0.centroid.length < $1.centroid.length }!
        let m = full.simplified(around: home.centroid, home: home.id)
        let lm = LandmarkDeriver.derive(in: m, home: home.id).map { Landmark(id: $0.id, name: "x", kind: $0.kind, pos: $0.pos, hasSeat: $0.hasSeat) }
        return (ShadeService(map: m, landmarks: lm), lm[0])
    }

    @Test func 夜晚问几点有遮荫唔会闪退() {
        let (s, lm) = service()
        let day = hk("2026-10-08 20:00")
        #expect(s.shadedFromHour(landmarkID: lm.id, day: day, after: 19) == nil)
        #expect(s.shadedFromHour(landmarkID: lm.id, day: day, after: 23) == nil)
    }

    @Test func 天黑唔算有樓遮() {
        let (s, lm) = service()
        let day = hk("2026-12-21 10:00")
        // At winter-solstice 18:00, the sun has set; computed full shade must not become a building-shade recommendation.
        if let h = s.shadedFromHour(landmarkID: lm.id, day: day, after: 14) {
            let el = SolarPosition.at(AppStore.hk.startOfDay(for: day).addingTimeInterval(Double(h) * 3600), lat: 22.5044, lon: 114.1563).elevation
            #expect(el > 5, "返回嘅钟点 \(h) 太阳要喺天上")
        }
        #expect(!s.isSunUp(at: hk("2026-10-08 19:00")))
        #expect(!s.isSunUp(at: hk("2026-12-21 18:00")))
        #expect(s.isSunUp(at: hk("2026-10-08 15:00")))
    }
}

@MainActor
struct DioramaFixTests {
    let full = MapService.fallback()
    let ai = TemplateAI()

    @Test func 细屋做屋企都留喺底座() {
        // Retain a rotated 9 x 7 m village home even when a 2.5 m inset leaves less than 4 m.
        let a = 0.4
        let pts = [Vec2(x: -4.5, y: -3.5), Vec2(x: 4.5, y: -3.5), Vec2(x: 4.5, y: 3.5), Vec2(x: -4.5, y: 3.5)]
            .map { Vec2(x: $0.x * cos(a) - $0.y * sin(a) + 30, y: $0.x * sin(a) + $0.y * cos(a) + 20) }
        let house = Building(id: 7, name: nil, outline: pts, minHeight: 0, height: 9, levels: 3, kind: .residential)
        let m = testMap([house, box(8, -40, -30), box(9, 60, 50)])
        let d = m.simplified(around: house.centroid, home: house.id)
        let kept = d.buildings.first { $0.id == house.id }
        #expect(kept != nil, "我屋企一定保留")
        if let k = kept {
            let xs = k.outline.map(\.x), ys = k.outline.map(\.y)
            #expect(xs.max()! - xs.min()! >= 7.9 && ys.max()! - ys.min()! >= 7.9, "最少 8×8 m")
        }
        // Apply the same retention rule to every selectable sample-estate building.
        for b in full.pickView(near: nil).buildings where b.kind == .residential {
            #expect(full.simplified(around: full.building(id: b.id)!.centroid, home: b.id).buildings.contains { $0.id == b.id })
        }
    }

    @Test func 地标三个以上而且唔撞名() {
        for h in full.buildings where h.kind == .residential {
            let d = full.simplified(around: h.centroid, home: h.id)
            let picked = LandmarkDeriver.derive(in: d, home: h.id)
            let named = LandmarkDeriver.uniqueNames(picked.map { Landmark(id: $0.id, name: ai.nameLandmark($0), kind: $0.kind, pos: $0.pos, hasSeat: $0.hasSeat) }, in: d)
            #expect(named.count >= 3, "\(h.name ?? "#\(h.id)") 只有 \(named.count) 个地标")
            #expect(Set(named.map(\.name)).count == named.count, "\(h.name ?? "#\(h.id)") 地标撞名：\(named.map(\.name))")
            #expect(Set(named.map(\.id)).count == named.count)
        }
    }

    @Test func 撞名加附近楼名() {
        let d = testMap([box(1, 0, 30, name: "17座")], size: 200)
        let l = [Landmark(id: "a", name: "公園櫈仔", kind: .park, pos: Vec2(x: 0, y: 0), hasSeat: true),
                 Landmark(id: "b", name: "公園櫈仔", kind: .park, pos: Vec2(x: 5, y: 15), hasSeat: true),
                 Landmark(id: "c", name: "公園櫈仔", kind: .park, pos: Vec2(x: -80, y: -80), hasSeat: true)]
        let u = LandmarkDeriver.uniqueNames(l, in: d).map(\.name)
        #expect(u == ["公園櫈仔", "17座旁公園櫈仔", "公園櫈仔（二）"])
    }

    @Test func 面状地标id用OSM编号() {
        // Different home crops must map area landmarks to the same OSM ID and geometry, not cropped array indices.
        func toFull(_ v: Vec2, from d: MapModel) -> Vec2 {
            let cs = cos(-d.rotation), sn = sin(-d.rotation)
            return full.scenePoint(LocalProjection(origin: d.center).toGeo(Vec2(x: v.x * cs - v.y * sn, y: v.x * sn + v.y * cs)))
        }
        var checked = 0
        for h in full.buildings where h.kind == .residential {
            let d = full.simplified(around: h.centroid, home: h.id)
            for c in LandmarkDeriver.candidates(in: d) where c.kind == .park || c.kind == .pitch {
                let n = Int64(c.id.split(separator: "-").last!)
                let area = full.areas.first { $0.osmID != nil && $0.osmID == n }
                #expect(area != nil, "\(c.id) 唔系 OSM 编号")
                if let a = area {
                    #expect(LandmarkDeriver.distance(from: toFull(c.pos, from: d), to: a.outline) < 40, "\(c.id) 指向唔同地方")
                    checked += 1
                }
            }
        }
        #expect(checked > 10)
    }

    @Test func 地名用屋苑名唔用公厕() {
        let estate = Area(kind: .residential, outline: rect(-40, -40, 40, 40), name: "逸東邨", osmID: 5)
        let m = testMap([box(1, 0, 0, name: "德逸樓"), box(2, 150, 150, name: "石湖新村公廁", kind: .other)], areas: [estate])
        #expect(m.placeName == "逸東邨")
        #expect(m.placeName(near: Vec2(x: 70, y: 60)) == "德逸樓", "屋苑外：底座内最近的有名住宅楼")
        let lonely = testMap([box(2, 0, 0, name: "石湖新村公廁", kind: .other)])
        #expect(lonely.placeName == "你附近", "公厕、商场的名唔用")
    }

    @Test func 冇住宅楼时都有楼可以揀() {
        // Allow general-building fallback for village houses tagged only building=yes.
        let village = testMap([box(1, 10, 10, kind: .other), box(2, -40, 30, kind: .other), box(3, 0, -60, kind: .small)])
        let v = village.pickView(near: Vec2(x: 5, y: 5))
        #expect(v.hasHomeCandidate)
        #expect(!v.buildings.contains { $0.id == 3 && $0.kind == .residential }, "细屋唔畀揀")
        // With no buildings, place a placeholder at my position and restore by ID on relaunch.
        let empty = testMap([box(3, 0, -60, kind: .small)])
        #expect(!empty.pickView(near: .zero).hasHomeCandidate)
        let p = Vec2(x: 123.4, y: -87.6)
        let (withHome, id) = empty.addingPlaceholderHome(at: p)
        #expect(MapModel.placeholderPos(id) == Vec2(x: 123, y: -88))
        #expect(MapModel.placeholderPos(659677269) == nil)
        #expect(withHome.pickView(near: p).buildings.contains { $0.id == id && $0.kind == .residential })
        #expect(withHome.simplified(around: withHome.building(id: id)!.centroid, home: id).buildings.contains { $0.id == id })
    }

    @Test func 酒店高楼唔当住宅() {
        // Exclude a 25-floor Tin Shui Wai hotel from generic residential-high-rise eligibility.
        let hotel = OSMParser.makeBuilding(id: 1, type: "hotel", tags: ["building": "hotel", "building:levels": "25"], name: "第二期", outline: rect(-10, -8, 10, 8))
        #expect(hotel.kind == .commercial)
        let tall = OSMParser.makeBuilding(id: 2, type: "yes", tags: ["building": "yes", "building:levels": "30"], name: nil, outline: rect(30, -8, 50, 8))
        let v = testMap([hotel, tall]).pickView(near: .zero)
        #expect(v.buildings.contains { $0.id == 2 && $0.kind == .residential }, "只标 building=yes 的高楼可以揀")
        #expect(!v.buildings.contains { $0.id == 1 && $0.kind == .residential }, "酒店唔畀揀")
    }

    @Test func 太近格边嘅楼唔畀揀() {
        // A home 300 m from a 720 m tile center may leave its 200 m base beyond fetched data.
        let m = testMap([box(1, 0, 0), box(2, 300, 0)], size: 720)
        let v = m.pickView(near: nil)
        #expect(v.buildings.contains { $0.id == 1 && $0.kind == .residential })
        #expect(!v.buildings.contains { $0.id == 2 && $0.kind == .residential })
    }

    @Test func 寻路唔行水() {
        // Route around water between start and destination.
        let pond = Area(kind: .water, outline: rect(-30, -60, 30, 60), name: nil, osmID: 9)
        let m = testMap([], areas: [pond], roads: [Road(kind: .residential, points: [Vec2(x: -90, y: -95), Vec2(x: 90, y: -95)], width: 7)], size: 200)
        let grid = PathGrid(map: m)
        let path = grid.path(from: Vec2(x: -60, y: 0), to: Vec2(x: 60, y: 0))
        #expect(path.count > 2)
        #expect(!path.dropFirst().dropLast().contains { Polygon.contains(pond.outline, $0) }, "路线穿过水面")
    }

    @Test func 示意樓唔借远处嘅楼名() {
        // A placeholder at Fung Wong Ling must not borrow a named building 180 m away outside the base.
        let (m, id) = testMap([box(1, 180, 0, name: "第五座")], size: 720).addingPlaceholderHome(at: .zero)
        let d = m.simplified(around: m.building(id: id)!.centroid, home: id)
        #expect(d.placeName == "你附近")
        #expect(d.homeLabel(id) == "示意樓")
        #expect(testMap([box(1, 60, 0, name: "第五座")]).placeName(near: .zero) == "第五座", "底座里面的有名住宅楼照用")
    }

    @Test func 工厦货仓唔当住宅() {
        // Exclude a 12-floor Mong Kok industrial building from generic residential fallback.
        let factory = OSMParser.makeBuilding(id: 1, type: "industrial", tags: ["building": "industrial", "building:levels": "12"], name: nil, outline: rect(-10, -8, 10, 8))
        let tall = OSMParser.makeBuilding(id: 2, type: "yes", tags: ["building": "yes", "building:levels": "20"], name: nil, outline: rect(30, -8, 50, 8))
        let flat = OSMParser.makeBuilding(id: 3, type: "apartments", tags: ["building": "apartments"], name: nil, outline: rect(-50, 20, -30, 34))
        let v = testMap([factory, tall, flat]).pickView(near: .zero)
        #expect(v.buildings.contains { $0.id == 2 && $0.kind == .residential })
        #expect(v.buildings.contains { $0.id == 3 && $0.kind == .residential })
        #expect(!v.buildings.contains { $0.id == 1 && $0.kind == .residential }, "工厦唔畀揀")
    }

    @Test func 附近冇住宅楼就近放宽() {
        // Near a mall with residences 250 m away, allow nearby general buildings instead of only distant homes.
        let m = testMap([box(1, 20, 10, kind: .commercial, height: 12), box(2, 250, 0)], size: 720)
        let v = m.pickView(near: .zero)
        #expect(v.size == MapModel.pickSize)
        #expect(v.buildings.contains { $0.id == 1 && $0.kind == .residential })
    }

    @Test func 附近乜都冇就睇最近嗰座() {
        // With no building within 150 m, center the nearest selectable area rather than zooming out to an untappable 720 m tile.
        let m = testMap([box(1, 0, -10, kind: .small), box(2, 230, 40)], size: 720)
        let v = m.pickView(near: .zero)
        #expect(v.size == MapModel.pickSize)
        #expect(v.buildings.contains { $0.id == 2 && $0.kind == .residential })
    }

    @Test func 转咗向近格边嘅楼唔畀揀() {
        // A 270 m edge home may pass unrotated with 10 m overflow but fail at a rotated corner with roughly 50 m overflow.
        func diamond(_ id: Int64, _ x: Double, _ y: Double) -> Building {
            Building(id: id, name: nil, outline: [Vec2(x: x, y: y - 12), Vec2(x: x + 12, y: y), Vec2(x: x, y: y + 12), Vec2(x: x - 12, y: y)],
                     minHeight: 0, height: 30, levels: 10, kind: .residential)
        }
        #expect(testMap([box(1, 270, 0)], size: 720).dioramaFits(at: Vec2(x: 270, y: 0)))
        let tilted = testMap([diamond(1, 270, 270), diamond(2, 250, 230)], size: 720)
        #expect(!tilted.dioramaFits(at: Vec2(x: 270, y: 270)))
        #expect(tilted.dioramaFits(at: Vec2(x: 100, y: 80)))
    }

    @Test func 冇名嘅楼下唔叫大堂() {
        // Unnamed Kwu Tung homes receive distinct home/near-building labels instead of repeated generic lobbies.
        let d = testMap([box(1, 0, 0), box(2, 60, 0), box(3, 60, 30, name: "21座")], size: 200)
        let l = [Landmark(id: "lobby-1", name: "大堂", kind: .lobby, pos: Vec2(x: 0, y: -12), hasSeat: false),
                 Landmark(id: "lobby-2", name: "大堂", kind: .lobby, pos: Vec2(x: 60, y: -12), hasSeat: false),
                 Landmark(id: "lobby-3", name: "21座樓下", kind: .lobby, pos: Vec2(x: 60, y: 42), hasSeat: false)]
        #expect(LandmarkDeriver.uniqueNames(l, in: d, home: 1).map(\.name) == ["你屋企樓下", "21座旁", "21座樓下"])
    }

    @Test func 地标唔够用底座外嘅巴士站() {
        // With one home, supplement its entrance with a bus stop 40 m outside the base, clamped to the edge, and a park.
        var m = testMap([box(1, 0, 0)], areas: [Area(kind: .park, outline: rect(-90, -90, -40, -40), name: nil, osmID: 7)], size: 720)
        m.pois = [POI(id: 5, kind: .busStop, name: "古洞", pos: Vec2(x: 140, y: 10))]
        let d = m.simplified(around: .zero, home: 1)
        let picked = LandmarkDeriver.derive(in: d, home: 1)
        #expect(picked.count >= 3, "\(picked.map(\.id))")
        let bus = picked.first { $0.kind == .busStop }
        #expect(bus != nil)
        if let b = bus { #expect(max(abs(b.pos.x), abs(b.pos.y)) <= d.half - 10) }
    }

    @Test func 写新快取会删旧格() throws {
        let t = TileKey(ix: 9_999, iy: 9_999)
        let v1 = TileCache.dir.appendingPathComponent("v1", isDirectory: true)
        try FileManager.default.createDirectory(at: v1, withIntermediateDirectories: true)
        let old = v1.appendingPathComponent("\(t).json")
        try Data("{}".utf8).write(to: old)
        TileCache.write(t, Data("{\"elements\":[]}".utf8))
        #expect(!FileManager.default.fileExists(atPath: old.path), "写了 v2 就删 v1")
        #expect(TileCache.read(t)?.size == MapService.fetchSize)
        try? FileManager.default.removeItem(at: TileCache.dir.appendingPathComponent("v2/\(t).json"))
    }
}
