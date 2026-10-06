import UIKit

/// 把地面（铺地、绿地、球场、水、道路）画成一张贴图，铺在底座顶面。北在图片上方。
enum GroundPainter {
    static func image(for map: MapModel, pixels: Int = 2048) -> UIImage {
        let size = CGSize(width: pixels, height: pixels)
        let k = CGFloat(pixels) / CGFloat(map.size)
        let half = map.half
        func pt(_ v: Vec2) -> CGPoint { CGPoint(x: CGFloat(v.x + half) * k, y: CGFloat(half - v.y) * k) }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            SceneStyle.paving.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            for a in map.areas {
                let path = UIBezierPath()
                path.move(to: pt(a.outline[0]))
                a.outline.dropFirst().forEach { path.addLine(to: pt($0)) }
                path.close()
                SceneStyle.area(a.kind).setFill()
                path.fill()
                if a.kind == .farmland {
                    UIColor(white: 1, alpha: 0.25).setStroke()
                    path.lineWidth = 1.2 * k
                    path.stroke()
                }
                if a.kind == .pitch {
                    UIColor(white: 1, alpha: 0.85).setStroke()
                    path.lineWidth = 0.5 * k
                    path.stroke()
                    let c = pt(Polygon.centroid(a.outline))
                    let r = 4 * k
                    UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).stroke()
                }
            }

            // 道路：先画边，再画路面；大路在下，行人路在上。
            let order: [RoadKind] = [.major, .minor, .residential, .service, .cycleway, .steps, .footway]
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for pass in 0..<2 {
                for kind in order {
                    let style = SceneStyle.road(kind)
                    for r in map.roads where r.kind == kind {
                        let path = UIBezierPath()
                        path.move(to: pt(r.points[0]))
                        r.points.dropFirst().forEach { path.addLine(to: pt($0)) }
                        if pass == 0 {
                            guard let edge = style.edge else { continue }
                            edge.setStroke()
                            path.lineWidth = CGFloat(r.width + 1.2) * k
                        } else {
                            style.fill.setStroke()
                            path.lineWidth = CGFloat(r.width) * k
                        }
                        path.lineCapStyle = .round
                        path.lineJoinStyle = .round
                        path.stroke()
                    }
                }
            }

            // 楼宇底下一圈浅色散水，让楼像"放"在地上。
            UIColor(white: 0.97, alpha: 1).setFill()
            for b in map.buildings where b.kind != .canopy {
                let path = UIBezierPath()
                path.move(to: pt(b.outline[0]))
                b.outline.dropFirst().forEach { path.addLine(to: pt($0)) }
                path.close()
                UIColor(white: 0.82, alpha: 1).setStroke()
                path.lineWidth = 2.0 * k
                path.stroke()
                path.fill()
            }
        }
    }

    /// 一个开间（3.6 m）× 一层（3 m）的立面贴图：一层一道窗缝（参考图 ② 的画法），远看干净。
    static func facadeTile(wall: UIColor, lit: Bool = false) -> UIImage {
        let size = CGSize(width: 72, height: 60)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            wall.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            (lit ? UIColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1) : UIColor(red: 0.36, green: 0.33, blue: 0.30, alpha: 0.78)).setFill()
            ctx.fill(CGRect(x: 18, y: 26, width: 36, height: 9))
        }
    }
}
