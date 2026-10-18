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
        Self.mapRetry?.cancel()
        mapLoadGen += 1
        let gen = mapLoadGen
        loadingMap = true
        mapNotice = nil
        // If the saved home belongs to the sample estate after unavailable location / map data, keep the clearly labeled sample.
        // Do not fetch that sample tile and present it as nearby (B-3); changing home restores a real map.
        let sampleHome: Bool = {
            guard case .main = phase else { return false }
            let d = UserDefaults.standard
            return d.bool(forKey: "onboarded") && d.bool(forKey: Self.homeFromSampleKey)
        }()
        // With a saved home, load its tile immediately without waiting for location or changing the base when opened elsewhere.
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
            // If location is unavailable, use the labeled built-in sample estate instead of pretending it is nearby.
            loaded = (MapService.fallback(), .fallback)
        }
        // Discard this result if the user selected the sample or restarted home selection while waiting; sample mode retries separately.
        guard gen == mapLoadGen else { return }
        var (m, source) = loaded
        // Restore placeholder buildings by ID when nearby building data is missing.
        if let h = home, let p = MapModel.placeholderPos(h), homeTile == nil || m.tile == homeTile { m = m.addingPlaceholderHome(at: p).map }
        fullMap = m
        mapSource = source
        if case .onboarding = phase {
            let me = loc.flatMap { TileKey.snap($0) == m.tile ? LocalProjection(origin: m.center).toLocal($0) : nil }
            let notice: String? = loc == nil && !LaunchArgs.videoClean ? L.t("攞唔到你嘅位置，所以冇幫你估。而家用緊示例屋邨（\(m.shownPlaceName)），唔係你附近。", "拿不到你的位置，所以没帮你猜。现在先显示示例屋邨（\(m.shownPlaceName)），不是你家附近。", "Couldn't get your location, so no guess. This is a sample estate (\(m.shownPlaceName)), not near you.")
                : source == .fallback ? L.t("暫時攞唔到你附近嘅地圖，先用示例屋邨（\(m.shownPlaceName)），唔係你附近。我會繼續搵，搵到就自動換。", "暂时拿不到你附近的地图，先显示示例屋邨（\(m.shownPlaceName)），不是你家附近。我会继续找，找到就自动换。", "Couldn't get the map near you yet, so this is a sample estate (\(m.shownPlaceName)), not near you. I'll keep trying and switch when it arrives.") : nil
            showPickHome(near: me, notice: notice, animated: animated)
            if source == .fallback, let loc { scheduleMapRetry(tile: TileKey.snap(loc), loc: loc) }
        } else {
            var homeID = home.flatMap { id in m.building(id: id) != nil ? id : nil }
            if homeID == nil {
                if let t = homeTile, m.tile != t {
                    // If the home tile is unavailable offline, show a sample without treating its buildings as home; retry and replace when loaded.
                    noticeMap(L.t("暫時攞唔到你屋企附近嘅地圖，先顯示示例屋邨。我會繼續搵，搵到就自動換。", "暂时拿不到你家附近的地图，先显示示例屋邨。我会继续找，找到就自动换。", "Couldn't get the map near your home yet. Showing a sample estate. I'll keep trying and switch when it arrives."), delay: 1)
                    scheduleMapRetry(tile: t, loc: nil)
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
            // If home was selected in the sample, fetch the current tile and offer reselection; never change home automatically.
            if sampleHome { scheduleMapRetry(tile: nil, loc: nil) }
        }
    }

    // MARK: - Retry real maps while displaying the sample estate

    @MainActor static var mapRetry: Task<Void, Never>?

    /// Retry after 5, 15, 30 seconds and so on, for roughly 15 minutes; replace the sample when the real map arrives.
    /// A nil tile uses current location; a home selected in the sample only triggers a reselection prompt.
    func scheduleMapRetry(tile: TileKey?, loc: GeoPoint?) {
        Self.mapRetry?.cancel()
        guard isMainStore, !LaunchArgs.has("-offline") else { return }
        let gen = mapLoadGen
        Self.mapRetry = Task { @MainActor [weak self] in
            for wait in [5.0, 15, 30, 60, 60, 120, 120, 240, 240] {
                try? await Task.sleep(for: .seconds(wait))
                guard let self, !Task.isCancelled, gen == self.mapLoadGen, self.mapSource == .fallback else { return }
                var target = tile
                if target == nil {
                    guard !self.mapService.locationUndetermined, let p = await self.mapService.currentLocation() else { continue }
                    target = TileKey.snap(p)
                }
                guard let t = target, await self.mapService.refresh(tile: t) else { continue }
                guard !Task.isCancelled, gen == self.mapLoadGen, self.mapSource == .fallback else { return }
                self.realMapArrived(loc: loc, sampleHome: tile == nil)
                return
            }
        }
    }

    /// When a real map enters cache, update selection / Today immediately, or prompt reselection for a sample home.
    private func realMapArrived(loc: GeoPoint?, sampleHome: Bool) {
        // If onboarding finished with a sample home, prompt instead of replacing home automatically.
        let sampleHome = sampleHome || UserDefaults.standard.bool(forKey: Self.homeFromSampleKey)
        let done = L.t("搵到你附近嘅地圖，換咗做真嘅。", "找到你附近的地图了，已经换成真的。", "Found the map near you. Switched to the real one.")
        switch phase {
        case .onboarding(.locate), .onboarding(.pickHome):
            mapService.pinnedLocation = loc
            Task { await loadMap(home: nil, animated: true); toast(done) }
        case .main where !sampleHome:
            let home = (UserDefaults.standard.object(forKey: "homeBuilding") as? NSNumber)?.int64Value
            Task { await loadMap(home: home, animated: true); toast(done) }
        case .main:
            noticeMap(L.t("搵到你附近嘅地圖喇。去設定「重新揀樓」，就換到你屋企附近。", "找到你附近的地图了。到设置里「重新选楼」，就能换成你家附近。", "Found the map near you. Use \"Choose again\" in Settings to switch to your area."))
        default:
            break
        }
    }

    // MARK: - Local GPS marker

    /// Follow GPS only while Today or home selection displays the map; count each who subscriber and stop when none remain.
    func startHere(_ who: String) {
        if mapService.here.onUpdate == nil { mapService.here.onUpdate = { [weak self] _ in self?.refreshHere() } }
        mapService.here.start(who)
        refreshHere()
    }

    func stopHere(_ who: String) { mapService.here.stop(who) }

    /// Hide on the sample estate and during walking / finding, which already show my avatar.
    func refreshHere() {
        guard let g = mapService.here.last, let m = map, walk == nil, find == nil,
              mapSource != .fallback || LaunchArgs.value("-hereAt") != nil else { scene.setHere(nil); return }
        scene.setHere(m.scenePoint(g))
    }

    /// Home selection centers on the nearest selectable building; if the tile has none, add a placeholder at my position to allow completion.
    private func showPickHome(near me: Vec2?, notice: String?, animated: Bool) {
        guard var full = fullMap else { return }
        var notice = notice
        var v = full.pickView(near: me)
        if let me, v.hasHomeCandidate {
            // Explain when the map is not centered on me so highlighted buildings are not mistaken for nearby ones.
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
        // With location and residential data, preselect the nearest building and ask for confirmation; see OnbPickHomeStep.
        // Explain why no guess was possible (A-2), such as when setup happens at school.
        if let me, notice == nil {
            if let id = guessHome(in: v, at: v.scenePoint(LocalProjection(origin: full.center).toGeo(me))) { pickHome(id) }
            else { notice = L.t("你而家附近冇住宅樓（可能唔喺屋企），所以冇幫你估。撳你住嗰座，或者返到屋企再揀。", "你现在附近没有住宅楼（可能不在家），所以没帮你猜。请点你住的那栋，或者回家后再选。", "No housing blocks near you right now (maybe you're not home), so no guess. Tap your block, or choose again at home.") }
        }
        // Wait until the building-selection prompt finishes speaking.
        if let notice { noticeMap(notice, delay: 2.5) }
    }

    /// Use a full-screen overview for home selection, scaled from a 300 m base rather than Today's half-screen viewport.
    /// K-2: always use the full-screen selection viewport, including entry from Settings; avoid the cropped Today zoom.
    /// Reset manual pinch zoom too.
    func pickCamera(animated: Bool) {
        guard let v = map else { return }
        let k = v.size / 300
        scene.viewportScale = 1
        scene.setCamera(target: Vec2(x: -65 * k, y: 65 * k), distance: Float(2.85 * k), animated: animated, keepZoom: false)
    }

    /// Suggest the selectable building underfoot, or the nearest real residential building within 120 m; otherwise let the user choose.
    /// Do not guess from generic buildings allowed as fallback near schools or shops; the user may be away from home (A-2).
    func guessHome(in v: MapModel, at p: Vec2) -> Int64? {
        let homes = v.buildings.filter { $0.kind == .residential }
        if let b = homes.first(where: { Polygon.contains($0.outline, p) }) { return b.id }
        let real = homes.filter { fullMap?.building(id: $0.id)?.looksLikeHome ?? true }
        guard let b = real.min(by: { $0.centroid.distance(to: p) < $1.centroid.distance(to: p) }), b.centroid.distance(to: p) <= 120 else { return nil }
        return b.id
    }

    /// Rejecting the suggestion clears it, highlights all residences orange and restores overview.
    func pickHomeManually() {
        pendingHome = nil
        highlightResidential(true)
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
        if let loc = mapService.lastLocation { scheduleMapRetry(tile: TileKey.snap(loc), loc: loc) }
        showPickHome(near: nil, notice: L.t("而家用緊示例屋邨（\(fullMap?.shownPlaceName ?? "皇后山邨")），唔係你附近。", "现在先显示示例屋邨（\(fullMap?.shownPlaceName ?? "皇后山邨")），不是你家附近。", "This is a sample estate (\(fullMap?.shownPlaceName ?? "Queen's Hill Estate")), not near you."), animated: true)
    }

    /// Keep mapNotice visible for sample / placeholder maps and also announce it with text and speech.
    func noticeMap(_ text: String, delay: Double = 0) {
        if LaunchArgs.videoClean { return }   // Promotional recording treats the sample estate as home.
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
        // Generate canonical Chinese landmark names in Cantonese; server synchronization and BackendMapping.LandmarkIndex require language-stable names.
        let zh = Self.inLanguage(.yue) {
            LandmarkDeriver.uniqueNames(picked.map { Landmark(id: $0.id, name: ai.nameLandmark($0), kind: $0.kind, pos: $0.pos, hasSeat: $0.hasSeat) },
                                        in: m, home: home)
        }
        // For English display use OSM name:en when available, otherwise retain the Chinese name.
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
        refreshHere()
    }

    /// Run landmark naming under a temporary language on the same main-thread turn, then restore the original visible language.
    static func inLanguage<T>(_ l: AppLang, _ f: () -> T) -> T {
        let lang = AppLanguage.shared
        let old = lang.current
        guard old != l else { return f() }
        lang.current = l
        defer { lang.current = old }
        return f()
    }

    /// Display nameEn in English and canonical Chinese otherwise; applyLandmarkNames later overrides user-renamed landmarks.
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

    /// Selectable home buildings are marked residential by MapModel.pickView, allowing generic or placeholder buildings when data is missing.
    func residentialBuildings() -> [Building] { map?.buildings.filter { $0.kind == .residential } ?? [] }

    /// K-2 consistent coloring: light orange for selectable buildings, glowing dark orange for the selection, gray for others.
    /// Use fixed morning southeast light for readable home selection at any time; restore actual sunlight afterward.
    func highlightResidential(_ on: Bool) {
        if on {
            scene.setSun(SolarPosition(elevation: 50, azimuth: 135), animated: false)
            scene.highlightPick(candidates: Set(residentialBuildings().map(\.id)), selected: pendingHome)
        } else {
            scene.highlightBuildings([], color: nil)
            updateSun(animated: false)
        }
    }

    /// Selection changes color only, not the camera; users can pinch to inspect a building.
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
        say(firstTime ? L.t("搞掂！今日試吓做呢三件事。", "搞定！今天试试做这三件事。", "All set! Try these 3 things today.") : L.t("改好咗。", "改好了。", "Changed."))
        startWalkDetection()   // Start motion sensing; request notifications only after adding a neighbor (requestNotificationsIfReady).
        locationOnboarded()    // Register the home region; AppStore+Location controls Always-permission timing.
    }

    /// F2: obtain circle members from CommunityService (demo neighbors locally), then restore relationships, landmark names and my records.
    func populate() {
        guard let m = map else { return }
        adoptMapKey()
        localizeLandmarkNames()
        applyLandmarkNames()
        let blocks = m.buildings.filter { $0.kind == .residential && $0.name != nil }.compactMap(\.name)
        community.setLandmarks(landmarks, originals: originalLandmarkNames)
        var list = community.circleMembers(blocks: blocks, landmarks: landmarks)
        list.removeAll { $0.isDemo && !nickname.isEmpty && ($0.name == nickname || $0.altName == nickname) }   // Avoid demo neighbors sharing my name.
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
        showMapPreviewIfNeeded()
    }

    /// Screenshot checks: -uiPreview landmarkCard opens the first card; changeHome opens selection from Settings. Run once.
    private func showMapPreviewIfNeeded() {
        guard !Self.mapPreviewShown else { return }
        if UIPreview.is("landmarkCard"), let id = landmarks.first?.id {
            Self.mapPreviewShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.select(.landmark(id)) }
        } else if UIPreview.is("mapZoom") {
            // Simulate a 2x center pinch and 60-point right drag to verify zoom direction and ground tracking.
            Self.mapPreviewShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let v = self.scene.view else { return }
                let c = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
                self.scene.userZoom(by: 2, around: c)
                self.scene.userPan(from: c, to: CGPoint(x: c.x + 60, y: c.y))
            }
        } else if UIPreview.is("mapRotate") {
            // Simulate a 40-degree center rotation to verify direction and the reset button.
            Self.mapPreviewShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let v = self.scene.view else { return }
                self.scene.userRotate(by: 40 * .pi / 180, around: CGPoint(x: v.bounds.midX, y: v.bounds.midY))
            }
        } else if UIPreview.is("homeCard") {
            Self.mapPreviewShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.select(.home) }
        } else if UIPreview.is("changeHome") || UIPreview.is("changeHomePick") {
            Self.mapPreviewShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.beginChangeHome() }
            // changeHomePick selects the first building automatically to inspect its confirmation card.
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
        // 10-18: when idle, show my avatar outside home so appearance changes are visible and walks begin there.
        if walk == nil, find == nil, phase == .main, map != nil {
            people.append(ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility,
                                      motion: .stand(at: scene.nearestWalkable(scene.homeTarget + Vec2(x: 0, y: -18))), label: nil))
        }
        if case .found(let id) = bumpStage, let p = resident(id) {
            // Stand together at my current walking position rather than jumping back home.
            let spot = bumpMeetSpot()
            people.removeAll { $0.id == "me" }
            people.append(ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility, motion: .stand(at: spot + Vec2(x: -4, y: 0)), label: L.t("你", "你", "You")))
            people.append(ScenePerson(id: p.id, color: p.uiColor, mobility: p.mobility, motion: .stand(at: spot + Vec2(x: 4, y: 0)), label: p.name, highlighted: true))
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
        scene.homeLabel = (walk == nil && find == nil) ? L.t("你屋企", "你家", "Your home") : nil
        scene.reportMarks = reports.map { (id: $0.id.uuidString, pos: $0.pos, text: $0.kind.rawValue) }
        refreshHere()
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
        guard let v = shadeValue(landmarkID, at: now) else { return ("lightbulb.fill", lampWords(landmarkID)) }
        return (v >= 0.5 ? "building.2.fill" : "sun.max.fill", Self.shadeWords(v))
    }

    /// After dark discuss lighting using OSM lit=yes/no within 60 m; advise main roads if unknown.
    func lampWords(_ landmarkID: String) -> String {
        var lit = 0, dark = 0
        if let m = map, let lm = landmarks.first(where: { $0.id == landmarkID }) {
            for r in m.roads { guard let l = r.lit else { continue }
                let near = (0..<max(r.points.count - 1, 0)).contains { LandmarkDeriver.closestPoint(on: r.points[$0], r.points[$0 + 1], to: lm.pos).distance(to: lm.pos) < 60 }
                if near { if l { lit += 1 } else { dark += 1 } }
            }
        }
        if lit > 0 && lit >= dark { return L.t("天黑咗，附近有路燈", "天黑了，附近有路灯", "Dark now. Street lights nearby") }
        if dark > 0 { return L.t("天黑咗，路燈少，小心腳下", "天黑了，路灯少，注意脚下", "Dark now. Few street lights, watch your step") }
        return L.t("天黑咗，行有燈嘅大路", "天黑了，走有灯的大路", "Dark now. Stay on lit main roads")
    }

    /// Use everyday shade descriptions instead of percentages, which confused older testers (UX review 16).
    static func shadeWords(_ v: Double) -> String {
        v >= 0.6 ? L.t("而家有陰", "现在有阴凉", "Shady now") : v >= 0.3 ? L.t("而家一半有陰", "现在一半有阴凉", "Half shady now") : L.t("而家曬", "现在晒", "Too sunny now")
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
