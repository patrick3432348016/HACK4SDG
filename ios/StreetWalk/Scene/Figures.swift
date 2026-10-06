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

    /// 橙色地标：细杆 + 圆牌，再加一圈贴地光圈。
    static func landmark(hasSeat: Bool) -> SCNNode {
        let root = SCNNode()
        let s = CGFloat(SceneStyle.scale)
        let orange = MeshBuilder.material(SceneStyle.accent)

        let pole = SCNCylinder(radius: 0.7 * s, height: 10 * s)
        pole.firstMaterial = orange
        let pn = SCNNode(geometry: pole)
        pn.position = SCNVector3(0, 5 * SceneStyle.scale, 0)
        root.addChildNode(pn)

        let disc = SCNCylinder(radius: 3.6 * s, height: 1.2 * s)
        disc.radialSegmentCount = 24
        disc.materials = [orange, MeshBuilder.material(.white), orange]
        let dn = SCNNode(geometry: disc)
        dn.position = SCNVector3(0, 10.6 * SceneStyle.scale, 0)
        root.addChildNode(dn)

        let halo = SCNCylinder(radius: 11 * s, height: 0.05 * s)
        halo.radialSegmentCount = 40
        let hm = MeshBuilder.material(SceneStyle.accent.withAlphaComponent(0.18), lit: false)
        hm.writesToDepthBuffer = false
        halo.firstMaterial = hm
        let hn = SCNNode(geometry: halo)
        hn.name = "halo"
        hn.position = SCNVector3(0, 0.15 * SceneStyle.scale, 0)
        hn.castsShadow = false
        root.addChildNode(hn)

        if hasSeat {
            let bench = SCNBox(width: 7 * s, height: 1.2 * s, length: 2.4 * s, chamferRadius: 0.3 * s)
            bench.firstMaterial = MeshBuilder.material(UIColor(red: 0.62, green: 0.48, blue: 0.36, alpha: 1))
            let bn = SCNNode(geometry: bench)
            bn.position = SCNVector3(6 * SceneStyle.scale, 2 * SceneStyle.scale, 4 * SceneStyle.scale)
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
