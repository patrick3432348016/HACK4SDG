import Foundation

/// 平面多边形工具：面积、方向、包含测试、裁剪、三角化。
enum Polygon {
    /// 有向面积，逆时针为正。
    static func signedArea(_ p: [Vec2]) -> Double {
        guard p.count >= 3 else { return 0 }
        var a = 0.0
        for i in 0..<p.count {
            let j = (i + 1) % p.count
            a += p[i].x * p[j].y - p[j].x * p[i].y
        }
        return a / 2
    }

    static func area(_ p: [Vec2]) -> Double { abs(signedArea(p)) }

    static func centroid(_ p: [Vec2]) -> Vec2 {
        let a = signedArea(p)
        guard abs(a) > 1e-6 else {
            let s = p.reduce(Vec2.zero, +)
            return s * (1.0 / Double(max(p.count, 1)))
        }
        var cx = 0.0, cy = 0.0
        for i in 0..<p.count {
            let j = (i + 1) % p.count
            let f = p[i].x * p[j].y - p[j].x * p[i].y
            cx += (p[i].x + p[j].x) * f
            cy += (p[i].y + p[j].y) * f
        }
        return Vec2(x: cx / (6 * a), y: cy / (6 * a))
    }

    /// 去掉首尾重复点，统一成逆时针。
    static func normalized(_ ring: [Vec2]) -> [Vec2] {
        var r = ring
        if r.count > 1, r.first == r.last { r.removeLast() }
        var cleaned: [Vec2] = []
        for v in r where cleaned.last.map({ $0.distance(to: v) > 0.05 }) ?? true { cleaned.append(v) }
        if cleaned.count > 2, let f = cleaned.first, let l = cleaned.last, f.distance(to: l) <= 0.05 { cleaned.removeLast() }
        if signedArea(cleaned) < 0 { cleaned.reverse() }
        return cleaned
    }

    static func contains(_ p: [Vec2], _ q: Vec2) -> Bool {
        var inside = false
        var j = p.count - 1
        for i in 0..<p.count {
            let a = p[i], b = p[j]
            if (a.y > q.y) != (b.y > q.y), q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// 用正方形 [-h, h]² 裁剪多边形（Sutherland–Hodgman）。
    static func clip(_ poly: [Vec2], half h: Double) -> [Vec2] {
        var out = poly
        let edges: [(Vec2) -> Double] = [{ h - $0.x }, { $0.x + h }, { h - $0.y }, { $0.y + h }]
        for inside in edges {
            guard !out.isEmpty else { break }
            let input = out
            out = []
            for i in 0..<input.count {
                let cur = input[i], prev = input[(i + input.count - 1) % input.count]
                let ci = inside(cur), pi = inside(prev)
                if ci >= 0 {
                    if pi < 0 { out.append(lerp(prev, cur, pi / (pi - ci))) }
                    out.append(cur)
                } else if pi >= 0 {
                    out.append(lerp(prev, cur, pi / (pi - ci)))
                }
            }
        }
        return out
    }

    /// 折线裁剪到正方形内，可能拆成多段。
    static func clipPolyline(_ line: [Vec2], half h: Double) -> [[Vec2]] {
        var result: [[Vec2]] = []
        var current: [Vec2] = []
        for i in 0..<max(line.count - 1, 0) {
            guard let (a, b) = clipSegment(line[i], line[i + 1], half: h) else {
                if current.count > 1 { result.append(current) }
                current = []
                continue
            }
            if let last = current.last, last.distance(to: a) < 0.01 {
                current.append(b)
            } else {
                if current.count > 1 { result.append(current) }
                current = [a, b]
            }
        }
        if current.count > 1 { result.append(current) }
        return result
    }

    /// Liang–Barsky 线段裁剪。
    static func clipSegment(_ a: Vec2, _ b: Vec2, half h: Double) -> (Vec2, Vec2)? {
        let d = b - a
        var t0 = 0.0, t1 = 1.0
        let p = [-d.x, d.x, -d.y, d.y]
        let q = [a.x + h, h - a.x, a.y + h, h - a.y]
        for i in 0..<4 {
            if abs(p[i]) < 1e-12 {
                if q[i] < 0 { return nil }
            } else {
                let r = q[i] / p[i]
                if p[i] < 0 { t0 = max(t0, r) } else { t1 = min(t1, r) }
                if t0 > t1 { return nil }
            }
        }
        return (a + d * t0, a + d * t1)
    }

    /// 简单多边形耳切三角化（输入逆时针）。返回三角形顶点下标。
    static func triangulate(_ p: [Vec2]) -> [Int] {
        let n = p.count
        guard n >= 3 else { return [] }
        var idx = Array(0..<n)
        var tris: [Int] = []
        var guardCount = 0
        while idx.count > 3 && guardCount < n * n {
            guardCount += 1
            var clipped = false
            for i in 0..<idx.count {
                let i0 = idx[(i + idx.count - 1) % idx.count], i1 = idx[i], i2 = idx[(i + 1) % idx.count]
                let a = p[i0], b = p[i1], c = p[i2]
                if (b - a).cross(c - b) <= 1e-9 { continue }
                var ear = true
                for j in idx where j != i0 && j != i1 && j != i2 {
                    if pointInTriangle(p[j], a, b, c) { ear = false; break }
                }
                if ear {
                    tris += [i0, i1, i2]
                    idx.remove(at: i)
                    clipped = true
                    break
                }
            }
            if !clipped { break }
        }
        if idx.count == 3 { tris += idx }
        return tris
    }

    /// Douglas–Peucker 简化闭合多边形（去掉小锯齿）。
    static func simplify(_ ring: [Vec2], tolerance: Double) -> [Vec2] {
        guard ring.count > 4 else { return ring }
        func dp(_ pts: ArraySlice<Vec2>) -> [Vec2] {
            guard pts.count > 2, let a = pts.first, let b = pts.last else { return Array(pts) }
            var maxD = 0.0, idx = pts.startIndex
            for i in pts.indices.dropFirst().dropLast() {
                let d = LandmarkDeriver.closestPoint(on: a, b, to: pts[i]).distance(to: pts[i])
                if d > maxD { maxD = d; idx = i }
            }
            if maxD <= tolerance { return [a, b] }
            return Array(dp(pts[pts.startIndex...idx]).dropLast()) + dp(pts[idx...pts.endIndex - 1])
        }
        let closed = ring + [ring[0]]
        var out = dp(closed[...])
        out.removeLast()
        return out.count >= 3 ? out : ring
    }

    /// 这一组楼的主方向（弧度，0…π/2）：按边长加权，4θ 平均消掉 90° 的对称。
    static func dominantAngle(_ rings: [[Vec2]]) -> Double {
        var c = 0.0, s = 0.0
        for r in rings {
            for i in 0..<r.count {
                let e = r[(i + 1) % r.count] - r[i]
                let len = e.length
                guard len > 1 else { continue }
                let th = atan2(e.y, e.x)
                c += len * cos(4 * th); s += len * sin(4 * th)
            }
        }
        return atan2(s, c) / 4
    }

    private static func pointInTriangle(_ p: Vec2, _ a: Vec2, _ b: Vec2, _ c: Vec2) -> Bool {
        let d1 = (b - a).cross(p - a), d2 = (c - b).cross(p - b), d3 = (a - c).cross(p - c)
        return d1 >= 0 && d2 >= 0 && d3 >= 0
    }

    private static func lerp(_ a: Vec2, _ b: Vec2, _ t: Double) -> Vec2 { a + (b - a) * t }
}
