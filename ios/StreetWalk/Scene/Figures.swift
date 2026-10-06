import SceneKit
import UIKit

enum Mobility: String, Codable, CaseIterable {
    case walk, cane, wheelchair, stroller

    var label: String {
        switch self {
        case .walk: return "行路"
        case .cane: return "拐杖"
        case .wheelchair: return "輪椅"
        case .stroller: return "推BB車"
        }
    }
}

/// 场景里的小人、地标标记、树。尺寸以地图米计（会被放大，保证远看也认得出）。
enum Figures {
    /// 小人高约 14 m（真人的 8 倍左右），远景也看得见。
    static func person(color: UIColor, mobility: Mobility) -> SCNNode {
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
        head.firstMaterial = MeshBuilder.material(SceneStyle.skin)
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, Float(seated ? 11.4 : 11.9) * SceneStyle.scale, 0)
        body.addChildNode(headNode)

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

    /// 橙色地标：参考图里的小凉亭（四根柱 + 橙色四角顶）+ 一圈贴地光晕。
    static func landmark(hasSeat: Bool) -> SCNNode {
        let root = SCNNode()
        let s = CGFloat(SceneStyle.scale)
        let k = SceneStyle.scale
        let orange = MeshBuilder.material(SceneStyle.accent)
        let post = MeshBuilder.material(UIColor(red: 0.45, green: 0.30, blue: 0.22, alpha: 1))

        let halo = SCNCylinder(radius: 13 * s, height: 0.05 * s)
        halo.radialSegmentCount = 48
        let hm = MeshBuilder.material(SceneStyle.accent.withAlphaComponent(0.20), lit: false)
        hm.writesToDepthBuffer = false
        halo.firstMaterial = hm
        let hn = SCNNode(geometry: halo)
        hn.name = "halo"
        hn.position = SCNVector3(0, 0.15 * k, 0)
        hn.castsShadow = false
        root.addChildNode(hn)

        let base = SCNBox(width: 10 * s, height: 0.8 * s, length: 10 * s, chamferRadius: 0.4 * s)
        base.firstMaterial = MeshBuilder.material(UIColor(red: 0.93, green: 0.90, blue: 0.85, alpha: 1))
        let bn = SCNNode(geometry: base)
        bn.position = SCNVector3(0, 0.4 * k, 0)
        root.addChildNode(bn)

        for (x, z) in [(-3.6, -3.6), (3.6, -3.6), (3.6, 3.6), (-3.6, 3.6)] as [(Float, Float)] {
            let p = SCNCylinder(radius: 0.55 * s, height: 6 * s)
            p.radialSegmentCount = 8
            p.firstMaterial = post
            let pn = SCNNode(geometry: p)
            pn.position = SCNVector3(x * k, 3.8 * k, z * k)
            root.addChildNode(pn)
        }

        let roof = SCNPyramid(width: 11.5 * s, height: 4.2 * s, length: 11.5 * s)
        roof.firstMaterial = orange
        let rn = SCNNode(geometry: roof)
        rn.position = SCNVector3(0, 6.6 * k, 0)
        root.addChildNode(rn)
        let eave = SCNBox(width: 11.5 * s, height: 0.6 * s, length: 11.5 * s, chamferRadius: 0)
        eave.firstMaterial = MeshBuilder.material(UIColor(red: 0.70, green: 0.28, blue: 0.14, alpha: 1))
        let en = SCNNode(geometry: eave)
        en.position = SCNVector3(0, 6.5 * k, 0)
        root.addChildNode(en)

        if hasSeat {
            let bench = SCNBox(width: 6 * s, height: 1.2 * s, length: 1.8 * s, chamferRadius: 0.3 * s)
            bench.firstMaterial = post
            let bnn = SCNNode(geometry: bench)
            bnn.position = SCNVector3(0, 1.6 * k, 0)
            root.addChildNode(bnn)
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
