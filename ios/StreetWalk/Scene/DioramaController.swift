import SceneKit
import UIKit
import QuartzCore

/// Scene appearance state for self and neighbors only; never add non-neighbors.
struct ScenePerson: Equatable {
    enum Motion: Equatable {
        case wander(around: Vec2)          // Wander slowly within 25 m of a landmark.
        case route([Vec2], speed: Double)  // Follow a route in metres per second, accelerated for demos.
        case catchUp(lead: [Vec2], fast: Double, rest: [Vec2], speed: Double)  // Traverse lead quickly to catch up, then follow rest at speed.
        case stand(at: Vec2)
    }
    var id: String
    var color: UIColor
    var mobility: Mobility
    var motion: Motion
    var label: String?
    var highlighted = false
    /// Skin/age appearance filled from resident data by AppStore.syncScene.
    var skin = 1
    var age: AgeGroup = .adult
}

/// A SwiftUI overlay label following its projected 3D position.
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

/// Complete diorama logic: construction, sunlight, camera, people, routes, occlusion fading, and projected labels.
/// Build/mutate on the main thread; the SceneKit render thread reads label/follow state only in renderer(_:updateAtTime:).
/// Lock writes to all render-read properties; the render thread copies a snapshot under the same lock.
final class DioramaController: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    weak var view: SCNView?
    let overlay = OverlayModel()

    private var _map: MapModel?
    var map: MapModel? { locked { _map } }
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

    // Camera: fixed tilt and heading, moved automatically by the flow; this historical scene has no drag or zoom controls.
    private let cameraNode = SCNNode()
    private let sunNode = SCNNode()
    private let ambientNode = SCNNode()
    private let pitch: Float = Float(LaunchArgs.value("-pitch").flatMap(Double.init) ?? 33) * .pi / 180
    private let azimuth: Float = 45 * .pi / 180      // View from the southeast.
    private var _target = Vec2(x: -72, y: 72)
    private var _distance: Float = 2.35
    /// Ground target in metres, locked because flight/follow updates occur on the render thread.
    private(set) var target: Vec2 {
        get { locked { _target } }
        set { locked { _target = newValue } }
    }
    private(set) var distance: Float {
        get { locked { _distance } }
        set { locked { _distance = newValue } }
    }
    var homeTarget = Vec2.zero

    // Labels: render-thread reads and main-thread writes both use the lock.
    private var _homeBuildingID: Int64?
    private var _homeLabel: String?
    private var _reportMarks: [(id: String, pos: Vec2, text: String)] = []
    private var _followID: String?
    var homeBuildingID: Int64? {
        get { locked { _homeBuildingID } }
        set { locked { _homeBuildingID = newValue }; labelsChanged() }
    }
    var homeLabel: String? {
        get { locked { _homeLabel } }
        set { guard newValue != homeLabel else { return }; locked { _homeLabel = newValue }; labelsChanged() }
    }
    var reportMarks: [(id: String, pos: Vec2, text: String)] {
        get { locked { _reportMarks } }
        set { locked { _reportMarks = newValue }; labelsChanged() }
    }
    /// Follow a person, normally self during a walk.
    var followID: String? {
        get { locked { _followID } }
        set { locked { _followID = newValue } }
    }
    /// Publish changed labels at most 20 times per second to limit SwiftUI work and power use.
    private static let overlayInterval = 1.0 / 20
    private var lastOverlayPush: TimeInterval = 0
    private var lastOverlay: [OverlayItem] = []
    private var trailingScheduled = false
    /// Increment snapshot versions and accept only newer ones on main, preventing stale render/main publications from overwriting updates.
    private var overlaySeq = 0
    private var lastOverlaySeq = 0
    private var appliedSeq = 0   // Access only on the main thread.
    private let lock = NSLock()

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    /// Reduce Motion: jump camera, omit building rise, and stop halo pulses. Cache the setting on main for render-thread access.
    private var _reduceMotion = UIAccessibility.isReduceMotionEnabled
    private var reduceMotion: Bool { locked { _reduceMotion } }

    /// Resolve SceneStyle adaptive colors using dark-mode state during construction.
    private(set) var isDark = UITraitCollection.current.userInterfaceStyle == .dark
    private var traits: UITraitCollection { UITraitCollection(userInterfaceStyle: isDark ? .dark : .light) }
    private var highlighted: (ids: Set<Int64>, color: UIColor?) = ([], nil)
    private var highlightedLandmark: String?
    /// Buildings currently faded, restored after rebuilding for appearance changes.
    private var faded: Set<Int64> = []

    override init() {
        super.init()
        scene.background.contents = SceneStyle.background.resolvedColor(with: traits)
        scene.rootNode.addChildNode(world)
        [plinthNode, buildingsNode, treesNode, landmarksNode, routesNode, peopleNode].forEach(world.addChildNode)
        setupCamera()
        setupLights()
        NotificationCenter.default.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            let on = UIAccessibility.isReduceMotionEnabled
            self?.locked { self?._reduceMotion = on }
        }
    }

    // MARK: - Construction

    func load(map: MapModel, landmarks: [Landmark], animated: Bool) {
        locked { _map = map }
        pathGrid = PathGrid(map: map)
        [plinthNode, buildingsNode, treesNode, landmarksNode, routesNode, peopleNode].forEach { $0.childNodes.forEach { $0.removeFromParentNode() } }
        locked { towerNodes = [:]; pickableNodes = [:]; landmarkNodes = [:]; personNodes = [:]; personState = [:] }
        faded = []

        // Scale shadow bounds with the base for sharper shadows on small scenes.
        sunNode.light?.orthographicScale = map.size * Double(SceneStyle.scale) * 0.75
        highlighted = ([], nil)
        highlightedLandmark = nil
        traits.performAsCurrent {
            buildPlinth(map)
            buildBuildings(map, animated: animated)
            buildTrees(map)
            setLandmarks(landmarks)
        }
    }

    /// On light/dark changes, rebuild ground/building/tree/landmark materials without replaying rise animation or moving people/routes.
    func setDark(_ dark: Bool) {
        guard dark != isDark else { return }
        isDark = dark
        scene.background.contents = SceneStyle.background.resolvedColor(with: traits)
        sunNode.light?.shadowColor = shadowColor
        guard let map else { return }
        [plinthNode, buildingsNode, treesNode].forEach { $0.childNodes.forEach { $0.removeFromParentNode() } }
        let lms: [Landmark] = locked { towerNodes = [:]; pickableNodes = [:]; return Array(landmarkInfo.values) }
        traits.performAsCurrent {
            buildPlinth(map)
            buildBuildings(map, animated: false)
            buildTrees(map)
            setLandmarks(lms)
        }
        highlightBuildings(highlighted.ids, color: highlighted.color)
        highlightLandmark(highlightedLandmark)
        for (id, node) in towerNodes where faded.contains(id) { node.opacity = 0.25 }
    }

    private var shadowColor: UIColor {
        isDark ? UIColor(white: 0, alpha: 0.32) : UIColor(red: 0.45, green: 0.45, blue: 0.52, alpha: 0.12)
    }

    private func buildPlinth(_ map: MapModel) {
        let L = CGFloat(Double(map.size) * Double(SceneStyle.scale))
        let t = CGFloat(SceneStyle.plinthThickness)
        let box = SCNBox(width: L, height: t, length: L, chamferRadius: 0.0015)
        let side = MeshBuilder.material(SceneStyle.plinthSide)
        let top = MeshBuilder.material(SceneStyle.paving)
        let bottom = MeshBuilder.material(SceneStyle.plinthSide)
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

    }

    private func buildBuildings(_ map: MapModel, animated: Bool) {
        let wallMats = SceneStyle.facadeTints.map { MeshBuilder.material($0) }
        let plainWall = MeshBuilder.material(SceneStyle.facadeTints[0])
        let roof = MeshBuilder.material(SceneStyle.roof)
        let constructionMat = MeshBuilder.material(SceneStyle.construction)
        let canopyMat = MeshBuilder.material(SceneStyle.canopy)
        let schoolMat = MeshBuilder.material(SceneStyle.school)
        let commercialMat = MeshBuilder.material(SceneStyle.commercial)
        let homeMat = MeshBuilder.material(SceneStyle.home)

        let lowGroup = SCNNode()
        let homeBuildingID = self.homeBuildingID
        for b in map.buildings {
            let geo = MeshBuilder.building(b)
            // Color by purpose; home is the focal point with pale orange and an orange outline.
            switch b.kind {
            case _ where b.id == homeBuildingID: geo.materials = [homeMat, homeMat]
            case .construction: geo.materials = [constructionMat, constructionMat]
            case .canopy: geo.materials = [canopyMat, canopyMat]
            case .small: geo.materials = [plainWall, roof]
            case .school: geo.materials = [schoolMat, schoolMat]
            case .commercial: geo.materials = [commercialMat, commercialMat]
            default: geo.materials = [wallMats[Int(abs(b.id) % Int64(wallMats.count))], roof]
            }
            let node = SCNNode(geometry: geo)
            node.name = "bld:\(b.id)"
            node.castsShadow = true
            if b.kind != .canopy, let edges = MeshBuilder.outline(b, color: b.id == homeBuildingID ? SceneStyle.accent : SceneStyle.outline) {
                let en = SCNNode(geometry: edges)
                en.castsShadow = false
                node.addChildNode(en)
            }
            if b.isTower || b.kind == .residential || b.id == homeBuildingID {
                // Give selectable buildings separate materials so highlighting one cannot tint others.
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

        guard animated, !reduceMotion else { return }
        // Stagger building-rise animations by distance from home.
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
            // Approximate a spring: rise quickly, rebound slightly, then settle.
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
                       !spots.contains(where: { $0.0.distance(to: p) < 22 }) { spots.append((p, rng.next(0.9, 1.2))) }
                    x += 18
                }
                y += 18
            }
        }
        // Keep the scene sparse: at most five trees.
        spots = Array(spots.prefix(5))
        guard let geo = MeshBuilder.trees(spots, greens: SceneStyle.treeGreens, trunk: SceneStyle.trunk) else { return }
        let node = SCNNode(geometry: geo)
        node.castsShadow = true
        treesNode.addChildNode(node)
    }

    func setLandmarks(_ landmarks: [Landmark]) {
        landmarksNode.childNodes.forEach { $0.removeFromParentNode() }
        var nodes: [String: SCNNode] = [:]
        for l in landmarks {
            let n = Figures.landmark(hasSeat: l.hasSeat)
            n.position = scenePoint(l.pos)
            n.name = "lm:\(l.id)"
            landmarksNode.addChildNode(n)
            nodes[l.id] = n
        }
        locked {
            landmarkInfo = Dictionary(landmarks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            landmarkNodes = nodes
        }
        labelsChanged()
    }

    func renameLandmark(_ id: String, to name: String) {
        locked { landmarkInfo[id]?.name = name }
        labelsChanged()
    }

    // MARK: - Sun

    private func setupLights() {
        let sun = SCNLight()
        sun.type = .directional
        sun.castsShadow = true
        sun.shadowMode = .forward
        sun.shadowBias = 3
        sun.shadowSampleCount = 16
        sun.shadowRadius = 4
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.shadowColor = shadowColor
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

    /// Sun elevation/bearing drive light direction, intensity, and color temperature; retain only soft ambient light at night.
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
        // No sun at night; skip the shadow pass too.
        sunNode.light?.castsShadow = day
        sunNode.light?.temperature = CGFloat(5200 + 1300 * warm)
        ambientNode.light?.intensity = day ? 820 : 520
        ambientNode.light?.color = day ? UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1) : UIColor(red: 0.62, green: 0.68, blue: 0.86, alpha: 1)
        SCNTransaction.commit()
    }

    // MARK: - Camera

    private func setupCamera() {
        let cam = SCNCamera()
        // Orthographic projection keeps parallel lines parallel like the reference; distance only determines scale.
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

    /// Viewport-height ratio relative to the former 42%-screen scene: crop vertically while preserving pixels per metre after the 10-12 reduction.
    /// One means the original ratio, also used for full-screen finding.
    var viewportScale: Float = 1 {
        didSet { if abs(viewportScale - oldValue) > 0.001 { applyCamera() } }
    }

    private func applyCamera() {
        let (tg, dist) = locked { (_target, _distance) }
        let t = scenePoint(tg)
        let far: Float = 4
        let horiz = cos(pitch) * far
        cameraNode.position = SCNVector3(t.x + horiz * sin(azimuth), sin(pitch) * far, t.z + horiz * cos(azimuth))
        cameraNode.look(at: t, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        // Match the previous 20-degree perspective framing: half-height = distance * tan(10 degrees).
        cameraNode.camera?.orthographicScale = Double(dist) * 0.1763 * Double(viewportScale)
    }

    /// Jump directly instead of flying under Reduce Motion.
    func setCamera(target t: Vec2, distance d: Float, animated: Bool, duration: Double = 0.75) {
        let half = (map?.half ?? 280) - 30
        let clamped = Vec2(x: max(-half, min(half, t.x)), y: max(-half, min(half, t.y)))
        guard animated, !reduceMotion else {
            cameraNode.removeAction(forKey: "fly")
            target = clamped; distance = d; applyCamera(); return
        }
        let from = (target, distance)
        let action = SCNAction.customAction(duration: duration) { [weak self] _, e in
            guard let self else { return }
            let x = Double(e) / duration
            // Critically damped spring shape: fast start, gentle finish.
            let k = 1 - exp(-7 * x) * (1 + 7 * x)
            self.target = from.0 + (clamped - from.0) * k
            self.distance = from.1 + (d - from.1) * Float(k)
            self.applyCamera()
        }
        cameraNode.removeAction(forKey: "fly")
        cameraNode.runAction(action, forKey: "fly")
    }

    /// Overview frames the whole base, offset along the northwest view axis to move vertically without sideways drift and leave room for controls.
    /// Values were tuned for a 560-m base and scale with the current width.
    var overviewTarget: Vec2 {
        let size = map?.size ?? 560
        // On a 300-m base, tall buildings are proportionally larger; lower the framing centre to keep roofs clear of the status bar.
        let k = LaunchArgs.value("-ovy").flatMap(Double.init) ?? (size < 400 ? 60 * size / 200 : 72 * size / 560)
        return Vec2(x: -k, y: k)
    }
    var overviewDistance: Float {
        let size = map?.size ?? 560
        return Float(LaunchArgs.value("-ovd").flatMap(Double.init) ?? (size < 400 ? 0.88 * size / 200 : 2.35 * size / 560))
    }
    func resetCamera() { setCamera(target: overviewTarget, distance: overviewDistance, animated: true) }

    // MARK: - Hit testing

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

    // MARK: - Highlighting and occlusion

    /// Tint white buildings by multiplication rather than emission; a single selected building uses a stronger orange.
    /// Dark-gray buildings need a warm overlay plus orange emission because multiplication alone remains too dark.
    func highlightBuildings(_ ids: Set<Int64>, color: UIColor?) {
        highlighted = (ids, color)
        // Use solid orange for selectable buildings; the former pale tint was hard for older users to identify. Selected is darker.
        let tint = color ?? (ids.count == 1 ? UIColor(red: 0.86, green: 0.40, blue: 0.22, alpha: 1)
                                            : UIColor(red: 0.95, green: 0.62, blue: 0.42, alpha: 1))
        let glow = ids.count == 1 ? UIColor(red: 0.62, green: 0.28, blue: 0.04, alpha: 1) : UIColor(red: 0.45, green: 0.22, blue: 0.06, alpha: 1)
        let warm = UIColor(red: 1, green: 0.78, blue: 0.5, alpha: 1)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.35
        for (id, node) in pickableNodes {
            let on = ids.contains(id)
            node.geometry?.materials.forEach {
                $0.multiply.contents = on ? (isDark ? warm : tint) : UIColor.white
                $0.emission.contents = on && isDark ? (color ?? glow) : UIColor.black
            }
        }
        SCNTransaction.commit()
    }

    func setHomeBuilding(_ id: Int64?) {
        homeBuildingID = id
        if let id, let b = map?.building(id: id) { homeTarget = b.centroid }
    }

    /// Selected-landmark halo pulses slowly, or remains statically enlarged under Reduce Motion.
    func highlightLandmark(_ id: String?) {
        highlightedLandmark = id
        for (lid, node) in landmarkNodes {
            let on = lid == id
            node.removeAction(forKey: "pulse")
            if let halo = node.childNode(withName: "halo", recursively: false) {
                if on && reduceMotion {
                    halo.removeAllActions()
                    halo.scale = SCNVector3(1.3, 1, 1.3)
                } else if on {
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

    /// Fade tall buildings between the camera and focus so people/landmarks behind them remain visible.
    func fadeOccluders(toward p: Vec2?) {
        var fade: Set<Int64> = []
        if let p {
            let from = cameraNode.presentation.worldPosition
            let to = scenePoint(p, height: 6)
            let hits = buildingsNode.hitTestWithSegment(from: from, to: to, options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue])
            for h in hits { if let name = h.node.name, name.hasPrefix("bld:"), let id = Int64(name.dropFirst(4)) { fade.insert(id) } }
        }
        faded = fade
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.35
        for (id, node) in towerNodes { node.opacity = fade.contains(id) ? 0.25 : 1 }
        SCNTransaction.commit()
    }

    // MARK: - People

    func setPeople(_ people: [ScenePerson]) {
        let ids = Set(people.map(\.id))
        for (id, node) in personNodes where !ids.contains(id) {
            let fade = SCNAction.fadeOut(duration: 0.3)
            node.runAction(.sequence([fade, .removeFromParentNode()]))
            locked { personNodes[id] = nil; personState[id] = nil }
        }
        for p in people {
            let old = personState[p.id]
            var node = personNodes[p.id]
            if node == nil || old?.mobility != p.mobility || old?.color != p.color || old?.skin != p.skin || old?.age != p.age {
                node?.removeFromParentNode()
                let n = Figures.person(color: p.color, mobility: p.mobility, skin: p.skin, age: p.age)
                n.name = "person:\(p.id)"
                n.opacity = 0
                n.runAction(.fadeIn(duration: 0.35))
                peopleNode.addChildNode(n)
                bob(n)
                node = n
                locked { personNodes[p.id] = n }
                if let start = startPoint(p.motion) { n.position = scenePoint(start) }
            }
            if old?.motion != p.motion { apply(p.motion, to: node!) }
            locked { personState[p.id] = p }
        }
        labelsChanged()
    }

    private func startPoint(_ m: ScenePerson.Motion) -> Vec2? {
        switch m {
        case .wander(let c): return pathGrid?.nearestWalkable(c + Vec2(x: 6, y: -4)) ?? c
        case .route(let r, _): return r.first
        case .catchUp(let lead, _, _, _): return lead.first
        case .stand(let p): return p
        }
    }

    private func bob(_ n: SCNNode) {
        guard let body = n.childNode(withName: "body", recursively: false), !reduceMotion else { return }
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
            node.runAction(walk(pts, speed: speed, from: point(of: node)), forKey: "move")
        case .catchUp(let lead, let fast, let rest, let speed):
            node.runAction(.sequence([walk(lead, speed: fast, from: point(of: node)), walk(rest, speed: speed, from: lead.last)]), forKey: "move")
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

    private func point(of node: SCNNode) -> Vec2 {
        let p = node.position
        let s = Double(SceneStyle.scale)
        return Vec2(x: Double(p.x) / s, y: -Double(p.z) / s)
    }

    /// Follow a polyline from start, turning along each segment; without start, teleport to its first point.
    private func walk(_ pts: [Vec2], speed: Double, from start: Vec2?) -> SCNAction {
        var actions: [SCNAction] = []
        var prev = start
        for p in pts {
            if let q = prev {
                let d = q.distance(to: p)
                if d < 0.3 { prev = p; continue }
                let heading = atan2(p.x - q.x, p.y - q.y)     // Clockwise from north.
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

    // MARK: - Routes

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

    /// Render-thread camera follow. Under Reduce Motion, jump only after the person moves 35 m instead of continuously tracking.
    private func followStep() {
        let (fid, node) = locked { (_followID, _followID.flatMap { personNodes[$0] }) }
        guard fid != nil, let n = node, cameraNode.action(forKey: "fly") == nil else { return }
        let p = n.presentation.worldPosition
        let s = Double(SceneStyle.scale)
        let goal = Vec2(x: Double(p.x) / s, y: -Double(p.z) / s)
        let cur = target
        if reduceMotion {
            guard goal.distance(to: cur) > 35 else { return }
            target = goal
        } else {
            target = cur + (goal - cur) * 0.06
        }
        applyCamera()
    }

    // MARK: - Label projection from render thread to main

    /// Publish once from main when label content changes while the scene is stationary, such as names/reports/home labels.
    /// DioramaView renders only on changes, so render callbacks alone are insufficient.
    private func labelsChanged() { scheduleTrailing() }

    /// Schedule one main-thread catch-up publication no earlier than the next allowed interval; avoid duplicate scheduling.
    /// Also catch up a throttled render frame so labels reach the final position after animation stops.
    private func scheduleTrailing() {
        let delay: Double? = locked {
            guard !trailingScheduled else { return nil }
            trailingScheduled = true
            return max(0, lastOverlayPush + Self.overlayInterval - CACurrentMediaTime())
        }
        guard let delay else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.locked { self.trailingScheduled = false }
            if let v = self.view { self.pushOverlay(v) }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        followStep()
        pushOverlay(renderer)
    }

    /// Publish changed projected labels to SwiftUI at most once per overlayInterval (20 Hz); schedule a later update if throttled.
    private func pushOverlay(_ renderer: SCNSceneRenderer) {
        let now = CACurrentMediaTime()
        let due: Bool = locked {
            guard now - lastOverlayPush >= Self.overlayInterval - 0.001 else { return false }
            lastOverlayPush = now
            return true
        }
        guard due else { scheduleTrailing(); return }
        var items: [OverlayItem] = []
        let s = SceneStyle.scale
        let (personState, personNodes, landmarkInfo, landmarkNodes, reportMarks, homeID, homeLabel, map, seq) = locked {
            overlaySeq += 1
            return (self.personState, self.personNodes, self.landmarkInfo, self.landmarkNodes, _reportMarks, _homeBuildingID, _homeLabel, _map, overlaySeq)
        }
        func project(_ p: SCNVector3) -> CGPoint? {
            let q = renderer.projectPoint(p)
            guard q.z > 0, q.z < 1 else { return nil }
            // Round to half-points to prevent tiny jitter from relaying out labels.
            return CGPoint(x: (CGFloat(q.x) * 2).rounded() / 2, y: (CGFloat(q.y) * 2).rounded() / 2)
        }
        for (id, st) in personState {
            guard let label = st.label, let n = personNodes[id] else { continue }
            var p = n.presentation.worldPosition
            p.y += 16 * s
            if let pt = project(p) { items.append(OverlayItem(id: "p:\(id)", kind: .person, text: label, point: pt, highlighted: st.highlighted, priority: st.highlighted ? 3 : 2)) }
        }
        for (id, l) in landmarkInfo {
            guard let n = landmarkNodes[id] else { continue }
            var p = n.presentation.worldPosition
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
        items.sort { $0.id < $1.id }
        // Compare snapshot versions before replacing lastOverlay; an older snapshot could otherwise suppress a necessary update.
        let changed: Bool = locked {
            guard seq > lastOverlaySeq, items != lastOverlay else { return false }
            lastOverlay = items
            lastOverlaySeq = seq
            return true
        }
        guard changed else { return }
        let apply = { [weak self] in
            guard let self, seq > self.appliedSeq else { return }
            self.appliedSeq = seq
            self.overlay.items = items
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }
}

/// Deterministic pseudorandom values keep trees/people consistent for the same grid.
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
