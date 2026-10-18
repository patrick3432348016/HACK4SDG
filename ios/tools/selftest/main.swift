import Foundation

// Simulator-free core tests compiled with swiftc on Mac; see tools/selftest.sh.
var failures = 0
func check(_ ok: Bool, _ msg: String) {
    print(ok ? "  ok  \(msg)" : "  FAIL \(msg)")
    if !ok { failures += 1 }
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])

print("TileKey")
let qh = GeoPoint(lat: 22.5044, lon: 114.1563)
check(TileKey.snap(qh) == TileKey(ix: 0, iy: 0), "Queen's Hill Estate is in tile 0_0")
check(TileKey.snap(GeoPoint(lat: 22.3193, lon: 114.1694)) != TileKey(ix: 0, iy: 0), "Mong Kok is in a different tile")
check(TileKey(ix: 0, iy: 0).bboxString == "22.5018715,114.1535787,22.5069285,114.1590213", "bbox matches fallback data: \(TileKey(ix: 0, iy: 0).bboxString)")

print("OSMParser")
let data = try Data(contentsOf: root.appendingPathComponent("StreetWalk/Resources/fallback_queenshill.json"))
let t0 = Date()
let map = try OSMParser.parse(data, tile: TileKey(ix: 0, iy: 0), source: "test")
print("     Parsing took \(Int(Date().timeIntervalSince(t0) * 1000)) ms; buildings \(map.buildings.count), roads \(map.roads.count), areas \(map.areas.count), POIs \(map.pois.count), trees \(map.trees.count)；Place name: \(map.placeName)")
let towers = map.buildings.filter { $0.kind == .residential && ($0.name ?? "").hasPrefix("皇") && $0.name!.hasSuffix("樓") }
check(towers.count >= 7, "Queen's Hill residential towers: \(towers.count)")
check(towers.allSatisfy { $0.height >= 120 }, "Tower height: \(towers.first.map { Int($0.height) } ?? 0) m")
check(map.buildings.allSatisfy { $0.outline.allSatisfy { abs($0.x) <= 280.01 && abs($0.y) <= 280.01 } }, "All geometry is clipped to the diorama base")
check(map.roads.count > 50, "Road segments: \(map.roads.count)")
check(map.placeName == "皇后山邨", "Place name: \(map.placeName)")
for k in AreaKind.allCases { let n = map.areas.filter { $0.kind == k }.count; if n > 0 { print("     Area \(k): \(n)") } }

print("Landmarks")
let cands = LandmarkDeriver.candidates(in: map)
let picked = LandmarkDeriver.pick(cands)
for c in picked { print("     \(c.kind) \(c.osmName ?? "-") (\(Int(c.pos.x)), \(Int(c.pos.y))) seats:\(c.hasSeat)") }
check((3...4).contains(picked.count), "Selected \(picked.count) landmarks (maximum four after reduction)")
var minGap = Double.infinity
for i in 0..<picked.count { for j in (i + 1)..<picked.count { minGap = min(minGap, picked[i].pos.distance(to: picked[j].pos)) } }
check(minGap >= 30, "Minimum spacing: \(Int(minGap)) m")

