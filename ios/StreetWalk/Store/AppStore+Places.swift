import SwiftUI

// F3 landmark renaming, F10 resident reports, F9 weather and shade.
extension AppStore {
    // MARK: - F3 landmark renaming

    func select(_ s: Selection?) {
        selection = s
        renaming = nil
        if case .landmark(let id) = s { scene.highlightLandmark(id); focus(onLandmark: id) }
        else { scene.highlightLandmark(nil); scene.fadeOccluders(toward: nil) }
        if s != nil { Haptics.select() }
    }

    func focus(onLandmark id: String) {
        guard let lm = landmark(id) else { return }
        scene.setCamera(target: lm.pos, distance: min(scene.distance, scene.overviewDistance), animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.scene.fadeOccluders(toward: lm.pos) }
    }

    func rename(_ id: String, to name: String) {
        guard let i = landmarks.firstIndex(where: { $0.id == id }) else { return }
        let old = landmarks[i].name
        let names = landmarks.map(\.name)
        landmarks[i].name = name
        landmarkNames[id] = name
        community.renameLandmark(id, to: name)
        scene.renameLandmark(id, to: name)
        // F3 / A83: update daily greetings consistently; replace whole landmark names without changing longer names containing them.
        for j in residents.indices where residents[j].todayLine.contains(old) {
            residents[j].todayLine = Self.renamed(residents[j].todayLine, names: names, old: old, new: name)
        }
        if me.todayLine.contains(name) { uploadDay(now) }   // Upload the daily greeting again after renaming.
        renaming = nil
        say(community.sharesLandmarkNames ? L.t("改咗。\(old)而家叫\(name)，同圈嘅街坊都會見到。", "改好了。\(old)现在叫\(name)，同圈的邻居都会看到。", "Changed. \(old) is now called \(name). Neighbours in your circle will see it.") : L.t("改咗。\(old)而家叫\(name)。暫時只喺你部手機。", "改好了。\(old)现在叫\(name)。暂时只在你的手机上。", "Changed. \(old) is now called \(name). Only on your phone for now."))
        Haptics.success()
    }

    /// Protect names longest-first with placeholders, replace the target, then restore other names to avoid partial matches.
    static func renamed(_ line: String, names: [String], old: String, new: String) -> String {
        let sorted = Array(Set(names + [old])).filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        // Use distinct private-use characters as placeholders to avoid landmark-name collisions.
        func mark(_ k: Int) -> String { String(Character(UnicodeScalar(0xF0000 + k)!)) }
        var s = line
        for (k, n) in sorted.enumerated() { s = s.replacingOccurrences(of: n, with: mark(k)) }
        for (k, n) in sorted.enumerated() { s = s.replacingOccurrences(of: mark(k), with: n == old ? new : n) }
        return s
    }

    // MARK: - F10 resident reports

    /// rawText preserves original voice input (section 7), absent for button reports. Return the ID for withdrawal.
    @discardableResult
    func report(_ kind: ReportKind, rawText: String? = nil) -> UUID {
        let pos = myPosition()
        let lm = nearestLandmark(to: pos)
        var r = Report(kind: kind, pos: pos, landmarkID: lm?.id, date: now)
        r.rawText = rawText
        reports.append(r)
        community.submitReport(r)
        syncScene()
        say(community.hasServer
            ? L.t("記低咗：\(lm?.name ?? "呢度")\(kind.label)。月尾會同其他街坊嘅反映一齊交俾屋邨管理。", "记下了：\(lm?.name ?? "这里")\(kind.label)。月底会和其他邻居的反映一起交给小区管理处。", "Noted: \(lm?.name ?? "here"), \(kind.label). At the end of the month it goes to estate management with other neighbours' reports.")
            : L.t("記低咗：\(lm?.name ?? "呢度")\(kind.label)。暫時只存喺你部手機。", "记下了：\(lm?.name ?? "这里")\(kind.label)。暂时只存在你的手机上。", "Noted: \(lm?.name ?? "here"), \(kind.label). Only kept on your phone for now."))
        Haptics.light()
        return r.id
    }

    /// A18: withdraw by ID, including reports already submitted, to avoid removing the wrong report.
    func retractReport(_ id: UUID) {
        guard let i = reports.firstIndex(where: { $0.id == id }) else { return }
        reports.remove(at: i)
        community.retractReport(id)
        syncScene()
    }

