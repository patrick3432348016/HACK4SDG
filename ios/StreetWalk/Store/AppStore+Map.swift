import SwiftUI

// 首次使用、地图装载、圈成员、场景同步、太阳
extension AppStore {
    // MARK: - 首次使用

    func consent() {
        phase = .onboarding(.locate)
        // 未问过定位：「屋企」一步先讲一句点解要定位，用户撳「好」先弹系统框（startLocating）。
        if !mapService.locationUndetermined { startLocating() }
    }

    /// 攞位置、装附近地图（第一次会弹「使用 App 期間」定位框）。装好就到选楼（showPickHome）。
    func startLocating() {
        Task { await loadMap(home: nil, animated: true) }
    }

    func loadMap(home: Int64?, animated: Bool) async {
        mapLoadGen += 1
        let gen = mapLoadGen
        loadingMap = true
        mapNotice = nil
        // 当初系喺示例屋邨揀嘅楼（攞唔到位置 / 地图）：继续用示例屋邨并讲明，唔好去拉示例嗰格嘅真地图，
        // 扮成「你附近」（B-3：测试员见到皇后山邨嘅「大快活門口」，以为系自己附近）。改楼先会换返真地图。
        let sampleHome: Bool = {
            guard case .main = phase else { return false }
            let d = UserDefaults.standard
            return d.bool(forKey: "onboarded") && d.bool(forKey: Self.homeFromSampleKey)
        }()
        // 已经揀咗楼：直接装我屋企嗰格（唔使等定位，喺外面打开都唔会换底座）。
        let homeTile: TileKey? = {
            guard case .main = phase, !sampleHome, let s = UserDefaults.standard.string(forKey: "homeTile") else { return nil }
            let p = s.split(separator: ",").compactMap { Int($0) }
            return p.count == 2 ? TileKey(ix: p[0], iy: p[1]) : nil
        }()
        let loc = homeTile == nil && !sampleHome ? await mapService.currentLocation() : nil
        guard gen == mapLoadGen else { return }
        let loaded: (MapModel, MapService.Source)
        if sampleHome {
            loaded = (MapService.fallback(), .fallback)
        } else if let tile = homeTile ?? loc.map(TileKey.snap) {
            loaded = await mapService.load(tile: tile)
        } else {
            // 拿不到位置：不要假装是你附近，直接用内置示例屋邨，并说明。
            loaded = (MapService.fallback(), .fallback)
        }
        // 等待期间按了「用示例屋邨」或又重新选楼：这次的结果不要。
        guard gen == mapLoadGen else { return }
        var (m, source) = loaded
        // 示意楼（附近没有楼宇资料时放的）按 id 放回原位。
        if let h = home, let p = MapModel.placeholderPos(h), homeTile == nil || m.tile == homeTile { m = m.addingPlaceholderHome(at: p).map }
        fullMap = m
        mapSource = source
        if case .onboarding = phase {
            let me = loc.flatMap { TileKey.snap($0) == m.tile ? LocalProjection(origin: m.center).toLocal($0) : nil }
            let notice: String? = loc == nil ? L.t("攞唔到你嘅位置，所以冇幫你估。而家用緊示例屋邨（\(m.shownPlaceName)），唔係你附近。", "拿不到你的位置，所以没帮你猜。现在先显示示例屋邨（\(m.shownPlaceName)），不是你家附近。", "Couldn't get your location, so no guess. This is a sample estate (\(m.shownPlaceName)), not near you.")
                : source == .fallback ? L.t("暫時攞唔到你附近嘅地圖，所以冇幫你估。而家用緊示例屋邨（\(m.shownPlaceName)），唔係你附近。", "暂时拿不到你附近的地图，所以没帮你猜。现在先显示示例屋邨（\(m.shownPlaceName)），不是你家附近。", "Couldn't get the map near you for now, so no guess. This is a sample estate (\(m.shownPlaceName)), not near you.") : nil
            showPickHome(near: me, notice: notice, animated: animated)
        } else {
            var homeID = home.flatMap { id in m.building(id: id) != nil ? id : nil }
            if homeID == nil {
                if let t = homeTile, m.tile != t {
                    // 拉不到我屋企那格（离线又没缓存）：显示示例屋邨，但不把示例的楼当成你屋企。
                    noticeMap(L.t("暫時攞唔到你屋企附近嘅地圖，而家顯示緊示例屋邨。", "暂时拿不到你家附近的地图，现在先显示示例屋邨。", "Couldn't get the map near your home for now. Showing a sample estate."), delay: 1)
                } else {
                    homeID = defaultHome(in: m)
                }
            } else if sampleHome {
                noticeMap(L.t("而家顯示緊示例屋邨（\(m.shownPlaceName)），唔係你附近。喺屋企開定位，去設定「重新揀樓」就換到你附近。",
                              "现在显示的是示例屋邨（\(m.shownPlaceName)），不是你家附近。在家打开定位，到设置里「重新选楼」就能换成你家附近。", "This is a sample estate (\(m.shownPlaceName)), not near you. At home, turn on location, then use \"Choose again\" in Settings to switch."), delay: 1)
            }
            installDiorama(home: homeID, animated: animated)
            loadingMap = false
            populate()
        }
    }

