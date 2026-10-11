import Foundation

// 灵动岛：而家进行紧嘅事（散步、找人、约会快到）→ App 入面岛两侧（IslandLayer）同真·灵动岛 / 锁屏（LiveIsland）。
extension AppStore {
    /// 按优先次序：找人 > 约会快到 > 散步。冇嘢进行紧 = 空。
    var islandStatuses: [IslandStatus] {
        var out: [IslandStatus] = []
        // 找人：出发咗先有距离（问紧对方嗰阵唔显示）
        if let f = find, f.stage == .going || f.stage == .near, let p = resident(f.partnerID) {
            out.append(IslandStatus(kind: .find, minutes: f.etaMinutes, meters: IslandStatus.roundMeters(f.distance),
                                    bearing: f.bearing, name: p.name, place: landmark(f.landmarkID)?.name, demo: p.isDemo))
        }
        if let (a, m) = meetSoon {
            let p = resident(a.partnerID)
            // 演示拨咗时间（demoHour）就唔俾实时活动自己倒数（真实时钟同演示时间唔同）
            out.append(IslandStatus(kind: .meet, minutes: m, name: p?.name, place: landmark(a.landmarkID)?.name,
                                    target: demoHour == nil ? a.date : nil, demo: p?.isDemo ?? false))
        }
        if let w = walk {
            out.append(IslandStatus(kind: .walk, minutes: w.minutes, places: w.passed.count, demo: !walkDetector.recording))
        }
        return IslandStatus.ordered(out)
    }

    /// 约好咗、30 分钟内（到过咗 10 分钟）嘅约会：最早嗰个同剩低几多分钟。已经出发去搵嗰个唔算（由找人接手）。
    var meetSoon: (Appointment, Int)? {
        let t = now
        return appointments
            .filter { $0.status == .accepted && $0.id != findAppointment && find?.partnerID != $0.partnerID }
            .sorted { $0.date < $1.date }
            .lazy
            .compactMap { a in IslandStatus.meetMinutes(left: a.date.timeIntervalSince(t)).map { (a, $0) } }
            .first
    }

    /// 撳岛两侧嘅状态：找人 = 返去找人全屏；约会 = 展开提醒（有「出發」）；散步 = 展开讲吓行咗几耐。
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

    /// 只俾 App 用紧嘅 store 开（单元测试自己 new 嘅唔好开实时活动）。
    func startLiveIsland() {
        guard isMainStore else { return }
        LiveIsland.shared.attach { [weak self] in self?.islandStatuses.first }
    }
}