    /// Monthly report combines my reports, other residents' anonymous reports and aggregates; local demo uses labeled sample data.
    var monthly: MonthlyReport {
        // Count me once per landmark and issue type each month, regardless of repeated submissions.
        var seen = Set<String>()
        let mine = reports.filter { r in
            Self.hk.isDate(r.date, equalTo: now, toGranularity: .month) && seen.insert("\(r.landmarkID ?? "-")|\(r.kind.rawValue)").inserted
        }
        return ai.monthlyReport(placeName: map?.shownPlaceName ?? L.t("屋邨", "小区", "Estate"), reports: mine + community.othersReports(landmarks: landmarks),
                                landmarks: landmarks, stats: monthlyStats)
    }

    var monthlyStats: MonthlyStats {
        let homes = (fullMap ?? map)?.buildings.filter { $0.kind == .residential }.reduce(0) { $0 + $1.levels * 8 } ?? 0
        let meetups = appointments.filter { $0.status == .done }.count
        return community.monthlyStats(myWalks: myMonthWalks, myMeetups: meetups, estateHomes: homes)
    }

    /// F10: notify residents when their report is addressed.
    func reportFollowedUp(_ id: UUID, text: String, isDemo: Bool) {
        guard let i = reports.firstIndex(where: { $0.id == id }) else { return }
        reports[i].followUp = text
        reports[i].followUpDemo = isDemo ? true : nil
        let r = reports[i]
        let place = landmark(r.landmarkID)?.name ?? L.t("呢度", "这里", "here")
        let line = L.t("你反映過「\(place)\(r.kind.label)」。\(text)", "你反映过「\(place)\(r.kind.label)」。\(text)", "You reported \"\(place): \(r.kind.label)\". \(text)")
        showBanner(BannerItem(symbol: "checkmark.seal.fill", text: line))
        say(line)
    }

    /// Demo management replies to the oldest unanswered report.
    func simulateFollowUp() {
        guard let r = reports.first(where: { $0.followUp == nil }) else { toast(L.t("你仲未反映過嘢。散步時撳「好曬」「冇櫈」就得。", "你还没反映过问题。散步时按「好晒」「没凳子」就行。", "You haven't reported anything yet. On a walk, tap \"Too sunny\" or \"No seats\".")); return }
        localCommunity?.simulateFollowUp(r, place: landmark(r.landmarkID)?.name ?? L.t("呢度", "这里", "here"))
    }

    /// Answered reports shown on Today.
    var answeredReports: [Report] { reports.filter { $0.followUp != nil && (demoMode || $0.followUpDemo != true) } }

    // MARK: - F9 live HKO weather and shade; manual demo overrides take priority

    /// A demo-menu or scripted weather choice overrides live data until Reset Demo.
    func setWeather(_ w: Weather) {
        hko.demoOverride = true
        weather = w
        refreshWeatherTip()
        if let tip = weatherTip {
            showBanner(BannerItem(symbol: w == .rain ? "cloud.heavyrain.fill" : "sun.max.fill", text: tip))
            say(tip)
        }
    }

    /// Fetch at launch and foreground return; omit unavailable weather rather than inventing it.
    func refreshLiveWeather(force: Bool = false) {
        Task {
            // Wait up to 10 seconds for the map to select the nearest station; otherwise use the Queen's Hill area.
            for _ in 0..<50 where map == nil { try? await Task.sleep(for: .milliseconds(200)) }
            _ = await hko.refresh(near: map?.center ?? TileKey.gridOrigin, force: force)
            applyLiveWeather()
        }
    }

    func applyLiveWeather() {
        guard !hko.demoOverride else { return }
        weather = hko.report.map { $0.isRain ? .rain : $0.isHot ? .hot : .normal } ?? .normal
        refreshWeatherTip()
        announceWeatherIfNeeded()
    }

    /// Announce heat / rain once per category per day; show the Today card without repeating unanswered prompts.
    func announceWeatherIfNeeded() {
        guard phase == .main, weather != .normal, let tip = weatherTip else { return }
        let key = "\(LocalStore.dayKey(now))|\(weather)"
        guard UserDefaults.standard.string(forKey: "weatherSpoken") != key else { return }
        UserDefaults.standard.set(key, forKey: "weatherSpoken")
        say(tip)
    }

    /// Reset Demo restores live weather.
    func useLiveWeather() {
        hko.demoOverride = false
        applyLiveWeather()
    }

