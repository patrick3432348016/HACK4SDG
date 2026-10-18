import SwiftUI

// Onboarding, map loading, circle members, scene synchronization and sunlight.
extension AppStore {
    // MARK: - Onboarding

    func consent() {
        phase = .onboarding(.locate)
        // Before initial location permission, explain its purpose in the home step and wait for consent before startLocating.
        if !mapService.locationUndetermined { startLocating() }
    }

    /// Locate and load the nearby map, requesting While Using permission on first use; then showPickHome.
    func startLocating() {
        Task { await loadMap(home: nil, animated: true) }
    }

    func loadMap(home: Int64?, animated: Bool) async {
        mapLoadGen += 1
        let gen = mapLoadGen
        loadingMap = true
        mapNotice = nil
        // With a saved home, load its tile immediately without waiting for location or changing the base when opened elsewhere.
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
            // If location is unavailable, use the labeled built-in sample estate instead of pretending it is nearby.
            loaded = (MapService.fallback(), .fallback)
        }
        // Discard this result if the user selected the sample estate or restarted building selection while waiting.
        guard gen == mapLoadGen else { return }
        var (m, source) = loaded
        // Restore placeholder buildings by ID when nearby building data is missing.
        if let h = home, let p = MapModel.placeholderPos(h), homeTile == nil || m.tile == homeTile { m = m.addingPlaceholderHome(at: p).map }
        fullMap = m
        mapSource = source
        if case .onboarding = phase {
            let me = loc.flatMap { TileKey.snap($0) == m.tile ? LocalProjection(origin: m.center).toLocal($0) : nil }
            let notice: String? = loc == nil ? L.t("攞唔到你嘅位置，而家用緊示例屋邨（\(m.placeName)）。", "获取不到你的位置，现在使用示例小区（\(m.placeName)）。")
                : source == .fallback ? L.t("攞唔到地圖資料，而家用緊示例屋邨（\(m.placeName)）。", "获取不到地图数据，现在使用示例小区（\(m.placeName)）。") : nil
            showPickHome(near: me, notice: notice, animated: animated)
        } else {
            var homeID = home.flatMap { id in m.building(id: id) != nil ? id : nil }
            if homeID == nil {
                if let t = homeTile, m.tile != t {
                    // If the home grid is unavailable offline, show the sample estate without treating a sample building as the user's home.
                    noticeMap(L.t("暫時攞唔到你屋企附近嘅地圖，而家顯示緊示例屋邨。", "暂时获取不到你家附近的地图，现在显示示例小区。"), delay: 1)
                } else {
                    homeID = defaultHome(in: m)
                }
            }
            installDiorama(home: homeID, animated: animated)
            loadingMap = false
            populate()
        }
    }

    /// Home selection centers on the nearest selectable building; if the tile has none, add a placeholder at my position to allow completion.
    private func showPickHome(near me: Vec2?, notice: String?, animated: Bool) {
        guard var full = fullMap else { return }
        var notice = notice
        var v = full.pickView(near: me)
        if let me, v.hasHomeCandidate {
            // Explain when the map is not centered on me so highlighted buildings are not mistaken for nearby ones.
            let p = v.scenePoint(LocalProjection(origin: full.center).toGeo(me))
            if max(abs(p.x), abs(p.y)) > v.half { notice = notice ?? L.t("你附近未有住宅樓資料，而家顯示緊離你最近嘅住宅樓。", "你附近还没有住宅楼数据，现在显示离你最近的住宅楼。") }
        }
        if !v.hasHomeCandidate {
            full = full.addingPlaceholderHome(at: me ?? .zero).map
            fullMap = full
            v = full.pickView(near: me)
            notice = L.t("附近未有樓宇資料，喺你位置放咗一座示意樓，撳佢就得。", "附近还没有楼宇数据，在你的位置放了一座示意楼，点它就行。")
        }
        install(v, home: nil, animated: animated)
        pickCamera(animated: false)
        loadingMap = false
        phase = .onboarding(.pickHome)
        highlightResidential(true)
        // With location and residential data, preselect the nearest building and ask for confirmation; see OnbPickHomeStep.
        if let me, notice == nil, let id = guessHome(in: v, at: v.scenePoint(LocalProjection(origin: full.center).toGeo(me))) { pickHome(id) }
        // Wait until the building-selection prompt finishes speaking.
        if let notice { noticeMap(notice, delay: 2.5) }
    }

    /// Use a full-screen overview for home selection, scaled from a 300 m base rather than Today's half-screen viewport.
    func pickCamera(animated: Bool) {
        guard let v = map else { return }
        let k = v.size / 300
        scene.setCamera(target: Vec2(x: -65 * k, y: 65 * k), distance: Float(2.85 * k), animated: animated)
    }

    /// Suggest the residential building under the current position, otherwise the nearest within 120 m; leave more distant choices to the user.
    func guessHome(in v: MapModel, at p: Vec2) -> Int64? {
        let homes = v.buildings.filter { $0.kind == .residential }
        if let b = homes.first(where: { Polygon.contains($0.outline, p) }) { return b.id }
        guard let b = homes.min(by: { $0.centroid.distance(to: p) < $1.centroid.distance(to: p) }), b.centroid.distance(to: p) <= 120 else { return nil }
        return b.id
    }

    /// Rejecting the suggestion clears it, highlights all residences orange and restores overview.
    func pickHomeManually() {
        pendingHome = nil
        highlightResidential(true)
        pickCamera(animated: true)
    }

    /// Selectable residential buildings in the home-selection screen.
    func isHomeCandidate(_ id: Int64) -> Bool { map?.building(id: id)?.kind == .residential }

    /// Switch to the built-in sample on request after a long wait; discard any pending map result.
    func useSampleMap() {
        guard case .onboarding = phase else { return }
        mapLoadGen += 1
        fullMap = MapService.fallback()
        mapSource = .fallback
        pendingHome = nil
        showPickHome(near: nil, notice: L.t("而家用緊示例屋邨（\(fullMap?.placeName ?? "皇后山邨")）。", "现在使用示例小区（\(fullMap?.placeName ?? "皇后山邨")）。"), animated: true)
    }

    /// Keep mapNotice visible for sample / placeholder maps and also announce it with text and speech.
    func noticeMap(_ text: String, delay: Double = 0) {
        mapNotice = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if self.mapNotice == text { self.toast(text) }
        }
    }

    /// Crop a 200 m base around home and load it into the scene.
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

    /// Selectable home buildings are marked residential by MapModel.pickView, allowing generic or placeholder buildings when data is missing.
    func residentialBuildings() -> [Building] { map?.buildings.filter { $0.kind == .residential } ?? [] }

    func highlightResidential(_ on: Bool) {
        scene.highlightBuildings(on ? Set(residentialBuildings().map(\.id)) : [], color: nil)
    }

    func pickHome(_ id: Int64) {
        guard let b = map?.building(id: id), b.kind == .residential else { toast(L.t("請揀一座亮咗橙色嘅樓", "请选一座亮橙色的楼")); return }
        pendingHome = id
        scene.highlightBuildings([id], color: nil)
        scene.setCamera(target: b.centroid, distance: 1.2, animated: true)
        Haptics.select()
    }

    func confirmHome() {
        guard let id = pendingHome else { return }
        floorChoice = min(floorChoice, max(1, map?.building(id: id)?.levels ?? 30))
        highlightResidential(false)
        // After selection, crop the base to 200 m around home and animate the buildings rising again.
        installDiorama(home: id, animated: true)
        phase = .onboarding(.floor)
    }

    func finishOnboarding() {
        let firstTime = !changingHome     // Changing home in Settings needs no task card.
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
        uploadProfile()     // After populate, update the building count for the new home.
        scene.resetCamera()
        if firstTime { startFirstDay() }   // Today's three first-day tasks (AppStore+FirstDay).
        say(firstTime ? L.t("搞掂！今日試吓做呢三件事。", "搞定！今天试试做这三件事。") : L.t("改好咗。", "改好了。"))
        startWalkDetection()   // Start motion sensing; request notifications only after adding a neighbor (requestNotificationsIfReady).
        locationOnboarded()    // Register the home region; AppStore+Location controls Always-permission timing.
    }

    /// F2: obtain circle members from CommunityService (demo neighbors locally), then restore relationships, landmark names and my records.
    func populate() {
        guard let m = map else { return }
        adoptMapKey()
        applyLandmarkNames()
        let blocks = m.buildings.filter { $0.kind == .residential && $0.name != nil }.compactMap(\.name)
        community.setLandmarks(landmarks, originals: originalLandmarkNames)
        var list = community.circleMembers(blocks: blocks, landmarks: landmarks)
        for i in list.indices {
            // The real backend supplies daily greetings and relationships; only demo neighbors generate greetings from templates.
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
        syncHomeLocation()     // Pass home location to background departure detection (AppStore+Location).
        dropStaleReferences()
        closeOrphanAppointments()
        refreshMe()
        syncScene()
        checkAppointments()
        uploadProfile()     // Upload building and streak counts only when changed on the real backend.
        runScriptIfNeeded()
    }

    /// After circle changes, dismiss finding, selections, suggestions, reminders and recap cards for absent or no-longer-connected residents.
    /// Avoid undismissable cards and remove non-neighbors from the scene.
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

    // MARK: - Scene synchronization: exclude non-neighbors

    func syncScene() {
        var people: [ScenePerson] = []
        if let w = walk, find == nil {
            // After meeting, walk back along roads instead of through buildings; route progress continued while standing,
            // so catch up at 2.5x speed, then resume normal speed and synchronize home arrival with walk completion.
            let rest = remainingRoute(w), v = Self.walkSpeed
            var motion = ScenePerson.Motion.route(rest, speed: v)
            if let cur = scene.personPosition("me"), let first = rest.first, cur.distance(to: first) > 8 {
                let back = scene.route(from: cur, to: first), fast = v * 2.5
                // Progress advances by d while catching up: d = v * (distance back to route + d) / fast.
                let (meet, i) = point(along: rest, at: v * pathLength(back) / (fast - v))
                motion = .catchUp(lead: back + rest.prefix(i + 1).dropFirst() + [meet], fast: fast, rest: [meet] + rest.dropFirst(i + 1), speed: v)
            }
            people.append(ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility, motion: motion, label: "你"))
        }
        if let f = find, f.live, let p = resident(f.partnerID), p.isNeighbor {
            people += livePeople(f, partner: p)
        } else if let f = find, let p = resident(f.partnerID), p.isNeighbor, let lm = landmark(f.landmarkID) {
            let myStart = myPosition()
            people.append(ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility,
                                      motion: f.stage == .asking || f.stage == .declined ? .stand(at: myStart) : .route(findRoute ?? [myStart, lm.pos], speed: Self.findSpeed), label: "你"))
            let spot = scene.nearestWalkable(lm.pos + Vec2(x: 5, y: 3))
            if f.spontaneous || f.partnerOut { people.append(ScenePerson(id: p.id, color: p.uiColor, mobility: p.mobility,
                                      motion: f.spontaneous ? .stand(at: spot) : .route(partnerRoute ?? [spot], speed: Self.findSpeed * 0.8),
                                      label: p.name, highlighted: true)) }
        }
        if case .found(let id) = bumpStage, let p = resident(id) {
            // Stand together at my current walking position rather than jumping back home.
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
        // Use the home label only; the old hidden-status suffix confused older testers (UX review 16).
        scene.homeLabel = (walk == nil && find == nil) ? L.t("你屋企", "你家") : nil
        scene.reportMarks = reports.map { (id: $0.id.uuidString, pos: $0.pos, text: $0.kind.rawValue) }
    }

    /// Freeze the bump meeting point at my walking position, or outside home when idle.
    func bumpMeetSpot() -> Vec2 {
        if let s = bumpSpot { return s }
        let s = walk != nil && find == nil ? scene.nearestWalkable(myPosition()) : scene.nearestWalkable(scene.homeTarget + Vec2(x: 0, y: -18))
        bumpSpot = s
        return s
    }

    // MARK: - Time and sunlight

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

    /// Landmark shade fraction at a time (0–1); return nil after sunset instead of claiming complete building shade.
    func shadeValue(_ landmarkID: String, at date: Date) -> Double? {
        guard let shade, shade.isSunUp(at: date) else { return nil }
        return shade.shade(landmarkID: landmarkID, at: date)
    }

    /// Shade sentence with icon for the landmark card; indicate sunset after dark.
    func shadeFact(_ landmarkID: String) -> (symbol: String, text: String) {
        guard shade != nil else { return ("sun.max.fill", Self.shadeWords(0)) }
        guard let v = shadeValue(landmarkID, at: now) else { return ("moon.stars.fill", L.t("太陽落咗山，冇得曬", "太阳下山了，晒不到")) }
        return (v >= 0.5 ? "building.2.fill" : "sun.max.fill", Self.shadeWords(v))
    }

    /// Use everyday shade descriptions instead of percentages, which confused older testers (UX review 16).
    static func shadeWords(_ v: Double) -> String {
        v >= 0.6 ? L.t("而家有陰", "现在有阴凉") : v >= 0.3 ? L.t("而家一半有陰", "现在一半有阴凉") : L.t("而家曬", "现在晒")
    }

    /// Replace the template's building-shade reason with a sunset explanation after dark.
    func honestReason(_ p: MeetProposal) -> MeetProposal {
        guard let shade, !shade.isSunUp(at: p.date) else { return p }
        var p = p
        p.reason = p.reason.replacingOccurrences(of: "嗰陣有樓遮住", with: "嗰陣已經日落")
            .replacingOccurrences(of: "那时有楼挡着", with: "那时已经日落")
        return p
    }
}
