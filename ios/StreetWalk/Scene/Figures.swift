import SceneKit
import UIKit

enum Mobility: String, Codable, CaseIterable {
    case walk, cane, wheelchair, stroller

    var label: String {
        switch self {
        case .walk: return L.t("行路", "步行")
        case .cane: return L.t("拐杖", "拐杖")
        case .wheelchair: return L.t("輪椅", "轮椅")
        case .stroller: return L.t("推BB車", "推婴儿车")
        }
    }
}

/// 场景里的小人、地标标记、树。尺寸以地图米计（会被放大，保证远看也认得出）。
enum Figures {
    /// 小人高约 14 m（真人的 8 倍左右），远景也看得见。
    /// 外形极简：胶囊身 + 圆头（肤色四档）+ 一块发片（長者白发）；後生身形小一号。
    static func person(color: UIColor, mobility: Mobility, skin: Int = 1, age: AgeGroup = .adult) -> SCNNode {
        let root = SCNNode()
        let body = SCNNode()
        body.name = "body"
        root.addChildNode(body)
        let s = CGFloat(SceneStyle.scale)
        let seated = mobility == .wheelchair

        let torso = SCNCapsule(capRadius: 2.4 * s, height: (seated ? 6.5 : 9.5) * s)
        torso.firstMaterial = MeshBuilder.material(color)
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.position = SCNVector3(0, Float((seated ? 6.2 : 4.75)) * SceneStyle.scale, 0)
        body.addChildNode(torsoNode)

        let head = SCNSphere(radius: 2.6 * s)
        head.segmentCount = 16
        head.firstMaterial = MeshBuilder.material(Palette.skinUI(skin))
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, Float(seated ? 11.4 : 11.9) * SceneStyle.scale, 0)
        body.addChildNode(headNode)

        // 头发：压扁的半球盖住头顶（只做一块，宁少勿杂）。
        let hair = SCNSphere(radius: 2.75 * s)
        hair.segmentCount = 16
        hair.firstMaterial = MeshBuilder.material(Palette.hairUI(age))
        let hairNode = SCNNode(geometry: hair)
        hairNode.scale = SCNVector3(1, 0.55, 1)
        hairNode.position = SCNVector3(0, Float(seated ? 12.5 : 13.0) * SceneStyle.scale, 0.15 * SceneStyle.scale)
        body.addChildNode(hairNode)
        if age == .young { body.scale = SCNVector3(0.86, 0.86, 0.86) }

