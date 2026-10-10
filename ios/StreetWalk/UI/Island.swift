import SwiftUI

// MARK: - 灵动岛（App 入面）
//
// 用户 10-09 / 10-11 定：横幅从灵动岛真实位置「长」出嚟、收起时缩返入岛；横幅收起后，散步、找人、约会快到时
// 喺岛两侧显示状态。刘海 / 冇刘海机型由顶部滑落；开咗「減少動態效果」只淡入淡出。
// - 横幅、两侧状态都係常驻视图，只按 store 状态改展开程度（插入 / 移除转场会卡住，见 5f785d4）。
// - store 里直接改值，唔好包 withAnimation（会丢更新，见 c7858de）；动画全部喺呢度按值做。
// - 岛嘅位置由 IslandGeometry 按屏幕尺寸 + 安全区推算。

/// 主界面最上层：两侧状态、自己画嘅时间、横幅；有岛时按需要收埋系统状态栏（横幅 / 两侧状态盖住佢嗰阵）。
struct IslandLayer: View {
    @Environment(AppStore.self) private var store
    let geo: IslandGeometry
    /// 每 30 秒重算一次（约会倒数：「而家」唔係 Observation 追踪得到嘅值）。
    @State private var tick = 0

    var body: some View {
        let _ = tick
        let bannerOn = store.banner != nil
        // 有半屏 / 全屏画面盖住主界面：唔显示两侧状态，状态栏照出
        let covered = store.showSettings || store.showReport || store.showTimeSlider || store.bumpStage == .searching
        // 找人全屏有自己嘅顶卡（距离、箭咀），岛唔再重复
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

// MARK: - 动画

/// 灵动岛嘅弹簧：长出嚟少少回弹（同系统灵动岛一样）、缩返入去唔弹。-slowIsland：慢 6 倍，录屏逐帧检查用。
enum IslandMotion {
    static let slow: Double = LaunchArgs.has("-slowIsland") ? 6 : 1
    static let expand = Animation.spring(response: 0.5 * slow, dampingFraction: 0.72)
    static let collapse = Animation.spring(response: 0.4 * slow, dampingFraction: 0.9)
    static let resize = Animation.spring(response: 0.4 * slow, dampingFraction: 0.84)
    /// 減少動態效果：只淡入淡出。
    static let fade = Animation.easeInOut(duration: 0.25 * slow)
}

// MARK: - 形变

/// 黑色圆角框由 from 变到 to（p = 0…1，弹簧会略为超过 1）；内容固定喺 to 嘅位置，用形变中嘅框裁住，
/// 所以横幅似由岛度「长」出嚟。Animatable：p 同 to 一齐做动画（横幅换句、两侧数字变长都会顺滑咁变）。
private struct IslandMorph<Content: View>: View, Animatable {
    var p: CGFloat
    var from: CGRect
    var to: CGRect
    var fromRadius: CGFloat
    var toRadius: CGFloat
    /// 内容几时开始出（p 由 fadeStart 到 1 渐现）；滑落（冇岛）时 0 = 一直清楚。
    var fadeStart: CGFloat
    /// 内容由边一点放大（岛中心）。
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

// MARK: - 横幅

/// 出门提醒、约会应承、天气提示……：由岛「长」出嚟（冇岛就由顶滑落），收起时缩返入岛。
/// 点横幅或者向上扫 = 收埋；有按钮时按钮执行动作。由 store.banner 直接驱动（审核 A10）。
struct IslandBanner: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let geo: IslandGeometry
    /// 收起动画期间仍然画上一个横幅（内容唔好一下变空）。
    @State private var last: BannerItem?
    /// 内容量出嚟嘅高度（字号大时横幅变高，唔截断：审核 A41）。
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
        .accessibilityAction(named: "關閉") { store.banner = nil }
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

    /// 收起时嘅框：有岛 = 岛本身（黑色叠黑色，睇落似缩返入去）；冇岛 = 同一个框移到屏幕上面。
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
                drag = dy < 0 ? dy : dy * 0.15   // 向下拉有阻尼
            }
            .onEnded { v in
                if v.translation.height < -24 || v.predictedEndTranslation.height < -80 {
                    store.banner = nil
                } else {
                    withAnimation(DS.motion(DS.snappy)) { drag = 0 }
                }
            }
    }

    // MARK: 内容

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
        // 黑底：里面嘅次按钮、示範标签都按深色画（白字白边）。
        .environment(\.colorScheme, .dark)
    }

    /// 有岛：图标同「示範」标签同岛并排（好似系统展开嘅灵动岛），正文由岛下面开始、全阔。
    private func islandContent(_ item: BannerItem, demo: Bool, island i: CGRect) -> some View {
        let frame = geo.bannerFrame(height: height)
        let rowTop = i.minY - frame.minY
        return VStack(alignment: .leading, spacing: 14) {
            // 不限行数、不缩字：大字号时横幅变高，不截断（审核 A41）。
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

    /// 冇岛：图标喺左、字喺右（由顶部滑落）。
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
            // 次按钮：今日页的卡已经有同一个主按钮（一屏只一个橙色主按钮）。
            Button { store.bannerAction() } label: {
                Text(title).frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsSecondary)
        }
    }

    /// 示範数据的横幅都标「示範」：有对象就看对象；没有对象的（示範街坊答应了、屋邨管理示範回覆、手选天气）看句子。
    private func isDemo(_ b: BannerItem) -> Bool {
        switch b.action {
        case .invite(let id), .goFind(let id): return store.resident(id)?.isDemo ?? false
        case .depart(let id): return store.appointments.first { $0.id == id }.flatMap { store.resident($0.partnerID) }?.isDemo ?? false
        case .openNeighbors: return store.community.isSimulated
        default: break
        }
        if store.residents.contains(where: { $0.isDemo && !$0.isMe && b.text.hasPrefix($0.name) }) { return true }
        if store.hko.demoOverride && b.text == store.weatherTip { return true }   // 演示菜单手选的天气
        return store.reports.contains { r in r.followUpDemo == true && (r.followUp.map { !$0.isEmpty && b.text.hasSuffix($0) } ?? false) }
    }
}

// MARK: - 两侧状态

/// 横幅收埋后，进行紧嘅事喺岛两侧显示：左边图标（散步小人 / 找人箭咀 / 约会时钟），右边数字（「12 分」「35 米」「15 分鐘後」）。
/// 同真·灵动岛嘅实时活动一样（App 喺前台时系统唔会喺岛度显示自己嘅实时活动，所以 App 自己画）。撳一下 = 展开睇详情。
private struct IslandCompact: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let geo: IslandGeometry
    let status: IslandStatus?
    let shown: Bool
    /// 收起途中继续画上一个状态。
    @State private var last: IslandStatus?
    @State private var valueWidth: CGFloat = 52
    /// 左边胶囊阔度（只放图标）。
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
            .accessibilityHint("撳一下睇詳情")
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

/// 两侧状态出现时系统状态栏收埋咗（佢会同黑色胶囊撞埋），喺左边补返时间：同系统一样嘅位置、字款。
private struct IslandClock: View {
    let geo: IslandGeometry
    let shown: Bool
    /// 用户揀咗 24 小时制：同系统状态栏一样补零（「03:25」）；12 小时制唔补零、唔出上午下午（「3:25」）。
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