print("Diorama")
var worstClear = Double.infinity, maxGreen = 0.0, wrongNames: [String] = [], dropped = 0, fewLandmarks = 0
let estates = map.areas.filter { $0.kind == .residential && $0.name != nil }
for h in map.buildings where h.kind == .residential {
    let d = map.simplified(around: h.centroid, home: h.id)
    // Use the home's residential estate name, otherwise the wider estate name.
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
check(wrongNames.isEmpty, "Base uses the home estate name (errors: \(wrongNames))")
check(dropped == 0, "Every selected residential home remains on the base (missing: \(dropped))")
check(fewLandmarks == 0, "Every base has at least three landmarks with unique IDs (insufficient: \(fewLandmarks))")
check(maxGreen <= 0.2001, "Largest green area occupies at most \(Int(maxGreen * 100))%")
check(worstClear >= 7.9, "Nearest landmark-to-building clearance: \(String(format: "%.1f", worstClear)) m")
let pickView = map.pickView(near: .zero)
check(pickView.buildings.filter { $0.kind == .residential }.count <= 10 && pickView.buildings.filter { $0.kind != .residential }.count <= 3,
      "Building picker: \(pickView.buildings.count) buildings (residential: \(pickView.buildings.filter { $0.kind == .residential }.count))")
// At every residence, its own building must be selectable; without location allow tile residences except unsafe edge crops.
let allHomes = map.simplified(around: .zero, size: map.size, maxBuildings: nil).buildings
    .filter { $0.kind == .residential && map.dioramaFits(at: map.building(id: $0.id)!.centroid) }.map(\.id)
let missing = allHomes.filter { id in !map.pickView(near: map.building(id: id)!.centroid).buildings.contains { $0.id == id && $0.kind == .residential } }
check(missing.isEmpty, "Home is selectable from all \(allHomes.count) residential positions (missing: \(missing.count))")
let noLoc = Set(map.pickView(near: nil).buildings.filter { $0.kind == .residential }.map(\.id))
check(allHomes.allSatisfy(noLoc.contains), "Without location, all \(allHomes.count) residential buildings are selectable (available: \(allHomes.filter(noLoc.contains).count))")
// A26: retain every selected home in the base under all alignment rotations.
let pickable = map.pickView(near: nil).buildings.filter { $0.kind == .residential }.map(\.id)
let lost = pickable.filter { id in !map.simplified(around: map.building(id: id)!.centroid, home: id).buildings.contains { $0.id == id } }
check(lost.isEmpty, "All \(pickable.count) selectable homes remain on the base (missing: \(lost.count))")

// For STREETWALK_TILES real caches, inspect estate names and landmarks with every selectable building as home.
if let dir = ProcessInfo.processInfo.environment["STREETWALK_TILES"] {
    print("Live tiles")
    func name(_ c: LandmarkCandidate) -> String {   // Approximate only TemplateAI's entrance naming, using a generic lobby for unnamed buildings and type names otherwise.
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
                // Estate naming uses named residences inside the base, not a distant building beside a placeholder.
                if let b = dm.buildings.first(where: { $0.name == dm.placeName }), b.kind == .residential,
                   max(abs(b.centroid.x), abs(b.centroid.y)) > MapModel.dioramaSize / 2 + 1 { bad.append("\(label) place name uses a building outside the base") }
            }
            check(bad.isEmpty, "\(v)/\(f): \(homes.count) selectable homes; at least three uniquely named landmarks without generic lobby names\(bad.isEmpty ? "" : " (\(bad.prefix(3)))")")
        }
    }
} else {
    print("Live tiles skipped: STREETWALK_TILES is unset")
}

print("SolarPosition")
func hk(_ s: String) -> Date { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = SolarPosition.hongKong; return f.date(from: s)! }
let jun = SolarPosition.at(hk("2026-06-21 12:25"), lat: 22.5044, lon: 114.1563)
check(abs(jun.elevation - 89) < 1.5, "Summer-solstice noon elevation: \(String(format: "%.1f", jun.elevation))°")
let dec = SolarPosition.at(hk("2026-12-21 12:21"), lat: 22.5044, lon: 114.1563)
check(abs(dec.elevation - 44) < 1.5 && abs(dec.azimuth - 180) < 3, "Winter-solstice noon elevation: \(String(format: "%.1f", dec.elevation)) degrees; azimuth \(String(format: "%.1f", dec.azimuth))°")
let morning = SolarPosition.at(hk("2026-10-06 09:00"), lat: 22.5044, lon: 114.1563)
let afternoon = SolarPosition.at(hk("2026-10-06 15:00"), lat: 22.5044, lon: 114.1563)
check(morning.azimuth < 180 && afternoon.azimuth > 180, "Morning eastward azimuth \(Int(morning.azimuth)) degrees; afternoon westward azimuth \(Int(afternoon.azimuth))°")

