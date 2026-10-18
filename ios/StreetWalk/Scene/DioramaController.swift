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
    enum Kind { case landmark, person, home, report, here }
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
    /// Show reset-camera control after user zoom/pan/rotation.
    var userMoved = false
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

    // Camera uses flow-controlled framing with user zoom/pan layered on top; double-tap resets.
    private let cameraNode = SCNNode()
    private let sunNode = SCNNode()
    private let ambientNode = SCNNode()
    private let pitch: Float = Float(LaunchArgs.value("-pitch").flatMap(Double.init) ?? 33) * .pi / 180
    private let baseAzimuth: Float = 45 * .pi / 180      // View from the southeast.
    /// User rotation around the vertical axis in radians; reset by double-tap, reset control, or flow overview.
    private var _yaw: Float = 0
    private var _target = Vec2(x: -72, y: 72)
    private var _distance: Float = 2.35
    /// User pan adds metres to the flow target; zoom multiplies distance, with values below one zooming in.
    private var _pan = Vec2.zero
    private var _zoom: Float = 1
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
    /// Current-location marker/label, already clamped to the scene edge by setHere on the main thread.
    private var _here: (pos: Vec2, text: String)?
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
    /// Home-selection tint from highlightPick; nil outside selection.
    private var pickHighlight: (candidates: Set<Int64>, selected: Int64?)?
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
        clearUserCamera()   // When changing bases or home-selection steps, let the flow reframe the camera and discard the previous gesture zoom.
        pathGrid = PathGrid(map: map)
        [plinthNode, buildingsNode, treesNode, landmarksNode, routesNode, peopleNode].forEach { $0.childNodes.forEach { $0.removeFromParentNode() } }
        locked { towerNodes = [:]; pickableNodes = [:]; landmarkNodes = [:]; personNodes = [:]; personState = [:] }
        faded = []

        // Scale shadow bounds with the base for sharper shadows on small scenes.
        sunNode.light?.orthographicScale = map.size * Double(SceneStyle.scale) * 0.75
        highlighted = ([], nil)
        pickHighlight = nil
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
        if let p = pickHighlight { highlightPick(candidates: p.candidates, selected: p.selected) } else { highlightBuildings(highlighted.ids, color: highlighted.color) }
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
        let (tg0, dist0, pan, zoom, yaw) = locked { (_target, _distance, _pan, _zoom, _yaw) }
        let azimuth = baseAzimuth + yaw
        let tg = tg0 + pan, dist = dist0 * zoom
        let t = scenePoint(tg)
        let far: Float = 4
        let horiz = cos(pitch) * far
        cameraNode.position = SCNVector3(t.x + horiz * sin(azimuth), sin(pitch) * far, t.z + horiz * cos(azimuth))
        cameraNode.look(at: t, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        // Match the previous 20-degree perspective framing: half-height = distance * tan(10 degrees).
        cameraNode.camera?.orthographicScale = Double(dist) * 0.1763 * Double(viewportScale)
    }

    /// Jump directly instead of flying under Reduce Motion.
    /// keepZoom=false also resets gesture zoom for overview/home selection.
    func setCamera(target t: Vec2, distance d: Float, animated: Bool, duration: Double = 0.75, keepZoom: Bool = true) {
        let half = (map?.half ?? 280) - 30
        let clamped = Vec2(x: max(-half, min(half, t.x)), y: max(-half, min(half, t.y)))
        // Flow camera changes discard pan because the target changed, but preserve zoom so tapping a landmark does not suddenly zoom out.
        // Fold existing pan into the flight origin to avoid a visual jump.
        let (pan, zoom) = locked { () -> (Vec2, Float) in
            let r = (_pan, _zoom); _pan = .zero
            if !keepZoom { _zoom = 1; _yaw = 0 }
            return r
        }
        if !keepZoom { setUserAdjusted(false) }
        guard animated, !reduceMotion else {
            cameraNode.removeAction(forKey: "fly")
            target = clamped; distance = d; applyCamera(); return
        }
        let from = (target + pan, distance * (keepZoom ? 1 : zoom))
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
    func resetCamera() { setCamera(target: overviewTarget, distance: overviewDistance, animated: true, keepZoom: false) }

    // MARK: - Two-finger zoom/pan; single-finger landmark taps and pull-to-enlarge

    /// Wait for double-tap reset only after a gesture changed the camera, avoiding delays on ordinary landmark taps.
    private(set) var userAdjusted = false
    private func setUserAdjusted(_ on: Bool) {
        userAdjusted = on
        if overlay.userMoved != on { overlay.userMoved = on }
    }
    /// Enable one-finger pan for home selection, full-screen finding, enlarged maps, or after gesture zoom.
    /// On the small Today map, single-finger downward drag belongs to enlarge; avoid conflicting pan handling.
    var oneFingerPan = false
    /// While or just after single-finger panning, prevent SwiftUI from interpreting it as pull-to-enlarge.
    private(set) var oneFingerPanning = false
    func setOneFingerPanning(_ on: Bool) {
        if on { oneFingerPanning = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.oneFingerPanning = false }
    }
    /// Remember the latest two-finger gesture so SwiftUI ignores an immediately following enlarge drag.
    private(set) var lastMultiTouch: CFTimeInterval = 0
    /// Zoom-in limit is one-quarter overview scale, about a 50-m area; zoom-out permits 25% beyond overview/flow framing.
    private var zoomRange: ClosedRange<Float> {
        let d = locked { _distance }
        let lo = overviewDistance * 0.25, hi = max(d, overviewDistance) * 1.25
        return (lo / max(d, 0.001))...(hi / max(d, 0.001))
    }

    /// Compute the ground point under a screen point directly from current orthographic camera target/pan.
    /// orthographicScale is half the viewport height in scene units. Avoid unprojectPoint's previous-frame projection when zoom and pan occur together.
    func groundPoint(at p: CGPoint) -> Vec2? {
        guard let v = view, v.bounds.height > 0, let cam = cameraNode.camera else { return nil }
        let (tg, pan, yaw) = locked { (_target, _pan, _yaw) }
        let upp = cam.orthographicScale * 2 / Double(v.bounds.height)          // Scene units per point.
        let s = Double(SceneStyle.scale)
        let dx = Double(p.x - v.bounds.midX) * upp / s                          // Metres to the right.
        let dy = Double(p.y - v.bounds.midY) * upp / s / Double(sin(pitch))     // Metres toward the camera, downward on screen.
        let az = Double(baseAzimuth + yaw)
        let right = Vec2(x: cos(az), y: sin(az)), toward = Vec2(x: sin(az), y: -cos(az))
        return tg + pan + right * dx + toward * dy
    }

    /// Clamp pan so the viewport centre remains within the base.
    private func clampPan(_ p: Vec2) -> Vec2 {
        let lim = (map?.half ?? 100) - 15
        let tg = target
        return Vec2(x: max(-lim - tg.x, min(lim - tg.x, p.x)), y: max(-lim - tg.y, min(lim - tg.y, p.y)))
    }

    private func touched() {
        lastMultiTouch = CACurrentMediaTime()
        setUserAdjusted(true)
        cameraNode.removeAction(forKey: "fly")
    }

    /// Rotate around the vertical axis while anchoring the ground beneath the two-finger midpoint. Gesture rotation is clockwise-positive.
    func userRotate(by rotation: CGFloat, around p: CGPoint) {
        guard abs(rotation) > 1e-5 else { return }
        touched()
        let before = groundPoint(at: p)
        locked {
            var y = _yaw + Float(rotation)
            if y > .pi { y -= 2 * .pi } else if y < -.pi { y += 2 * .pi }
            _yaw = y
        }
        applyCamera()
        if let a = before, let b = groundPoint(at: p) {
            let pan = clampPan(locked { _pan } + (a - b))
            locked { _pan = pan }
            applyCamera()
        }
    }

    /// Current gesture rotation in radians, used by screenshot checks.
    var yaw: Float { locked { _yaw } }

    /// Pinch around the two-finger midpoint, keeping its ground point under the fingers.
    func userZoom(by scale: CGFloat, around p: CGPoint) {
        guard scale > 0 else { return }
        touched()
        let (z0, pan0) = locked { (_zoom, _pan) }
        let z = min(zoomRange.upperBound, max(zoomRange.lowerBound, z0 / Float(scale)))
        guard abs(z - z0) > 1e-5 else { return }
        var pan = pan0
        // Orthographic zoom scales around C by f; to keep P fixed, move the centre to P + (C - P)*f.
        if let P = groundPoint(at: p) {
            let C = target + pan0, f = Double(z / z0)
            pan = pan0 + (P + (C - P) * f - C)
        }
        let clamped = clampPan(pan)
        locked { _zoom = z; _pan = clamped }
        applyCamera()
    }

    /// Two-finger pan keeps the ground under the fingers moving with them.
    func userPan(from a: CGPoint, to b: CGPoint) {
        touched()
        guard let pa = groundPoint(at: a), let pb = groundPoint(at: b) else { return }
        let pan = clampPan(locked { _pan } + (pa - pb))
        locked { _pan = pan }
        applyCamera()
    }

    /// Double-tap or enlarge/shrink resets gesture zoom/pan to the flow's camera framing.
    func resetUserCamera(animated: Bool = true) {
        guard userAdjusted else { return }
        setUserAdjusted(false)
        let (z0, p0, y0) = locked { (_zoom, _pan, _yaw) }
        guard animated, !reduceMotion else { clearUserCamera(); return }
        let duration = 0.45
        let action = SCNAction.customAction(duration: duration) { [weak self] _, e in
            guard let self else { return }
            let x = Double(e) / duration
            let k = 1 - exp(-7 * x) * (1 + 7 * x)
            self.locked { self._zoom = z0 + (1 - z0) * Float(k); self._pan = p0 * (1 - k); self._yaw = y0 * Float(1 - k) }
            self.applyCamera()
        }
        cameraNode.removeAction(forKey: "fly")
        cameraNode.runAction(.sequence([action, .run { [weak self] _ in self?.locked { self?._zoom = 1; self?._pan = .zero; self?._yaw = 0 } }]), forKey: "fly")
    }

    /// Immediately clear gesture zoom/pan when changing base or home-selection scene.
    func clearUserCamera() {
        setUserAdjusted(false)
        locked { _zoom = 1; _pan = .zero; _yaw = 0 }
        applyCamera()
    }

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
        if pickHighlight != nil {
            pickHighlight = nil
            buildingsNode.childNode(withName: "low", recursively: false)?.geometry?.materials.forEach { $0.multiply.contents = UIColor.white }
        }
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

    /// Consistent K-2 selection colors: candidates pale orange, selected dark orange/glowing, all others gray including low buildings.
    func highlightPick(candidates: Set<Int64>, selected: Int64?) {
        pickHighlight = (candidates, selected)
        highlighted = ([], nil)
        let light = UIColor(red: 0.97, green: 0.68, blue: 0.48, alpha: 1)
        let deep = UIColor(red: 0.84, green: 0.33, blue: 0.12, alpha: 1)
        let gray = isDark ? UIColor(white: 0.62, alpha: 1) : UIColor(white: 0.80, alpha: 1)
        let warm = UIColor(red: 1, green: 0.78, blue: 0.5, alpha: 1)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.35
        for (id, node) in pickableNodes {
            let sel = id == selected, cand = candidates.contains(id)
            node.geometry?.materials.forEach {
                if sel {
                    $0.multiply.contents = isDark ? warm : deep
                    $0.emission.contents = isDark ? UIColor(red: 0.85, green: 0.36, blue: 0.05, alpha: 1) : UIColor(red: 0.30, green: 0.08, blue: 0, alpha: 1)
                } else if cand {
                    $0.multiply.contents = isDark ? warm : light
                    $0.emission.contents = isDark ? UIColor(red: 0.40, green: 0.20, blue: 0.06, alpha: 1) : UIColor.black
                } else {
                    $0.multiply.contents = gray
                    $0.emission.contents = UIColor.black
                }
            }
        }
        buildingsNode.childNode(withName: "low", recursively: false)?.geometry?.materials.forEach { $0.multiply.contents = gray }
        SCNTransaction.commit()
    }

    /// Current location in scene metres, nil to hide. Clamp off-base markers to the edge and show distance from home/scene centre.
    func setHere(_ p: Vec2?) {
        guard let p, let map else { locked { _here = nil }; labelsChanged(); return }
        let lim = map.half - 6
        let c = Vec2(x: max(-lim, min(lim, p.x)), y: max(-lim, min(lim, p.y)))
        let text: String
        if c.distance(to: p) < 1, homeBuildingID != nil, p.distance(to: homeTarget) < 30 {
            text = ""   // At home, show only the dot so the tappable home label remains unobscured.
        } else if c.distance(to: p) < 1 {
            text = L.t("你喺呢度", "你在这里", "You are here")
        } else if homeBuildingID != nil {
            let d = HereText.distance(p.distance(to: homeTarget))
            text = L.t("你喺呢邊 · 離屋企\(d)", "你在这边 · 离家\(d)", "You: \(d) from home")
        } else {
            let d = HereText.distance(p.length)
            text = L.t("你喺呢邊 · 大約\(d)外", "你在这边 · 约\(d)外", "You: about \(d) this way")
        }
        locked { _here = (c, text) }
        labelsChanged()
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
        let (personState, personNodes, landmarkInfo, landmarkNodes, reportMarks, homeID, homeLabel, map, seq, here) = locked {
            overlaySeq += 1
            return (self.personState, self.personNodes, self.landmarkInfo, self.landmarkNodes, _reportMarks, _homeBuildingID, _homeLabel, _map, overlaySeq, _here)
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
        if let h = here, let pt = project(scenePoint(h.pos, height: 0.5)) {
            items.append(OverlayItem(id: "here", kind: .here, text: h.text, point: pt, highlighted: false, priority: 5))
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
