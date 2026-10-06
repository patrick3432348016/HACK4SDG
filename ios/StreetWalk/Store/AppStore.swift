import SwiftUI
import UIKit

/// 成员 A：应用状态和全部流程。B 侧能力（AI、语音、碰一碰）通过 Contracts 里的协议调用。
@MainActor
@Observable
final class AppStore: NeighborRegistry {
    enum Phase: Equatable { case onboarding(Step), main }
    enum Step: Int { case consent, locate, pickHome, floor, avatar }
    enum Tab: Hashable { case today, board, neighbors }
    enum BumpStage: Equatable { case idle, searching, found(String) }
    enum Selection: Equatable { case landmark(String), person(String) }

    // 服务
    @ObservationIgnored let ai: AIService = TemplateAI()
    @ObservationIgnored let bump: BumpService = SimulatedBumpService()
    @ObservationIgnored let speaker = Speaker()
    @ObservationIgnored let listener = Listener()
    @ObservationIgnored let mapService = MapService()
    @ObservationIgnored let scene = DioramaController()
    @ObservationIgnored private(set) var shade: ShadeService?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var forceDecline = false

    // 状态
    var phase: Phase = .onboarding(.consent)
    var tab: Tab = .today
    var map: MapModel?
    var mapSource: MapService.Source = .fallback
    var loadingMap = false
    var landmarks: [Landmark] = []
    var residents: [Resident] = []
    var walk: WalkSession?
    var todayMinutes = 24
    var appointments: [Appointment] = []
    var proposal: (partnerID: String, options: [MeetProposal], index: Int)?
    var find: FindSession?
    var findFullScreen = false
    var banner: BannerItem?
    var voiceCard: VoiceCard?
    var listening = false
    var phrasePicker = false
    var bumpStage: BumpStage = .idle
    var remindPromptFor: String?
    var selection: Selection?
    var renaming: String?
    var reports: [Report] = []
    var weather: Weather = .normal
    var weatherTip: String?
    var paceTip: String?
    var demoHour: Double?
    var showReport = false
    var showTimeSlider = false
    var toast: String?
    var pendingHome: Int64?
    var floorChoice = 12
    var mobilityChoice: Mobility = .walk
    var colorChoice = Palette.meIndex

    let demoMode = LaunchArgs.has("-demo") || UserDefaults.standard.object(forKey: "demoMode") as? Bool ?? true

    var me: Resident { residents.first { $0.isMe } ?? Resident(id: "me", name: "你", floor: floorChoice, colorIndex: colorChoice, mobility: mobilityChoice, streakDays: 9, todayLine: "", isMe: true) }
    var neighbors: [Resident] { residents.filter { $0.isNeighbor && !$0.isMe } }
    var outNeighbors: [Resident] { neighbors.filter(\.isOut) }
    var ranking: [Resident] { residents.sorted { $0.streakDays != $1.streakDays ? $0.streakDays > $1.streakDays : $0.floor < $1.floor } }
    func resident(_ id: String) -> Resident? { residents.first { $0.id == id } }
    func landmark(_ id: String?) -> Landmark? { landmarks.first { $0.id == id } }

    var now: Date {
        guard let h = demoHour else { return Date() }
        return Self.today(at: h)
    }

    static func today(at hour: Double, dayOffset: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SolarPosition.hongKong
        return cal.startOfDay(for: Date()).addingTimeInterval(Double(dayOffset) * 86400 + hour * 3600)
    }

    // MARK: - 启动

    init() {
        demoHour = LaunchArgs.hour
        let d = UserDefaults.standard
        if LaunchArgs.has("-resetOnboarding") { ["onboarded", "homeBuilding", "floor", "mobility", "color"].forEach { d.removeObject(forKey: $0) } }
        if d.bool(forKey: "onboarded") || LaunchArgs.has("-skipOnboarding") {
            floorChoice = d.object(forKey: "floor") as? Int ?? 12
            mobilityChoice = Mobility(rawValue: d.string(forKey: "mobility") ?? "") ?? .walk
            colorChoice = d.object(forKey: "color") as? Int ?? Palette.meIndex
            phase = .main
            Task { await loadMap(home: (d.object(forKey: "homeBuilding") as? NSNumber)?.int64Value, animated: true) }
        }
        runOnboardingScriptIfNeeded()
    }

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
        map = m
        mapSource = source
        let picked = LandmarkDeriver.pick(LandmarkDeriver.candidates(in: m))
        landmarks = picked.map { Landmark(id: $0.id, name: ai.nameLandmark($0), kind: $0.kind, pos: $0.pos, hasSeat: $0.hasSeat) }
        shade = ShadeService(map: m, landmarks: landmarks)