    func refreshWeatherTip() {
        watchLanguageForWeather()
        var advice: String?
        if let shade {
            let hour = Self.hk.component(.hour, from: now)
            let tip = shade.shadeTip(landmarks, day: now, after: max(hour, 14))
            advice = ai.walkAdvice(weather: weather, now: now, shadeTip: tip)
        }
        guard !hko.demoOverride, let r = hko.report else {
            // Attribute only real HKO readings to HKO, never simulated weather.
            if hko.demoOverride, let a = advice, (a.hasPrefix("天文台話") || a.hasPrefix("天文台说")) { advice = String(a.dropFirst(4)) }
            if hko.demoOverride, let a = advice {
                for p in ["The Observatory says ", "Observatory says "] where a.hasPrefix(p) { advice = String(a.dropFirst(p.count)) }
            }
            weatherTip = advice.map { Self.oneSentence([$0]) }
            return
        }
        // For live weather state the source and reading; replace the template's potentially inaccurate afternoon-heavy-rain prediction.
        // A81: suggest waiting for rain to stop only when it is raining; high probability means possible rain.
        let rainingNow = r.warnings.contains { $0.code.hasPrefix("WRAIN") || $0.code == "WTS" }
            || (r.rainMM ?? 0) >= 0.5 || (63...65).contains(r.icon ?? 0)
        var rest = r.isDanger ? L.t("今日唔好出門，留喺屋企安全啲", "今天别出门，待在家里安全些", "Stay home today, it's safer")
            : weather != .rain ? advice ?? ""
            : !rainingNow ? L.t("可能會落雨，出門記得帶遮，或者聽日先行", "可能会下雨，出门记得带伞，或者明天再走", "It may rain. Take an umbrella, or walk tomorrow")
            : ["低", "中低"].contains(r.tomorrowPSR ?? "") ? L.t("唔好勉強出門，聽日天氣好啲先行", "别勉强出门，明天天气好些再走", "Don't push yourself. Walk tomorrow when the weather is better") : L.t("唔好勉強出門，等雨停先", "别勉强出门，等雨停了再说", "Don't push yourself. Wait for the rain to stop")
        // Do not repeat a heat statement after announcing HKO's Very Hot Weather Warning.
        if r.hasHeatWarning {
            rest = rest.replacingOccurrences(of: "今日好熱。", with: "").replacingOccurrences(of: "今日好熱，", with: "")
                .replacingOccurrences(of: "今天很热。", with: "").replacingOccurrences(of: "今天很热，", with: "")
        }
        // Outside Hong Kong, refer to the forecast instead of attributing it to HKO.
        if r.source != .hko { rest = rest.replacingOccurrences(of: "天文台話", with: "天氣預報話").replacingOccurrences(of: "天文台说", with: "天气预报说")
            .replacingOccurrences(of: "The Observatory says", with: "The forecast says") }
        let line = Self.oneSentence([r.line, rest])
        weatherTip = line.isEmpty ? nil : line
    }

    /// Regenerate weather text immediately when the interface language changes in Settings or onboarding.
    /// 10-18 device feedback found mixed-language weather responses and Today cards after switching languages.
    /// The weather sentence had been fixed to the language active during data retrieval.
    private func watchLanguageForWeather() {
        guard !Self.weatherWatchesLanguage else { return }
        Self.weatherWatchesLanguage = true
        withObservationTracking { _ = AppLanguage.shared.current } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                Self.weatherWatchesLanguage = false
                self?.refreshWeatherTip()
            }
        }
    }

    private static var weatherWatchesLanguage = false

    /// F9: keep each prompt to one sentence by joining clauses with commas and retaining one final period.
    static func oneSentence(_ parts: [String]) -> String {
        // English: join with comma-space, replace internal periods except decimal points, and retain one final period.
        if L.isEn {
            let body = parts.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,。， ")) }.filter { !$0.isEmpty }
                .joined(separator: ", ")
                .replacingOccurrences(of: ". ", with: ", ")
                .replacingOccurrences(of: "。", with: ", ")
            return body.isEmpty ? "" : body + "."
        }
        let ends = CharacterSet(charactersIn: "。，, ")
        let body = parts.map { $0.trimmingCharacters(in: ends) }.filter { !$0.isEmpty }
            .joined(separator: "，")
            .replacingOccurrences(of: "。", with: "，")
        return body.isEmpty ? "" : body + "。"
    }
}
