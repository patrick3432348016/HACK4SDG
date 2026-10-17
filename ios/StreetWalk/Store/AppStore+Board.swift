import Foundation

/// F4：上个月圈对圈结果（月末公布胜出的圈，胜出圈全员有卡通奖牌）。
struct MonthResult: Equatable {
    var month: Int              // 1...12（香港时间的上个月）
    var ourName: String
    var rivalName: String
    var ourSteps: Int
    var rivalSteps: Int
    var isDemo: Bool
    var weWon: Bool { ourSteps >= rivalSteps }
}

extension LocalCommunityService {
    /// 上个月结果。单机演示：示範数据（我们圈小胜）；没开演示就没有（未接后端）。
    /// 接后端时：CommunityService 加同名方法，由每月结算表出（见 docs/backend_supabase.md 的 circle_race）。
    func lastMonthRace(placeName: String, month: Int) -> MonthResult? {
        guard demoEnabled else { return nil }
        return MonthResult(month: month, ourName: L.t("我哋呢頭", "我们这边", "Our area"), rivalName: L.t("隔籬", "隔壁", "Next door"),
                           ourSteps: 96_400, rivalSteps: 91_800, isDemo: true)
    }
}

extension AppStore {
    var lastMonthResult: MonthResult? {
        let last = Self.hk.date(byAdding: .month, value: -1, to: now) ?? now
        return localCommunity?.lastMonthRace(placeName: map?.placeName ?? L.t("我哋", "我们", "Our area"), month: Self.hk.component(.month, from: last))
    }
}
