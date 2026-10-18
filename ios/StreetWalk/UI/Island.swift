import SwiftUI

// MARK: - In-App Dynamic Island
//
// User decisions on 10-09 / 10-11: expand banners from the physical island, collapse back into it, and show active states beside it.
// Notched / plain devices slide from the top; Reduce Motion uses fading only.
// Keep banners and side states mounted, changing expansion only; insertion/removal transitions could stall (5f785d4).
// Assign store values without withAnimation to avoid lost updates (c7858de); animate values locally here.
// IslandGeometry estimates island position from screen dimensions and safe area.

/// Topmost layer contains side status, replacement clock and banners; hide the system status bar only when covered.
struct IslandLayer: View {
    @Environment(AppStore.self) private var store
    let geo: IslandGeometry
    /// Recompute every 30 seconds because current time for countdowns is not Observation-tracked.
    @State private var tick = 0

    var body: some View {
        let _ = tick
        let bannerOn = store.banner != nil
        // When a sheet or full-screen view covers the main screen, hide side status and retain the system status bar.
        let covered = store.showSettings || store.showReport || store.showTimeSlider || store.bumpStage == .searching
        // Full-screen finding already has distance and arrow controls; avoid duplicate island status.
        let status = store.findFullScreen ? nil : store.islandStatuses.first
        let compactOn = geo.hasIsland && status != nil && !bannerOn && !covered
        ZStack(alignment: .topLeading) {
            if geo.hasIsland {
                IslandCompact(geo: geo, status: status, shown: compactOn)
                IslandClock(geo: geo, shown: compactOn)
            }
            IslandBanner(geo: geo)
        }
        .frame(width: geo.screen.width, height: geo.screen.height, alignment: .topLeading)
        .statusBarHidden(geo.hasIsland && (bannerOn || compactOn) && !covered)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                tick &+= 1
            }
        }
    }
}

// MARK: - Animation

/// Expansion springs slightly past its target; collapse does not bounce. -slowIsland runs 6x slower for recording inspection.
enum IslandMotion {
    static let slow: Double = LaunchArgs.has("-slowIsland") ? 6 : 1
    static let expand = Animation.spring(response: 0.5 * slow, dampingFraction: 0.72)
    static let collapse = Animation.spring(response: 0.4 * slow, dampingFraction: 0.9)
    static let resize = Animation.spring(response: 0.4 * slow, dampingFraction: 0.84)
    /// Reduce Motion uses fading only.
    static let fade = Animation.easeInOut(duration: 0.25 * slow)
}

// MARK: - Morphing

/// Morph the black rounded rectangle from from to to with p in 0…1, allowing spring overshoot; clip fixed destination content inside it.
/// Animate p and to together for smooth banner-text and side-number size changes.
private struct IslandMorph<Content: View>: View, Animatable {
    var p: CGFloat
    var from: CGRect
    var to: CGRect
    var fromRadius: CGFloat
    var toRadius: CGFloat
    /// Fade content from fadeStart to 1; zero keeps content visible during the no-island slide.
    var fadeStart: CGFloat
    /// Content scaling anchor at the island center.
    var anchor: UnitPoint
    var stroke: Bool
    @ViewBuilder var content: Content

    var animatableData: AnimatablePair<CGFloat, CGRect.AnimatableData> {
        get { AnimatablePair(p, to.animatableData) }
        set { p = newValue.first; to.animatableData = newValue.second }
    }

    var body: some View {
        let q = max(0, p)
        let r = CGRect(x: from.minX + (to.minX - from.minX) * q,
                       y: from.minY + (to.minY - from.minY) * q,
                       width: max(0, from.width + (to.width - from.width) * q),
                       height: max(0, from.height + (to.height - from.height) * q))
        let radius = max(0, min(fromRadius + (toRadius - fromRadius) * min(q, 1), min(r.width, r.height) / 2))
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let alpha = fadeStart <= 0 ? 1 : min(1, max(0, (q - fadeStart) / (1 - fadeStart)))
        content
            .frame(width: to.width, height: to.height, alignment: .top)
            .opacity(alpha)
            .blur(radius: (1 - alpha) * 6)
            .scaleEffect(fadeStart <= 0 ? 1 : 0.88 + 0.12 * min(q, 1), anchor: anchor)
            .offset(x: to.minX - r.minX, y: to.minY - r.minY)
            .frame(width: r.width, height: r.height, alignment: .topLeading)
            .background(Color.black, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(stroke ? 0.12 * min(q, 1) : 0), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.28 * min(q, 1)), radius: 18, y: 8)
            .contentShape(shape)
            .offset(x: r.minX, y: r.minY)
    }
}

