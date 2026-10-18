import Foundation

/// F4 previous-month circle result and cartoon medals for winning members.
struct MonthResult: Equatable {
    var month: Int              // Previous month in Hong Kong time, numbered 1...12.
    var ourName: String
    var rivalName: String
    var ourSteps: Int
    var rivalSteps: Int
    var isDemo: Bool
    var weWon: Bool { ourSteps >= rivalSteps }
}

extension LocalCommunityService {
    /// Previous-month results are simulated in demo mode (a narrow local win); absent in normal mode without a backend result.
    /// Future backend integration should supply the matching CommunityService method from monthly settlement data; see circle_race in docs/backend_supabase.md.
    func lastMonthRace(placeName: String, month: Int) -> MonthResult? {
        guard demoEnabled else { return nil }
        return MonthResult(month: month, ourName: L.t("我哋呢頭", "我们这边"), rivalName: L.t("隔籬", "隔壁"),
                           ourSteps: 96_400, rivalSteps: 91_800, isDemo: true)
    }
}

extension AppStore {
    var lastMonthResult: MonthResult? {
        let last = Self.hk.date(byAdding: .month, value: -1, to: now) ?? now
        return localCommunity?.lastMonthRace(placeName: map?.placeName ?? L.t("我哋", "我们"), month: Self.hk.component(.month, from: last))
    }
}