    /// 选楼一步：附近没有可选的楼就看离我最近那座可选的楼一带；整格都没有（资料不全的新屋邨）就在我的位置放一座示意楼，保证首次使用能走完。
    private func showPickHome(near me: Vec2?, notice: String?, animated: Bool) {
        guard var full = fullMap else { return }
        var notice = notice
        var v = full.pickView(near: me)
        if let me, v.hasHomeCandidate {
            // 画面不是以我为中心（附近没有可选的楼）：讲清楚，免得以为橙色那几座就是我附近。
            let p = v.scenePoint(LocalProjection(origin: full.center).toGeo(me))
            if max(abs(p.x), abs(p.y)) > v.half { notice = notice ?? L.t("你而家附近冇住宅樓（可能唔喺屋企），所以冇幫你估。而家顯示緊離你最近嘅住宅樓。", "你现在附近没有住宅楼（可能不在家），所以没帮你猜。现在显示的是离你最近的住宅楼。", "No housing blocks near you right now (maybe you're not home), so no guess. Showing the nearest housing blocks.") }
        }
        if !v.hasHomeCandidate {
            full = full.addingPlaceholderHome(at: me ?? .zero).map
            fullMap = full
            v = full.pickView(near: me)
            notice = L.t("附近未有樓宇資料，喺你位置放咗一座示意樓，撳佢就得。", "附近还没有楼宇数据，在你的位置放了一座示意楼，点它就行。", "No building data nearby yet. A sample block is placed where you are. Just tap it.")
        }
        install(v, home: nil, animated: animated)
        pickCamera(animated: false)
        loadingMap = false
        pendingHome = nil
        phase = .onboarding(.pickHome)
        highlightResidential(true)
        // 知道你喺边、附近有住宅楼：先替你揀最近嗰座，问「你係咪住XX樓？」（唔啱先自己揀，见 OnbPickHomeStep）。
        // 估唔到都要讲点解（A-2：喺学校装，冇估又冇讲，以为坏咗）。
        if let me, notice == nil {
            if let id = guessHome(in: v, at: v.scenePoint(LocalProjection(origin: full.center).toGeo(me))) { pickHome(id) }
            else { notice = L.t("你而家附近冇住宅樓（可能唔喺屋企），所以冇幫你估。撳你住嗰座，或者返到屋企再揀。", "你现在附近没有住宅楼（可能不在家），所以没帮你猜。请点你住的那栋，或者回家后再选。", "No housing blocks near you right now (maybe you're not home), so no guess. Tap your block, or choose again at home.") }
        }
        // 等「你係咪住…」/「撳一下你住嗰座樓」说完再说。
        if let notice { noticeMap(notice, delay: 2.5) }
    }

