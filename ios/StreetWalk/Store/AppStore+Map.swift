import SwiftUI

// 首次使用、地图装载、圈成员、场景同步、太阳
extension AppStore {
    // MARK: - 首次使用

    func consent() {
        phase = .onboarding(.locate)
        Task { await loadMap(home: nil, animated: true) }
    }

    func loadMap(home: Int64?, animated: Bool) async {
        mapLoadGen += 1
        let gen = mapLoadGen
        loadingMap = true
        mapNotice = nil
        // 已经揀咗楼：直接装我屋企嗰格（唔使等定位，喺外面打开都唔会换底座）。
        let homeTile: TileKey? = {
            guard case .main = phase, let s = UserDefaults.standard.string(forKey: "homeTile") else { return nil }
            let p = s.split(separator: ",").compactMap { Int($0) }
            return p.count == 2 ? TileKey(ix: p[0], iy: p[1]) : nil
        }()
        let loc = homeTile == nil ? await mapService.currentLocation() : nil
        guard gen == mapLoadGen else { return }
        let loaded: (MapModel, MapService.Source)
        if let tile = homeTile ?? loc.map(TileKey.snap) {
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
            let notice: String? = loc == nil ? "攞唔到你嘅位置，而家用緊示例屋邨（\(m.placeName)）。"
                : source == .fallback ? "攞唔到地圖資料，而家用緊示例屋邨（\(m.placeName)）。" : nil
            showPickHome(near: me, notice: notice, animated: animated)
        } else {
            var homeID = home.flatMap { id in m.building(id: id) != nil ? id : nil }
            if homeID == nil {
                if let t = homeTile, m.tile != t {
                    // 拉不到我屋企那格（离线又没缓存）：显示示例屋邨，但不把示例的楼当成你屋企。
                    noticeMap("暫時攞唔到你屋企附近嘅地圖，而家顯示緊示例屋邨。", delay: 1)
                } else {
                    homeID = defaultHome(in: m)
                }
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
            if max(abs(p.x), abs(p.y)) > v.half { notice = notice ?? "你附近未有住宅樓資料，而家顯示緊離你最近嘅住宅樓。" }
        }
        if !v.hasHomeCandidate {
            full = full.addingPlaceholderHome(at: me ?? .zero).map
            fullMap = full
            v = full.pickView(near: me)
            notice = "附近未有樓宇資料，喺你位置放咗一座示意樓，撳佢就得。"
        }
        install(v, home: nil, animated: animated)
        // 全屏看整个底座（主界面的总览按上半屏调的，这里另算；数值按 300 m 调，再按边长缩放）。
        let k = v.size / 300
        scene.setCamera(target: Vec2(x: -65 * k, y: 65 * k), distance: Float(2.85 * k), animated: false)
        loadingMap = false
        phase = .onboarding(.pickHome)
        highlightResidential(true)
        // 等「撳一下你住嗰座樓」说完再说。
        if let notice { noticeMap(notice, delay: 2.5) }
    }

    /// 等太久时改用内置示例屋邨（给选楼一步的「用示例屋邨」按钮用）。正在拉的地图拉到了也不要。
    func useSampleMap() {
        guard case .onboarding = phase else { return }
        mapLoadGen += 1
        fullMap = MapService.fallback()
        mapSource = .fallback
        pendingHome = nil
        showPickHome(near: nil, notice: "而家用緊示例屋邨（\(fullMap?.placeName ?? "皇后山邨")）。", animated: true)
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
        let named = picked.map { Landmark(id: $0.id, name: ai.nameLandmark($0), kind: $0.kind, pos: $0.pos, hasSeat: $0.hasSeat) }
        landmarks = LandmarkDeriver.uniqueNames(named, in: m, home: home)
        originalLandmarkNames = Dictionary(landmarks.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        shade = ShadeService(map: m, landmarks: landmarks)
        scene.setHomeBuilding(home)
        scene.homeTarget = home.flatMap { m.building(id: $0)?.centroid } ?? .zero
        scene.load(map: m, landmarks: landmarks, animated: animated)
        scene.setCamera(target: scene.overviewTarget, distance: scene.overviewDistance, animated: false)
        updateSun(animated: false)
    }

    func defaultHome(in m: MapModel) -> Int64? {
        m.buildings.filter { $0.kind == .residential }.min { $0.centroid.length < $1.centroid.length }?.id
    }

    /// 可以选做屋企的楼。选楼画面已把可选的楼标成住宅楼（没有住宅资料时放宽到一般建筑或示意楼，见 MapModel.pickView）。
    func residentialBuildings() -> [Building] { map?.buildings.filter { $0.kind == .residential } ?? [] }

    func highlightResidential(_ on: Bool) {
        scene.highlightBuildings(on ? Set(residentialBuildings().map(\.id)) : [], color: nil)
    }

    func pickHome(_ id: Int64) {
        guard let b = map?.building(id: id), b.kind == .residential else { toast("請揀一座亮咗橙色嘅樓"); return }
        pendingHome = id
        scene.highlightBuildings([id], color: nil)
        scene.setCamera(target: b.centroid, distance: 1.2, animated: true)
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
        say("搞掂。你行街嘅時候我會自動記錄，唔使撳任何掣。")
        startWalkDetection()   // 同意之后先问动作 / 定位权限
    }

    /// 圈成员（F2）：由 CommunityService 给（单机演示时是示範街坊），再套回已保存的街坊关系、地标名、我的记录。
    func populate() {
        guard let m = map else { return }
        adoptMapKey()
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
        dropStaleReferences()
        closeOrphanAppointments()
        refreshMe()
        syncScene()
        checkAppointments()
        uploadProfile()     // 真后端：座数、连续天数跟返而家（一样就唔再传）
        runScriptIfNeeded()
    }

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
            people.append(ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility, motion: motion, label: "你"))
        }
        if let f = find, let p = resident(f.partnerID), p.isNeighbor, let lm = landmark(f.landmarkID) {
            let myStart = myPosition()
            people.append(ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility,
                                      motion: f.stage == .asking || f.stage == .declined ? .stand(at: myStart) : .route(findRoute ?? [myStart, lm.pos], speed: Self.findSpeed), label: "你"))
            let spot = scene.nearestWalkable(lm.pos + Vec2(x: 5, y: 3))
            if f.spontaneous || f.partnerOut { people.append(ScenePerson(id: p.id, color: p.uiColor, mobility: p.mobility,
                                      motion: f.spontaneous ? .stand(at: spot) : .route(partnerRoute ?? [spot], speed: Self.findSpeed * 0.8),
                                      label: p.name, highlighted: true)) }
        }
        if case .found(let id) = bumpStage, let p = resident(id) {
            // 两人在碰面的地方并排站：散步中就在我走到的位置，不要跳回屋企。
            let spot = bumpMeetSpot()
            people.removeAll { $0.id == "me" }
            people.append(ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility, motion: .stand(at: spot + Vec2(x: -4, y: 0)), label: "你"))
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
        scene.homeLabel = (walk == nil && find == nil) ? "你屋企 · 已隱身" : nil
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
        guard shade != nil else { return ("sun.max.fill", "而家大約 0% 有樓遮") }
        guard let v = shadeValue(landmarkID, at: now) else { return ("moon.stars.fill", "太陽落咗山，冇得曬") }
        let pct = Int((v * 100).rounded())
        return (pct >= 50 ? "building.2.fill" : "sun.max.fill", "而家大約 \(pct)% 有樓遮")
    }

    /// 约人理由：模板按遮荫写"嗰陣有樓遮住"，但日落后遮荫按 100% 计，要改成"嗰陣已經日落"。
    func honestReason(_ p: MeetProposal) -> MeetProposal {
        guard let shade, !shade.isSunUp(at: p.date) else { return p }
        var p = p
        p.reason = p.reason.replacingOccurrences(of: "嗰陣有樓遮住", with: "嗰陣已經日落")
        return p
    }
}
