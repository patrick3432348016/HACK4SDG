import SwiftUI

// F3 地标改名、F10 反映、F9 天气遮荫
extension AppStore {
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
        // 每日一句都用新名（F3 全产品统一，A83）；只换完整嘅地标名，「車站涼亭」唔会因为改「涼亭」而变。
        for j in residents.indices where residents[j].todayLine.contains(old) {
            residents[j].todayLine = Self.renamed(residents[j].todayLine, names: names, old: old, new: name)
        }
        if me.todayLine.contains(name) { uploadDay(now) }   // 今日一句跟住新名，再传一次
        renaming = nil
        say(community.sharesLandmarkNames ? L.t("改咗。\(old)而家叫\(name)，同圈嘅街坊都會見到。", "改好了。\(old)现在叫\(name)，同圈的邻居都会看到。", "Changed. \(old) is now called \(name). Neighbours in your circle will see it.") : L.t("改咗。\(old)而家叫\(name)。暫時只喺你部手機。", "改好了。\(old)现在叫\(name)。暂时只在你的手机上。", "Changed. \(old) is now called \(name). Only on your phone for now."))
        Haptics.success()
    }

    /// 句子入面嘅地标名由长到短先换做记号，再将旧名换新名、其余换返原名：短名唔会误中长名嘅一部分。
    static func renamed(_ line: String, names: [String], old: String, new: String) -> String {
        let sorted = Array(Set(names + [old])).filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        // 记号用私用区字符（一个名一个），唔会撞到地标名。
        func mark(_ k: Int) -> String { String(Character(UnicodeScalar(0xF0000 + k)!)) }
        var s = line
        for (k, n) in sorted.enumerated() { s = s.replacingOccurrences(of: n, with: mark(k)) }
        for (k, n) in sorted.enumerated() { s = s.replacingOccurrences(of: mark(k), with: n == old ? new : n) }
        return s
    }

    // MARK: - F10 反映

    /// rawText：语音反映的原话（规格 §7），撳掣反映没有。返回记低嗰条的 id（撤回用）。
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

    /// 撤回一条反映：按 id 撤，唔会撤错；同时撤回已经交出去嘅（A18）。
    func retractReport(_ id: UUID) {
        guard let i = reports.firstIndex(where: { $0.id == id }) else { return }
        reports.remove(at: i)
        community.retractReport(id)
        syncScene()
    }

    /// 月报：我的反映 + 全邨其他居民的匿名反映 + 匿名汇总（单机演示时是示範数据）。
    var monthly: MonthlyReport {
        // 我只算一个人：本月、同一地标同一类问题只计一次（一个人撳十次都唔会变成十个人）。
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

    /// F10：反映落实后告诉居民。
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

    /// 演示：屋邨管理回覆最早一条未回覆的反映。
    func simulateFollowUp() {
        guard let r = reports.first(where: { $0.followUp == nil }) else { toast(L.t("你仲未反映過嘢。散步時撳「好曬」「冇櫈」就得。", "你还没反映过问题。散步时按「好晒」「没凳子」就行。", "You haven't reported anything yet. On a walk, tap \"Too sunny\" or \"No seats\".")); return }
        localCommunity?.simulateFollowUp(r, place: landmark(r.landmarkID)?.name ?? L.t("呢度", "这里", "here"))
    }

    /// 有回覆的反映（今日页显示）。
    var answeredReports: [Report] { reports.filter { $0.followUp != nil && (demoMode || $0.followUpDemo != true) } }

    // MARK: - F9 天气遮荫（香港天文台实时数据；演示菜单手动选的优先）

    /// 演示菜单 / 脚本手动选天气：覆盖实时数据，直到重置演示。
    func setWeather(_ w: Weather) {
        hko.demoOverride = true
        weather = w
        refreshWeatherTip()
        if let tip = weatherTip {
            showBanner(BannerItem(symbol: w == .rain ? "cloud.heavyrain.fill" : "sun.max.fill", text: tip))
            say(tip)
        }
    }

    /// 启动和回到前台时调用。拉不到就不显示天气（不编）。
    func refreshLiveWeather(force: Bool = false) {
        Task {
            // 等地图装好再挑最近测站（最多 10 秒），否则用皇后山邨附近。
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

    /// 实时天气转咗热 / 落雨：每日每档只讲一次（F9 唔回应唔重复）；画面喺今日卡。
    func announceWeatherIfNeeded() {
        guard phase == .main, weather != .normal, let tip = weatherTip else { return }
        let key = "\(LocalStore.dayKey(now))|\(weather)"
        guard UserDefaults.standard.string(forKey: "weatherSpoken") != key else { return }
        UserDefaults.standard.set(key, forKey: "weatherSpoken")
        say(tip)
    }

    /// 重置演示：回到实时天气。
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
            // "天文台話"只留给真实数据；演示选的天气唔好冒认天文台
            if hko.demoOverride, let a = advice, (a.hasPrefix("天文台話") || a.hasPrefix("天文台说")) { advice = String(a.dropFirst(4)) }
            if hko.demoOverride, let a = advice {
                for p in ["The Observatory says ", "Observatory says "] where a.hasPrefix(p) { advice = String(a.dropFirst(p.count)) }
            }
            weatherTip = advice.map { Self.oneSentence([$0]) }
            return
        }
        // 实时：句首讲明来源和读数；落雨时模板那句"下晝會落大雨"不一定对，改用这边的说法。
        // 真係落紧雨先讲「等雨停」；只係降雨概率高就讲「可能會落雨」（A81）。
        let rainingNow = r.warnings.contains { $0.code.hasPrefix("WRAIN") || $0.code == "WTS" }
            || (r.rainMM ?? 0) >= 0.5 || (63...65).contains(r.icon ?? 0)
        var rest = r.isDanger ? L.t("今日唔好出門，留喺屋企安全啲", "今天别出门，待在家里安全些", "Stay home today, it's safer")
            : weather != .rain ? advice ?? ""
            : !rainingNow ? L.t("可能會落雨，出門記得帶遮，或者聽日先行", "可能会下雨，出门记得带伞，或者明天再走", "It may rain. Take an umbrella, or walk tomorrow")
            : ["低", "中低"].contains(r.tomorrowPSR ?? "") ? L.t("唔好勉強出門，聽日天氣好啲先行", "别勉强出门，明天天气好些再走", "Don't push yourself. Walk tomorrow when the weather is better") : L.t("唔好勉強出門，等雨停先", "别勉强出门，等雨停了再说", "Don't push yourself. Wait for the rain to stop")
        // 天文台已经讲咗酷熱警告，就唔再讲一次「今日好熱」。
        if r.hasHeatWarning {
            rest = rest.replacingOccurrences(of: "今日好熱。", with: "").replacingOccurrences(of: "今日好熱，", with: "")
                .replacingOccurrences(of: "今天很热。", with: "").replacingOccurrences(of: "今天很热，", with: "")
        }
        // 香港以外：模板句讲「天文台話」唔啱，改讲天气预报。
        if r.source != .hko { rest = rest.replacingOccurrences(of: "天文台話", with: "天氣預報話").replacingOccurrences(of: "天文台说", with: "天气预报说")
            .replacingOccurrences(of: "The Observatory says", with: "The forecast says") }
        let line = Self.oneSentence([r.line, rest])
        weatherTip = line.isEmpty ? nil : line
    }

    /// 转咗界面语言（设定页、首次使用欢迎页都得）：天气句即刻用新语言重出。
    /// 10-18 真机：普通话问天气答「天文台話九龍城而家 27 度，天文台说明天…」、英文今日卡写「天文台说九龍城现在 27 度」——
    /// 天气句喺攞数据嗰阵用当时嘅语言定死咗。
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

    /// F9：每次提示唔超过一句——几段用逗号接埋，只留最尾一个句号。
    static func oneSentence(_ parts: [String]) -> String {
        // 英文：逗号 + 空格接埋，句中句号改逗号（唔郁小数点），最尾一个句号
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
