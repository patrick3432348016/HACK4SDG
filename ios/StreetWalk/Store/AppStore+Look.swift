import SwiftUI

// Avatar skin tones and age groups (specification section 4).
extension AppStore {
    /// Assign demo neighbors consistent skin tones and age groups matching their characters, including older residents and a young parent.
    static let demoLooks: [String: (skin: Int, age: AgeGroup)] = [
        "chan": (1, .adult), "wong": (0, .elder), "lee": (3, .elder),
        "leung": (2, .young), "ho": (2, .adult), "cheung": (1, .elder),
    ]

    /// Apply saved appearance to me and preset appearance to demo neighbors; award medals to last month's winning circle.
    func applyLooks(_ list: inout [Resident]) {
        let medal = lastMonthResult?.weWon == true
        for i in list.indices {
            if list[i].isMe {
                list[i].skinTone = skinChoice
                list[i].ageGroup = ageChoice
            } else if let look = Self.demoLooks[list[i].id] {
                list[i].skinTone = look.skin
                list[i].ageGroup = look.age
            }
            list[i].hasMedal = medal
        }
    }

    /// Scene figures use resident-profile appearance.
    func withLook(_ p: ScenePerson) -> ScenePerson {
        guard let r = resident(p.id) else { return p }
        var q = p
        q.skin = r.skinTone
        q.age = r.ageGroup
        return q
    }

    /// Change my appearance in onboarding or Settings.
    func setLook(skin: Int? = nil, age: AgeGroup? = nil) {
        if let skin { skinChoice = min(max(skin, 0), Palette.skins.count - 1) }
        if let age { ageChoice = age }
        if let i = residents.firstIndex(where: \.isMe) {
            residents[i].skinTone = skinChoice
            residents[i].ageGroup = ageChoice
        }
        // Do not upload midway through onboarding / home changes; upload on completion and restore on cancellation.
        if phase == .main { uploadProfile() }
        syncScene()
    }
}
