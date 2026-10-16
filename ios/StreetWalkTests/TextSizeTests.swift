import Foundation
import SwiftUI
import Testing
@testable import StreetWalk

// 设定页「字體大小」：存档、启动参数、未揀过跟 iOS、场景高度。
// 唔改全局 TextSizeSetting.shared（其他测试并行跑）。
struct TextSizeTests {
    @Test func 存档同启动参数() {
        let d = UserDefaults(suiteName: "textsize-test-\(UUID())")!
        #expect(TextSizeSetting(defaults: d, arguments: []).saved == nil, "旧存档冇呢个键：未揀过")
        #expect(TextSizeSetting(defaults: d, arguments: []).current == .standard, "iOS 默认字号 → 標準")
        TextSizeSetting(defaults: d, arguments: []).set(.xlarge)
        #expect(TextSizeSetting(defaults: d, arguments: []).current == .xlarge, "揀咗会记住")
        #expect(TextSizeSetting(defaults: d, arguments: ["-textSize", "small"]).current == .small, "-textSize 截图用")
        #expect(d.string(forKey: TextSizeSetting.key) == "xlarge", "-textSize 唔存")
        d.set("乱写", forKey: TextSizeSetting.key)
        #expect(TextSizeSetting(defaults: d, arguments: []).saved == nil, "读唔明就当未揀过")
    }

    @Test func 未揀过跟iOS文字大小() {
        #expect(TextSize.matching(.xSmall) == .standard, "以前下限锁喺默认：唔会自动变細")
        #expect(TextSize.matching(.large) == .standard)
        #expect(TextSize.matching(.xLarge) == .large)
        #expect(TextSize.matching(.xxLarge) == .xlarge)
        #expect(TextSize.matching(.accessibility3) == .xlarge)
        let s = TextSizeSetting(defaults: UserDefaults(suiteName: "textsize-sys-\(UUID())")!, arguments: [])
        s.system = .accessibility1
        #expect(s.current == .xlarge)
        s.set(.small)
        #expect(s.current == .small, "揀咗就唔再跟 iOS")
    }

    @Test func 字号同场景高度() {
        #expect(TextSize.standard.dynamicType == .large, "標準 = 正文 24 / 辅助 20 / 标题 34")
        #expect(TextSize.allCases.map(\.dynamicType) == TextSize.allCases.map(\.dynamicType).sorted(), "由細到大")
        #expect(TextSize.standard.sceneFraction == 0.38, "10-16 组员测试：今日页场景太细 → 约 38%（由灵动岛下面开始画）")
        #expect(TextSize.small.sceneFraction == 0.38)
        #expect(TextSize.large.sceneFraction < 0.38 && TextSize.xlarge.sceneFraction < TextSize.large.sceneFraction, "字大场景缩")
        #expect(!TextSize.xlarge.dynamicType.isAccessibilitySize, "特大都唔用无障碍档（一屏要见到两张卡）")
    }
}