// MARK: - Banners

/// Outings, acceptance and weather banners expand from the island, or slide from the top, and reverse on dismissal.
/// A10: tap or swipe up to dismiss; buttons perform actions. Drive directly from store.banner.
struct IslandBanner: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let geo: IslandGeometry
    /// Retain the previous banner content during collapse.
    @State private var last: BannerItem?
    /// A41: measure content height so larger text expands the banner instead of truncating.
    @State private var height: CGFloat = 150
    @State private var drag: CGFloat = 0
    @State private var bounce = 0
    private static let blank = BannerItem(symbol: "bell.fill", text: " ")

    var body: some View {
        let current = store.banner
        let shown = current != nil
        let item = current ?? last ?? Self.blank
        let to = geo.bannerFrame(height: height)
        let from = collapsedFrame(to)
        let fade = reduceMotion
        IslandMorph(p: fade || shown ? 1 : 0, from: from, to: to,
                    fromRadius: geo.island.map { $0.height / 2 } ?? geo.bannerRadius, toRadius: geo.bannerRadius,
                    fadeStart: geo.hasIsland && !fade ? 0.45 : 0,
                    anchor: anchor(to), stroke: true) {
            content(item)
        }
        .opacity(fade ? (shown ? 1 : 0) : 1)
        .offset(y: drag)
        .gesture(dragToClose)
        .onTapGesture { store.banner = nil }
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: L.t("關閉", "关闭")) { store.banner = nil }
        .animation(fade ? IslandMotion.fade : (shown ? IslandMotion.expand : IslandMotion.collapse), value: shown)
        .animation(fade ? nil : IslandMotion.resize, value: height)
        .onChange(of: current) { _, new in
            if let new { last = new }
            drag = 0
        }
        .task(id: item.id) {
            try? await Task.sleep(for: .milliseconds(260))
            bounce += 1
        }
    }

    /// Collapsed frame matches the black island, or moves above the screen when no island exists.
    private func collapsedFrame(_ to: CGRect) -> CGRect {
        if let i = geo.island { return i }
        return to.offsetBy(dx: 0, dy: -(to.maxY + 12))
    }

    private func anchor(_ to: CGRect) -> UnitPoint {
        guard let i = geo.island, to.width > 0, to.height > 0 else { return .top }
        return UnitPoint(x: (i.midX - to.minX) / to.width, y: (i.midY - to.minY) / to.height)
    }

    private var dragToClose: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { v in
                let dy = v.translation.height
                drag = dy < 0 ? dy : dy * 0.15   // Apply resistance to downward dragging.
            }
            .onEnded { v in
                if v.translation.height < -24 || v.predictedEndTranslation.height < -80 {
                    store.banner = nil
                } else {
                    withAnimation(DS.motion(DS.snappy)) { drag = 0 }
                }
            }
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ item: BannerItem) -> some View {
        let demo = isDemo(item)
        Group {
            if let i = geo.island {
                islandContent(item, demo: demo, island: i)
            } else {
                plainContent(item, demo: demo)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: geo.bannerFrame(height: 0).width, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in if h > 0 { height = h } }
        // On black backgrounds, render secondary buttons and Demo labels in dark appearance with white text / borders.
        .environment(\.colorScheme, .dark)
    }

    /// With an island, align the icon and Demo label beside it and place full-width body text below.
    private func islandContent(_ item: BannerItem, demo: Bool, island i: CGRect) -> some View {
        let frame = geo.bannerFrame(height: height)
        let rowTop = i.minY - frame.minY
        return VStack(alignment: .leading, spacing: 14) {
            // A41: allow unlimited lines without shrinking text; increase height instead.
            Text(item.text)
                .ds(.body)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            actionButton(item)
        }
        .padding(.horizontal, 20)
        .padding(.top, geo.bannerTextTop(height: height))
        .padding(.bottom, 20)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 0) {
                symbol(item)
                    .frame(width: max(0, i.minX - frame.minX - 20), alignment: .center)
                Spacer(minLength: i.width)
                Group { if demo { DemoBadge() } }
                    .frame(width: max(0, frame.maxX - i.maxX - 20), alignment: .center)
            }
            .frame(height: i.height)
            .padding(.top, rowTop)
            .padding(.horizontal, 10)
        }
    }

    /// Without an island, use icon-left / text-right layout sliding from the top.
    private func plainContent(_ item: BannerItem, demo: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                symbol(item).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.text)
                        .ds(.body)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if demo { DemoBadge() }
                }
            }
            actionButton(item)
        }
        .padding(16)
    }

    private func symbol(_ item: BannerItem) -> some View {
        Image(systemName: item.symbol)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(DS.accent)
            .symbolEffect(.bounce, options: .nonRepeating, value: bounce)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func actionButton(_ item: BannerItem) -> some View {
        if let title = item.actionTitle, item.action != .none {
            // Use a secondary action because Today's card already provides the one orange primary action.
            Button { store.bannerAction() } label: {
                Text(title).frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsSecondary)
        }
    }

    /// Label simulated banners from the target's demo state or, without a target, from simulated response / weather text.
    private func isDemo(_ b: BannerItem) -> Bool {
        switch b.action {
        case .invite(let id), .goFind(let id): return store.resident(id)?.isDemo ?? false
        case .depart(let id): return store.appointments.first { $0.id == id }.flatMap { store.resident($0.partnerID) }?.isDemo ?? false
        case .openNeighbors: return store.community.isSimulated
        default: break
        }
        if store.residents.contains(where: { $0.isDemo && !$0.isMe && b.text.hasPrefix($0.name) }) { return true }
        if store.hko.demoOverride && b.text == store.weatherTip { return true }   // Weather manually selected from the demo menu.
        return store.reports.contains { r in r.followUpDemo == true && (r.followUp.map { !$0.isEmpty && b.text.hasSuffix($0) } ?? false) }
    }
}

