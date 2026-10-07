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
var worstClear = Double.infinity, maxGreen = 0.0, names: Set<String> = []
for h in map.buildings where h.kind == .residential {
    let d = map.simplified(around: h.centroid, home: h.id)
    names.insert(d.placeName)
    maxGreen = max(maxGreen, d.areas.map { Polygon.area($0.outline) / (d.size * d.size) }.max() ?? 0)
    for c in LandmarkDeriver.settle(LandmarkDeriver.pick(LandmarkDeriver.candidates(in: d)), in: d) {
        worstClear = min(worstClear, d.buildings.map { LandmarkDeriver.distance(from: c.pos, to: $0.outline) }.min() ?? .infinity)
    }
}
check(names == ["皇后山邨"], "裁切后地名沿用整格：\(names.sorted())")
check(maxGreen <= 0.2001, "单块绿地最多占底座 \(Int(maxGreen * 100))%")
check(worstClear >= 7.9, "地标离楼最近 \(String(format: "%.1f", worstClear)) m")
let pickView = map.pickView(near: .zero)
check(pickView.buildings.filter { $0.kind == .residential }.count <= 10 && pickView.buildings.filter { $0.kind != .residential }.count <= 3,
      "选楼画面 \(pickView.buildings.count) 座楼（住宅 \(pickView.buildings.filter { $0.kind == .residential }.count)）")
// 站在每座住宅楼：自己那座一定选得到；没有位置时整格的住宅楼都选得到。
let allHomes = map.simplified(around: .zero, size: map.size, maxBuildings: nil).buildings.filter { $0.kind == .residential }.map(\.id)
let missing = allHomes.filter { id in !map.pickView(near: map.building(id: id)!.centroid).buildings.contains { $0.id == id } }
check(missing.isEmpty, "站在 \(allHomes.count) 座住宅楼，自己那座都在选楼画面（漏 \(missing.count)）")
let noLoc = Set(map.pickView(near: nil).buildings.map(\.id))
check(allHomes.allSatisfy(noLoc.contains), "没有位置时 \(allHomes.count) 座住宅楼都选得到（\(allHomes.filter(noLoc.contains).count) 座）")

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
