import SceneKit
import UIKit

/// 地图米坐标 → 场景坐标：X 向东，Y 向上，Z 向南（-北）。
@inline(__always) func scenePoint(_ v: Vec2, height: Double = 0) -> SCNVector3 {
    let s = Double(SceneStyle.scale)
    return SCNVector3(Float(v.x * s), Float(height * s), Float(-v.y * s))
}

/// 楼宇、路线带等自建几何。
enum MeshBuilder {
    private struct Buffer {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [UInt32] = []

        mutating func vertex(_ p: SCNVector3, _ n: SCNVector3, _ uv: CGPoint) -> UInt32 {
            positions.append(p); normals.append(n); uvs.append(uv)
            return UInt32(positions.count - 1)
        }

        /// 按期望法线自动决定三角形绕序，保证正面朝外。
        mutating func tri(_ a: UInt32, _ b: UInt32, _ c: UInt32, facing n: SCNVector3) {
            let pa = positions[Int(a)], pb = positions[Int(b)], pc = positions[Int(c)]
            let u = SCNVector3(pb.x - pa.x, pb.y - pa.y, pb.z - pa.z)
            let v = SCNVector3(pc.x - pa.x, pc.y - pa.y, pc.z - pa.z)
            let cr = SCNVector3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
            if cr.x * n.x + cr.y * n.y + cr.z * n.z >= 0 { indices += [a, b, c] } else { indices += [a, c, b] }
        }

        func element() -> SCNGeometryElement { SCNGeometryElement(indices: indices, primitiveType: .triangles) }
    }