    /// 选楼画面全屏看整个底座（主界面的总览按上半屏调的，这里另算；数值按 300 m 调，再按边长缩放）。
    /// 每次都一样（K-2）：选楼系全屏，唔用主画面「今日」页嗰个裁细咗嘅视窗比例（以前由设定改楼会放大到只见一块地），
    /// 手指放大亦还原。
    func pickCamera(animated: Bool) {
        guard let v = map else { return }
        let k = v.size / 300
        scene.viewportScale = 1
        scene.setCamera(target: Vec2(x: -65 * k, y: 65 * k), distance: Float(2.85 * k), animated: animated, keepZoom: false)
    }

    /// 估你住边座：脚下嗰座可以揀嘅楼，冇就最近嗰座真住宅楼（120 米以外唔估，交俾你自己揀）。
    /// 附近冇住宅楼时放宽出嚟嘅一般建筑（学校、商铺旁边）唔估「最近」：你多数唔喺屋企（A-2）。
    func guessHome(in v: MapModel, at p: Vec2) -> Int64? {
        let homes = v.buildings.filter { $0.kind == .residential }
        if let b = homes.first(where: { Polygon.contains($0.outline, p) }) { return b.id }
        let real = homes.filter { fullMap?.building(id: $0.id)?.looksLikeHome ?? true }
        guard let b = real.min(by: { $0.centroid.distance(to: p) < $1.centroid.distance(to: p) }), b.centroid.distance(to: p) <= 120 else { return nil }
        return b.id
    }

    /// 「唔係，我揀」：收起估嘅楼，全部住宅楼亮橙色，镜头退返睇成个底座。
    func pickHomeManually() {
        pendingHome = nil
        highlightResidential(true)
    }

    /// 选楼画面里可以揀嘅楼（住宅楼）。
    func isHomeCandidate(_ id: Int64) -> Bool { map?.building(id: id)?.kind == .residential }

