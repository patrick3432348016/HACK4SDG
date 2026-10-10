import Foundation

// 不依赖模拟器的核心逻辑自测：在 Mac 上用 swiftc 编译运行（见 tools/selftest.sh）。
var failures = 0
func check(_ ok: Bool, _ msg: String) {
    print(ok ? "  ok  \(msg)" : "  FAIL \(msg)")
    if !ok { failures += 1 }
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])

print("TileKey")
let qh = GeoPoint(lat: 22.5044, lon: 114.1563)
check(TileKey.snap(qh) == TileKey(ix: 0, iy: 0), "皇后山邨落在 0_0 格")
check(TileKey.snap(GeoPoint(lat: 22.3193, lon: 114.1694)) != TileKey(ix: 0, iy: 0), "旺角是另一格")
check(TileKey(ix: 0, iy: 0).bboxString == "22.5018715,114.1535787,22.5069285,114.1590213", "bbox 与兜底数据一致：\(TileKey(ix: 0, iy: 0).bboxString)")

print("OSMParser")
let data = try Data(contentsOf: root.appendingPathComponent("StreetWalk/Resources/fallback_queenshill.json"))
let t0 = Date()
let map = try OSMParser.parse(data, tile: TileKey(ix: 0, iy: 0), source: "test")
print("     解析耗时 \(Int(Date().timeIntervalSince(t0) * 1000)) ms；楼 \(map.buildings.count)、路 \(map.roads.count)、面 \(map.areas.count)、点 \(map.pois.count)、树 \(map.trees.count)；地名 \(map.placeName)")
let towers = map.buildings.filter { $0.kind == .residential && ($0.name ?? "").hasPrefix("皇") && $0.name!.hasSuffix("樓") }
check(towers.count >= 7, "皇X樓 \(towers.count) 座")
check(towers.allSatisfy { $0.height >= 120 }, "塔楼高度 \(towers.first.map { Int($0.height) } ?? 0) m")
check(map.buildings.allSatisfy { $0.outline.allSatisfy { abs($0.x) <= 280.01 && abs($0.y) <= 280.01 } }, "全部裁剪在底座内")
check(map.roads.count > 50, "道路 \(map.roads.count) 段")
check(map.placeName == "皇后山邨", "地名 \(map.placeName)")
for k in AreaKind.allCases { let n = map.areas.filter { $0.kind == k }.count; if n > 0 { print("     面 \(k): \(n)") } }

print("Landmarks")
let cands = LandmarkDeriver.candidates(in: map)
let picked = LandmarkDeriver.pick(cands)
for c in picked { print("     \(c.kind) \(c.osmName ?? "-") (\(Int(c.pos.x)), \(Int(c.pos.y))) 座位:\(c.hasSeat)") }
check((3...4).contains(picked.count), "选出 \(picked.count) 个地标（做减法后最多 4 个）")
var minGap = Double.infinity
for i in 0..<picked.count { for j in (i + 1)..<picked.count { minGap = min(minGap, picked[i].pos.distance(to: picked[j].pos)) } }
check(minGap >= 30, "最小间隔 \(Int(minGap)) m")

