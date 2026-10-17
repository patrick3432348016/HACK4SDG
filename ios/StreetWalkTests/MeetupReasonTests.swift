import Foundation
import Testing
@testable import StreetWalk

/// 10-18：约会理由喺本机按界面语言重算，对方传嚟嘅句子只用嚟认「一齊行几耐」。
struct MeetupReasonTests {
    @Test func 认得三种语言嘅一齊行几耐() {
        #expect(AppStore.walkMinutes(in: "嗰陣有樓遮住、有櫈，一齊行 45 分鐘") == 45)
        #expect(AppStore.walkMinutes(in: "那时有楼挡着，一起走半个小时") == 30)
        #expect(AppStore.walkMinutes(in: "shady then, walk together for an hour and a half") == 90)
        #expect(AppStore.walkMinutes(in: "那时有楼挡着、有凳子、两人都走 5 分钟左右") == nil)
    }

    @Test func 粤语界面唔直接用普通话句() {
        #expect(AppStore.matchesLanguage("嗰陣有樓遮住、有櫈"))
        #expect(!AppStore.matchesLanguage("那时有楼挡着、有凳子"))
    }
}
