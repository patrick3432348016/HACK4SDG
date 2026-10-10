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
        // 深浅色按调用时的 trait 解析。
        let tc = UITraitCollection.current
        func c(_ color: UIColor) -> UIColor { color.resolvedColor(with: tc) }
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            c(SceneStyle.paving).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            for a in map.areas {
                let path = UIBezierPath()
                path.move(to: pt(a.outline[0]))
                a.outline.dropFirst().forEach { path.addLine(to: pt($0)) }
                path.close()
                c(SceneStyle.area(a.kind)).setFill()
                path.fill()
                c(SceneStyle.areaEdge(a.kind)).setStroke()
                path.lineWidth = 0.8 * k
                path.stroke()
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
                            c(edge).setStroke()
                            path.lineWidth = CGFloat(r.width + 1.2) * k
                        } else {
                            c(style.fill).setStroke()
                            path.lineWidth = CGFloat(r.width) * k
                        }
                        path.lineCapStyle = .round
                        path.lineJoinStyle = .round
                        path.stroke()
                    }
                }
            }
        }
    }
}
