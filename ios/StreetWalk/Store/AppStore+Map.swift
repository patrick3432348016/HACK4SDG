import SwiftUI

// 首次使用、地图装载、圈成员、场景同步、太阳
extension AppStore {
    // MARK: - 首次使用

    func consent() {
        phase = .onboarding(.locate)
        Task { await loadMap(home: nil, animated: true) }
    }

    func loadMap(home: Int64?, animated: Bool) async {
        loadingMap = true
        let loc = await mapService.currentLocation()
        let tile = loc.map(TileKey.snap) ?? TileKey(ix: 0, iy: 0)
        let (m, source) = await mapService.load(tile: tile)
        fullMap = m
        mapSource = source
        var homeID = home.flatMap { id in m.building(id: id) != nil ? id : nil }
        if homeID == nil, case .main = phase { homeID = defaultHome(in: m) }
        if case .onboarding = phase {
            // 选楼时看完整一格（同样转正、去掉小屋），选定后再收窄。
            install(m.simplified(around: .zero, size: m.size, maxBuildings: nil), home: nil, animated: animated)
            loadingMap = false
            phase = .onboarding(.pickHome)
            highlightResidential(true)
        } else {
            installDiorama(home: homeID, animated: animated)
            loadingMap = false
            populate()
        }
    }

    /// 以我屋企为中心裁出 300 m 底座并装进场景。
    func installDiorama(home: Int64?, animated: Bool) {
        guard let full = fullMap else { return }
        // 底座中心放在我屋企稍南一点（楼下大堂那边），高楼不会顶住画面上沿。
        let c = home.flatMap { full.building(id: $0)?.centroid } ?? .zero
        install(full.simplified(around: c, home: home), home: home, animated: animated)
    }

    func install(_ m: MapModel, home: Int64?, animated: Bool) {
        map = m
        let picked = LandmarkDeriver.pick(LandmarkDeriver.candidates(in: m))
        landmarks = picked.map { Landmark(id: $0.id, name: ai.nameLandmark($0), kind: $0.kind, pos: $0.pos, hasSeat: $0.hasSeat) }
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

    func residentialBuildings() -> [Building] { map?.buildings.filter { $0.kind == .residential } ?? [] }

    func highlightResidential(_ on: Bool) {
        scene.highlightBuildings(on ? Set(residentialBuildings().map(\.id)) : [], color: nil)
    }

    func pickHome(_ id: Int64) {
        guard let b = map?.building(id: id), b.kind == .residential else { toast("請揀一座住宅樓"); return }
        pendingHome = id
        scene.highlightBuildings([id], color: nil)
        scene.setCamera(target: b.centroid, distance: 1.2, animated: true)
        Haptics.select()
    }

    func confirmHome() {
        guard let id = pendingHome else { return }
        floorChoice = min(floorChoice, max(1, map?.building(id: id)?.levels ?? 30))
        highlightResidential(false)
        // 选好楼：底座收窄到我屋企周围 300 m，楼宇重新"升起"。
        installDiorama(home: id, animated: true)
        phase = .onboarding(.floor)
    }

    func finishOnboarding() {
        let d = UserDefaults.standard
        d.set(true, forKey: "onboarded")
        if let id = pendingHome { d.set(NSNumber(value: id), forKey: "homeBuilding") }
        d.set(floorChoice, forKey: "floor")
        d.set(mobilityChoice.rawValue, forKey: "mobility")
        d.set(colorChoice, forKey: "color")
        highlightResidential(false)
        scene.highlightBuildings([], color: nil)
        phase = .main
        populate()
        scene.resetCamera()
        speaker.speak("搞掂。你行街嘅時候我會自動記錄，唔使撳任何掣。")
    }

    /// 圈成员（F2）：由 CommunityService 给（单机演示时是示範街坊），再套回已保存的街坊关系、地标名、我的记录。
    func populate() {
        guard let m = map else { return }
        adoptMapKey()
        applyLandmarkNames()
        let blocks = m.buildings.filter { $0.kind == .residential && $0.name != nil }.compactMap(\.name)
        var list = community.circleMembers(blocks: blocks, landmarks: landmarks)
        for i in list.indices {
            let passed = [landmark(list[i].homeLandmarkID)].compactMap { $0 }
            list[i].todayLine = ai.dailyLine(for: list[i], passed: list[i].id == "cheung" ? [] : passed)
            if let link = savedNeighbors[list[i].id] {
                list[i].isNeighbor = true
                list[i].neighborSince = link.since
                list[i].sendRemind = link.send
                list[i].receiveRemind = link.receive
            }
        }
        var meR = Resident(id: "me", name: "你", floor: floorChoice, blockName: scene.homeBuildingID.flatMap { m.building(id: $0)?.name },
                           colorIndex: colorChoice, mobility: mobilityChoice, streakDays: 0, todayLine: "", isMe: true)
        meR.homeLandmarkID = nearestLandmark(to: scene.homeTarget)?.id
        list.append(meR)
        residents = list
        if LaunchArgs.has("-withNeighbor"), !list.isEmpty, !list[0].isMe { residents[0].isNeighbor = true; residents[0].neighborSince = Date() }
        refreshMe()
        syncScene()
        checkAppointments()
        runScriptIfNeeded()
    }

    func nearestLandmark(to p: Vec2) -> Landmark? { landmarks.min { $0.pos.distance(to: p) < $1.pos.distance(to: p) } }

    // MARK: - 场景同步（隐私规则在这里落实：非街坊永远不进场景）

    func syncScene() {
        var people: [ScenePerson] = []
        if let w = walk, find == nil {
            people.append(ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility, motion: .route(remainingRoute(w), speed: Self.walkSpeed), label: "你"))
        }
        if let f = find, let p = resident(f.partnerID), let lm = landmark(f.landmarkID) {
            let myStart = myPosition()
            people.append(ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility,
                                      motion: f.stage == .asking || f.stage == .declined ? .stand(at: myStart) : .route(findRoute ?? [myStart, lm.pos], speed: Self.findSpeed), label: "你"))
            let spot = scene.nearestWalkable(lm.pos + Vec2(x: 5, y: 3))
            people.append(ScenePerson(id: p.id, color: p.uiColor, mobility: p.mobility,
                                      motion: f.spontaneous ? .stand(at: spot) : .route(partnerRoute ?? [spot], speed: Self.findSpeed * 0.8),
                                      label: p.name, highlighted: true))
        }
        if case .found(let id) = bumpStage, let p = resident(id) {
            let home = scene.nearestWalkable(scene.homeTarget + Vec2(x: 0, y: -18))
            people.append(ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility, motion: .stand(at: home + Vec2(x: -4, y: 0)), label: "你"))
            people.append(ScenePerson(id: p.id, color: p.uiColor, mobility: p.mobility, motion: .stand(at: home + Vec2(x: 4, y: 0)), label: "\(p.floorLabel) \(p.name)", highlighted: true))
        }
        let shown = Set(people.map(\.id))
        for n in outNeighbors where !shown.contains(n.id) {
            guard let lm = landmark(n.atLandmarkID) else { continue }
            people.append(ScenePerson(id: n.id, color: n.uiColor, mobility: n.mobility, motion: .wander(around: lm.pos), label: n.name))
        }
        scene.setPeople(people)
        scene.homeLabel = (walk == nil && find == nil) ? "你屋企 · 已隱身" : nil
        scene.reportMarks = reports.map { (id: $0.id.uuidString, pos: $0.pos, text: $0.kind.rawValue) }
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
}
