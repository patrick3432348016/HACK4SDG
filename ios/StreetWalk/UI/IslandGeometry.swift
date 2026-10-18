import CoreGraphics

/// No public API exposes camera-island geometry; estimate from screen dimensions and top safe area.
/// Island iPhones typically have a top inset of at least 59 pt, versus 44–50 for notches and 20 for plain screens.
/// Use measured simulator geometry for known devices; fallback is centered 125 x 37, top at safe area minus 48.
/// For notched/plain devices and iPads, island=nil makes banners slide from the top.
struct IslandGeometry: Equatable {
    var screen: CGSize
    var safeTop: CGFloat
    /// Island rectangle in screen points, or nil when absent.
    var island: CGRect?

    var hasIsland: Bool { island != nil }

    /// Minimum island top inset is 59 pt from iPhone 14 Pro; notch devices reach at most 50.
    static let minIslandSafeTop: CGFloat = 55

    /// Measurements from simulator black capsules, converting 3x pixels to points: screen width/height to island top/width/height.
    static let known: [(w: CGFloat, h: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat)] = [
        (393, 852, 11.33, 125, 36.67),    // iPhone 14 Pro / 15 / 15 Pro / 16, measured on the iPhone 15 simulator.
        (430, 932, 11.33, 125, 36.67),    // iPhone 14 Pro Max / 15 Plus / 15 Pro Max / 16 Plus share this island geometry.
        (402, 874, 14, 125.33, 36.67),    // iPhone 16 Pro / 17 / 17 Pro, measured on the 17 Pro simulator; 18 Pro provisionally reuses it.
        (440, 956, 14, 125.33, 36.67),    // iPhone 16 Pro Max / 17 Pro Max
    ]

    static func make(screen: CGSize, safeTop: CGFloat, isPhone: Bool = true) -> IslandGeometry {
        var g = IslandGeometry(screen: screen, safeTop: safeTop, island: nil)
        // Landscape, iPad and notched devices have no supported island layout.
        guard isPhone, screen.height > screen.width, safeTop >= minIslandSafeTop else { return g }
        let k = known.first { abs($0.w - screen.width) < 0.5 && abs($0.h - screen.height) < 0.5 }
        let top = k?.top ?? max(11, safeTop - 48)
        let w = k?.width ?? 125.33
        let h = k?.height ?? 37
        g.island = CGRect(x: (screen.width - w) / 2, y: top, width: w, height: h)
        return g
    }

    // MARK: - Banner and side-status layout

    /// Horizontal banner margins.
    static let edge: CGFloat = 10

    /// Expanded frame uses content height; grow down and outward from the island or position below the status bar.
    func bannerFrame(height: CGFloat) -> CGRect {
        let w = screen.width - 2 * Self.edge
        if let i = island {
            return CGRect(x: Self.edge, y: max(5, i.minY - 4), width: w, height: height)
        }
        return CGRect(x: Self.edge, y: safeTop + 6, width: w, height: height)
    }

    /// Island-banner corners are concentric with roughly 55–62 pt screen corners at a 10 pt inset; otherwise use ordinary card corners.
    var bannerRadius: CGFloat { island != nil ? 42 : 28 }

    /// Align the first icon / Demo row beside the island, with body text below it.
    func bannerTextTop(height: CGFloat) -> CGFloat {
        guard let i = island else { return 16 }
        return i.maxY - bannerFrame(height: height).minY + 12
    }

    /// Return the combined black capsule frame: narrow left icon and right-side value.
    func compactFrame(leading: CGFloat, trailing: CGFloat) -> CGRect? {
        guard let i = island else { return nil }
        let maxTrailing = screen.width - Self.edge - 6 - i.maxX
        let t = min(trailing, maxTrailing)
        return CGRect(x: i.minX - leading, y: i.minY, width: i.width + leading + t, height: i.height)
    }

    /// When hiding the system bar, center the replacement clock in the space left of the left capsule.
    func clockCenter(leading: CGFloat) -> CGPoint? {
        guard let i = island else { return nil }
        return CGPoint(x: (i.minX - leading) / 2 + 2, y: i.midY)
    }
}