// MARK: - Side status

/// After banner collapse, show the activity icon on the left and walking minutes, finding distance or meeting countdown on the right.
/// Draw the App's foreground equivalent of Live Activity status; tap for details because iOS does not display its own activity there in foreground.
private struct IslandCompact: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let geo: IslandGeometry
    let status: IslandStatus?
    let shown: Bool
    /// Retain the previous status during collapse.
    @State private var last: IslandStatus?
    @State private var valueWidth: CGFloat = 52
    /// Width of the icon-only left capsule.
    static let leading: CGFloat = 40

    var body: some View {
        if let i = geo.island {
            let s = status ?? last
            let to = geo.compactFrame(leading: Self.leading, trailing: valueWidth + 22) ?? i
            let fade = reduceMotion
            IslandMorph(p: fade || shown ? 1 : 0, from: i, to: to,
                        fromRadius: i.height / 2, toRadius: i.height / 2,
                        fadeStart: fade ? 0 : 0.5,
                        anchor: UnitPoint(x: (i.midX - to.minX) / max(1, to.width), y: 0.5), stroke: false) {
                if let s { row(s, island: i, frame: to) }
            }
            .opacity(fade ? (shown ? 1 : 0) : 1)
            .onTapGesture { store.islandTapped() }
            .allowsHitTesting(shown)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(s?.spoken ?? "")
            .accessibilityHint(L.t("撳一下睇詳情", "点一下看详情"))
            .accessibilityAddTraits(.isButton)
            .accessibilityHidden(!shown)
            .animation(fade ? IslandMotion.fade : (shown ? IslandMotion.expand : IslandMotion.collapse), value: shown)
            .animation(fade ? nil : IslandMotion.resize, value: valueWidth)
            .onChange(of: status, initial: true) { _, new in if let new { last = new } }
        }
    }

    private func row(_ s: IslandStatus, island i: CGRect, frame: CGRect) -> some View {
        HStack(spacing: 0) {
            icon(s)
                .frame(width: Self.leading, height: i.height)
            Color.clear.frame(width: i.width + 8)
            Text(s.short)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText(value: Double(s.minutes * 10_000 + (s.meters ?? 0))))
                .animation(DS.motion(DS.snappy), value: s.short)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { valueWidth = $0 }
            Spacer(minLength: 0)
        }
        .frame(width: frame.width, height: i.height, alignment: .leading)
    }

    @ViewBuilder
    private func icon(_ s: IslandStatus) -> some View {
        Image(systemName: s.symbol)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(DS.accent)
            .rotationEffect(.degrees(s.kind == .find ? s.bearing ?? 0 : 0))
            .animation(DS.motion(DS.snappy), value: s.bearing)
            .contentTransition(.symbolEffect(.replace))
    }
}

/// When capsules hide the system status bar, redraw the clock at the matching position and font.
private struct IslandClock: View {
    let geo: IslandGeometry
    let shown: Bool
    /// Respect 24-hour leading zero, or 12-hour time without leading zero or AM/PM, matching the status bar.
    static let hour24 = !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")

    var body: some View {
        if let c = geo.clockCenter(leading: IslandCompact.leading) {
            TimelineView(.everyMinute) { ctx in
                Text(ctx.date, format: .dateTime.hour(Self.hour24 ? .twoDigits(amPM: .omitted) : .defaultDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .fixedSize()
            }
            .position(c)
            .opacity(shown ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: shown)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