print("ShadeCalculator")
let box = Building(id: 1, name: nil, outline: [Vec2(x: -10, y: -20), Vec2(x: 10, y: -20), Vec2(x: 10, y: -10), Vec2(x: -10, y: -10)], minHeight: 0, height: 30, levels: 10, kind: .other)
let testMap = MapModel(tile: TileKey(ix: 0, iy: 0), center: qh, size: 560, buildings: [box], roads: [], areas: [], pois: [], trees: [], fetchedAt: Date(), source: "t")
let calc = ShadeCalculator(map: testMap)
check(calc.isShaded(Vec2(x: 0, y: 0), sun: dec), "A 30 m building 10 m south blocks winter-solstice noon sunlight")
check(!calc.isShaded(Vec2(x: 0, y: -40), sun: dec), "The south side of the building is sunlit")
check(!calc.isShaded(Vec2(x: 0, y: 0), sun: jun), "Near-overhead summer-solstice noon sunlight is unblocked")
let realCalc = ShadeCalculator(map: map)
let t1 = Date()
for c in picked {
    let am = realCalc.shade(at: c.pos, sun: morning), pm = realCalc.shade(at: c.pos, sun: afternoon)
    print("     \(c.osmName ?? c.kind.rawValue): shade at 9 am \(Int(am * 100))%, at 3 pm \(Int(pm * 100))%")
}
print("     Shade calculation took \(Int(Date().timeIntervalSince(t1) * 1000)) ms")

print("PathGrid")
let grid = PathGrid(map: map)
let t2 = Date()
let a = grid.nearestWalkable(picked[0].pos), b = grid.nearestWalkable(picked[picked.count - 1].pos)
let path = grid.path(from: a, to: b)
print("     Pathfinding took \(Int(Date().timeIntervalSince(t2) * 1000)) ms; \(path.count) points; length \(Int(grid.length(of: path))) m; straight-line \(Int(a.distance(to: b))) m")
check(path.count >= 2 && grid.length(of: path) >= a.distance(to: b) - 1, "Route is no shorter than the straight line")
let insideCount = path.filter { map.isInsideBuilding($0) }.count
check(insideCount <= 1, "Route avoids buildings (points inside: \(insideCount))")

print("MapModel.scenePoint")
let home = map.buildings.first { $0.kind == .residential && $0.name != nil }!
let small = map.simplified(around: home.centroid, home: home.id)
let fullProj = LocalProjection(origin: map.center)
var worst = 0.0
for p in small.pois {
    guard let orig = map.pois.first(where: { $0.id == p.id }) else { continue }
    worst = max(worst, small.scenePoint(fullProj.toGeo(orig.pos)).distance(to: p.pos))
}
check(!small.pois.isEmpty && worst < 1, "Geographic-to-rotated-scene conversion error: \(String(format: "%.2f", worst)) m (\(small.pois.count) points; rotation \(Int(small.rotation * 180 / .pi)) degrees)")

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
check(hot?.station == "打鼓嶺" && hot?.temperature == 34, "Queen's Hill uses nearby Ta Kwu Ling station: \(hot?.station ?? "-") \(hot?.temperature ?? 0) degrees")
check(hot?.rainMM == 0, "Rainfall uses nearby North District, excluding Yau Tsim Mong rain")
check(hot?.isHot == true && hot?.isRain == false, "Very Hot Weather Warning maps to hot")
check(hot?.tomorrowPSR == "低" && hot?.todayPSR == nil, "Nine-day forecast starts tomorrow, without today")
check(hot?.line == "天文台話打鼓嶺而家 34 度，酷熱天氣警告生效。", "Sentence: \(hot?.line ?? "")")
let rain = HKOReport.parse(rhrread: rhr, warnsum: warnRain, fnd: nil, near: GeoPoint(lat: 22.300, lon: 114.175), today: today)
check(rain?.isRain == true && rain?.station == "香港天文台", "Amber rain maps to rain; Tsim Sha Tsui uses the Observatory station")
check(rain?.line == "天文台話而家 31 度，黃色暴雨警告信號生效。", "Sentence: \(rain?.line ?? "")")
let warnTC = #"{"WTCSGNL":{"name":"熱帶氣旋警告信號","code":"TC8NE","actionCode":"ISSUE"},"WL":{"name":"山泥傾瀉警告","code":"WL","actionCode":"ISSUE"}}"#.data(using: .utf8)!
let tc = HKOReport.parse(rhrread: rhr, warnsum: warnTC, fnd: nil, near: qh, today: today)
check(tc?.isDanger == true && tc?.isRain == true, "Signal 8 and landslip warnings map to avoiding outings")
check(tc?.line == "天文台話打鼓嶺而家 34 度，八號烈風或暴風信號、山泥傾瀉警告生效。", "Sentence: \(tc?.line ?? "")")
let drizzle = HKOReport.parse(rhrread: Data(rhrText.replacingOccurrences(of: "[50]", with: "[62]").utf8), warnsum: nil, fnd: nil, near: qh, today: today)
check(drizzle?.isRain == false, "Hong Kong-wide light-rain icon 62 does not trigger rain")
let showers = HKOReport.parse(rhrread: Data(rhrText.replacingOccurrences(of: "[50]", with: "[63]").utf8), warnsum: nil, fnd: nil, near: qh, today: today)
check(showers?.isRain == true && showers?.line == "天文台話打鼓嶺而家 34 度，有雨。", "Rain icon 63 triggers rain and a rain statement: \(showers?.line ?? "")")
check(HKOReport.parse(rhrread: Data("oops".utf8), warnsum: nil, fnd: nil, near: qh, today: today) == nil, "Invalid data returns no weather, without fabrication")

