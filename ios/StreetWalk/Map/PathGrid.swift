import Foundation

/// 4 m 网格寻路：楼宇不可走，道路和行人路便宜，空地贵一点。用于"我"的散步路线和找人路线。
struct PathGrid {
    let cell = 4.0
    let n: Int
    let half: Double
    private var cost: [Float]   // 0 表示不可走

    init(map: MapModel) {
        half = map.half
        n = Int(map.size / cell)
        cost = Array(repeating: 2.5, count: n * n)

        func cellCenter(_ i: Int, _ j: Int) -> Vec2 { Vec2(x: -half + (Double(i) + 0.5) * cell, y: -half + (Double(j) + 0.5) * cell) }
        func range(_ lo: Double, _ hi: Double) -> ClosedRange<Int> {
            let a = max(0, Int(((lo + half) / cell).rounded(.down))), b = min(n - 1, Int(((hi + half) / cell).rounded(.down)))
            return a...max(a, b)
        }

        for r in map.roads {
            let c: Float = r.kind == .footway ? 0.8 : (r.kind == .major ? 1.4 : 1.0)
            for k in 0..<max(r.points.count - 1, 0) {
                let a = r.points[k], b = r.points[k + 1]
                let reach = r.width / 2 + 1.5
                for i in range(min(a.x, b.x) - reach, max(a.x, b.x) + reach) {
                    for j in range(min(a.y, b.y) - reach, max(a.y, b.y) + reach) {
                        let p = cellCenter(i, j)
                        if LandmarkDeriver.closestPoint(on: a, b, to: p).distance(to: p) <= reach {
                            cost[j * n + i] = min(cost[j * n + i], c)
                        }
                    }
                }
            }
        }
        for b in map.buildings where b.kind != .canopy {
            let xs = b.outline.map(\.x), ys = b.outline.map(\.y)
            for i in range(xs.min()!, xs.max()!) {
                for j in range(ys.min()!, ys.max()!) where Polygon.contains(b.outline, cellCenter(i, j)) {
                    cost[j * n + i] = 0
                }
            }
        }
    }

    private func index(_ p: Vec2) -> (Int, Int) {
        (min(n - 1, max(0, Int((p.x + half) / cell))), min(n - 1, max(0, Int((p.y + half) / cell))))
    }

    private func center(_ i: Int, _ j: Int) -> Vec2 {
        Vec2(x: -half + (Double(i) + 0.5) * cell, y: -half + (Double(j) + 0.5) * cell)
    }

    func isWalkable(_ p: Vec2) -> Bool { let (i, j) = index(p); return cost[j * n + i] > 0 }

    /// 离 p 最近的可走格子中心。
    func nearestWalkable(_ p: Vec2) -> Vec2 {
        let (i0, j0) = index(p)
        if cost[j0 * n + i0] > 0 { return p }
        for r in 1..<20 {
            for di in -r...r { for dj in -r...r where abs(di) == r || abs(dj) == r {
                let i = i0 + di, j = j0 + dj
                if i >= 0, j >= 0, i < n, j < n, cost[j * n + i] > 0 { return center(i, j) }
            } }
        }
        return p
    }

    /// A*（8 邻接）。返回平滑过的米坐标路线，首尾是原始起点终点。
    func path(from start: Vec2, to goal: Vec2) -> [Vec2] {
        let s = index(nearestWalkable(start)), g = index(nearestWalkable(goal))
        let sid = s.1 * n + s.0, gid = g.1 * n + g.0
        var gScore = [Float](repeating: .infinity, count: n * n)
        var came = [Int32](repeating: -1, count: n * n)
        var closed = [Bool](repeating: false, count: n * n)
        var heap = MinHeap()
        gScore[sid] = 0
        func h(_ id: Int) -> Float {
            let dx = Float(abs(id % n - g.0)), dy = Float(abs(id / n - g.1))
            return 0.8 * (max(dx, dy) + 0.414 * min(dx, dy))
        }
        heap.push((h(sid), sid))
        let steps: [(Int, Int, Float)] = [(1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1), (1, 1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (-1, -1, 1.414)]
        while let (_, cur) = heap.pop() {
            if cur == gid { break }
            if closed[cur] { continue }
            closed[cur] = true
            let ci = cur % n, cj = cur / n
            for (di, dj, w) in steps {
                let ni = ci + di, nj = cj + dj
                guard ni >= 0, nj >= 0, ni < n, nj < n else { continue }
                let nid = nj * n + ni
                let c = cost[nid]
                guard c > 0, !closed[nid] else { continue }
                if di != 0 && dj != 0 && (cost[cj * n + ni] == 0 || cost[nj * n + ci] == 0) { continue }
                let tentative = gScore[cur] + w * c
                if tentative < gScore[nid] {
                    gScore[nid] = tentative
                    came[nid] = Int32(cur)
                    heap.push((tentative + h(nid), nid))
                }
            }
        }
        guard came[gid] >= 0 || gid == sid else { return [start, goal] }
        var cells: [Int] = [gid]
        var c = gid
        while c != sid, came[c] >= 0 { c = Int(came[c]); cells.append(c) }
        cells.reverse()

        // 去掉同方向的中间点，再做一次 Chaikin 平滑。
        var pts: [Vec2] = [start]
        for k in 1..<max(cells.count - 1, 1) {
            let a = cells[k - 1], b = cells[k], cc = cells[k + 1]
            let d1 = (b % n - a % n, b / n - a / n), d2 = (cc % n - b % n, cc / n - b / n)
            if d1 != d2 { pts.append(center(b % n, b / n)) }
        }
        pts.append(goal)
        return chaikin(pts)
    }

    private func chaikin(_ p: [Vec2]) -> [Vec2] {
        guard p.count > 2 else { return p }
        var out = [p[0]]
        for i in 0..<(p.count - 1) {
            let a = p[i], b = p[i + 1]
            out.append(a + (b - a) * 0.25)
            out.append(a + (b - a) * 0.75)
        }
        out.append(p[p.count - 1])
        return out
    }

    func length(of path: [Vec2]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }
}

/// 简单二叉最小堆。
private struct MinHeap {
    private var a: [(Float, Int)] = []
    mutating func push(_ e: (Float, Int)) {
        a.append(e)
        var i = a.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            if a[p].0 <= a[i].0 { break }
            a.swapAt(p, i); i = p
        }
    }
    mutating func pop() -> (Float, Int)? {
        guard !a.isEmpty else { return nil }
        let top = a[0]
        let last = a.removeLast()
        if !a.isEmpty {
            a[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < a.count, a[l].0 < a[m].0 { m = l }
                if r < a.count, a[r].0 < a[m].0 { m = r }
                if m == i { break }
                a.swapAt(i, m); i = m
            }
        }
        return top
    }
}
