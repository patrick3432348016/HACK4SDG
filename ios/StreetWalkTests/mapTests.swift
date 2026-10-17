import Foundation
import Testing
@testable import StreetWalk

// 地图、场景与遮荫的回归测试（2026-10-08 审核修正：A01 A08 A25 A26 A29 A32 A98 A99 A100；10-09 复核补充）。

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
        // 冬至 18:00 太阳已经落山：就算遮荫按 100% 计，也不能答"6 點後有樓遮住"。
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
        // 9×7 m 斜放的村屋：转正后外接矩形内缩 2.5 m 不够 4 m，以前会被丢掉。
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
        // 示例屋邨里每座可选的楼都一样。
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
        // 两座不同的屋企各自裁底座：面状地标的 id 是 OSM 编号，而且指向整格里同一块地（不再是裁切后的下标）。
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
        // 村屋只标 building=yes：放宽到一般建筑。
        let village = testMap([box(1, 10, 10, kind: .other), box(2, -40, 30, kind: .other), box(3, 0, -60, kind: .small)])
        let v = village.pickView(near: Vec2(x: 5, y: 5))
        #expect(v.hasHomeCandidate)
        #expect(!v.buildings.contains { $0.id == 3 && $0.kind == .residential }, "细屋唔畀揀")
        // 一座楼都没有：示意楼放在我的位置，下次启动按 id 放回原位。
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
        // 天水围银座：25 层的酒店（building=hotel）以前被当成"只标 building=yes 的住宅高楼"可以选。
        let hotel = OSMParser.makeBuilding(id: 1, type: "hotel", tags: ["building": "hotel", "building:levels": "25"], name: "第二期", outline: rect(-10, -8, 10, 8))
        #expect(hotel.kind == .commercial)
        let tall = OSMParser.makeBuilding(id: 2, type: "yes", tags: ["building": "yes", "building:levels": "30"], name: nil, outline: rect(30, -8, 50, 8))
        let v = testMap([hotel, tall]).pickView(near: .zero)
        #expect(v.buildings.contains { $0.id == 2 && $0.kind == .residential }, "只标 building=yes 的高楼可以揀")
        #expect(!v.buildings.contains { $0.id == 1 && $0.kind == .residential }, "酒店唔畀揀")
    }

    @Test func 太近格边嘅楼唔畀揀() {
        // 720 m 一格：离格心 300 m 的楼做屋企，200 m 底座会超出资料范围。
        let m = testMap([box(1, 0, 0), box(2, 300, 0)], size: 720)
        let v = m.pickView(near: nil)
        #expect(v.buildings.contains { $0.id == 1 && $0.kind == .residential })
        #expect(!v.buildings.contains { $0.id == 2 && $0.kind == .residential })
    }

    @Test func 寻路唔行水() {
        // 一个水池挡在起点和终点中间：路线要绕过去。
        let pond = Area(kind: .water, outline: rect(-30, -60, 30, 60), name: nil, osmID: 9)
        let m = testMap([], areas: [pond], roads: [Road(kind: .residential, points: [Vec2(x: -90, y: -95), Vec2(x: 90, y: -95)], width: 7)], size: 200)
        let grid = PathGrid(map: m)
        let path = grid.path(from: Vec2(x: -60, y: 0), to: Vec2(x: 60, y: 0))
        #expect(path.count > 2)
        #expect(!path.dropFirst().dropLast().contains { Polygon.contains(pond.outline, $0) }, "路线穿过水面")
    }

    @Test func 示意樓唔借远处嘅楼名() {
        // 鳳凰嶺：示意楼 180 m 外才有"第五座"，不在底座里，地名不能叫"第五座"，设定页显示"示意樓"。
        let (m, id) = testMap([box(1, 180, 0, name: "第五座")], size: 720).addingPlaceholderHome(at: .zero)
        let d = m.simplified(around: m.building(id: id)!.centroid, home: id)
        #expect(d.placeName == "你附近")
        #expect(d.homeLabel(id) == "示意樓")
        #expect(testMap([box(1, 60, 0, name: "第五座")]).placeName(near: .zero) == "第五座", "底座里面的有名住宅楼照用")
    }

    @Test func 工厦货仓唔当住宅() {
        // 旺角：标 building=industrial 又有 12 层的工厦，以前当成"只标 yes 的住宅高楼"亮橙色。
        let factory = OSMParser.makeBuilding(id: 1, type: "industrial", tags: ["building": "industrial", "building:levels": "12"], name: nil, outline: rect(-10, -8, 10, 8))
        let tall = OSMParser.makeBuilding(id: 2, type: "yes", tags: ["building": "yes", "building:levels": "20"], name: nil, outline: rect(30, -8, 50, 8))
        let flat = OSMParser.makeBuilding(id: 3, type: "apartments", tags: ["building": "apartments"], name: nil, outline: rect(-50, 20, -30, 34))
        let v = testMap([factory, tall, flat]).pickView(near: .zero)
        #expect(v.buildings.contains { $0.id == 2 && $0.kind == .residential })
        #expect(v.buildings.contains { $0.id == 3 && $0.kind == .residential })
        #expect(!v.buildings.contains { $0.id == 1 && $0.kind == .residential }, "工厦唔畀揀")
    }

    @Test func 附近冇住宅楼就近放宽() {
        // 天水围：我在商场旁，住宅楼在 250 m 外。附近的一般建筑可以揀，不会只剩远处那几座。
        let m = testMap([box(1, 20, 10, kind: .commercial, height: 12), box(2, 250, 0)], size: 720)
        let v = m.pickView(near: .zero)
        #expect(v.size == MapModel.pickSize)
        #expect(v.buildings.contains { $0.id == 1 && $0.kind == .residential })
    }

    @Test func 附近乜都冇就睇最近嗰座() {
        // 附近 150 m 内一座楼都没有：不要退回整格（720 m 时楼细到点不到），看最近那座可选的楼一带。
        let m = testMap([box(1, 0, -10, kind: .small), box(2, 230, 40)], size: 720)
        let v = m.pickView(near: .zero)
        #expect(v.size == MapModel.pickSize)
        #expect(v.buildings.contains { $0.id == 2 && $0.kind == .residential })
    }

    @Test func 转咗向近格边嘅楼唔畀揀() {
        // 270 m：不转时只出界一条 10 m 窄边，可以；近格角、附近的楼斜 45°：底座转正后两个角各出界约 50 m，不给选。
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
        // 古洞村屋：我屋企和隔篱屋都没有名。我屋企叫"你屋企樓下"，隔篱叫"21座旁"，不再是"大堂""大堂（二）"。
        let d = testMap([box(1, 0, 0), box(2, 60, 0), box(3, 60, 30, name: "21座")], size: 200)
        let l = [Landmark(id: "lobby-1", name: "大堂", kind: .lobby, pos: Vec2(x: 0, y: -12), hasSeat: false),
                 Landmark(id: "lobby-2", name: "大堂", kind: .lobby, pos: Vec2(x: 60, y: -12), hasSeat: false),
                 Landmark(id: "lobby-3", name: "21座樓下", kind: .lobby, pos: Vec2(x: 60, y: 42), hasSeat: false)]
        #expect(LandmarkDeriver.uniqueNames(l, in: d, home: 1).map(\.name) == ["你屋企樓下", "21座旁", "21座樓下"])
    }

    @Test func 地标唔够用底座外嘅巴士站() {
        // 只有我屋企一座楼：楼下 1 个 + 底座外 40 m 的巴士站（放在底座边）+ 公园。
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

// 10-18 组员真机测试：香港 5G 拉唔到地图、「你喺呢度」、转动地图
@MainActor
struct MapFix18Tests {
    @Test func 服务器回覆要有资料先算() {
        #expect(MapService.endpoints.first == "https://overpass.openstreetmap.fr/api/interpreter", "实测最快嗰个排头")
        #expect(MapService.fetchTimeout >= 60, "overpass-api.de 繁忙时要 30 几秒")
        let ok = Data(("{\"version\":0.6,\"elements\":[{\"type\":\"node\",\"id\":1,\"lat\":22.3,\"lon\":114.1}]}" + String(repeating: " ", count: 200)).utf8)
        #expect(MapService.usable(ok))
        let empty = Data(("{\"version\":0.6,\"elements\":[]}" + String(repeating: " ", count: 300)).utf8)
        #expect(!MapService.usable(empty), "osm.ch 呢类只有本国资料，回空")
        let partial = Data(("{\"elements\":[{\"type\":\"way\"}],\"remark\":\"runtime error: Query timed out\"}" + String(repeating: " ", count: 200)).utf8)
        #expect(!MapService.usable(partial))
    }

    @Test func 你喺呢度位置同裁切后嘅底座对得上() {
        let full = MapService.fallback()
        let home = full.buildings.filter { $0.kind == .residential }.min { $0.centroid.length < $1.centroid.length }!
        let m = full.simplified(around: home.centroid, home: home.id)
        // 屋企楼中心嘅经纬度，放返落裁切后嘅底座，应该系屋企楼喺底座入面嘅中心
        let g = LocalProjection(origin: full.center).toGeo(home.centroid)
        let p = m.scenePoint(g), want = m.building(id: home.id)!.centroid
        #expect(p.distance(to: want) < 3, "\(p) vs \(want)")
    }

    @Test func 场景外嘅位置贴边写距离() {
        let c = DioramaController()
        var m = MapService.fallback()
        m = m.simplified(around: .zero)
        c.load(map: m, landmarks: [], animated: false)
        c.setHere(Vec2(x: 0, y: 0))
        c.setHere(Vec2(x: 1500, y: 0))
        #expect(HereText.distance(1500).contains("1.5"))
        #expect(HereText.distance(347).contains("350"))
    }
}
