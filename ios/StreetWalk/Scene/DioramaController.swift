import SceneKit
import UIKit
import QuartzCore

/// 场景里一个人的显示状态（只给街坊和"我"用；非街坊永远不进场景）。
struct ScenePerson: Equatable {
    enum Motion: Equatable {
        case wander(around: Vec2)          // 在地标附近 25 m 内慢慢走
        case route([Vec2], speed: Double)  // 沿路线走（米/秒，演示时加速）
        case stand(at: Vec2)
    }
    var id: String
    var color: UIColor
    var mobility: Mobility
    var motion: Motion
    var label: String?
    var highlighted = false
}

/// 覆盖层上的一个标签（SwiftUI 画，跟随 3D 投影）。
struct OverlayItem: Identifiable, Equatable {
    enum Kind { case landmark, person, home, report }
    var id: String
    var kind: Kind
    var text: String
    var point: CGPoint
    var highlighted: Bool
    var priority: Int
}

@Observable
final class OverlayModel {
    var items: [OverlayItem] = []
}

/// 3D 微缩模型的全部场景逻辑：搭建、太阳、相机、人物、路线、遮挡淡化、标签投影。
final class DioramaController: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    weak var view: SCNView?
    let overlay = OverlayModel()

    private(set) var map: MapModel?
    private let world = SCNNode()
    private let plinthNode = SCNNode()
    private let buildingsNode = SCNNode()
    private let treesNode = SCNNode()
    private let landmarksNode = SCNNode()
    private let peopleNode = SCNNode()
    private let routesNode = SCNNode()
    private var towerNodes: [Int64: SCNNode] = [:]
    private var pickableNodes: [Int64: SCNNode] = [:]
    private var landmarkNodes: [String: SCNNode] = [:]
    private var landmarkInfo: [String: Landmark] = [:]
    private var personNodes: [String: SCNNode] = [:]
    private var personState: [String: ScenePerson] = [:]
    private var pathGrid: PathGrid?

    // 相机：固定俯角和方位，只平移、缩放。
    private let cameraNode = SCNNode()
    private let sunNode = SCNNode()
    private let ambientNode = SCNNode()
    private let pitch: Float = Float(LaunchArgs.value("-pitch").flatMap(Double.init) ?? 33) * .pi / 180
    private let azimuth: Float = 45 * .pi / 180      // 从东南方看
    private(set) var target = Vec2(x: -72, y: 72)
    private(set) var distance: Float = 2.35
    let minDistance: Float = 0.32
    let maxDistance: Float = 2.8
    var homeTarget = Vec2.zero
    var homeDistance: Float = 2.45

    // 平移惯性
    private var velocity = Vec2.zero
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    // 标签
    var homeBuildingID: Int64?
    var homeLabel: String?
    var reportMarks: [(id: String, pos: Vec2, text: String)] = []
    private var lastOverlayPush: TimeInterval = 0
    private let lock = NSLock()

    var onOverlay: (([OverlayItem]) -> Void)?
    /// 跟随某个人（散步时跟着"我"）。用户拖动后暂停 3 秒。
    var followID: String?
    private var lastUserInteraction: CFTimeInterval = 0
    var debugInfo: [String: Int] = [:]

    override init() {
        super.init()
        scene.background.contents = SceneStyle.background
        scene.rootNode.addChildNode(world)
        [plinthNode, buildingsNode, treesNode, landmarksNode, routesNode, peopleNode].forEach(world.addChildNode)
        setupCamera()
        setupLights()
    }

    // MARK: - 搭建

    func load(map: MapModel, landmarks: [Landmark], animated: Bool) {
        self.map = map
        pathGrid = PathGrid(map: map)
        [plinthNode, buildingsNode, treesNode, landmarksNode, routesNode, peopleNode].forEach { $0.childNodes.forEach { $0.removeFromParentNode() } }
        lock.lock(); towerNodes = [:]; pickableNodes = [:]; landmarkNodes = [:]; personNodes = [:]; personState = [:]; lock.unlock()

        // 阴影范围跟着底座大小走，小底座的影子更清楚。
        sunNode.light?.orthographicScale = map.size * Double(SceneStyle.scale) * 0.75
        buildPlinth(map)
        buildBuildings(map, animated: animated)
        buildTrees(map)
        setLandmarks(landmarks)
    }

    private func buildPlinth(_ map: MapModel) {
        let L = CGFloat(Double(map.size) * Double(SceneStyle.scale))
        let t = CGFloat(SceneStyle.plinthThickness)
        let box = SCNBox(width: L, height: t, length: L, chamferRadius: 0.0015)
        let side = MeshBuilder.material(SceneStyle.plinthSide)
        let top = MeshBuilder.material(SceneStyle.paving)
        let bottom = MeshBuilder.material(SceneStyle.plinthSide.withAlphaComponent(1))
        box.materials = [side, side, side, side, top, bottom]
        let boxNode = SCNNode(geometry: box)
        boxNode.position = SCNVector3(0, -Float(t) / 2 - 0.0002, 0)
        boxNode.castsShadow = false
        plinthNode.addChildNode(boxNode)

        let plane = SCNPlane(width: L, height: L)
        let gm = SCNMaterial()
        gm.diffuse.contents = GroundPainter.image(for: map)
        gm.diffuse.mipFilter = .linear
        gm.lightingModel = .lambert
        plane.firstMaterial = gm
        let ground = SCNNode(geometry: plane)
        ground.eulerAngles.x = -.pi / 2
        ground.castsShadow = false
        plinthNode.addChildNode(ground)

        // 前沿铭牌：屋邨名 · 比例 · 地图署名。
        let text = SCNText(string: "\(map.placeName)  ·  1:1000  ·  © OpenStreetMap contributors", extrusionDepth: 0.2)
        text.font = UIFont.systemFont(ofSize: 6, weight: .medium)
        text.flatness = 0.2
        text.firstMaterial = MeshBuilder.material(UIColor(red: 0.35, green: 0.27, blue: 0.18, alpha: 1))
        let tn = SCNNode(geometry: text)
        let (minB, maxB) = tn.boundingBox
        let k: Float = 0.00085
        tn.scale = SCNVector3(k, k, k)
        tn.pivot = SCNMatrix4MakeTranslation((maxB.x + minB.x) / 2, (maxB.y + minB.y) / 2, 0)
        // 贴在南侧（面向相机的一侧）的侧面。
        tn.position = SCNVector3(0, -Float(t) / 2, Float(L) / 2 + 0.0003)
        tn.castsShadow = false
        plinthNode.addChildNode(tn)
    }

    private func buildBuildings(_ map: MapModel, animated: Bool) {
        let wallMats = SceneStyle.facadeTints.map { MeshBuilder.material($0) }
        let plainWall = MeshBuilder.material(SceneStyle.facadeTints[0])
        let roof = MeshBuilder.material(SceneStyle.roof)
        let constructionMat = MeshBuilder.material(SceneStyle.construction)
        let canopyMat = MeshBuilder.material(SceneStyle.canopy)

        let lowGroup = SCNNode()
        for b in map.buildings {
            let geo = MeshBuilder.building(b)
            switch b.kind {
            case .construction: geo.materials = [constructionMat, constructionMat]
            case .canopy: geo.materials = [canopyMat, canopyMat]
            case .small: geo.materials = [plainWall, roof]
            default: geo.materials = [wallMats[Int(abs(b.id) % Int64(wallMats.count))], roof]
            }
            let node = SCNNode(geometry: geo)
            node.name = "bld:\(b.id)"
            node.castsShadow = true
            if b.kind != .canopy, let edges = MeshBuilder.outline(b) {
                let en = SCNNode(geometry: edges)
                en.castsShadow = false
                node.addChildNode(en)
            }
            if b.isTower || b.kind == .residential {
                // 可选中的楼各用一份材质，高亮时不会连累其他楼。
                geo.materials = geo.materials.map { $0.copy() as! SCNMaterial }
                buildingsNode.addChildNode(node)
                pickableNodes[b.id] = node
                if b.isTower { towerNodes[b.id] = node }
            } else {
                lowGroup.addChildNode(node)
            }
        }
        let low = lowGroup.flattenedClone()
        low.name = "low"
        low.castsShadow = true
        buildingsNode.addChildNode(low)

        guard animated else { return }
        // 楼宇按离我屋企的距离错峰"升起"。
        let origin = homeTarget
        for (id, node) in pickableNodes {
            let d = map.building(id: id).map { $0.centroid.distance(to: origin) } ?? 0
            rise(node, delay: 0.15 + d / 900)
        }
        rise(low, delay: 0.1)
    }

    private func rise(_ node: SCNNode, delay: Double) {
        node.scale = SCNVector3(1, 0.001, 1)
        let grow = SCNAction.customAction(duration: 0.9) { n, t in
            let x = Float(t / 0.9)
            // 近似弹簧：快速冲上去，轻微回弹后停住。
            let y = 1 - exp(-6 * x) * cos(7.5 * x)
            n.scale = SCNVector3(1, max(0.001, y), 1)
        }
        node.runAction(.sequence([.wait(duration: delay), grow, .run { $0.scale = SCNVector3(1, 1, 1) }]))
    }

    private func buildTrees(_ map: MapModel) {
        var rng = SeededRandom(seed: UInt64(bitPattern: Int64(map.tile.ix * 7919 + map.tile.iy * 104_729 + 17)))
        var spots: [(Vec2, Double)] = map.trees.map { ($0, 1.0) }
        for a in map.areas where a.kind == .park {
            let xs = a.outline.map(\.x), ys = a.outline.map(\.y)
            var y = ys.min()!
            while y < ys.max()! {
                var x = xs.min()!
                while x < xs.max()! {
                    let p = Vec2(x: x + rng.next(-4, 4), y: y + rng.next(-4, 4))
                    if Polygon.contains(a.outline, p), !map.isInsideBuilding(p),
                       !spots.contains(where: { $0.0.distance(to: p) < 30 }) { spots.append((p, rng.next(0.9, 1.2))) }
                    x += 18
                }
                y += 18
            }
        }
        // 做减法：最多 12 棵。
        spots = Array(spots.prefix(12))
        debugInfo["trees"] = min(spots.count, 1200)
        guard let geo = MeshBuilder.trees(Array(spots.prefix(1200)), greens: SceneStyle.treeGreens, trunk: SceneStyle.trunk) else { return }
        let node = SCNNode(geometry: geo)
        node.castsShadow = true
        treesNode.addChildNode(node)
    }

    func setLandmarks(_ landmarks: [Landmark]) {
        landmarksNode.childNodes.forEach { $0.removeFromParentNode() }
        landmarkNodes = [:]
        lock.lock(); landmarkInfo = Dictionary(uniqueKeysWithValues: landmarks.map { ($0.id, $0) }); lock.unlock()
        for l in landmarks {
            let n = Figures.landmark(hasSeat: l.hasSeat)
            n.position = scenePoint(l.pos)
            n.name = "lm:\(l.id)"
            landmarksNode.addChildNode(n)
            landmarkNodes[l.id] = n
        }
    }

    func renameLandmark(_ id: String, to name: String) {
        lock.lock(); landmarkInfo[id]?.name = name; lock.unlock()
    }

    // MARK: - 太阳

    private func setupLights() {
        let sun = SCNLight()
        sun.type = .directional
        sun.castsShadow = true
        sun.shadowMode = .forward
        sun.shadowBias = 3
        sun.shadowSampleCount = 16
        sun.shadowRadius = 4
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.shadowColor = UIColor(red: 0.45, green: 0.45, blue: 0.52, alpha: 0.12)
        sun.automaticallyAdjustsShadowProjection = false
        sun.orthographicScale = 0.42
        sun.zNear = 0.05
        sun.zFar = 3
        sunNode.light = sun
        scene.rootNode.addChildNode(sunNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 820
        amb.color = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        ambientNode.light = amb
        scene.rootNode.addChildNode(ambientNode)
        setSun(SolarPosition(elevation: 45, azimuth: 135), animated: false)
    }

    /// 太阳高度和方位驱动光照方向、强度和色温；夜晚只留柔和环境光。
    func setSun(_ sun: SolarPosition, animated: Bool) {
        let d = sun.direction
        let up = max(d.up, 0.02)
        let dir = SCNVector3(Float(d.east), Float(up), Float(-d.north))
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.8 : 0
        sunNode.position = SCNVector3(dir.x * 1.2, dir.y * 1.2, dir.z * 1.2)
        sunNode.look(at: SCNVector3(0, 0, 0))
        let day = sun.elevation > 0
        let warm = max(0, min(1, (sun.elevation - 5) / 35))
        sunNode.light?.intensity = day ? CGFloat(230 + 60 * warm) : 0
        sunNode.light?.temperature = CGFloat(5200 + 1300 * warm)
        ambientNode.light?.intensity = day ? 820 : 520
        ambientNode.light?.color = day ? UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1) : UIColor(red: 0.62, green: 0.68, blue: 0.86, alpha: 1)
        SCNTransaction.commit()
    }

    // MARK: - 相机


    private func setupCamera() {
        let cam = SCNCamera()
        // 等距（正交）投影：和参考图一样平行线不汇聚。distance 只用来换算放大倍数。
        cam.usesOrthographicProjection = true
        cam.zNear = 0.05
        cam.zFar = 12
        cam.wantsHDR = LaunchArgs.has("-hdr")
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = 0.15
        cam.bloomIntensity = 0
        cam.screenSpaceAmbientOcclusionIntensity = LaunchArgs.has("-ssao") ? 0.75 : 0
        cam.screenSpaceAmbientOcclusionRadius = 0.006
        cam.screenSpaceAmbientOcclusionBias = 0.0005
        cam.screenSpaceAmbientOcclusionDepthThreshold = 0.05
        cam.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        cam.wantsDepthOfField = false
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        applyCamera()
    }

    private func applyCamera() {
        let t = scenePoint(target)
        let far: Float = 4
        let horiz = cos(pitch) * far
        cameraNode.position = SCNVector3(t.x + horiz * sin(azimuth), sin(pitch) * far, t.z + horiz * cos(azimuth))
        cameraNode.look(at: t, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        // 与之前 20° 透视在同等 distance 下的取景高度一致：半高 = distance · tan(10°)。
        cameraNode.camera?.orthographicScale = Double(distance) * 0.1763
    }

    func setCamera(target t: Vec2, distance d: Float, animated: Bool, duration: Double = 0.75) {
        stopMomentum()
        let half = (map?.half ?? 280) - 30
        let clamped = Vec2(x: max(-half, min(half, t.x)), y: max(-half, min(half, t.y)))
        guard animated else { target = clamped; distance = d; applyCamera(); return }
        let from = (target, distance)
        let action = SCNAction.customAction(duration: duration) { [weak self] _, e in
            guard let self else { return }
            let x = Double(e) / duration
            // 临界阻尼弹簧的形状：起步快、结尾柔。
            let k = 1 - exp(-7 * x) * (1 + 7 * x)
            self.target = from.0 + (clamped - from.0) * k
            self.distance = from.1 + (d - from.1) * Float(k)
            self.applyCamera()
        }
        cameraNode.removeAction(forKey: "fly")
        cameraNode.runAction(action, forKey: "fly")
    }

    /// 总览：看到整个底座，沿视线（西北）方向偏移，底座只上下移、不左右偏，给顶部按钮留位置。
    /// 数值按 560 m 底座调好，再按当前底座边长等比缩放。
    var overviewTarget: Vec2 {
        let size = map?.size ?? 560
        // 300 m 小底座上高楼相对更高：取景中心再往下压一点，楼顶不碰顶部状态栏。
        let k = LaunchArgs.value("-ovy").flatMap(Double.init) ?? (size < 400 ? 90 : 72 * size / 560)
        return Vec2(x: -k, y: k)
    }
    var overviewDistance: Float {
        let size = map?.size ?? 560
        return Float(LaunchArgs.value("-ovd").flatMap(Double.init) ?? (size < 400 ? 1.42 : 2.35 * size / 560))
    }
    func resetCamera() { setCamera(target: overviewTarget, distance: overviewDistance, animated: true) }
    /// 回到我屋企：推近到自己住的楼。
    func flyHome() { setCamera(target: homeTarget, distance: 1.1, animated: true) }

    /// 屏幕点对应的地面（y=0）米坐标。
    func groundPoint(at p: CGPoint) -> Vec2? {
        guard let v = view else { return nil }
        let near = v.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 0))
        let far = v.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 1))
        let dy = far.y - near.y
        guard abs(dy) > 1e-7 else { return nil }
        let t = -near.y / dy
        let x = near.x + (far.x - near.x) * t, z = near.z + (far.z - near.z) * t
        let s = Double(SceneStyle.scale)
        return Vec2(x: Double(x) / s, y: -Double(z) / s)
    }

    // 手势
    private var panAnchor: Vec2?
    private var pinchStart: Float = 1

    func panBegan(at p: CGPoint) {
        lastUserInteraction = CACurrentMediaTime()
        stopMomentum()
        cameraNode.removeAction(forKey: "fly")
        panAnchor = groundPoint(at: p)
    }

    func panChanged(at p: CGPoint) {
        lastUserInteraction = CACurrentMediaTime()
        guard let anchor = panAnchor, let g = groundPoint(at: p) else { return }
        moveTarget(by: anchor - g)
    }

    func panEnded(at p: CGPoint, velocity v: CGPoint) {
        panAnchor = nil
        guard let a = groundPoint(at: p), let b = groundPoint(at: CGPoint(x: p.x + v.x * 0.01, y: p.y + v.y * 0.01)) else { return }
        velocity = (a - b) * 100   // 米/秒
        guard velocity.length > 8 else { velocity = .zero; return }
        lastTick = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = now - lastTick
        lastTick = now
        moveTarget(by: velocity * dt)
        // 与系统滚动一致的减速：每秒保留 13.5%。
        velocity = velocity * pow(0.135, dt)
        if velocity.length < 3 { stopMomentum() }
    }

    private func stopMomentum() {
        displayLink?.invalidate()
        displayLink = nil
        velocity = .zero
    }

    private func moveTarget(by d: Vec2) {
        let half = (map?.half ?? 280) - 30
        target = Vec2(x: max(-half, min(half, target.x + d.x)), y: max(-half, min(half, target.y + d.y)))
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        applyCamera()
        SCNTransaction.commit()
    }

    func pinchBegan() { lastUserInteraction = CACurrentMediaTime(); pinchStart = distance; cameraNode.removeAction(forKey: "fly") }
    func pinchChanged(scale: CGFloat) {
        distance = max(minDistance, min(maxDistance, pinchStart / Float(max(scale, 0.05))))
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        applyCamera()
        SCNTransaction.commit()
    }

    // MARK: - 命中

    enum Hit { case building(Int64), landmark(String), person(String) }

    func hit(at p: CGPoint) -> Hit? {
        guard let v = view else { return nil }
        let results = v.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
        for r in results {
            var n: SCNNode? = r.node
            while let cur = n {
                if let name = cur.name {
                    if name.hasPrefix("person:") { return .person(String(name.dropFirst(7))) }
                    if name.hasPrefix("lm:") { return .landmark(String(name.dropFirst(3))) }
                    if name.hasPrefix("bld:"), let id = Int64(name.dropFirst(4)) { return .building(id) }
                }
                n = cur.parent
            }
        }
        return nil
    }

    // MARK: - 高亮与遮挡

    func highlightBuildings(_ ids: Set<Int64>, color: UIColor?) {
        for (id, node) in pickableNodes {
            let on = ids.contains(id)
            node.geometry?.materials.forEach { $0.emission.contents = on ? (color ?? SceneStyle.accent).withAlphaComponent(0.35) : UIColor.black }
        }
    }

    func setHomeBuilding(_ id: Int64?) {
        homeBuildingID = id
        if let id, let b = map?.building(id: id) { homeTarget = b.centroid }
    }

    func highlightLandmark(_ id: String?) {
        for (lid, node) in landmarkNodes {
            let on = lid == id
            node.removeAction(forKey: "pulse")
            if let halo = node.childNode(withName: "halo", recursively: false) {
                if on {
                    let up = SCNAction.scale(to: 1.5, duration: 0.7); up.timingMode = .easeInEaseOut
                    let down = SCNAction.scale(to: 1.0, duration: 0.7); down.timingMode = .easeInEaseOut
                    halo.runAction(.repeatForever(.sequence([up, down])), forKey: "pulse")
                } else {
                    halo.removeAllActions()
                    halo.scale = SCNVector3(1, 1, 1)
                }
            }
        }
    }

    /// 相机与焦点之间的高楼变半透明（固定视角下看不到楼后的人和地标）。
    func fadeOccluders(toward p: Vec2?) {
        var fade: Set<Int64> = []
        if let p {
            let from = cameraNode.presentation.worldPosition
            let to = scenePoint(p, height: 6)
            let hits = buildingsNode.hitTestWithSegment(from: from, to: to, options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue])
            for h in hits { if let name = h.node.name, name.hasPrefix("bld:"), let id = Int64(name.dropFirst(4)) { fade.insert(id) } }
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.35
        for (id, node) in towerNodes { node.opacity = fade.contains(id) ? 0.25 : 1 }
        SCNTransaction.commit()
    }

    // MARK: - 人物

    func setPeople(_ people: [ScenePerson]) {
        let ids = Set(people.map(\.id))
        for (id, node) in personNodes where !ids.contains(id) {
            let fade = SCNAction.fadeOut(duration: 0.3)
            node.runAction(.sequence([fade, .removeFromParentNode()]))
            lock.lock(); personNodes[id] = nil; personState[id] = nil; lock.unlock()
        }
        for p in people {
            let old = personState[p.id]
            var node = personNodes[p.id]
            if node == nil || old?.mobility != p.mobility || old?.color != p.color {
                node?.removeFromParentNode()
                let n = Figures.person(color: p.color, mobility: p.mobility)
                n.name = "person:\(p.id)"
                n.opacity = 0
                n.runAction(.fadeIn(duration: 0.35))
                peopleNode.addChildNode(n)
                bob(n)
                node = n
                lock.lock(); personNodes[p.id] = n; lock.unlock()
                if let start = startPoint(p.motion) { n.position = scenePoint(start) }
            }
            if old?.motion != p.motion { apply(p.motion, to: node!) }
            lock.lock(); personState[p.id] = p; lock.unlock()
        }
    }

    private func startPoint(_ m: ScenePerson.Motion) -> Vec2? {
        switch m {
        case .wander(let c): return pathGrid?.nearestWalkable(c + Vec2(x: 6, y: -4)) ?? c
        case .route(let r, _): return r.first
        case .stand(let p): return p
        }
    }

    private func bob(_ n: SCNNode) {
        guard let body = n.childNode(withName: "body", recursively: false), !UIAccessibility.isReduceMotionEnabled else { return }
        let up = SCNAction.moveBy(x: 0, y: CGFloat(1.0 * SceneStyle.scale), z: 0, duration: 0.28); up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0, y: -CGFloat(1.0 * SceneStyle.scale), z: 0, duration: 0.28); down.timingMode = .easeIn
        body.runAction(.repeatForever(.sequence([up, down])), forKey: "bob")
    }

    private func apply(_ m: ScenePerson.Motion, to node: SCNNode) {
        node.removeAction(forKey: "move")
        switch m {
        case .stand(let p):
            let a = SCNAction.move(to: scenePoint(p), duration: 0.4); a.timingMode = .easeInEaseOut
            node.runAction(a, forKey: "move")
        case .route(let pts, let speed):
            node.runAction(walk(pts, speed: speed, from: node), forKey: "move")
        case .wander(let c):
            var rng = SeededRandom(seed: UInt64(abs(c.x * 1000 + c.y)))
            var pts: [Vec2] = []
            for _ in 0..<5 {
                let p = Vec2(x: c.x + rng.next(-22, 22), y: c.y + rng.next(-22, 22))
                pts.append(pathGrid?.nearestWalkable(p) ?? p)
            }
            let loop = walk(pts + [pts[0]], speed: 3.5, from: nil)
            node.runAction(.repeatForever(.sequence([loop, .wait(duration: 1.5)])), forKey: "move")
        }
    }

    /// 沿折线走，每段转向前进方向。
    private func walk(_ pts: [Vec2], speed: Double, from node: SCNNode?) -> SCNAction {
        var actions: [SCNAction] = []
        var prev: Vec2? = nil
        if let node {
            let p = node.position
            let s = Double(SceneStyle.scale)
            prev = Vec2(x: Double(p.x) / s, y: -Double(p.z) / s)
        }
        for p in pts {
            if let q = prev {
                let d = q.distance(to: p)
                if d < 0.3 { prev = p; continue }
                let heading = atan2(p.x - q.x, p.y - q.y)     // 从北顺时针
                let turn = SCNAction.rotateTo(x: 0, y: CGFloat(.pi - heading), z: 0, duration: 0.18, usesShortestUnitArc: true)
                let move = SCNAction.move(to: scenePoint(p), duration: d / max(speed, 0.1))
                actions.append(.group([turn, move]))
            } else {
                actions.append(.move(to: scenePoint(p), duration: 0))
            }
            prev = p
        }
        return .sequence(actions)
    }

    func route(from a: Vec2, to b: Vec2) -> [Vec2] { pathGrid?.path(from: a, to: b) ?? [a, b] }
    func nearestWalkable(_ p: Vec2) -> Vec2 { pathGrid?.nearestWalkable(p) ?? p }

    func personPosition(_ id: String) -> Vec2? {
        guard let n = personNodes[id] else { return nil }
        let p = n.presentation.position
        let s = Double(SceneStyle.scale)
        return Vec2(x: Double(p.x) / s, y: -Double(p.z) / s)
    }

    // MARK: - 路线

    func setTrail(_ pts: [Vec2]) { setRibbon("trail", pts, width: 4, color: SceneStyle.accent.withAlphaComponent(0.55), dash: 0, height: 0.35) }
    func setRoute(_ pts: [Vec2]?) { setRibbon("route", pts ?? [], width: 3, color: SceneStyle.accent, dash: 5, height: 0.45) }

    private func setRibbon(_ name: String, _ pts: [Vec2], width: Double, color: UIColor, dash: Double, height: Double) {
        routesNode.childNode(withName: name, recursively: false)?.removeFromParentNode()
        guard let geo = MeshBuilder.ribbon(pts, width: width, height: height, dash: dash) else { return }
        let m = MeshBuilder.material(color, lit: false)
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = true
        geo.firstMaterial = m
        let n = SCNNode(geometry: geo)
        n.name = name
        n.castsShadow = false
        n.renderingOrder = 5
        routesNode.addChildNode(n)
    }

    private func followStep() {
        guard let fid = followID, panAnchor == nil, displayLink == nil,
              CACurrentMediaTime() - lastUserInteraction > 3, cameraNode.action(forKey: "fly") == nil else { return }
        lock.lock(); let node = personNodes[fid]; lock.unlock()
        guard let n = node else { return }
        let p = n.presentation.worldPosition
        let s = Double(SceneStyle.scale)
        let goal = Vec2(x: Double(p.x) / s, y: -Double(p.z) / s)
        target = target + (goal - target) * 0.06
        applyCamera()
    }

    // MARK: - 标签投影（渲染线程 → 主线程）

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        followStep()
        guard time - lastOverlayPush > 1.0 / 30 else { return }
        lastOverlayPush = time
        var items: [OverlayItem] = []
        let s = SceneStyle.scale
        lock.lock()
        let personState = self.personState, personNodes = self.personNodes, landmarkInfo = self.landmarkInfo, landmarkNodes = self.landmarkNodes
        let reportMarks = self.reportMarks, homeID = self.homeBuildingID, homeLabel = self.homeLabel, map = self.map
        lock.unlock()
        func project(_ p: SCNVector3) -> CGPoint? {
            let q = renderer.projectPoint(p)
            guard q.z > 0, q.z < 1 else { return nil }
            return CGPoint(x: CGFloat(q.x), y: CGFloat(q.y))
        }
        for (id, st) in personState {
            guard let label = st.label, let n = personNodes[id] else { continue }
            var p = n.presentation.worldPosition
            p.y += 16 * s
            if let pt = project(p) { items.append(OverlayItem(id: "p:\(id)", kind: .person, text: label, point: pt, highlighted: st.highlighted, priority: st.highlighted ? 3 : 2)) }
        }
        for (id, l) in landmarkInfo {
            guard let n = landmarkNodes[id] else { continue }
            var p = n.worldPosition
            p.y -= 0.5 * s
            if let pt = project(p) { items.append(OverlayItem(id: "l:\(id)", kind: .landmark, text: l.name, point: pt, highlighted: false, priority: 1)) }
        }
        if let id = homeID, let label = homeLabel, let b = map?.building(id: id) {
            if let pt = project(scenePoint(b.centroid, height: b.height + 6)) {
                items.append(OverlayItem(id: "home", kind: .home, text: label, point: pt, highlighted: false, priority: 2))
            }
        }
        for r in reportMarks {
            if let pt = project(scenePoint(r.pos, height: 2)) { items.append(OverlayItem(id: "r:\(r.id)", kind: .report, text: r.text, point: pt, highlighted: false, priority: 0)) }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.overlay.items = items
            self.onOverlay?(items)
        }
    }
}

/// 可重复的伪随机数（同一格子每次生成一样的树和人）。
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func nextUInt() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var x = state
        x ^= x >> 33; x = x &* 0xff51afd7ed558ccd; x ^= x >> 33
        return x
    }
    mutating func next(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * Double(nextUInt() % 1_000_000) / 1_000_000
    }
}
