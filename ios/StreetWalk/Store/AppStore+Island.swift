import Foundation

// Current activity (walking, finding, upcoming meeting) drives IslandLayer and LiveIsland on Dynamic Island / Lock Screen.
extension AppStore {
    /// Priority: finding > upcoming meeting > walking. Empty when inactive.
    var islandStatuses: [IslandStatus] {
        var out: [IslandStatus] = []
        // Finding distance appears after departure, not while awaiting consent.
        if let f = find, f.stage == .going || f.stage == .near, let p = resident(f.partnerID) {
            out.append(IslandStatus(kind: .find, minutes: f.etaMinutes, meters: IslandStatus.roundMeters(f.distance),
                                    bearing: f.bearing, name: p.name, place: landmark(f.landmarkID)?.name, demo: p.isDemo))
        }
        if let (a, m) = meetSoon {
            let p = resident(a.partnerID)
            // Disable real-time countdown when demoHour overrides the clock.
            out.append(IslandStatus(kind: .meet, minutes: m, name: p?.name, place: landmark(a.landmarkID)?.name,
                                    target: demoHour == nil ? a.date : nil, demo: p?.isDemo ?? false))
        }
        if let w = walk {
            out.append(IslandStatus(kind: .walk, minutes: w.minutes, places: w.passed.count, demo: !walkDetector.recording))
        }
        return IslandStatus.ordered(out)
    }

    /// Earliest confirmed meeting from 30 minutes before to 10 minutes after; exclude a meeting already handled by finding.
    var meetSoon: (Appointment, Int)? {
        let t = now
        return appointments
            .filter { $0.status == .accepted && $0.id != findAppointment && find?.partnerID != $0.partnerID }
            .sorted { $0.date < $1.date }
            .lazy
            .compactMap { a in IslandStatus.meetMinutes(left: a.date.timeIntervalSince(t)).map { (a, $0) } }
            .first
    }

    /// Tapping status opens finding, the departure reminder, or elapsed walking details.
    func islandTapped() {
        guard let s = islandStatuses.first else { return }
        switch s.kind {
        case .find:
            if find != nil { findFullScreen = true }
        case .meet:
            guard let (a, _) = meetSoon else { return }
            showBanner(BannerItem(symbol: "clock.fill", text: "\(s.title)，\(s.detail)。", action: .depart(a.id), actionTitle: L.t("出發", "出发")), haptic: false)
        case .walk:
            showBanner(BannerItem(symbol: "figure.walk", text: L.t("\(s.title)，\(s.detail)。返到屋企會自動記低。", "\(s.title)，\(s.detail)。回到家会自动记下。")), haptic: false)
        }
        Haptics.light()
    }

    /// Only the active App store may start Live Activities, not stores created by unit tests.
    func startLiveIsland() {
        guard isMainStore else { return }
        LiveIsland.shared.attach { [weak self] in self?.islandStatuses.first }
    }
}
