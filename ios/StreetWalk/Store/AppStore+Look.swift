import SwiftUI

// 卡通形象：肤色、年龄段（规格 §4「不同年龄和肤色」）
extension AppStore {
    /// 示範街坊各配一套（肤色档、年龄段），同名字对得上：伯 = 長者，太 = 中年 / 長者，梁太推 BB 车 = 後生。
    static let demoLooks: [String: (skin: Int, age: AgeGroup)] = [
        "chan": (1, .adult), "wong": (0, .elder), "lee": (3, .elder),
        "leung": (2, .young), "ho": (2, .adult), "cheung": (1, .elder),
    ]

    /// 圈成员装好后套上外形：我用自己选的，示範街坊用上面那套；上个月赢了的圈全员有奖牌。
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

    /// 场景里的小人用和居民资料一样的外形。
    func withLook(_ p: ScenePerson) -> ScenePerson {
        guard let r = resident(p.id) else { return p }
        var q = p
        q.skin = r.skinTone
        q.age = r.ageGroup
        return q
    }

    /// 改我的外形（首次使用、设置页用）。
    func setLook(skin: Int? = nil, age: AgeGroup? = nil) {
        if let skin { skinChoice = min(max(skin, 0), Palette.skins.count - 1) }
        if let age { ageChoice = age }
        if let i = residents.firstIndex(where: \.isMe) {
            residents[i].skinTone = skinChoice
            residents[i].ageGroup = ageChoice
        }
        syncScene()
    }
}