    /// 一座楼：墙（窗格贴图，UV 以开间/层计）+ 平屋顶。返回的几何有两个元素：墙、屋顶。
    static func building(_ b: Building) -> SCNGeometry {
        var walls = Buffer()
        var roof = Buffer()
        let ring = b.outline
        var run = 0.0
        for i in 0..<ring.count {
            let p0 = ring[i], p1 = ring[(i + 1) % ring.count]
            let e = p1 - p0
            let len = e.length
            guard len > 0.05 else { continue }
            // 逆时针外环：外法线在边的右侧。
            let out = Vec2(x: e.y, y: -e.x).normalized
            let n = SCNVector3(Float(out.x), 0, Float(-out.y))
            let u0 = run / 3.6, u1 = (run + len) / 3.6
            let v0 = b.minHeight / 3.0, v1 = b.height / 3.0
            let a = walls.vertex(scenePoint(p0, height: b.minHeight), n, CGPoint(x: u0, y: v0))
            let bb = walls.vertex(scenePoint(p1, height: b.minHeight), n, CGPoint(x: u1, y: v0))
            let c = walls.vertex(scenePoint(p1, height: b.height), n, CGPoint(x: u1, y: v1))
            let d = walls.vertex(scenePoint(p0, height: b.height), n, CGPoint(x: u0, y: v1))
            walls.tri(a, bb, c, facing: n)
            walls.tri(a, c, d, facing: n)
            run += len
        }

        let up = SCNVector3(0, 1, 0)
        let base = roof.positions.count
        for p in ring { _ = roof.vertex(scenePoint(p, height: b.height), up, CGPoint(x: p.x / 10, y: p.y / 10)) }
        let tris = Polygon.triangulate(ring)
        var i = 0
        while i + 2 < tris.count {
            roof.tri(UInt32(base + tris[i]), UInt32(base + tris[i + 1]), UInt32(base + tris[i + 2]), facing: up)
            i += 3
        }
        // 遮蓬底面也要看得见。
        if b.kind == .canopy {
            let down = SCNVector3(0, -1, 0)
            let base2 = roof.positions.count
            for p in ring { _ = roof.vertex(scenePoint(p, height: b.minHeight), down, CGPoint(x: p.x / 10, y: p.y / 10)) }
            var j = 0
            while j + 2 < tris.count {
                roof.tri(UInt32(base2 + tris[j]), UInt32(base2 + tris[j + 1]), UInt32(base2 + tris[j + 2]), facing: down)
                j += 3
            }
        }

        // 两个元素共用一套顶点源：把屋顶顶点接在墙后面。
        let offset = UInt32(walls.positions.count)
        let positions = walls.positions + roof.positions
        let normals = walls.normals + roof.normals
        let uvs = walls.uvs + roof.uvs
        let roofIdx = roof.indices.map { $0 + offset }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: positions),
                                     SCNGeometrySource(normals: normals),
                                     SCNGeometrySource(textureCoordinates: uvs)],
                           elements: [walls.element(), SCNGeometryElement(indices: roofIdx, primitiveType: .triangles)])
    }

    /// 楼宇轮廓线：屋顶一圈 + 外角竖线，像插画里的描边。
    static func outline(_ b: Building) -> SCNGeometry? {
        let ring = b.outline
        guard ring.count >= 3 else { return nil }
        var pts: [SCNVector3] = []
        var idx: [UInt32] = []
        let top = b.height + 0.15
        for i in 0..<ring.count {
            let a = ring[i], c = ring[(i + 1) % ring.count]
            let base = UInt32(pts.count)
            pts += [scenePoint(a, height: top), scenePoint(c, height: top)]
            idx += [base, base + 1]
            // 只画凸角的竖线（凹角会被墙挡住，画了反而乱）。
            let prev = ring[(i + ring.count - 1) % ring.count]
            if (a - prev).cross(c - a) > 0 {
                let v = UInt32(pts.count)
                pts += [scenePoint(a, height: b.minHeight), scenePoint(a, height: top)]
                idx += [v, v + 1]
            }
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: pts)], elements: [SCNGeometryElement(indices: idx, primitiveType: .line)])
        let m = SCNMaterial()
        m.diffuse.contents = SceneStyle.outline
        m.lightingModel = .constant
        geo.firstMaterial = m
        return geo
    }

    /// 贴地的带子（走过的路、约会路线）。dash > 0 时画成虚线。
    static func ribbon(_ points: [Vec2], width: Double, height: Double, dash: Double = 0) -> SCNGeometry? {
        guard points.count >= 2 else { return nil }
        var buf = Buffer()
        let up = SCNVector3(0, 1, 0)
        let half = width / 2
        var acc = 0.0
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let len = a.distance(to: b)
            guard len > 0.01 else { continue }
            let dir = (b - a).normalized
            let side = Vec2(x: -dir.y, y: dir.x) * half
            var pieces: [(Vec2, Vec2)] = [(a, b)]
            if dash > 0 {
                pieces = []
                var t = 0.0
                while t < len {
                    let on = Int((acc + t) / dash) % 2 == 0
                    let step = min(dash - (acc + t).truncatingRemainder(dividingBy: dash), len - t)
                    if on { pieces.append((a + dir * t, a + dir * (t + step))) }
                    t += max(step, 0.01)
                }
            }
            for (p, q) in pieces {
                let v0 = buf.vertex(scenePoint(p + side, height: height), up, .zero)
                let v1 = buf.vertex(scenePoint(p - side, height: height), up, .zero)
                let v2 = buf.vertex(scenePoint(q - side, height: height), up, .zero)
                let v3 = buf.vertex(scenePoint(q + side, height: height), up, .zero)
                buf.tri(v0, v1, v2, facing: up)
                buf.tri(v0, v2, v3, facing: up)
            }
            acc += len
        }
        guard !buf.indices.isEmpty else { return nil }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: buf.positions), SCNGeometrySource(normals: buf.normals)],
                           elements: [buf.element()])
    }

    /// 所有树合并成一个几何（低多边形树冠 + 方树干，顶点色），一次绘制。
    static func trees(_ spots: [(Vec2, Double)], greens: [UIColor], trunk: UIColor) -> SCNGeometry? {
        guard !spots.isEmpty else { return nil }
        let t = (1.0 + 5.0.squareRoot()) / 2
        let ico: [(Double, Double, Double)] = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
        let faces: [(Int, Int, Int)] = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
                                         (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
        let norm = (1 + t * t).squareRoot()
        var pos: [SCNVector3] = [], nor: [SCNVector3] = [], col: [SCNVector3] = [], idx: [UInt32] = []
        let sc = Double(SceneStyle.scale)
        func rgb(_ c: UIColor) -> SCNVector3 { var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; c.getRed(&r, green: &g, blue: &b, alpha: &a); return SCNVector3(Float(r), Float(g), Float(b)) }
        let trunkC = rgb(trunk)
        for (k, (p, size)) in spots.enumerated() {
            let cx = p.x * sc, cz = -p.y * sc
            let r = 4.6 * size * sc, cy = 7.6 * size * sc
            let c = rgb(greens[k % greens.count])
            for f in faces {
                let vs = [ico[f.0], ico[f.1], ico[f.2]].map { v in (cx + v.0 / norm * r, cy + v.1 / norm * r * 1.12, cz + v.2 / norm * r) }
                let a = vs[0], b = vs[1], d = vs[2]
                let u = (b.0 - a.0, b.1 - a.1, b.2 - a.2), w = (d.0 - a.0, d.1 - a.1, d.2 - a.2)
                var n = (u.1 * w.2 - u.2 * w.1, u.2 * w.0 - u.0 * w.2, u.0 * w.1 - u.1 * w.0)
                let center = ((a.0 + b.0 + d.0) / 3 - cx, (a.1 + b.1 + d.1) / 3 - cy, (a.2 + b.2 + d.2) / 3 - cz)
                var flip = false
                if n.0 * center.0 + n.1 * center.1 + n.2 * center.2 < 0 { n = (-n.0, -n.1, -n.2); flip = true }
                let l = (n.0 * n.0 + n.1 * n.1 + n.2 * n.2).squareRoot()
                let nv = SCNVector3(Float(n.0 / l), Float(n.1 / l), Float(n.2 / l))
                let base = UInt32(pos.count)
                for v in (flip ? [a, d, b] : [a, b, d]) { pos.append(SCNVector3(Float(v.0), Float(v.1), Float(v.2))); nor.append(nv); col.append(c) }
                idx += [base, base + 1, base + 2]
            }
            // 树干：四棱柱的四个侧面。
            let tw = 0.8 * size * sc, th = 4.5 * size * sc
            let corners = [(-tw, -tw), (tw, -tw), (tw, tw), (-tw, tw)]
            for i in 0..<4 {
                let (x0, z0) = corners[i], (x1, z1) = corners[(i + 1) % 4]
                let nx = (z0 + z1) / 2, nz = -(x0 + x1) / 2
                _ = nx; _ = nz
                let mid = ((x0 + x1) / 2, (z0 + z1) / 2)
                let ml = (mid.0 * mid.0 + mid.1 * mid.1).squareRoot()
                let nv = SCNVector3(Float(mid.0 / ml), 0, Float(mid.1 / ml))
                let base = UInt32(pos.count)
                let quad = [(cx + x0, 0.0, cz + z0), (cx + x1, 0.0, cz + z1), (cx + x1, th, cz + z1), (cx + x0, th, cz + z0)]
                for v in quad { pos.append(SCNVector3(Float(v.0), Float(v.1), Float(v.2))); nor.append(nv); col.append(trunkC) }
                // 外法线朝外时的绕序。
                let a = quad[0], b = quad[1], d = quad[2]
                let cr = ((b.1 - a.1) * (d.2 - a.2) - (b.2 - a.2) * (d.1 - a.1), (b.2 - a.2) * (d.0 - a.0) - (b.0 - a.0) * (d.2 - a.2), (b.0 - a.0) * (d.1 - a.1) - (b.1 - a.1) * (d.0 - a.0))
                if cr.0 * mid.0 + cr.2 * mid.1 >= 0 { idx += [base, base + 1, base + 2, base, base + 2, base + 3] }
                else { idx += [base, base + 2, base + 1, base, base + 3, base + 2] }
            }
        }
        let colorData = col.withUnsafeBufferPointer { Data(buffer: $0) }
        let colors = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: col.count, usesFloatComponents: true,
                                       componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<SCNVector3>.stride)
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor), colors],
                              elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let m = SCNMaterial()
        m.diffuse.contents = UIColor.white
        m.lightingModel = .lambert
        geo.firstMaterial = m
        return geo
    }

    static func material(_ color: UIColor, lit: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = lit ? .lambert : .constant
        return m
    }
}
