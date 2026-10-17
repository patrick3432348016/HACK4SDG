import ActivityKit
import Foundation
import SwiftUI

/// 实时活动（真·灵动岛 + 锁屏）：App 同小组件扩展共用嘅定义。
/// 内容就係 IslandStatus；App 开始、更新、结束（本地更新，冇推送：免费开发者账号用唔到推送）。
struct StreetWalkActivityAttributes: ActivityAttributes {
    typealias ContentState = IslandStatus
}

/// 灵动岛同锁屏用嘅颜色（App 嘅 DS 只喺 App 目标）：同 DS.accent 一样嘅橙。
enum IslandStyle {
    static let accent = Color(red: 0.847, green: 0.353, blue: 0.188)      // #D85A30
    /// 黑底上面嘅橙字（对比度够）：同 DS.accentInk 深色版一样。
    static let accentOnBlack = Color(red: 1.0, green: 0.604, blue: 0.431)  // #FF9A6E
    /// 约会倒数用粤语格式（「15 分鐘後」，数字同字之间有空格，同 App 一致）。
    static let locale = Locale(identifier: "yue-Hant-HK")
    static let localeCmn = Locale(identifier: "zh-Hans-CN")
    static let localeEn = Locale(identifier: "en_GB")
    static func locale(_ s: IslandStatus) -> Locale {
        switch s.lang ?? L.lang {
        case .yue: return locale
        case .cmn: return localeCmn
        case .en: return localeEn
        }
    }
}