print("Weather outside Hong Kong (Open-Meteo)")
check(HongKongArea.contains(qh), "Queen's Hill Estate is in Hong Kong")
check(HongKongArea.contains(GeoPoint(lat: 22.505, lon: 114.07)), "Lok Ma Chau on the Hong Kong side is in Hong Kong")
check(!HongKongArea.contains(GeoPoint(lat: 22.566, lon: 114.046)), "Shenzhen Meilin is outside Hong Kong")
check(!HongKongArea.contains(GeoPoint(lat: 22.48, lon: 113.91)), "Shenzhen Shekou is outside Hong Kong despite its lower latitude")
check(!HongKongArea.contains(GeoPoint(lat: 22.54, lon: 114.05)), "Shenzhen Futian is outside Hong Kong")
check(OpenMeteo.url(near: GeoPoint(lat: 22.5661, lon: 114.0463))?.absoluteString.contains("latitude=22.6&longitude=114.0") == true, "Send only a coarsely rounded location, approximately 10 km")
let om = #"{"utc_offset_seconds":28800,"current":{"time":"2026-10-10T17:00","temperature_2m":33.6,"precipitation":0.0,"weather_code":2},"daily":{"temperature_2m_max":[34.2,31.0],"precipitation_probability_max":[15,65]}}"#.data(using: .utf8)!
let sz = HKOReport.parseOpenMeteo(om)
check(sz?.temperature == 34 && sz?.todayMax == 34 && sz?.isHot == true && sz?.isRain == false, "Shenzhen at 34 degrees maps to hot")
check(sz?.todayPSR == "低" && sz?.tomorrowPSR == "中高", "Rain probabilities: 15% maps to low; 65% to medium-high")
check(sz?.line == "天氣預報話而家 34 度。", "Do not misattribute this forecast to HKO: \(sz?.line ?? "")")
let omRain = HKOReport.parseOpenMeteo(Data(String(data: om, encoding: .utf8)!.replacingOccurrences(of: "\"weather_code\":2", with: "\"weather_code\":95").utf8))
check(omRain?.isRain == true, "Thunderstorm code 95 maps to rain")
check(HKOReport.parseOpenMeteo(Data("{}".utf8)) == nil, "Invalid data returns no weather")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
