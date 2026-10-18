import ActivityKit
import Foundation
import SwiftUI

/// Live Activity definitions shared by the app and widget extension: real Dynamic Island and Lock Screen.
/// Content is IslandStatus. The app starts, updates, and ends it locally; no push updates with the free developer account.
struct StreetWalkActivityAttributes: ActivityAttributes {
    typealias ContentState = IslandStatus
}

/// Dynamic Island/Lock Screen accent matches DS.accent; DS itself belongs only to the app target.
enum IslandStyle {
    static let accent = Color(red: 0.847, green: 0.353, blue: 0.188)      // #D85A30
    /// Orange text with sufficient contrast on black, matching dark-mode DS.accentInk.
    static let accentOnBlack = Color(red: 1.0, green: 0.604, blue: 0.431)  // #FF9A6E
    /// Cantonese meetup countdown format uses a space between the number and unit, matching the app.
    static let locale = Locale(identifier: "yue-Hant-HK")
    static let localeCmn = Locale(identifier: "zh-Hans-CN")
    static func locale(_ s: IslandStatus) -> Locale { (s.lang ?? L.lang) == .cmn ? localeCmn : locale }
}
