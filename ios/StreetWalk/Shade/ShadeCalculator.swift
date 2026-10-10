import Foundation

/// 遮荫计算：从地标周围的采样点朝太阳射线，看有没有被楼宇棱柱挡住。
struct ShadeCalculator {
    struct Prism {
        var outline: [Vec2]
        var minHeight: Double
        var maxHeight: Double
        var bboxMin: Vec2
        var bboxMax: Vec2
    }

    let prisms: [Prism]
    let solidOutlines: [[Vec2]]

    init(map: MapModel) {
        prisms = map.buildings.map { b in
            let xs = b.outline.map(\.x), ys = b.outline.map(\.y)
            return Prism(outline: b.outline, minHeight: b.minHeight, maxHeight: b.height,
                         bboxMin: Vec2(x: xs.min()!, y: ys.min()!), bboxMax: Vec2(x: xs.max()!, y: ys.max()!))
        }
        solidOutlines = map.buildings.filter { $0.kind != .canopy }.map(\.outline)
    }

    /// 采样点：中心 + 4 m 一圈 6 个 + 8 m 一圈 12 个，落在楼里的跳过。
    func samplePoints(around c: Vec2) -> [Vec2] {
        var pts = [c]
        for k in 0..<6 { let a = Double(k) * .pi / 3; pts.append(c + Vec2(x: cos(a), y: sin(a)) * 4) }
        for k in 0..<12 { let a = Double(k) * .pi / 6 + .pi / 12; pts.append(c + Vec2(x: cos(a), y: sin(a)) * 8) }
        return pts.filter { p in !solidOutlines.contains { Polygon.contains($0, p) } }
    }

    /// 遮荫比例 0–1。太阳低于 2° 当作全阴（只用于排序；文案要分开讲"日落"，见 ShadeService.isSunUp）。
    func shade(at c: Vec2, sun: SolarPosition) -> Double {
        guard sun.elevation > 2 else { return 1 }
        let pts = samplePoints(around: c)
        guard !pts.isEmpty else { return 1 }
        let blocked = pts.filter { isShaded($0, sun: sun) }.count
        return Double(blocked) / Double(pts.count)
    }

    func isShaded(_ p: Vec2, sun: SolarPosition, eyeHeight: Double = 1.2) -> Bool {
        let d = sun.direction
        let dir = Vec2(x: d.east, y: d.north).normalized
        let slope = tan(sun.elevation * .pi / 180)
        // 太阳越高，能挡住的楼越近；最远只看 400 m。
        let reach = min(400, (prisms.map(\.maxHeight).max() ?? 0) / max(slope, 0.01) + 10)
        let end = p + dir * reach
        let segMin = Vec2(x: min(p.x, end.x), y: min(p.y, end.y)), segMax = Vec2(x: max(p.x, end.x), y: max(p.y, end.y))

        for prism in prisms {
            if prism.bboxMax.x < segMin.x || prism.bboxMin.x > segMax.x || prism.bboxMax.y < segMin.y || prism.bboxMin.y > segMax.y { continue }
            let ts = crossings(from: p, dir: dir, polygon: prism.outline).filter { $0 > 0 }.sorted()
            var i = 0
            while i + 1 < ts.count {
                let hIn = eyeHeight + ts[i] * slope, hOut = eyeHeight + ts[i + 1] * slope
                if hIn <= prism.maxHeight && hOut >= prism.minHeight { return true }
                i += 2
            }
        }
        return false
    }

    /// 射线 p + t·dir 与多边形各边的交点参数 t。
    private func crossings(from p: Vec2, dir: Vec2, polygon: [Vec2]) -> [Double] {
        var ts: [Double] = []
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let e = b - a
            let denom = dir.cross(e)
            if abs(denom) < 1e-12 { continue }
            let ap = a - p
            let t = ap.cross(e) / denom
            let u = ap.cross(dir) / denom
            if u >= 0 && u < 1 { ts.append(t) }
        }
        return ts
    }
}
