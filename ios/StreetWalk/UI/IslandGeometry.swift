import CoreGraphics

/// 灵动岛（摄像头）喺屏幕上嘅位置。系统冇公开接口，按屏幕尺寸 + 顶部安全区推算：
/// - 有灵动岛嘅 iPhone 顶部安全区 ≥ 59（刘海机 44–50，冇刘海 20）；
/// - 已知机型用模拟器截图量出嚟嘅数（见 known）；新机型按「岛顶 = 安全区 − 48、125 × 37、居中」估。
/// 冇岛（刘海 / 冇刘海 / iPad）就 island = nil：横幅改为由顶部滑落。
struct IslandGeometry: Equatable {
    var screen: CGSize
    var safeTop: CGFloat
    /// 岛嘅位置（屏幕坐标，pt）；冇岛 = nil。
    var island: CGRect?

    var hasIsland: Bool { island != nil }

    /// 有灵动岛嘅最细顶部安全区（iPhone 14 Pro 起 59；刘海机最多 50）。
    static let minIslandSafeTop: CGFloat = 55

    /// 模拟器截图量出嚟（--mask=black 之外直接量黑色胶囊，3x 像素 ÷ 3）：屏幕阔 × 高 → 岛顶、阔、高。
    static let known: [(w: CGFloat, h: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat)] = [
        (393, 852, 11.33, 125, 36.67),    // iPhone 14 Pro / 15 / 15 Pro / 16（iPhone 15 模拟器实测）
        (430, 932, 11.33, 125, 36.67),    // iPhone 14 Pro Max / 15 Plus / 15 Pro Max / 16 Plus（同一粒岛）
        (402, 874, 14, 125.33, 36.67),    // iPhone 16 Pro / 17 / 17 Pro（iPhone 17 Pro 模拟器实测；18 Pro 暂按同一个）
        (440, 956, 14, 125.33, 36.67),    // iPhone 16 Pro Max / 17 Pro Max
    ]

    static func make(screen: CGSize, safeTop: CGFloat, isPhone: Bool = true) -> IslandGeometry {
        var g = IslandGeometry(screen: screen, safeTop: safeTop, island: nil)
        // 横屏、iPad、刘海机：冇岛
        guard isPhone, screen.height > screen.width, safeTop >= minIslandSafeTop else { return g }
        let k = known.first { abs($0.w - screen.width) < 0.5 && abs($0.h - screen.height) < 0.5 }
        let top = k?.top ?? max(11, safeTop - 48)
        let w = k?.width ?? 125.33
        let h = k?.height ?? 37
        g.island = CGRect(x: (screen.width - w) / 2, y: top, width: w, height: h)
        return g
    }

    // MARK: - 横幅、两侧状态嘅排位

    /// 横幅离屏幕左右边。
    static let edge: CGFloat = 10

    /// 展开横幅嘅框（高度由内容决定）：有岛就由岛顶开始向下、向两边长；冇岛就喺状态栏下面。
    func bannerFrame(height: CGFloat) -> CGRect {
        let w = screen.width - 2 * Self.edge
        if let i = island {
            return CGRect(x: Self.edge, y: max(5, i.minY - 4), width: w, height: height)
        }
        return CGRect(x: Self.edge, y: safeTop + 6, width: w, height: height)
    }

    /// 横幅圆角：有岛时跟屏幕圆角同心（屏幕约 55–62，横幅离边 10），冇岛用普通卡片圆角。
    var bannerRadius: CGFloat { island != nil ? 42 : 28 }

    /// 展开横幅入面，内容第一行（图标、示範标签）同岛并排；正文由岛下面开始。
    func bannerTextTop(height: CGFloat) -> CGFloat {
        guard let i = island else { return 16 }
        return i.maxY - bannerFrame(height: height).minY + 12
    }

    /// 两侧状态：左边只放图标（窄，自己画嘅时钟喺佢左边），右边放数字。返回整粒黑胶囊嘅框。
    func compactFrame(leading: CGFloat, trailing: CGFloat) -> CGRect? {
        guard let i = island else { return nil }
        let maxTrailing = screen.width - Self.edge - 6 - i.maxX
        let t = min(trailing, maxTrailing)
        return CGRect(x: i.minX - leading, y: i.minY, width: i.width + leading + t, height: i.height)
    }

    /// 两侧状态出现时系统状态栏收埋，左边补返时间：放喺左边耳仔（岛左边胶囊再左）中间。
    func clockCenter(leading: CGFloat) -> CGPoint? {
        guard let i = island else { return nil }
        return CGPoint(x: (i.minX - leading) / 2 + 2, y: i.midY)
    }
}