    /// 等太久时改用内置示例屋邨（给选楼一步的「用示例屋邨」按钮用）。正在拉的地图拉到了也不要。
    func useSampleMap() {
        guard case .onboarding = phase else { return }
        mapLoadGen += 1
        fullMap = MapService.fallback()
        mapSource = .fallback
        pendingHome = nil
        showPickHome(near: nil, notice: L.t("而家用緊示例屋邨（\(fullMap?.shownPlaceName ?? "皇后山邨")），唔係你附近。", "现在先显示示例屋邨（\(fullMap?.shownPlaceName ?? "皇后山邨")），不是你家附近。", "This is a sample estate (\(fullMap?.shownPlaceName ?? "Queen's Hill Estate")), not near you."), animated: true)
    }

    /// 地图有状况（示例屋邨、示意楼）：mapNotice 留给画面显示，再用提示说一次（字 + 声）。
    func noticeMap(_ text: String, delay: Double = 0) {
        mapNotice = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if self.mapNotice == text { self.toast(text) }
        }
    }

    /// 以我屋企为中心裁出 200 m 底座并装进场景。
    func installDiorama(home: Int64?, animated: Bool) {
        guard let full = fullMap else { return }
        let c = home.flatMap { full.building(id: $0)?.centroid } ?? .zero
        install(full.simplified(around: c, home: home), home: home, animated: animated)
    }

    func install(_ m: MapModel, home: Int64?, animated: Bool) {
        map = m
        let picked = LandmarkDeriver.derive(in: m, home: home)
        // 中文原名一律用粤语起：上传服务器、两部手机对地标都靠呢个名（BackendMapping.LandmarkIndex），唔可以跟界面语言变。
        let zh = Self.inLanguage(.yue) {
            LandmarkDeriver.uniqueNames(picked.map { Landmark(id: $0.id, name: ai.nameLandmark($0), kind: $0.kind, pos: $0.pos, hasSeat: $0.hasSeat) },
                                        in: m, home: home)
        }
        // 英文界面显示嘅名：有 OSM 英文名（name:en）就用英文名起，冇就照用中文名。
        let en = Self.inLanguage(.en) {
            LandmarkDeriver.uniqueNames(picked.map { c -> Landmark in
                var c = c
                c.osmName = c.osmNameEn ?? c.osmName
                return Landmark(id: c.id, name: ai.nameLandmark(c), kind: c.kind, pos: c.pos, hasSeat: c.hasSeat)
            }, in: m, home: home, en: true)
        }
        let enByID = Dictionary(en.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        landmarks = zh.map { var l = $0; l.nameEn = enByID[l.id]; return l }
        originalLandmarkNames = Dictionary(landmarks.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        localizeLandmarkNames()
        shade = ShadeService(map: m, landmarks: landmarks)
        scene.setHomeBuilding(home)
        scene.homeTarget = home.flatMap { m.building(id: $0)?.centroid } ?? .zero
        scene.load(map: m, landmarks: landmarks, animated: animated)
        scene.setCamera(target: scene.overviewTarget, distance: scene.overviewDistance, animated: false)
        updateSun(animated: false)
    }

    /// 用指定语言跑 f（地标起名用），跑完即刻转返；同一个主线程回合内完成，画面只会见到原来嘅语言。
    static func inLanguage<T>(_ l: AppLang, _ f: () -> T) -> T {
        let lang = AppLanguage.shared
        let old = lang.current
        guard old != l else { return f() }
        lang.current = l
        defer { lang.current = old }
        return f()
    }

    /// 地标显示名跟界面语言：英文界面用 nameEn，其余用中文原名（自己改过嘅名之后由 applyLandmarkNames 盖上）。
    func localizeLandmarkNames() {
        for i in landmarks.indices {
            let id = landmarks[i].id
            let n = (L.isEn ? landmarks[i].nameEn : nil) ?? originalLandmarkNames[id] ?? landmarks[i].name
            guard landmarks[i].name != n else { continue }
            landmarks[i].name = n
            scene.renameLandmark(id, to: n)
        }
    }

    func defaultHome(in m: MapModel) -> Int64? {
        m.buildings.filter { $0.kind == .residential }.min { $0.centroid.length < $1.centroid.length }?.id
    }

    /// 可以选做屋企的楼。选楼画面已把可选的楼标成住宅楼（没有住宅资料时放宽到一般建筑或示意楼，见 MapModel.pickView）。
    func residentialBuildings() -> [Building] { map?.buildings.filter { $0.kind == .residential } ?? [] }

    /// 选楼染色（K-2：每次一样）：可以揀嘅楼一律浅橙，揀中嗰座深橙加发光，其他楼灰。
    /// 选楼画面用固定嘅日光（上午、东南）：夜晚揀楼橙色都睇得清，每次一样；离开选楼就用返真太阳。
    func highlightResidential(_ on: Bool) {
        if on {
            scene.setSun(SolarPosition(elevation: 50, azimuth: 135), animated: false)
            scene.highlightPick(candidates: Set(residentialBuildings().map(\.id)), selected: pendingHome)
        } else {
            scene.highlightBuildings([], color: nil)
            updateSun(animated: false)
        }
    }

    /// 揀中一座：只换染色，镜头唔郁（以前飞埋去放到好大，有时得一块地；要睇清楚可以双指放大）。
    func pickHome(_ id: Int64) {
        guard map?.building(id: id)?.kind == .residential else { toast(L.t("請揀一座亮咗橙色嘅樓", "请选一座亮橙色的楼", "Please choose a bright orange block")); return }
        pendingHome = id
        highlightResidential(true)
        Haptics.select()
    }

    func confirmHome() {
        guard let id = pendingHome else { return }
        floorChoice = min(floorChoice, max(1, map?.building(id: id)?.levels ?? 30))
        highlightResidential(false)
        // 选好楼：底座收窄到我屋企周围 200 m，楼宇重新"升起"。
        installDiorama(home: id, animated: true)
        phase = .onboarding(.floor)
    }

    func finishOnboarding() {
        let firstTime = !changingHome     // 改楼（设定）唔使任务卡
        let d = UserDefaults.standard
        d.set(true, forKey: "onboarded")
        if let id = pendingHome { d.set(NSNumber(value: id), forKey: "homeBuilding") }
        if let t = fullMap?.tile { d.set("\(t.ix),\(t.iy)", forKey: "homeTile") }
        d.set(floorChoice, forKey: "floor")
        d.set(mobilityChoice.rawValue, forKey: "mobility")
        d.set(colorChoice, forKey: "color")
        lookBeforeChange = nil
        highlightResidential(false)
        scene.highlightBuildings([], color: nil)
        mapNotice = nil
        phase = .main
        homeChanged()
        populate()
        uploadProfile()     // populate 之后：座数跟新屋企
        scene.resetCamera()
        if firstTime { startFirstDay() }   // 「今日」页顶「今日三件事」（AppStore+FirstDay）
        say(firstTime ? L.t("搞掂！今日試吓做呢三件事。", "搞定！今天试试做这三件事。", "All set! Try these 3 things today.") : L.t("改好咗。", "改好了。", "Changed."))
        startWalkDetection()   // 动作感应；通知权限等有街坊先问（requestNotificationsIfReady）
        locationOnboarded()    // 屋企范围；「始终允许」等第一次散步返屋企先问（AppStore+Location）
    }

    /// 圈成员（F2）：由 CommunityService 给（单机演示时是示範街坊），再套回已保存的街坊关系、地标名、我的记录。
    func populate() {
        guard let m = map else { return }
        adoptMapKey()
        localizeLandmarkNames()
        applyLandmarkNames()
        let blocks = m.buildings.filter { $0.kind == .residential && $0.name != nil }.compactMap(\.name)
        community.setLandmarks(landmarks, originals: originalLandmarkNames)
        var list = community.circleMembers(blocks: blocks, landmarks: landmarks)
        for i in list.indices {
            // 真后端：今日一句、街坊关系由服务器嚟（只有街坊先有今日一句）；示範街坊先用模板生成
            guard list[i].isDemo || !community.ownsNeighborLinks else { continue }
            let passed = [landmark(list[i].homeLandmarkID)].compactMap { $0 }
            list[i].todayLine = ai.dailyLine(for: list[i], passed: list[i].id == "cheung" ? [] : passed)
            if let link = savedNeighbors[list[i].id] {
                list[i].isNeighbor = true
                list[i].neighborSince = link.since
                list[i].sendRemind = link.send
                list[i].receiveRemind = link.receive
            }
        }
        var meR = Resident(id: "me", name: "你", floor: floorChoice, blockName: scene.homeBuildingID.flatMap(m.homeLabel),
                           colorIndex: colorChoice, mobility: mobilityChoice, streakDays: 0, todayLine: "", isMe: true)
        meR.homeLandmarkID = nearestLandmark(to: scene.homeTarget)?.id
        meR.nickname = nickname
        list.append(meR)
        applyLooks(&list)
        residents = list
        if LaunchArgs.has("-withNeighbor"), !list.isEmpty, !list[0].isMe { residents[0].isNeighbor = true; residents[0].neighborSince = Date() }
        syncHomeLocation()     // 屋企位置交俾后台出门检测（AppStore+Location）
        dropStaleReferences()
        closeOrphanAppointments()
        refreshMe()
        syncScene()
        checkAppointments()
        uploadProfile()     // 真后端：座数、连续天数跟返而家（一样就唔再传）
        runScriptIfNeeded()
        showMapPreviewIfNeeded()
    }

    /// 截图自检（模拟器点不到）：-uiPreview landmarkCard 打开第一个地标卡；-uiPreview changeHome 由设定「重新揀樓」入选楼画面。只做一次。
    private func showMapPreviewIfNeeded() {
        guard !Self.mapPreviewShown else { return }
        if UIPreview.is("landmarkCard"), let id = landmarks.first?.id {
            Self.mapPreviewShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.select(.landmark(id)) }
        } else if UIPreview.is("mapZoom") {
            // 当双指喺画面中间放大两倍，再向右拖 60 点（检查放大方向、手指下面嘅地面跟住手指）
            Self.mapPreviewShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let v = self.scene.view else { return }
                let c = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
                self.scene.userZoom(by: 2, around: c)
                self.scene.userPan(from: c, to: CGPoint(x: c.x + 60, y: c.y))
            }
        } else if UIPreview.is("changeHome") || UIPreview.is("changeHomePick") {
            Self.mapPreviewShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.beginChangeHome() }
            // changeHomePick：入到选楼之后自己揀第一座（睇「就係呢座」卡）
            if UIPreview.is("changeHomePick") {
                Task { @MainActor in
                    while self.phase != .onboarding(.pickHome) { try? await Task.sleep(for: .milliseconds(300)) }
                    try? await Task.sleep(for: .seconds(3))
                    if let b = self.residentialBuildings().first(where: { $0.id != self.pendingHome }) { self.pickHome(b.id) }
                }
            }
        }
    }
    @MainActor private static var mapPreviewShown = false

