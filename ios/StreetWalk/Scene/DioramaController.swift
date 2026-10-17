import SceneKit
import UIKit
import QuartzCore

/// 场景里一个人的显示状态（只给街坊和"我"用；非街坊永远不进场景）。
struct ScenePerson: Equatable {
    enum Motion: Equatable {
        case wander(around: Vec2)          // 在地标附近 25 m 内慢慢走
        case route([Vec2], speed: Double)  // 沿路线走（米/秒，演示时加速）
        case catchUp(lead: [Vec2], fast: Double, rest: [Vec2], speed: Double)  // 先快步走完 lead 追上进度，再按 speed 走 rest
        case stand(at: Vec2)
    }
    var id: String
    var color: UIColor
    var mobility: Mobility
    var motion: Motion
    var label: String?
    var highlighted = false
    /// 外形：肤色档、年龄段（AppStore.syncScene 按居民资料填）。
    var skin = 1
    var age: AgeGroup = .adult
}

/// 覆盖层上的一个标签（SwiftUI 画，跟随 3D 投影）。
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
    /// 用户用手指郁过镜头（放大、移动、转动），画面出「回正」掣。
    var userMoved = false
}

/// 3D 微缩模型的全部场景逻辑：搭建、太阳、相机、人物、路线、遮挡淡化、标签投影。
/// 线程：场景由主线程搭建和修改；SceneKit 渲染线程只在 renderer(_:updateAtTime:) 里读标签和跟随要用的状态。
/// 渲染线程会读的属性（map、人物、地标、屋企标签、反映标记、跟随、相机位置）一律在 lock 里写，渲染线程在 lock 里复制一份再用。
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

    // 相机：固定俯角和方位，由流程自动移动；用户可以双指缩放、双指平移（_zoom / _pan，叠喺流程镜头上面），双击复位。
    private let cameraNode = SCNNode()
    private let sunNode = SCNNode()
    private let ambientNode = SCNNode()
    private let pitch: Float = Float(LaunchArgs.value("-pitch").flatMap(Double.init) ?? 33) * .pi / 180
    private let baseAzimuth: Float = 45 * .pi / 180      // 从东南方看
    /// 用户双指转动嘅角度（绕竖轴，弧度）；双击 / 「回正」/ 流程换总览时归零。
    private var _yaw: Float = 0
    private var _target = Vec2(x: -72, y: 72)
    private var _distance: Float = 2.35
    /// 用户双指平移（米，加喺流程镜头 target 上）同缩放（乘喺 distance 上，< 1 = 放大）。
    private var _pan = Vec2.zero
    private var _zoom: Float = 1
    /// 镜头对准的地面点（米）。镜头飞行和跟随在渲染线程改，所以加锁。
    private(set) var target: Vec2 {
        get { locked { _target } }
        set { locked { _target = newValue } }
    }
    private(set) var distance: Float {
        get { locked { _distance } }
        set { locked { _distance = newValue } }
    }
    var homeTarget = Vec2.zero

    // 标签（渲染线程读，主线程写：都经 lock）
    private var _homeBuildingID: Int64?
    private var _homeLabel: String?
    private var _reportMarks: [(id: String, pos: Vec2, text: String)] = []
    /// 「你喺呢度」：已经贴好边嘅场景位置同标签（setHere 喺主线程计好）。
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
    /// 跟随某个人（散步时跟着"我"）。
    var followID: String? {
        get { locked { _followID } }
        set { locked { _followID = newValue } }
    }
    /// 标签每秒最多推 20 次，而且只在有变化时推（SwiftUI 跟得上，也省电）。
    private static let overlayInterval = 1.0 / 20
    private var lastOverlayPush: TimeInterval = 0
    private var lastOverlay: [OverlayItem] = []
    private var trailingScheduled = false
    /// 每次取快照加一；主线程只采用比已显示更新的一份（渲染线程和主线程同时推时，旧快照不会盖过新的）。
    private var overlaySeq = 0
    private var lastOverlaySeq = 0
    private var appliedSeq = 0   // 只在主线程读写
    private let lock = NSLock()

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    /// 减少动态效果：镜头直接跳到位、楼宇不升起、光晕不脉冲。渲染线程也要读，所以在主线程缓存一份。
    private var _reduceMotion = UIAccessibility.isReduceMotionEnabled
    private var reduceMotion: Bool { locked { _reduceMotion } }

    /// 深色模式：搭建场景时按它解析 SceneStyle 的动态色。
    private(set) var isDark = UITraitCollection.current.userInterfaceStyle == .dark
    private var traits: UITraitCollection { UITraitCollection(userInterfaceStyle: isDark ? .dark : .light) }
    private var highlighted: (ids: Set<Int64>, color: UIColor?) = ([], nil)
    /// 选楼画面嘅染色（highlightPick）；nil = 唔喺选楼。
    private var pickHighlight: (candidates: Set<Int64>, selected: Int64?)?
    private var highlightedLandmark: String?
    /// 当前被调成半透明的楼（切深浅色重建后补回）。
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

    // MARK: - 搭建

    func load(map: MapModel, landmarks: [Landmark], animated: Bool) {
        locked { _map = map }
        clearUserCamera()   // 换底座（选楼、改楼、返上一步）：镜头每次都由流程框好，唔带返上次手指放大
        pathGrid = PathGrid(map: map)
        [plinthNode, buildingsNode, treesNode, landmarksNode, routesNode, peopleNode].forEach { $0.childNodes.forEach { $0.removeFromParentNode() } }
        locked { towerNodes = [:]; pickableNodes = [:]; landmarkNodes = [:]; personNodes = [:]; personState = [:] }
        faded = []

        // 阴影范围跟着底座大小走，小底座的影子更清楚。
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

    /// 系统切换深浅色：按新配色重建地面、楼、树、地标的材质，不重放楼宇升起；人和路线不动。
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
            // 按用途区分颜色；我屋企淡橙 + 橙色描边，是画面主角。
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

        guard animated, !reduceMotion else { return }
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
                       !spots.contains(where: { $0.0.distance(to: p) < 22 }) { spots.append((p, rng.next(0.9, 1.2))) }
                    x += 18
                }
                y += 18
            }
        }
        // 做减法：最多 5 棵。
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
        // 夜晚没有太阳：阴影 pass 也不用跑。
        sunNode.light?.castsShadow = day
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

    /// 场景视窗比原来（屏幕 42%）矮几多：用嚟保持每米几多像素唔变，只系裁走上下（用户 10-12：场景缩到约 25%）。
    /// 1 = 原来嘅比例（找人全屏都系 1）。
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
        // 与之前 20° 透视在同等 distance 下的取景高度一致：半高 = distance · tan(10°)。
        cameraNode.camera?.orthographicScale = Double(dist) * 0.1763 * Double(viewportScale)
    }

    /// 减少动态效果时不飞，直接跳到位。
    /// keepZoom = false：连手指放大都还原（总览、选楼）。
    func setCamera(target t: Vec2, distance d: Float, animated: Bool, duration: Double = 0.75, keepZoom: Bool = true) {
        let half = (map?.half ?? 280) - 30
        let clamped = Vec2(x: max(-half, min(half, t.x)), y: max(-half, min(half, t.y)))
        // 流程换镜头：双指平移作废（target 已经换咗），手指放大嘅倍数保留（撳地标唔会突然缩返细）。
        // 平移并入起点，飞过去时画面唔会跳。
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
        let k = LaunchArgs.value("-ovy").flatMap(Double.init) ?? (size < 400 ? 60 * size / 200 : 72 * size / 560)
        return Vec2(x: -k, y: k)
    }
    var overviewDistance: Float {
        let size = map?.size ?? 560
        return Float(LaunchArgs.value("-ovd").flatMap(Double.init) ?? (size < 400 ? 0.88 * size / 200 : 2.35 * size / 560))
    }
    func resetCamera() { setCamera(target: overviewTarget, distance: overviewDistance, animated: true, keepZoom: false) }

    // MARK: - 手势：双指缩放 / 平移（单指照旧：撳地标、向下拉放大）

    /// 用户手指郁过镜头、未复位。双击复位只喺呢个时候先等（唔郁过就唔拖慢撳地标）。
    private(set) var userAdjusted = false
    private func setUserAdjusted(_ on: Bool) {
        userAdjusted = on
        if overlay.userMoved != on { overlay.userMoved = on }
    }
    /// 单指拖动平移几时生效：选楼画面、找人全屏、「睇大啲」放大咗（由画面设定）；手指放大过之后亦得。
    /// 平时（今日页细地图）单指向下拉系「睇大啲」，唔好撞。
    var oneFingerPan = false
    /// 单指拖紧（或者啱啱拖完）：SwiftUI「向下拉放大」唔好当系拉。
    private(set) var oneFingerPanning = false
    func setOneFingerPanning(_ on: Bool) {
        if on { oneFingerPanning = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.oneFingerPanning = false }
    }
    /// 最近一次双指手势嘅时间：SwiftUI 嘅「向下拉放大」见到啱啱双指郁过就唔当拉。
    private(set) var lastMultiTouch: CFTimeInterval = 0
    /// 放大上限：底座总览嘅 1/4（大约睇到 50 m 一带）；缩细下限：总览或者流程镜头再细 1/4（成个底座仲睇得到）。
    private var zoomRange: ClosedRange<Float> {
        let d = locked { _distance }
        let lo = overviewDistance * 0.25, hi = max(d, overviewDistance) * 1.25
        return (lo / max(d, 0.001))...(hi / max(d, 0.001))
    }

    /// 屏幕上一点对住嘅地面点（米）。按而家嘅镜头直接计（正交投影：画面中心 = target + pan，
    /// orthographicScale = 半个画面高嘅场景单位）；唔用 unprojectPoint，佢用上一帧嘅投影，同一轮先放大再拖会计错。
    func groundPoint(at p: CGPoint) -> Vec2? {
        guard let v = view, v.bounds.height > 0, let cam = cameraNode.camera else { return nil }
        let (tg, pan, yaw) = locked { (_target, _pan, _yaw) }
        let upp = cam.orthographicScale * 2 / Double(v.bounds.height)          // 场景单位 / 点
        let s = Double(SceneStyle.scale)
        let dx = Double(p.x - v.bounds.midX) * upp / s                          // 米，向右
        let dy = Double(p.y - v.bounds.midY) * upp / s / Double(sin(pitch))     // 米，向镜头（屏幕向下）
        let az = Double(baseAzimuth + yaw)
        let right = Vec2(x: cos(az), y: sin(az)), toward = Vec2(x: sin(az), y: -cos(az))
        return tg + pan + right * dx + toward * dy
    }

    /// 平移限喺底座入面（画面中心唔会拖出模型）。
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

    /// 双指转动：绕竖轴转，两指中间嗰点地面留喺手指下面。rotation 跟 UIRotationGestureRecognizer（顺时针为正），地图跟住手指转。
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

    /// 而家转咗几多（弧度，截图自检用）。
    var yaw: Float { locked { _yaw } }

    /// 双指捏合：以两指中间为中心放大缩细（嗰点地面留喺手指下面）。
    func userZoom(by scale: CGFloat, around p: CGPoint) {
        guard scale > 0 else { return }
        touched()
        let (z0, pan0) = locked { (_zoom, _pan) }
        let z = min(zoomRange.upperBound, max(zoomRange.lowerBound, z0 / Float(scale)))
        guard abs(z - z0) > 1e-5 else { return }
        var pan = pan0
        // 正交镜头：地面绕画面中心 C 按 f 缩放；要 P 唔郁，中心移去 P + (C − P)·f。
        if let P = groundPoint(at: p) {
            let C = target + pan0, f = Double(z / z0)
            pan = pan0 + (P + (C - P) * f - C)
        }
        let clamped = clampPan(pan)
        locked { _zoom = z; _pan = clamped }
        applyCamera()
    }

    /// 双指拖动：手指下面嗰点地面跟住手指走。
    func userPan(from a: CGPoint, to b: CGPoint) {
        touched()
        guard let pa = groundPoint(at: a), let pb = groundPoint(at: b) else { return }
        let pan = clampPan(locked { _pan } + (pa - pb))
        locked { _pan = pan }
        applyCamera()
    }

    /// 双击、「睇大啲 / 收細」：手指放大、平移全部还原，返去流程摆好嘅镜头。
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

    /// 即刻清走手指放大、平移（换底座、选楼画面用）。
    func clearUserCamera() {
        setUserAdjusted(false)
        locked { _zoom = 1; _pan = .zero; _yaw = 0 }
        applyCamera()
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

    /// 给楼染色（白色楼体上用自发光看不出来，所以改用正片叠底）：只有一座时用深一点的橙，表示"选中"。
    /// 深色时深灰楼体正片叠底不够亮：先叠一层暖色压掉蓝，再加橙色自发光。
    func highlightBuildings(_ ids: Set<Int64>, color: UIColor?) {
        highlighted = (ids, color)
        if pickHighlight != nil {
            pickHighlight = nil
            buildingsNode.childNode(withName: "low", recursively: false)?.geometry?.materials.forEach { $0.multiply.contents = UIColor.white }
        }
        // 选楼：可以揀嘅楼用实心橙（以前太淡，近肉色，长者搵唔到）；揀中嗰座再深一档。
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

    /// 选楼画面（K-2：每次一样）：可以揀嘅楼一律浅橙；揀中嗰座深橙、加发光；其他楼（包括矮楼）灰色，唔会同可以揀嘅混埋。
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

    /// 「你喺呢度」（场景坐标，米；nil = 唔显示）。超出底座就贴住边，标签写离屋企（或者画面中心）几远。
    func setHere(_ p: Vec2?) {
        guard let p, let map else { locked { _here = nil }; labelsChanged(); return }
        let lim = map.half - 6
        let c = Vec2(x: max(-lim, min(lim, p.x)), y: max(-lim, min(lim, p.y)))
        let text: String
        if c.distance(to: p) < 1, homeBuildingID != nil, p.distance(to: homeTarget) < 30 {
            text = ""   // 喺屋企楼下：只出圆点，唔好遮住「你屋企」名牌（要撳得到）
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

    /// 选中地标的光晕慢慢一呼一吸；减少动态效果时改成静止放大。
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

    /// 相机与焦点之间的高楼变半透明（固定视角下看不到楼后的人和地标）。
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

    // MARK: - 人物

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

    /// 从 start 起沿折线走，每段转向前进方向；没有 start 就先瞬移到第一点。
    private func walk(_ pts: [Vec2], speed: Double, from start: Vec2?) -> SCNAction {
        var actions: [SCNAction] = []
        var prev = start
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

    /// 镜头跟着某个人（渲染线程每帧调用）。减少动态效果时不慢慢移，人走出 35 m 才一下跳过去。
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

    // MARK: - 标签投影（渲染线程 → 主线程）

    /// 场景没有在动、但标签内容变了（改名、反映、屋企标签）：主线程补推一次。
    /// 场景只在有变化时才渲染（见 DioramaView），所以不能只靠渲染回调。
    private func labelsChanged() { scheduleTrailing() }

    /// 安排一次主线程补推：最早在上次推送一个间隔之后；已经安排了就不再安排。
    /// 渲染回调因为限速跳过的那一帧也靠它补，动画停下后标签也会停在最后位置。
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

    /// 投影出全部标签，有变化先推给 SwiftUI。两次推送至少隔 overlayInterval（每秒最多 20 次）；未到时间就约一次补推。
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
            // 取到半点，细微抖动不会让标签重排
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
        // 比较时也按快照先后：较旧的快照不会覆盖 lastOverlay（否则可能误判"没有变化"而漏推）。
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