        var homeID = home.flatMap { id in m.building(id: id) != nil ? id : nil }
        if homeID == nil, case .main = phase { homeID = defaultHome(in: m) }
        scene.setHomeBuilding(homeID)
        scene.homeTarget = homeID.flatMap { m.building(id: $0)?.centroid } ?? .zero
        scene.load(map: m, landmarks: landmarks, animated: animated)
        scene.setCamera(target: DioramaController.overviewTarget, distance: DioramaController.overviewDistance, animated: false)
        updateSun(animated: false)
        loadingMap = false
        if case .onboarding = phase { phase = .onboarding(.pickHome); highlightResidential(true) }
        else { populate() }
    }

    private func defaultHome(in m: MapModel) -> Int64? {
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
        scene.setHomeBuilding(id)
        scene.homeTarget = map?.building(id: id)?.centroid ?? .zero
        floorChoice = min(floorChoice, max(1, map?.building(id: id)?.levels ?? 30))
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

    /// 演示用的圈成员：同一格子每次一样。住在附近的住宅楼，常去的地标各不相同。
    private func populate() {
        guard let m = map else { return }
        let blocks = m.buildings.filter { $0.kind == .residential && $0.name != nil }
        let roster: [(String, String, Int, Int, Mobility, Int)] = [
            ("chan", "陳太", 8, 0, .walk, 21), ("wong", "黃太", 3, 1, .walk, 30), ("lee", "李伯", 15, 2, .wheelchair, 14),
            ("leung", "梁太", 6, 3, .stroller, 12), ("ho", "何生", 21, 4, .walk, 5), ("cheung", "張伯", 9, 5, .cane, 2),
        ]
        var list: [Resident] = []
        let seatFirst = landmarks.sorted { ($0.hasSeat ? 0 : 1, $0.pos.length) < ($1.hasSeat ? 0 : 1, $1.pos.length) }
        for (i, r) in roster.enumerated() {
            var res = Resident(id: r.0, name: r.1, floor: r.2, blockName: blocks.isEmpty ? nil : blocks[i % blocks.count].name,
                               colorIndex: r.3, mobility: r.4, streakDays: r.5, todayLine: "")
            res.homeLandmarkID = seatFirst.isEmpty ? nil : seatFirst[i % seatFirst.count].id
            let passed = [landmark(res.homeLandmarkID)].compactMap { $0 }
            res.todayLine = ai.dailyLine(for: res, passed: i == 5 ? [] : passed)
            list.append(res)
        }
        var meR = Resident(id: "me", name: "你", floor: floorChoice, blockName: scene.homeBuildingID.flatMap { m.building(id: $0)?.name },
                           colorIndex: colorChoice, mobility: mobilityChoice, streakDays: 9, todayLine: "", isMe: true)
        meR.homeLandmarkID = nearestLandmark(to: scene.homeTarget)?.id
        meR.todayLine = ai.dailyLine(for: meR, passed: [landmark(meR.homeLandmarkID)].compactMap { $0 })
        list.append(meR)
        residents = list
        if LaunchArgs.has("-withNeighbor") { residents[0].isNeighbor = true }
        syncScene()
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
        scene.setSun(SolarPosition.at(now, lat: m.center.lat, lon: m.center.lon), animated: animated)
    }

    func setDemoHour(_ h: Double?) {
        demoHour = h
        updateSun(animated: true)
        refreshWeatherTip()
    }

    // MARK: - F1 散步（演示：1 秒 = 1 分钟）

    static let walkSpeed = 9.0     // 米/秒（演示加速）
    static let findSpeed = 7.0

    func startWalk() {
        guard walk == nil, find == nil, map != nil else { return }
        let start = scene.nearestWalkable(scene.homeTarget + Vec2(x: 0, y: -18))
        var stops = landmarks.sorted { $0.pos.distance(to: start) < $1.pos.distance(to: start) }.prefix(3).map(\.pos)
        if stops.count >= 2 { stops = [stops[0], stops[2 % stops.count], stops[1]] }
        var route: [Vec2] = [start]
        var prev = start
        for s in stops + [start] {
            let leg = scene.route(from: prev, to: scene.nearestWalkable(s))
            route += leg.dropFirst()
            prev = route.last!
        }
        walk = WalkSession(start: Date(), route: route)
        paceTip = nil
        tab = .today
        speaker.speak("偵測到你出咗門，開始記錄，唔使撳任何掣。")
        Haptics.light()
        scene.followID = "me"
        scene.setCamera(target: start, distance: 1.35, animated: true)
        syncScene()
        startTicker()
    }

    private func remainingRoute(_ w: WalkSession) -> [Vec2] {
        let (pt, idx) = point(along: w.route, at: w.travelled)
        return [pt] + w.route.dropFirst(idx + 1)
    }

    func myPosition() -> Vec2 {
        if let p = scene.personPosition("me") { return p }
        if let w = walk { return point(along: w.route, at: w.travelled).0 }
        return scene.nearestWalkable(scene.homeTarget + Vec2(x: 0, y: -18))
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                let dt = Date().timeIntervalSince(last)
                last = Date()
                self.tick(dt)
            }
        }
    }

    private func tick(_ dt: Double) {
        if var f = find { tickFind(&f, dt); find = f }
        else if var w = walk { tickWalk(&w, dt) }
        if walk == nil && find == nil { ticker?.cancel(); ticker = nil }
    }

    private func tickWalk(_ w: inout WalkSession, _ dt: Double) {
        w.travelled += dt * Self.walkSpeed
        let total = pathLength(w.route)
        w.minutes = Int(Date().timeIntervalSince(w.start))
        let (pos, _) = point(along: w.route, at: w.travelled)
        for l in landmarks where !w.passed.contains(l.id) && l.pos.distance(to: pos) < 26 {
            w.passed.append(l.id)
            if var meR = residents.first(where: \.isMe), let i = residents.firstIndex(where: \.isMe) {
                meR.todayLine = ai.dailyLine(for: meR, passed: w.passed.compactMap(landmark))
                residents[i] = meR
            }
        }
        scene.setTrail(prefix(of: w.route, upTo: w.travelled))
        if w.minutes == 18 && paceTip == nil, let seat = landmarks.first(where: { $0.hasSeat && !w.passed.contains($0.id) }) ?? landmarks.first(where: \.hasSeat) {
            paceTip = "行慢咗少少。前面\(seat.name)有櫈，可以唞陣。"
            speaker.speak(paceTip!)
        }
        walk = w
        if w.travelled >= total { finishWalk() }
    }

    func finishWalk() {
        guard let w = walk else { return }
        walk = nil
        scene.followID = nil
        scene.setTrail([])
        todayMinutes += max(w.minutes, 1)
        if let i = residents.firstIndex(where: \.isMe) {
            residents[i].streakDays += 1
            residents[i].todayLine = ai.dailyLine(for: residents[i], passed: w.passed.compactMap(landmark))
        }
        paceTip = nil
        syncScene()
        scene.resetCamera()
        speaker.speak("返到屋企喇。今日行咗 \(max(w.minutes, 1)) 分鐘，經過 \(w.passed.count) 個地方。而家已經隱身。")
        Haptics.success()
    }

    // MARK: - F4 请假

    func toggleLeave() {
        guard let i = residents.firstIndex(where: \.isMe) else { return }
        residents[i].onLeave.toggle()
        residents[i].todayLine = ai.dailyLine(for: residents[i], passed: [])
        speaker.speak(residents[i].onLeave ? "收到，今日請假。連續 \(residents[i].streakDays) 日會保留。" : "撤回咗請假。")
        Haptics.light()
    }

    // MARK: - F5 碰一碰

    func startBump() {
        bumpStage = .searching
        bump.startSearching(candidates: residents) { [weak self] r in
            guard let self else { return }
            Haptics.success()
            self.bumpStage = .found(r.id)
            self.speaker.speak("你同\(r.floorLabel)\(r.name)而家係街坊。")
            self.syncScene()
            self.scene.setCamera(target: self.scene.homeTarget + Vec2(x: 0, y: -18), distance: 0.55, animated: true, duration: 1.0)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.6))
                self.remindPromptFor = r.id
            }
        }
        if case .searching = bumpStage, residents.allSatisfy({ $0.isMe || $0.isNeighbor }) {
            bumpStage = .idle
            toast("圈入面嘅人都已經係你街坊")
        }
    }

    func cancelBump() {
        bump.cancel()
        bumpStage = .idle
        syncScene()
    }

    func createNeighbor(_ residentID: String, remind: Bool) {
        guard let i = residents.firstIndex(where: { $0.id == residentID }) else { return }
        residents[i].isNeighbor = true
        residents[i].sendRemind = remind
        residents[i].receiveRemind = remind
        remindPromptFor = nil
        bumpStage = .idle
        syncScene()
        scene.resetCamera()
        speaker.speak(remind ? "開咗出門提醒。" : "冇問題，之後想開隨時可以。")
    }

    func setRemind(_ id: String, _ on: Bool) {
        guard let i = residents.firstIndex(where: { $0.id == id }) else { return }
        residents[i].receiveRemind = on
        residents[i].sendRemind = on
    }

    // MARK: - F6 出门提醒

    func neighborGoesOut(_ id: String = "chan") {
        guard let i = residents.firstIndex(where: { $0.id == id }) else { return }
        residents[i].isOut = true
        residents[i].atLandmarkID = residents[i].homeLandmarkID
        let r = residents[i]
        guard r.isNeighbor else {
            toast("\(r.floorLabel)出咗門，但佢未係你街坊，所以地圖上唔會見到佢。")
            return
        }
        syncScene()
        guard r.receiveRemind, let lm = landmark(r.atLandmarkID) else { return }
        let text = "\(r.floorLabel)\(r.name)啱啱出門，應該喺\(lm.name)嗰邊。"
        showBanner(BannerItem(symbol: "figure.walk", text: text, action: walk != nil ? .goFind(r.id) : .invite(r.id), actionTitle: walk != nil ? "過去搵佢" : "約佢"))
        speaker.speak(text)
    }

    // MARK: - F7 约人

    func proposeMeetup(with partnerID: String, day: Int? = nil, hour: Int? = nil) {
        guard let p = resident(partnerID), let shade else { return }
        guard p.isNeighbor else { toast("你同\(p.floorLabel)仲未係街坊。見到面碰一碰，先可以約。"); return }
        var options: [MeetProposal] = []
        let nowH = Calendar.current.component(.hour, from: now)
        let candidates: [(Int, Int)] = {
            if let day, let hour { return [(day, hour), (day, hour + 1), (day + 1, 8)] }
            if let day { return [(day, 8), (day, 16), (day, 18)] }
            var c: [(Int, Int)] = []
            for h in [8, 16, 17, 18] where h > nowH + 1 { c.append((0, h)) }
            c += [(1, 8), (1, 17)]
            return c
        }()
        for (d, h) in candidates {
            if let prop = ai.pickMeetupSpot(me: me, partner: p, date: Self.today(at: Double(h), dayOffset: d), landmarks: landmarks, shade: shade) {
                options.append(prop)
            }
        }
        guard !options.isEmpty else { return }
        proposal = (partnerID, options, 0)
        scene.highlightLandmark(options[0].landmarkID)
        focus(onLandmark: options[0].landmarkID)
    }

    func nextProposalTime() {
        guard var p = proposal else { return }
        p.index = (p.index + 1) % p.options.count
        proposal = p
        scene.highlightLandmark(p.options[p.index].landmarkID)
        Haptics.select()
    }

    func nextProposalPlace() {
        guard var p = proposal, let partner = resident(p.partnerID) else { return }
        let cur = p.options[p.index]
        let others = landmarks.filter { $0.id != cur.landmarkID }.sorted { (shade?.shade(landmarkID: $0.id, at: cur.date) ?? 0) > (shade?.shade(landmarkID: $1.id, at: cur.date) ?? 0) }
        guard let next = others.first(where: { $0.hasSeat }) ?? others.first, let shade else { return }
        let s = shade.shade(landmarkID: next.id, at: cur.date)
        _ = partner
        p.options[p.index] = MeetProposal(date: cur.date, landmarkID: next.id, reason: (s >= 0.5 ? "嗰陣有樹蔭" : "嗰陣有啲曬") + (next.hasSeat ? "、有櫈" : ""))
        proposal = p
        scene.highlightLandmark(next.id)
        focus(onLandmark: next.id)
        Haptics.select()
    }

    func confirmProposal() {
        guard let p = proposal else { return }
        let opt = p.options[p.index]
        let a = Appointment(partnerID: p.partnerID, date: opt.date, landmarkID: opt.landmarkID, reason: opt.reason, status: .waiting)
        appointments.insert(a, at: 0)
        proposal = nil
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
        let name = resident(p.partnerID)?.name ?? ""
        speaker.speak("幫你約咗\(name)\(dayTimeLabel(opt.date))，喺\(landmark(opt.landmarkID)?.name ?? "")附近。等緊\(name)確認。")
        Haptics.success()
        let id = a.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            self.partnerAccepts(id)
        }
    }

    private func partnerAccepts(_ id: UUID) {
        guard let i = appointments.firstIndex(where: { $0.id == id }), appointments[i].status == .waiting else { return }
        appointments[i].status = .accepted
        let a = appointments[i]
        let name = resident(a.partnerID)?.name ?? ""
        let text = "\(name)應承咗：\(dayTimeLabel(a.date))，喺\(landmark(a.landmarkID)?.name ?? "")附近見。"
        showBanner(BannerItem(symbol: "checkmark.circle.fill", text: text))
        speaker.speak(text)
        Haptics.success()
    }

    func cancelProposal() {
        proposal = nil
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
    }

    /// 演示：陈太约你。
    func partnerInvites(_ id: String = "chan") {
        guard let p = resident(id), p.isNeighbor, let shade else {
            toast("要先同陳太碰一碰做街坊，佢先可以約你。")
            return
        }
        let h = Calendar.current.component(.hour, from: now) < 15 ? 16 : 8
        let day = h == 8 ? 1 : 0
        guard let opt = ai.pickMeetupSpot(me: me, partner: p, date: Self.today(at: Double(h), dayOffset: day), landmarks: landmarks, shade: shade) else { return }
        appointments.insert(Appointment(partnerID: id, date: opt.date, landmarkID: opt.landmarkID, reason: opt.reason, status: .waiting, fromPartner: true), at: 0)
        let text = "\(p.name)約你\(dayTimeLabel(opt.date))喺\(landmark(opt.landmarkID)?.name ?? "")一齊行。"
        showBanner(BannerItem(symbol: "envelope.fill", text: text, action: .openNeighbors, actionTitle: "睇吓"))
        speaker.speak(text)
    }

    func acceptInvitation(_ id: UUID) {
        guard let i = appointments.firstIndex(where: { $0.id == id }) else { return }
        appointments[i].status = .accepted
        speaker.speak("約好咗。")
        Haptics.success()
    }

    func rescheduleInvitation(_ id: UUID) {
        guard let i = appointments.firstIndex(where: { $0.id == id }) else { return }
        appointments[i].date = appointments[i].date.addingTimeInterval(3600)
        Haptics.select()
    }

    var todaysAppointments: [Appointment] {
        let cal = Calendar.current
        return appointments.filter { cal.isDate($0.date, inSameDayAs: now) && $0.status != .done && !($0.fromPartner && $0.status == .waiting) }
    }
    var invitations: [Appointment] { appointments.filter { $0.fromPartner && $0.status == .waiting } }
    var upcomingAppointments: [Appointment] {
        let cal = Calendar.current
        return appointments.filter { !cal.isDate($0.date, inSameDayAs: now) && $0.status != .done && !($0.fromPartner && $0.status == .waiting) }
    }

    func dayTimeLabel(_ d: Date) -> String {
        let cal = Calendar.current
        let day = cal.isDate(d, inSameDayAs: now) ? "今日" : cal.isDate(d, inSameDayAs: now.addingTimeInterval(86400)) ? "聽日" : "後日"
        return day + TemplateAI.hourLabel(cal.component(.hour, from: d))
    }

    // MARK: - F8 找人（约好的当天 / 散步中临时）

    @ObservationIgnored private var findRoute: [Vec2]?
    @ObservationIgnored private var partnerRoute: [Vec2]?
    @ObservationIgnored private var findTravelled = 0.0
    @ObservationIgnored private var partnerTravelled = 0.0
    @ObservationIgnored private var findAppointment: UUID?

    func goFind(_ partnerID: String) {
        guard let p = resident(partnerID), p.isNeighbor, let lm = landmark(p.atLandmarkID ?? p.homeLandmarkID) else { return }
        banner = nil
        let start = myPosition()
        findRoute = scene.route(from: start, to: scene.nearestWalkable(lm.pos + Vec2(x: -4, y: -3)))
        findTravelled = 0
        find = FindSession(partnerID: partnerID, landmarkID: lm.id, spontaneous: true, stage: .asking)
        scene.setRoute(findRoute)
        scene.highlightLandmark(lm.id)
        syncScene()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard var f = self.find, f.stage == .asking else { return }
            if self.forceDecline {
                self.forceDecline = false
                f.stage = .declined
                self.find = f
                self.speaker.speak("\(p.name)而家唔方便。")
                try? await Task.sleep(for: .seconds(2))
                self.endFind()
                return
            }
            self.speaker.speak("\(p.name)話好，喺\(lm.name)等你。")
            Haptics.success()
            f.stage = .going
            f.etaMinutes = 0
            self.find = f
            self.find?.stage = .asking   // 等用户按「去」
            self.partnerAgreed = true
        }
    }

    var partnerAgreed = false

    func startGoing() {
        guard var f = find else { return }
        f.stage = .going
        find = f
        findFullScreen = true
        partnerAgreed = false
        scene.followID = nil
        startTicker()
        syncScene()
        if let lm = landmark(f.landmarkID) { scene.setCamera(target: lm.pos + Vec2(x: -20, y: -20), distance: 0.75, animated: true, duration: 1.0) }
    }

    func departForAppointment(_ a: Appointment) {
        guard let p = resident(a.partnerID), let lm = landmark(a.landmarkID) else { return }
        let start = myPosition()
        findRoute = scene.route(from: start, to: scene.nearestWalkable(lm.pos + Vec2(x: -4, y: -3)))
        let theirStart = landmark(p.homeLandmarkID)?.pos ?? lm.pos
        partnerRoute = scene.route(from: scene.nearestWalkable(theirStart + Vec2(x: 30, y: 25)), to: scene.nearestWalkable(lm.pos + Vec2(x: 5, y: 3)))
        findTravelled = 0
        partnerTravelled = 0
        findAppointment = a.id
        find = FindSession(partnerID: p.id, landmarkID: lm.id, spontaneous: false, stage: .going)
        findFullScreen = true
        scene.setRoute(findRoute)
        scene.highlightLandmark(lm.id)
        syncScene()
        startTicker()
        scene.setCamera(target: lm.pos + Vec2(x: -20, y: -20), distance: 0.8, animated: true, duration: 1.0)
        speaker.speak("今日約咗\(p.name)喺\(lm.name)。\(p.name)出咗門，大約 \(max(1, Int(pathLength(partnerRoute ?? []) / 70))) 分鐘到。")
    }

    private func tickFind(_ f: inout FindSession, _ dt: Double) {
        guard f.stage == .going || f.stage == .near, let route = findRoute else { return }
        findTravelled = min(pathLength(route), findTravelled + dt * Self.findSpeed)
        if !f.spontaneous, let pr = partnerRoute { partnerTravelled = min(pathLength(pr), partnerTravelled + dt * Self.findSpeed * 0.8) }
        let mePos = point(along: route, at: findTravelled).0
        let partnerPos: Vec2 = {
            if f.spontaneous { return landmark(f.landmarkID).map { scene.nearestWalkable($0.pos + Vec2(x: 5, y: 3)) } ?? mePos }
            return point(along: partnerRoute ?? [mePos], at: partnerTravelled).0
        }()
        let d = mePos.distance(to: partnerPos)
        f.distance = d
        f.etaMinutes = max(0, Int((d / 70).rounded(.up)))
        // 屏幕上方 = 西北（相机从东南看），所以把方位角减 315°。
        let bearing = atan2(partnerPos.x - mePos.x, partnerPos.y - mePos.y) * 180 / .pi
        f.bearing = bearing - 315
        if d <= 50 && f.stage == .going {
            f.stage = .near
            Haptics.success()
            speaker.speak("\(resident(f.partnerID)?.name ?? "")喺附近，跟住箭咀行。")
        }
        if d <= 9 || (findTravelled >= pathLength(route) && (f.spontaneous || partnerTravelled >= pathLength(partnerRoute ?? []))) {
            f.stage = .met
            Haptics.success()
            speaker.speak("見到喇！")
            if let id = findAppointment, let i = appointments.firstIndex(where: { $0.id == id }) { appointments[i].status = .done }
            let finished = f
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if self.find == finished || self.find?.stage == .met { self.endFind() }
            }
        }
    }

    func lateDemo() {
        guard var f = find else { return }
        f.latePrompt = true
        find = f
        speaker.speak("過咗約定時間 10 分鐘，仲未見到\(resident(f.partnerID)?.name ?? "")。要唔要打電話俾佢？")
    }

    func broadcastHere() {
        guard var f = find, let lm = landmark(f.landmarkID) else { return }
        f.broadcast = "我喺\(lm.name)"
        find = f
        speaker.speak("已經話俾\(resident(f.partnerID)?.name ?? "")知：我喺\(lm.name)。")
        Haptics.light()
    }

    func endFind() {
        find = nil
        findFullScreen = false
        findRoute = nil
        partnerRoute = nil
        findAppointment = nil
        partnerAgreed = false
        scene.setRoute(nil)
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
        if walk != nil {
            // 找完人继续散步：从当前位置回屋企。
            let here = myPosition()
            walk?.route = scene.route(from: here, to: scene.nearestWalkable(scene.homeTarget + Vec2(x: 0, y: -18)))
            walk?.travelled = 0
            scene.followID = "me"
            startTicker()
        } else {
            scene.resetCamera()
        }
        syncScene()
    }

    func declineNextAsk() { forceDecline = true }

    // MARK: - F3 地标改名

    func select(_ s: Selection?) {
        selection = s
        renaming = nil
        if case .landmark(let id) = s { scene.highlightLandmark(id); focus(onLandmark: id) }
        else { scene.highlightLandmark(nil); scene.fadeOccluders(toward: nil) }
        if s != nil { Haptics.select() }
    }

    func focus(onLandmark id: String) {
        guard let lm = landmark(id) else { return }
        scene.setCamera(target: lm.pos, distance: min(scene.distance, 1.2), animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.scene.fadeOccluders(toward: lm.pos) }
    }

    func rename(_ id: String, to name: String) {
        guard let i = landmarks.firstIndex(where: { $0.id == id }) else { return }
        let old = landmarks[i].name
        landmarks[i].name = name
        scene.renameLandmark(id, to: name)
        renaming = nil
        speaker.speak("改咗。\(old)而家叫\(name)，同圈嘅街坊都會見到。")
        Haptics.success()
    }

    // MARK: - F10 反映

    func report(_ kind: ReportKind) {
        let pos = myPosition()
        let lm = nearestLandmark(to: pos)
        reports.append(Report(kind: kind, pos: pos, landmarkID: lm?.id, date: now))
        syncScene()
        speaker.speak("記低咗：\(lm?.name ?? "呢度")\(kind.rawValue)。月尾會同其他街坊嘅反映一齊交俾屋邨管理。")
        Haptics.light()
    }

    func undoLastReport() {
        _ = reports.popLast()
        syncScene()
    }

    var monthly: MonthlyReport { ai.monthlyReport(placeName: map?.placeName ?? "屋邨", reports: reports, landmarks: landmarks) }

    // MARK: - F9 天气遮荫

    func setWeather(_ w: Weather) {
        weather = w
        refreshWeatherTip()
        if let tip = weatherTip {
            showBanner(BannerItem(symbol: w == .rain ? "cloud.heavyrain.fill" : "sun.max.fill", text: tip))
            speaker.speak(tip)
        }
    }

    func refreshWeatherTip() {
        guard let shade else { weatherTip = nil; return }
        let hour = Calendar.current.component(.hour, from: now)
        let seat = landmarks.first(where: \.hasSeat)
        let tip = seat.map { ($0, shade.shadedFromHour(landmarkID: $0.id, day: now, after: max(hour, 14))) }
        weatherTip = ai.walkAdvice(weather: weather, now: now, shadeTip: tip.map { (landmark: $0.0, shadedFrom: $0.1) })
    }

    // MARK: - 语音

    @ObservationIgnored private var askedSpeechAuth = false

    func micTapped() {
        if listening { stopListening(); return }
        if !askedSpeechAuth {
            // 第一次按咪才请求麦克风和语音识别权限。
            askedSpeechAuth = true
            listener.requestAuth()
        }
        voiceCard = nil
        do {
            try listener.start()
            listening = true
            Haptics.light()
        } catch {
            listening = false
            phrasePicker = true
        }
    }

    func stopListening() {
        let text = listener.stop()
        listening = false
        if text.isEmpty { phrasePicker = true } else { handle(text) }
    }

    var suggestedPhrases: [String] {
        let p = neighbors.first ?? residents.first { !$0.isMe }
        let name = p?.name ?? "陳太"
        if find != nil { return ["我喺\(landmark(find?.landmarkID)?.name ?? "涼亭")"] }
        if walk != nil { return ["呢度好曬", "呢度冇櫈", "過去搵\(name)", "約\(name)聽日朝早一齊行"] }
        return ["約\(name)聽日下晝三點一齊行", "今日請假", "\(landmarks.first?.name ?? "涼亭")改名做大樹底", "呢度好曬"]
    }

    func handle(_ text: String) {
        phrasePicker = false
        if listening { _ = listener.stop() }
        listening = false
        let ctx = AIContext(residents: residents, landmarks: landmarks, now: now, walking: walk != nil, finding: find != nil)
        let intent = ai.parseVoice(text, context: ctx)
        switch intent {
        case .invite(let id, let day, let hour):
            guard let p = resident(id) else { return }
            guard p.isNeighbor else { toast("你同\(p.floorLabel)仲未係街坊。見到面碰一碰，先可以約。"); return }
            proposeMeetup(with: id, day: day, hour: hour)
            if let prop = proposal?.options.first {
                voiceCard = VoiceCard(heard: text, title: "約\(p.name)\(dayTimeLabel(prop.date))一齊行",
                                      detail: "地點：\(landmark(prop.landmarkID)?.name ?? "")\n\(prop.reason)", needsConfirm: true, intent: intent)
            }
        case .goFind(let id):
            guard let p = resident(id), p.isNeighbor, p.isOut else { toast("而家冇街坊喺外面。"); return }
            voiceCard = VoiceCard(heard: text, title: "過去搵\(p.name)", detail: "會先問\(p.name)方唔方便", needsConfirm: true, intent: intent)
        case .leave:
            voiceCard = VoiceCard(heard: text, title: "今日請假", detail: "連續日數會保留", needsConfirm: false, intent: intent)
            if !me.onLeave { toggleLeave() }
        case .rename(let id, let name):
            let old = landmark(id)?.name ?? ""
            voiceCard = VoiceCard(heard: text, title: "\(old)改名做\(name)", detail: "同圈街坊都會見到", needsConfirm: false, intent: intent)
            rename(id, to: name)
        case .report(let kind):
            voiceCard = VoiceCard(heard: text, title: "記低：呢度\(kind.rawValue)", detail: "月尾匿名交俾屋邨管理", needsConfirm: false, intent: intent)
            report(kind)
        case .broadcast:
            voiceCard = VoiceCard(heard: text, title: "播俾對方聽", detail: text, needsConfirm: true, intent: intent)
        case .unknown:
            speaker.speak("唔好意思，我未聽明白。可以揀一句。")
            phrasePicker = true
        }
    }

    func confirmVoice() {
        guard let card = voiceCard else { return }
        voiceCard = nil
        switch card.intent {
        case .invite: confirmProposal()
        case .goFind(let id): goFind(id)
        case .broadcast: broadcastHere()
        default: break
        }
    }

    func rejectVoice() {
        guard let card = voiceCard else { return }
        voiceCard = nil
        switch card.intent {
        case .invite: cancelProposal()
        case .leave: if me.onLeave { toggleLeave() }
        case .report: undoLastReport()
        default: break
        }
    }

    // MARK: - 横幅与提示

    func showBanner(_ b: BannerItem) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { banner = b }
        Haptics.warning()
        bannerTask?.cancel()
        bannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { self.banner = nil } }
        }
    }

    func bannerAction() {
        guard let b = banner else { return }
        banner = nil
        switch b.action {
        case .invite(let id): proposeMeetup(with: id)
        case .goFind(let id): goFind(id)
        case .openNeighbors: tab = .neighbors
        case .none: break
        }
    }

    func toast(_ s: String) {
        withAnimation(.snappy) { toast = s }
        speaker.speak(s)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            if self.toast == s { withAnimation(.snappy) { self.toast = nil } }
        }
    }

    // MARK: - 演示

    func regenerateHere() {
        walk = nil; find = nil; findFullScreen = false
        TileCache.clear()
        Task { await loadMap(home: nil, animated: true) }
    }

    func resetDemo() {
        ticker?.cancel()
        walk = nil; find = nil; findFullScreen = false; proposal = nil; voiceCard = nil; banner = nil
        appointments = []; reports = []; weather = .normal; weatherTip = nil; demoHour = LaunchArgs.hour
        scene.setRoute(nil); scene.setTrail([]); scene.highlightLandmark(nil); scene.followID = nil
        populate()
        updateSun(animated: true)
        scene.resetCamera()
    }

    // MARK: - 几何辅助

    func pathLength(_ p: [Vec2]) -> Double { zip(p, p.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } }

    func point(along path: [Vec2], at dist: Double) -> (Vec2, Int) {
        guard path.count > 1 else { return (path.first ?? .zero, 0) }
        var rest = max(0, dist)
        for i in 0..<(path.count - 1) {
            let seg = path[i].distance(to: path[i + 1])
            if rest <= seg { return (path[i] + (path[i + 1] - path[i]) * (seg > 0 ? rest / seg : 0), i) }
            rest -= seg
        }
        return (path.last!, path.count - 2)
    }

    func prefix(of path: [Vec2], upTo dist: Double) -> [Vec2] {
        guard path.count > 1 else { return path }
        var out = [path[0]]
        var rest = dist
        for i in 0..<(path.count - 1) {
            let seg = path[i].distance(to: path[i + 1])
            if rest <= seg { out.append(path[i] + (path[i + 1] - path[i]) * (seg > 0 ? rest / seg : 0)); return out }
            out.append(path[i + 1])
            rest -= seg
        }
        return out
    }
}

extension TileCache {
    static func clear() { try? FileManager.default.removeItem(at: dir) }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}