    /// 圈成员变了（关演示模式、清除纪录）：指向已不在圈里、或不再是街坊的人的找人、选中、提议、提醒、复述卡都收起，
    /// 不会留下关不掉的卡，非街坊也不会留在场景。
    private func dropStaleReferences() {
        func neighbor(_ id: String) -> Bool { resident(id)?.isNeighbor == true }
        if let f = find, !neighbor(f.partnerID) { endFind() }
        if let p = proposal, !neighbor(p.partnerID) { cancelProposal() }
        if case .person(let id) = selection, resident(id) == nil { select(nil) }
        if let id = remindPromptFor, resident(id) == nil { remindPromptFor = nil }
        if let ask = incomingFind, !neighbor(ask.fromID) { incomingFind = nil }
        switch voiceCard?.intent {
        case .invite(let id, _, _)?, .goFind(let id)?: if !neighbor(id) { voiceCard = nil }
        default: break
        }
    }

    func nearestLandmark(to p: Vec2) -> Landmark? { landmarks.min { $0.pos.distance(to: p) < $1.pos.distance(to: p) } }

    // MARK: - 场景同步（隐私规则在这里落实：非街坊永远不进场景）

    func syncScene() {
        var people: [ScenePerson] = []
        if let w = walk, find == nil {
            // 碰完面再走：从站着的位置沿路走回路线，不要直线穿楼。站着期间进度照走（路线已画到前面），
            // 所以先用 2.5 倍速追上，再按正常速度走，到屋企时和散步结束同步。
            let rest = remainingRoute(w), v = Self.walkSpeed
            var motion = ScenePerson.Motion.route(rest, speed: v)
            if let cur = scene.personPosition("me"), let first = rest.first, cur.distance(to: first) > 8 {
                let back = scene.route(from: cur, to: first), fast = v * 2.5
                // 追上那一刻进度又走了 d：d = v × (走回路线的距离 + d) / fast
                let (meet, i) = point(along: rest, at: v * pathLength(back) / (fast - v))
                motion = .catchUp(lead: back + rest.prefix(i + 1).dropFirst() + [meet], fast: fast, rest: [meet] + rest.dropFirst(i + 1), speed: v)
            }
            people.append(ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility, motion: motion, label: L.t("你", "你", "You")))
        }
        if let f = find, f.live, let p = resident(f.partnerID), p.isNeighbor {
            people += livePeople(f, partner: p)
        } else if let f = find, let p = resident(f.partnerID), p.isNeighbor, let lm = landmark(f.landmarkID) {
            let myStart = myPosition()
            people.append(ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility,
                                      motion: f.stage == .asking || f.stage == .declined ? .stand(at: myStart) : .route(findRoute ?? [myStart, lm.pos], speed: Self.findSpeed), label: L.t("你", "你", "You")))
            let spot = scene.nearestWalkable(lm.pos + Vec2(x: 5, y: 3))
            if f.spontaneous || f.partnerOut { people.append(ScenePerson(id: p.id, color: p.uiColor, mobility: p.mobility,
                                      motion: f.spontaneous ? .stand(at: spot) : .route(partnerRoute ?? [spot], speed: Self.findSpeed * 0.8),
                                      label: p.name, highlighted: true)) }
        }
        if case .found(let id) = bumpStage, let p = resident(id) {
            // 两人在碰面的地方并排站：散步中就在我走到的位置，不要跳回屋企。
            let spot = bumpMeetSpot()
            people.removeAll { $0.id == "me" }
            people.append(ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility, motion: .stand(at: spot + Vec2(x: -4, y: 0)), label: L.t("你", "你", "You")))
            people.append(ScenePerson(id: p.id, color: p.uiColor, mobility: p.mobility, motion: .stand(at: spot + Vec2(x: 4, y: 0)), label: "\(p.floorLabel) \(p.name)", highlighted: true))
        } else {
            bumpSpot = nil
        }
        let shown = Set(people.map(\.id))
        for n in outNeighbors where !shown.contains(n.id) {
            guard let lm = landmark(n.atLandmarkID) else { continue }
            people.append(ScenePerson(id: n.id, color: n.uiColor, mobility: n.mobility, motion: .wander(around: lm.pos), label: n.name))
        }
        scene.setPeople(people.map(withLook))
        // 只写「你屋企」：以前「· 已隱身」长者以为自己开咗乜嘢或者被人封咗（UX 评审 16）。
        scene.homeLabel = (walk == nil && find == nil) ? L.t("你屋企", "你家", "Your home") : nil
        scene.reportMarks = reports.map { (id: $0.id.uuidString, pos: $0.pos, text: $0.kind.rawValue) }
    }

    /// 碰一碰时两个人见面的位置：散步中是我当时行到的地方，否则是我屋企楼下。碰面期间固定不变。
    func bumpMeetSpot() -> Vec2 {
        if let s = bumpSpot { return s }
        let s = walk != nil && find == nil ? scene.nearestWalkable(myPosition()) : scene.nearestWalkable(scene.homeTarget + Vec2(x: 0, y: -18))
        bumpSpot = s
        return s
    }

    // MARK: - 时间与太阳

    func updateSun(animated: Bool) {
        guard let m = map else { return }
        scene.setSun(m.localSun(SolarPosition.at(now, lat: m.center.lat, lon: m.center.lon)), animated: animated)
    }

    func setDemoHour(_ h: Double?) {
        demoHour = h
        updateSun(animated: true)
        refreshWeatherTip()
        checkAppointments()
    }

    /// 某地标某时刻的遮荫（0–1）；太阳已经落山就返回 nil（画面显示"—"，不说"100% 有樓遮"）。
    func shadeValue(_ landmarkID: String, at date: Date) -> Double? {
        guard let shade, shade.isSunUp(at: date) else { return nil }
        return shade.shade(landmarkID: landmarkID, at: date)
    }

    /// 地标信息卡的遮荫一句（图标 + 文字）。日落后说"太陽落咗山"。
    func shadeFact(_ landmarkID: String) -> (symbol: String, text: String) {
        guard shade != nil else { return ("sun.max.fill", Self.shadeWords(0)) }
        guard let v = shadeValue(landmarkID, at: now) else { return ("moon.stars.fill", L.t("太陽落咗山，冇得曬", "太阳下山了，晒不到", "Sun has set")) }
        return (v >= 0.5 ? "building.2.fill" : "sun.max.fill", Self.shadeWords(v))
    }

    /// 遮荫讲日常话，唔讲百分比（长者睇唔明「0% 有樓遮」，UX 评审 16）：有陰 / 一半有陰 / 曬。
    static func shadeWords(_ v: Double) -> String {
        v >= 0.6 ? L.t("而家有陰", "现在有阴凉", "Shady now") : v >= 0.3 ? L.t("而家一半有陰", "现在一半有阴凉", "Half shady now") : L.t("而家曬", "现在晒", "Too sunny now")
    }

    /// 约人理由：模板按遮荫写"嗰陣有樓遮住"，但日落后遮荫按 100% 计，要改成"嗰陣已經日落"。
    func honestReason(_ p: MeetProposal) -> MeetProposal {
        guard let shade, !shade.isSunUp(at: p.date) else { return p }
        var p = p
        p.reason = p.reason.replacingOccurrences(of: "嗰陣有樓遮住", with: "嗰陣已經日落")
            .replacingOccurrences(of: "那时有楼挡着", with: "那时已经日落")
        return p
    }
}
