import Foundation
import Testing
import UIKit
@testable import StreetWalk

// 界面、无障碍与形象：人物配色色弱检查、排行榜名称、外形、圈对圈结果。

/// 色弱模拟（Machado 2009，严重度 1.0）+ CIEDE2000，同 ios/tools/cvd_check.py 一致。
enum CVD {
    static let matrices: [String: [[Double]]] = [
        "红色盲": [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
        "绿色盲": [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
        "蓝色盲": [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
    ]
    static func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func gam(_ c: Double) -> Double { let c = min(1, max(0, c)); return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }
    static func rgb(_ c: UIColor) -> [Double] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Double(r), Double(g), Double(b)]
    }
    static func simulate(_ c: [Double], _ m: [[Double]]?) -> [Double] {
        guard let m else { return c }
        let l = c.map(lin)
        return (0..<3).map { i in gam((0..<3).reduce(0) { $0 + m[i][$1] * l[$1] }) }
    }
    static func lab(_ c: [Double]) -> (Double, Double, Double) {
        let r = lin(c[0]), g = lin(c[1]), b = lin(c[2])
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047, y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }
    static func de2000(_ p: (Double, Double, Double), _ q: (Double, Double, Double)) -> Double {
        let (L1, a1, b1) = p, (L2, a2, b2) = q
        let rad = Double.pi / 180
        let Cb = (hypot(a1, b1) + hypot(a2, b2)) / 2
        let G = 0.5 * (1 - sqrt(pow(Cb, 7) / (pow(Cb, 7) + pow(25, 7))))
        let a1p = (1 + G) * a1, a2p = (1 + G) * a2
        let C1p = hypot(a1p, b1), C2p = hypot(a2p, b2)
        func hue(_ b: Double, _ a: Double) -> Double { let h = atan2(b, a) / rad; return h < 0 ? h + 360 : h }
        let h1p = hue(b1, a1p), h2p = hue(b2, a2p)
        let dL = L2 - L1, dC = C2p - C1p
        var dh = 0.0
        if C1p * C2p != 0 { dh = abs(h2p - h1p) <= 180 ? h2p - h1p : (h2p > h1p ? h2p - h1p - 360 : h2p - h1p + 360) }
        let dH = 2 * sqrt(C1p * C2p) * sin(dh / 2 * rad)
        let Lb = (L1 + L2) / 2, Cbp = (C1p + C2p) / 2
        var hb = h1p + h2p
        if C1p * C2p != 0 { hb = abs(h1p - h2p) <= 180 ? (h1p + h2p) / 2 : (h1p + h2p < 360 ? (h1p + h2p + 360) / 2 : (h1p + h2p - 360) / 2) }
        let T = 1 - 0.17 * cos((hb - 30) * rad) + 0.24 * cos(2 * hb * rad) + 0.32 * cos((3 * hb + 6) * rad) - 0.2 * cos((4 * hb - 63) * rad)
        let Sl = 1 + 0.015 * pow(Lb - 50, 2) / sqrt(20 + pow(Lb - 50, 2)), Sc = 1 + 0.045 * Cbp, Sh = 1 + 0.015 * Cbp * T
        let Rt = -2 * sqrt(pow(Cbp, 7) / (pow(Cbp, 7) + pow(25, 7))) * sin(60 * exp(-pow((hb - 275) / 25, 2)) * rad)
        return sqrt(pow(dL / Sl, 2) + pow(dC / Sc, 2) + pow(dH / Sh, 2) + Rt * (dC / Sc) * (dH / Sh))
    }
    static func luminance(_ c: [Double]) -> Double { 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]) }
    static func contrast(_ a: [Double], _ b: [Double]) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

struct PaletteTests {
    @Test func 人物配色色弱下两两分得开() {
        let colors = Palette.people.map(CVD.rgb)
        for kind in [nil, "红色盲", "绿色盲", "蓝色盲"] {
            let labs = colors.map { CVD.lab(CVD.simulate($0, kind.flatMap { CVD.matrices[$0] })) }
            var worst = Double.infinity
            for i in labs.indices { for j in labs.indices where j > i { worst = min(worst, CVD.de2000(labs[i], labs[j])) } }
            #expect(worst >= 12, "\(kind ?? "正常")：最小色差 \(worst)")
        }
    }