        let grey = MeshBuilder.material(UIColor(white: 0.35, alpha: 1))
        switch mobility {
        case .walk:
            break
        case .cane:
            let cane = SCNCylinder(radius: 0.45 * s, height: 8 * s)
            cane.firstMaterial = grey
            let n = SCNNode(geometry: cane)
            n.position = SCNVector3(3.4 * SceneStyle.scale, 4 * SceneStyle.scale, -1.5 * SceneStyle.scale)
            n.eulerAngles.z = -0.12
            body.addChildNode(n)
        case .wheelchair:
            for side: Float in [-1, 1] {
                let wheel = SCNTorus(ringRadius: 3.2 * s, pipeRadius: 0.5 * s)
                wheel.firstMaterial = grey
                let w = SCNNode(geometry: wheel)
                w.eulerAngles.z = .pi / 2
                w.position = SCNVector3(side * 3.0 * SceneStyle.scale, 3.4 * SceneStyle.scale, 0)
                body.addChildNode(w)
            }
            let seat = SCNBox(width: 5.5 * s, height: 0.8 * s, length: 5 * s, chamferRadius: 0.3 * s)
            seat.firstMaterial = grey
            let sn = SCNNode(geometry: seat)
            sn.position = SCNVector3(0, 4 * SceneStyle.scale, 0)
            body.addChildNode(sn)
        case .stroller:
            let cart = SCNBox(width: 4 * s, height: 4 * s, length: 5 * s, chamferRadius: 1.2 * s)
            cart.firstMaterial = MeshBuilder.material(UIColor(red: 0.55, green: 0.65, blue: 0.78, alpha: 1))
            let cn = SCNNode(geometry: cart)
            cn.position = SCNVector3(0, 4.2 * SceneStyle.scale, 6 * SceneStyle.scale)
            body.addChildNode(cn)
        }
        root.castsShadow = true
        return root
    }

    /// 地标：参考图 ③ 的小凉亭——白色顶、橙色描边、细灰柱，下面一圈橙色光晕（20%）。
    static func landmark(hasSeat: Bool) -> SCNNode {
        let root = SCNNode()
        let s = CGFloat(SceneStyle.scale)
        let k = SceneStyle.scale
        let grey = MeshBuilder.material(UIColor(red: 0.62, green: 0.62, blue: 0.66, alpha: 1))

        let halo = SCNCylinder(radius: 12 * s, height: 0.05 * s)
        halo.radialSegmentCount = 48
        let hm = MeshBuilder.material(SceneStyle.accent.withAlphaComponent(0.30), lit: false)
        hm.writesToDepthBuffer = false
        halo.firstMaterial = hm
        let hn = SCNNode(geometry: halo)
        hn.name = "halo"
        hn.position = SCNVector3(0, 0.15 * k, 0)
        hn.castsShadow = false
        root.addChildNode(hn)

        for (x, z) in [(-3.4, -3.4), (3.4, -3.4), (3.4, 3.4), (-3.4, 3.4)] as [(Float, Float)] {
            let p = SCNCylinder(radius: 0.35 * s, height: 7 * s)
            p.radialSegmentCount = 6
            p.firstMaterial = grey
            let pn = SCNNode(geometry: p)
            pn.position = SCNVector3(x * k, 3.5 * k, z * k)
            root.addChildNode(pn)
        }

        let w: CGFloat = 9.5
        let roof = SCNBox(width: w * s, height: 1.0 * s, length: w * s, chamferRadius: 0)
        roof.firstMaterial = MeshBuilder.material(SceneStyle.pavilionRoof)
        let rn = SCNNode(geometry: roof)
        rn.position = SCNVector3(0, 7.4 * k, 0)
        root.addChildNode(rn)

        // 橙色描边：屋顶一圈。
        let hw = Float(w) / 2, top: Float = 7.95
        let corners = [(-hw, -hw), (hw, -hw), (hw, hw), (-hw, hw)].map { SCNVector3($0.0 * k, top * k, $0.1 * k) }
        let idx: [UInt32] = [0, 1, 1, 2, 2, 3, 3, 0]
        let edge = SCNGeometry(sources: [SCNGeometrySource(vertices: corners)], elements: [SCNGeometryElement(indices: idx, primitiveType: .line)])
        edge.firstMaterial = MeshBuilder.material(SceneStyle.accent, lit: false)
        root.addChildNode(SCNNode(geometry: edge))

        if hasSeat {
            let bench = SCNBox(width: 5 * s, height: 0.8 * s, length: 1.6 * s, chamferRadius: 0.2 * s)
            bench.firstMaterial = grey
            let bn = SCNNode(geometry: bench)
            bn.position = SCNVector3(0, 1.4 * k, 0)
            root.addChildNode(bn)
        }
        return root
    }

    /// 一棵低多边形树（会被合并成一个节点）。
    static func tree(variant: Int, size: Double) -> SCNNode {
        let s = CGFloat(SceneStyle.scale) * CGFloat(size)
        let root = SCNNode()
        let trunk = SCNCylinder(radius: 0.8 * s, height: 4.5 * s)
        trunk.radialSegmentCount = 6
        trunk.firstMaterial = MeshBuilder.material(SceneStyle.trunk)
        let tn = SCNNode(geometry: trunk)
        tn.position = SCNVector3(0, Float(2.25 * s), 0)
        root.addChildNode(tn)
        let crown = SCNSphere(radius: 4.6 * s)
        crown.segmentCount = 7
        crown.firstMaterial = MeshBuilder.material(SceneStyle.treeGreens[variant % SceneStyle.treeGreens.count])
        let cn = SCNNode(geometry: crown)
        cn.position = SCNVector3(0, Float(7.8 * s), 0)
        cn.scale = SCNVector3(1, 1.15, 1)
        root.addChildNode(cn)
        return root
    }
}
