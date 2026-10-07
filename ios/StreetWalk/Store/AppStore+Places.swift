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
}