    @Test func 浅色深色地面都睇得到() {
        let light = [0.969, 0.969, 0.976], dark = [0.185, 0.185, 0.200]   // SceneStyle.paving 浅 / 深
        for c in Palette.people.map(CVD.rgb) {
            #expect(CVD.contrast(c, light) >= 2.2)
            #expect(CVD.contrast(c, dark) >= 2.2)
        }
    }

    @Test func 我系橙色_颜色有读屏名() {
        let me = CVD.rgb(Palette.personUI(Palette.meIndex))
        #expect(abs(me[0] - 0.847) < 0.01 && abs(me[1] - 0.353) < 0.01 && abs(me[2] - 0.188) < 0.01)
        let names = (0..<Palette.people.count).map(Palette.name)
        #expect(Set(names).count == Palette.people.count, "每个颜色名不同")
        #expect(Palette.name(Palette.meIndex) == "橙色")
        #expect(Palette.skinName(-1) == Palette.skinName(0) && Palette.skinName(99) == Palette.skinName(Palette.skins.count - 1), "越界不会崩")
    }
}

struct BoardNameTests {
    func resident(neighbor: Bool, block: String?) -> Resident {
        var r = Resident(id: "chan", name: "陳太", floor: 8, blockName: block, colorIndex: 0, mobility: .walk, streakDays: 3, todayLine: "")
        r.isNeighbor = neighbor
        return r
    }

    /// 2026-10-10 定：人人显示网名；座数楼层只有街坊先见到（地址私隐）。
    @Test func 排行榜人人网名_街坊先有座数楼层() {
        #expect(resident(neighbor: false, block: "皇滙樓 Wong Wui House").listName == "陳太", "非街坊：只有网名，唔出座数楼层")
        #expect(resident(neighbor: true, block: "皇滙樓 Wong Wui House").listName == "陳太 · 皇滙樓 8 樓")
        #expect(resident(neighbor: true, block: nil).listName == "陳太 · 8 樓", "街坊冇座名就只出楼层")
        var unknown = resident(neighbor: true, block: nil)
        unknown.floor = 0
        #expect(unknown.listName == "陳太", "街坊冇填楼层：唔出「0 樓」")
        #expect(unknown.floorLabel == "")
        var me = resident(neighbor: false, block: "皇樂樓")
        me.isMe = true
        #expect(me.listName == "你")
        me.nickname = "阿明"
        #expect(me.listName == "阿明 · 你")
    }
}

@MainActor
struct LookTests {
    @Test func 示範街坊外形各不同() {
        let looks = AppStore.demoLooks.values.map { "\($0.skin)-\($0.age.rawValue)" }
        #expect(Set(looks).count == AppStore.demoLooks.count, "每个示範街坊一套不同的组合")
        #expect(Set(AppStore.demoLooks.values.map(\.skin)).count >= 4, "四档肤色都有人用")
        #expect(Set(AppStore.demoLooks.values.map(\.age)) == Set(AgeGroup.allCases), "三个年龄段都有")
        let members = LocalCommunityService(demoEnabled: true).circleMembers(blocks: [], landmarks: [])
        #expect(members.allSatisfy { AppStore.demoLooks[$0.id] != nil }, "名单里每个人都有外形")
    }

    @Test func 上个月结果只喺演示有_赢咗有奖牌() {
        let demo = LocalCommunityService(demoEnabled: true).lastMonthRace(placeName: "皇后山邨", month: 9)
        #expect(demo?.isDemo == true)
        #expect(demo?.weWon == true)
        #expect(demo?.ourName == "皇后山邨圈")
        #expect(LocalCommunityService(demoEnabled: false).lastMonthRace(placeName: "皇后山邨", month: 9) == nil, "未接后端不编数据")
    }
}