print("Diorama")
var worstClear = Double.infinity, maxGreen = 0.0, wrongNames: [String] = [], dropped = 0, fewLandmarks = 0
let estates = map.areas.filter { $0.kind == .residential && $0.name != nil }
for h in map.buildings where h.kind == .residential {
    let d = map.simplified(around: h.centroid, home: h.id)
    // 地名：屋企所在的屋苑（住宅用地）名，否则是整个邨名。
    let expected = estates.first { Polygon.contains($0.outline, h.centroid) }?.name ?? "皇后山邨"
    if d.placeName != expected { wrongNames.append("\(h.name ?? "#\(h.id)")→\(d.placeName)") }
    if !d.buildings.contains(where: { $0.id == h.id }) { dropped += 1 }
    maxGreen = max(maxGreen, d.areas.map { Polygon.area($0.outline) / (d.size * d.size) }.max() ?? 0)
    let lms = LandmarkDeriver.derive(in: d, home: h.id)
    if lms.count < 3 || Set(lms.map(\.id)).count != lms.count { fewLandmarks += 1 }
    for c in lms {
        worstClear = min(worstClear, d.buildings.map { LandmarkDeriver.distance(from: c.pos, to: $0.outline) }.min() ?? .infinity)
    }
}
check(wrongNames.isEmpty, "底座地名用屋企所在屋苑 / 邨名（错 \(wrongNames)）")
check(dropped == 0, "每座住宅楼做屋企时都留喺底座（漏 \(dropped)）")
check(fewLandmarks == 0, "每个底座都有 3 个以上、id 唔重复嘅地标（唔够 \(fewLandmarks)）")
check(maxGreen <= 0.2001, "单块绿地最多占底座 \(Int(maxGreen * 100))%")
check(worstClear >= 7.9, "地标离楼最近 \(String(format: "%.1f", worstClear)) m")
let pickView = map.pickView(near: .zero)
check(pickView.buildings.filter { $0.kind == .residential }.count <= 10 && pickView.buildings.filter { $0.kind != .residential }.count <= 3,
      "选楼画面 \(pickView.buildings.count) 座楼（住宅 \(pickView.buildings.filter { $0.kind == .residential }.count)）")
// 站在每座住宅楼：自己那座一定选得到；没有位置时整格的住宅楼都选得到（离格心太远、底座会出界的除外）。
let allHomes = map.simplified(around: .zero, size: map.size, maxBuildings: nil).buildings
    .filter { $0.kind == .residential && map.dioramaFits(at: map.building(id: $0.id)!.centroid) }.map(\.id)
let missing = allHomes.filter { id in !map.pickView(near: map.building(id: id)!.centroid).buildings.contains { $0.id == id && $0.kind == .residential } }
check(missing.isEmpty, "站在 \(allHomes.count) 座住宅楼，自己那座都可以揀（漏 \(missing.count)）")
let noLoc = Set(map.pickView(near: nil).buildings.filter { $0.kind == .residential }.map(\.id))
check(allHomes.allSatisfy(noLoc.contains), "没有位置时 \(allHomes.count) 座住宅楼都选得到（\(allHomes.filter(noLoc.contains).count) 座）")
// 每座可选的楼，做屋企时都要留在底座（A26：转正角度不同也不能漏）。
let pickable = map.pickView(near: nil).buildings.filter { $0.kind == .residential }.map(\.id)
let lost = pickable.filter { id in !map.simplified(around: map.building(id: id)!.centroid, home: id).buildings.contains { $0.id == id } }
check(lost.isEmpty, "\(pickable.count) 座可揀的楼做屋企都留喺底座（漏 \(lost.count)）")

// 实时拉到的格子（STREETWALK_TILES=放 v1/、v2/ 缓存的目录）：每座可揀的楼做屋企，地名、地标都要合理。
if let dir = ProcessInfo.processInfo.environment["STREETWALK_TILES"] {
    print("Live tiles")
    func name(_ c: LandmarkCandidate) -> String {   // 只模仿模板 AI 的楼下命名（没名叫"大堂"），其他用类型
        c.kind == .lobby ? (c.osmName.map { "\($0)樓下" } ?? "大堂") : (c.osmName ?? c.kind.rawValue)
    }
    for (v, size) in [("v2", 720.0), ("v1", TileKey.plinthSize)] {
        let d = URL(fileURLWithPath: dir).appendingPathComponent(v)
        for f in ((try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []).sorted() where f.hasSuffix(".json") {
            let k = f.dropLast(5).split(separator: "_").compactMap { Int($0) }
            guard k.count == 2, let data = try? Data(contentsOf: d.appendingPathComponent(f)),
                  let m = try? OSMParser.parse(data, tile: TileKey(ix: k[0], iy: k[1]), size: size, source: "live") else { continue }
            var homes = m.pickView(near: nil).buildings.filter { $0.kind == .residential }.map(\.id)
            var full = m
            if homes.isEmpty { let r = m.addingPlaceholderHome(at: .zero); full = r.map; homes = [r.id] }
            var bad: [String] = []
            for h in homes {
                let dm = full.simplified(around: full.building(id: h)!.centroid, home: h)
                let lms = LandmarkDeriver.derive(in: dm, home: h).map { Landmark(id: $0.id, name: name($0), kind: $0.kind, pos: $0.pos, hasSeat: $0.hasSeat) }
                let named = LandmarkDeriver.uniqueNames(lms, in: dm, home: h).map(\.name)
                let label = "\(full.homeLabel(h) ?? "#\(h)")@\(dm.placeName)"
                if named.count < 3 || Set(named).count != named.count || named.contains(where: { $0.hasPrefix("大堂") }) { bad.append("\(label) \(named)") }
                // 地名只用底座里的有名住宅楼（示意楼不借 180 m 外的"第五座"）
                if let b = dm.buildings.first(where: { $0.name == dm.placeName }), b.kind == .residential,
                   max(abs(b.centroid.x), abs(b.centroid.y)) > MapModel.dioramaSize / 2 + 1 { bad.append("\(label) 地名用底座外的楼") }
            }
            check(bad.isEmpty, "\(v)/\(f)：\(homes.count) 座可揀，地标 ≥3、唔撞名、冇「大堂」\(bad.isEmpty ? "" : "（\(bad.prefix(3))）")")
        }
    }
} else {
    print("Live tiles（未设 STREETWALK_TILES，跳过）")
}

print("SolarPosition")
func hk(_ s: String) -> Date { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = SolarPosition.hongKong; return f.date(from: s)! }
let jun = SolarPosition.at(hk("2026-06-21 12:25"), lat: 22.5044, lon: 114.1563)
check(abs(jun.elevation - 89) < 1.5, "夏至正午高度 \(String(format: "%.1f", jun.elevation))°")
let dec = SolarPosition.at(hk("2026-12-21 12:21"), lat: 22.5044, lon: 114.1563)
check(abs(dec.elevation - 44) < 1.5 && abs(dec.azimuth - 180) < 3, "冬至正午高度 \(String(format: "%.1f", dec.elevation))°，方位 \(String(format: "%.1f", dec.azimuth))°")
let morning = SolarPosition.at(hk("2026-10-06 09:00"), lat: 22.5044, lon: 114.1563)
let afternoon = SolarPosition.at(hk("2026-10-06 15:00"), lat: 22.5044, lon: 114.1563)
check(morning.azimuth < 180 && afternoon.azimuth > 180, "上午偏东 \(Int(morning.azimuth))°，下午偏西 \(Int(afternoon.azimuth))°")

print("ShadeCalculator")
let box = Building(id: 1, name: nil, outline: [Vec2(x: -10, y: -20), Vec2(x: 10, y: -20), Vec2(x: 10, y: -10), Vec2(x: -10, y: -10)], minHeight: 0, height: 30, levels: 10, kind: .other)
let testMap = MapModel(tile: TileKey(ix: 0, iy: 0), center: qh, size: 560, buildings: [box], roads: [], areas: [], pois: [], trees: [], fetchedAt: Date(), source: "t")
let calc = ShadeCalculator(map: testMap)
check(calc.isShaded(Vec2(x: 0, y: 0), sun: dec), "冬至正午，南面 10 m 外 30 m 高的楼挡住太阳")
check(!calc.isShaded(Vec2(x: 0, y: -40), sun: dec), "楼的南边晒到")
check(!calc.isShaded(Vec2(x: 0, y: 0), sun: jun), "夏至正午太阳几乎直射，不被挡")
let realCalc = ShadeCalculator(map: map)
let t1 = Date()
for c in picked {
    let am = realCalc.shade(at: c.pos, sun: morning), pm = realCalc.shade(at: c.pos, sun: afternoon)
    print("     \(c.osmName ?? c.kind.rawValue)：9 點遮蔭 \(Int(am * 100))%，3 點 \(Int(pm * 100))%")
}
print("     遮荫计算耗时 \(Int(Date().timeIntervalSince(t1) * 1000)) ms")

print("PathGrid")
let grid = PathGrid(map: map)
let t2 = Date()
let a = grid.nearestWalkable(picked[0].pos), b = grid.nearestWalkable(picked[picked.count - 1].pos)
let path = grid.path(from: a, to: b)
print("     寻路耗时 \(Int(Date().timeIntervalSince(t2) * 1000)) ms，\(path.count) 点，长 \(Int(grid.length(of: path))) m，直线 \(Int(a.distance(to: b))) m")
check(path.count >= 2 && grid.length(of: path) >= a.distance(to: b) - 1, "路线不短于直线")
let insideCount = path.filter { map.isInsideBuilding($0) }.count
check(insideCount <= 1, "路线不穿楼（落在楼里的点 \(insideCount) 个）")

print("MapModel.scenePoint")
let home = map.buildings.first { $0.kind == .residential && $0.name != nil }!
let small = map.simplified(around: home.centroid, home: home.id)
let fullProj = LocalProjection(origin: map.center)
var worst = 0.0
for p in small.pois {
    guard let orig = map.pois.first(where: { $0.id == p.id }) else { continue }
    worst = max(worst, small.scenePoint(fullProj.toGeo(orig.pos)).distance(to: p.pos))
}
check(!small.pois.isEmpty && worst < 1, "经纬度换算到转正后的场景坐标，误差 \(String(format: "%.2f", worst)) m（\(small.pois.count) 个点，转 \(Int(small.rotation * 180 / .pi))°）")

print("HKOReport")
let rhrText = """
{"temperature":{"data":[{"place":"京士柏","value":30},{"place":"打鼓嶺","value":34},{"place":"香港天文台","value":31}]},
 "rainfall":{"data":[{"place":"北區","max":0,"main":"FALSE"},{"place":"油尖旺","max":12,"main":"FALSE"}]},
 "icon":[50],"updateTime":"2026-10-07T13:02:00+08:00"}
"""
let rhr = rhrText.data(using: .utf8)!
let warnHot = #"{"WHOT":{"name":"酷熱天氣警告","code":"WHOT","actionCode":"ISSUE"},"WFIRE":{"name":"火災危險警告","code":"WFIRER","type":"紅色","actionCode":"ISSUE"}}"#.data(using: .utf8)!
let warnRain = #"{"WRAIN":{"name":"暴雨警告信號","code":"WRAINA","type":"黃色","actionCode":"ISSUE"}}"#.data(using: .utf8)!
let fnd = #"{"weatherForecast":[{"forecastDate":"20261008","PSR":"低","forecastMaxtemp":{"value":30}}]}"#.data(using: .utf8)!
let today = hk("2026-10-07 13:00")
let hot = HKOReport.parse(rhrread: rhr, warnsum: warnHot, fnd: fnd, near: qh, today: today)
check(hot?.station == "打鼓嶺" && hot?.temperature == 34, "皇后山邨用最近测站打鼓嶺：\(hot?.station ?? "-") \(hot?.temperature ?? 0) 度")
check(hot?.rainMM == 0, "雨量用最近分区北區（油尖旺落雨不算）")
check(hot?.isHot == true && hot?.isRain == false, "酷熱警告 → 熱")
check(hot?.tomorrowPSR == "低" && hot?.todayPSR == nil, "九天预报从聽日开始，今日冇")
check(hot?.line == "天文台話打鼓嶺而家 34 度，酷熱天氣警告生效。", "句子：\(hot?.line ?? "")")
let rain = HKOReport.parse(rhrread: rhr, warnsum: warnRain, fnd: nil, near: GeoPoint(lat: 22.300, lon: 114.175), today: today)
check(rain?.isRain == true && rain?.station == "香港天文台", "黃雨 → 落雨；尖沙咀附近用天文台站")
check(rain?.line == "天文台話而家 31 度，黃色暴雨警告信號生效。", "句子：\(rain?.line ?? "")")
let warnTC = #"{"WTCSGNL":{"name":"熱帶氣旋警告信號","code":"TC8NE","actionCode":"ISSUE"},"WL":{"name":"山泥傾瀉警告","code":"WL","actionCode":"ISSUE"}}"#.data(using: .utf8)!
let tc = HKOReport.parse(rhrread: rhr, warnsum: warnTC, fnd: nil, near: qh, today: today)
check(tc?.isDanger == true && tc?.isRain == true, "八號風球 / 山泥 → 唔好出門")
check(tc?.line == "天文台話打鼓嶺而家 34 度，八號烈風或暴風信號、山泥傾瀉警告生效。", "句子：\(tc?.line ?? "")")
let drizzle = HKOReport.parse(rhrread: Data(rhrText.replacingOccurrences(of: "[50]", with: "[62]").utf8), warnsum: nil, fnd: nil, near: qh, today: today)
check(drizzle?.isRain == false, "全港微雨圖標 62 唔算落雨")
let showers = HKOReport.parse(rhrread: Data(rhrText.replacingOccurrences(of: "[50]", with: "[63]").utf8), warnsum: nil, fnd: nil, near: qh, today: today)
check(showers?.isRain == true && showers?.line == "天文台話打鼓嶺而家 34 度，有雨。", "雨圖標 63 → 落雨，句子要講有雨：\(showers?.line ?? "")")
check(HKOReport.parse(rhrread: Data("oops".utf8), warnsum: nil, fnd: nil, near: qh, today: today) == nil, "坏数据 → 冇天气（唔會編）")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
