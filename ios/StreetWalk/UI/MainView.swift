import SwiftUI

// MARK: - 底部卡片槽（一次只显示一张，按优先级）

/// 底部卡片槽里显示哪一类卡。卡片内容由各自的视图提供，MainView 只提供容器。
enum MainBottomCard: Hashable {
    case voice, remind, proposal, findAsk, info

    /// 语音、出门提醒是"要先答"的卡，整个屏幕变暗；
    /// 约人、找人、地标/街坊信息要配合场景看，只把场景以下变暗。
    var coversScene: Bool { self == .voice || self == .remind }
}

extension AppStore {
    /// 优先级：语音 > 出门提醒 > 约人提议 > 找人询问 > 信息卡。找人全屏时只保留语音卡。
    var uiActiveCard: MainBottomCard? {
        if listening || phrasePicker || voiceCard != nil { return .voice }
        if findFullScreen { return nil }
        if remindPromptFor != nil { return .remind }
        if proposal != nil { return .proposal }
        if find != nil { return .findAsk }
        if selection != nil { return .info }
        return nil
    }

    /// 点场景选东西：只在没有更重要的卡时才响应，免得打断约人/找人的高亮。
    var uiSceneTapsEnabled: Bool {
        guard !findFullScreen else { return false }
        let c = uiActiveCard
        return c == nil || c == .info
    }

    func uiCanDismiss(_ c: MainBottomCard) -> Bool {
        switch c {
        case .voice: return !listening
        case .proposal, .info: return true
        case .remind, .findAsk: return false
        }
    }

    func uiDismiss(_ c: MainBottomCard) {
        guard uiCanDismiss(c) else { return }
        switch c {
        case .voice:
            if voiceCard != nil {
                if voiceCard?.needsConfirm == true { rejectVoice() } else { voiceCard = nil }
            } else {
                phrasePicker = false
            }
        case .proposal: cancelProposal()
        case .info: select(nil)
        case .remind, .findAsk: break
        }
    }
}

fileprivate extension AppStore.Tab {
    static let ordered: [AppStore.Tab] = [.today, .board, .neighbors]
    var order: Int { Self.ordered.firstIndex(of: self) ?? 0 }
    var title: String {
        switch self {
        case .today: return "今日"
        case .board: return "排行榜"
        case .neighbors: return "街坊"
        }
    }
    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .board: return "trophy"
        case .neighbors: return "person.2"
        }
    }
}

// MARK: - 主界面

/// 上：3D 场景（伸到状态栏下）；咪骑在场景与内容交界右侧；下：当前标签内容；最底：三个大标签。
struct MainView: View {
    @Environment(AppStore.self) private var store
    @State private var todayScroll = ScrollPosition(edge: .top)
    @State private var boardScroll = ScrollPosition(edge: .top)
    @State private var neighborsScroll = ScrollPosition(edge: .top)

    var body: some View {
        @Bindable var store = store
        // 在 GeometryReader 闭包外读取会变的状态：闭包里的读取不会被 Observation 追踪，
        // 之前切标签时内容区偶尔不刷新（停在旧页或整页空白）就是这个原因。
        let tab = store.tab
        let full = store.findFullScreen
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let size = CGSize(width: geo.size.width + safe.leading + safe.trailing,
                              height: geo.size.height + safe.top + safe.bottom)
            let sceneH = full ? size.height : (size.height * DS.sceneFraction).rounded()
            let tabH = max(DS.tabBarHeight, safe.bottom + 49)
            let micCenter = CGPoint(x: size.width - DS.side - DS.micSize / 2, y: sceneH)

            ZStack(alignment: .topLeading) {
                Color(.systemGroupedBackground)

                // 内容区（在场景之下；找人全屏时被场景盖住，保留状态不销毁）
                contentArea(tab: tab, width: size.width, height: max(0, size.height - sceneH), tabH: tabH)
                    .offset(y: sceneH)
                    .opacity(full ? 0 : 1)
                    .allowsHitTesting(!full)
                    .accessibilityHidden(full)

                // 场景 + 标签
                sceneArea(width: size.width, height: sceneH, safe: safe, micCenter: micCenter, full: full)

                // 左上 / 右上胶囊
                topChips(width: size.width, safeTop: safe.top)
                    .opacity(full ? 0 : 1)
                    .allowsHitTesting(!full)
                    .accessibilityHidden(full)

                // 底部三个大标签
                MainTabBar(onReselect: reselect)
                    .frame(width: size.width, height: tabH)
                    .offset(y: size.height - tabH + (full ? tabH : 0))
                    .opacity(full ? 0 : 1)
                    .allowsHitTesting(!full)
                    .accessibilityHidden(full)

                // 找人全屏
                if full {
                    // 这一层忽略了安全区，FindOverlay 按安全区排版，所以把安全区补回去。
                    FindOverlay()
                        .padding(.top, safe.top)
                        .padding(.bottom, safe.bottom)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity)
                }

                // 底部卡片：暗层 → 咪 → 卡片（咪在暗层之上、卡片之下）
                BottomCardDim(size: size, sceneHeight: sceneH)

                MicButton()
                    .scaleEffect(full ? 0.4 : 1)
                    .opacity(full ? 0 : 1)
                    .allowsHitTesting(!full)
                    .accessibilityHidden(full)
                    .position(micCenter)

                BottomCardSlot(size: size, bottomInset: safe.bottom)

                // 提示：在标签栏之上；找人全屏时放到顶部
                ToastView()
                    .padding(.top, full ? safe.top + 64 : 0)
                    .padding(.bottom, full ? 0 : tabH + 12)
                    .frame(width: size.width, height: size.height, alignment: full ? .top : .bottom)
                    .allowsHitTesting(false)

                // 灵动岛式横幅（最上层）
                BannerView()
                    .frame(width: size.width, height: size.height, alignment: .top)
            }
            .frame(width: size.width, height: size.height)
            .ignoresSafeArea()
            .animation(DS.motion(DS.spring), value: full)
        }
        .fullScreenCover(isPresented: Binding(
            get: { store.bumpStage == .searching },
            set: { shown in if !shown, store.bumpStage == .searching { store.cancelBump() } }
        )) {
            BumpView().environment(store)
        }
        .sheet(isPresented: $store.showReport) {
            ReportView()
                .environment(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $store.showSettings) {
            SettingsView().environment(store)
        }
        .sheet(isPresented: $store.showTimeSlider) {
            TimeSliderSheet()
                .environment(store)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                // 拉时间时仍然看得到上面场景的阴影移动。
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    // MARK: 场景

    private func sceneArea(width: CGFloat, height: CGFloat, safe: EdgeInsets, micCenter: CGPoint, full: Bool) -> some View {
        // 标签不放进状态栏和左右上胶囊那一条，也不压咪。
        var reserved = [CGRect(x: 0, y: 0, width: width, height: safe.top + DS.gap + 44)]
        if !full {
            reserved.append(CGRect(x: micCenter.x - DS.micSize / 2 - 4, y: micCenter.y - DS.micSize / 2 - 4,
                                   width: DS.micSize + 8, height: DS.micSize / 2 + 4))
        }
        return ZStack(alignment: .topLeading) {
            DioramaView(controller: store.scene, onTap: handleSceneTap)
            // 状态栏可读：顶部一层很淡的渐变（浅色白、深色黑）。
            LinearGradient(colors: [Color(.systemBackground).opacity(0.55), Color(.systemBackground).opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: safe.top + 28)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            SceneLabelsLayer(reserved: reserved)
            // 地图署名（OpenStreetMap 协议要求可见）：左下角一行小字。
            Text("© OpenStreetMap")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.leading, DS.side)
                .padding(.bottom, 6)
                .frame(width: width, height: height, alignment: .bottomLeading)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private func handleSceneTap(_ hit: DioramaController.Hit?) {
        guard store.uiSceneTapsEnabled else { return }
        switch hit {
        case .landmark(let id): store.select(.landmark(id))
        case .person(let id): if id != "me" { store.select(.person(id)) }
        case .building: break
        case .none: if store.selection != nil { store.select(nil) }
        }
    }

    private func topChips(width: CGFloat, safeTop: CGFloat) -> some View {
        HStack(alignment: .top, spacing: DS.gap) {
            HomeChip()
            Spacer(minLength: DS.gap)
            if store.demoMode { DemoMenu() }
        }
        .padding(.horizontal, DS.side)
        .padding(.top, safeTop + DS.gap)
        .frame(width: width, alignment: .topLeading)
    }

    // MARK: 内容

    private func contentArea(tab: AppStore.Tab, width: CGFloat, height: CGFloat, tabH: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题行：左对齐，右边让出咪的位置。
            HStack(spacing: 0) {
                Text(tab.title)
                    .ds(.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .id(tab)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DS.micSize + DS.side + DS.gap)
            }
            .padding(.leading, DS.side)
            .padding(.top, 12)
            .padding(.bottom, DS.gap)

            // 只渲染当前页（三页同时靠透明度叠放时，动画叠在一起偶尔会卡在全透明）。切换时淡入 + 轻微横移。
            ZStack(alignment: .top) {
                page(for: tab, tabH: tabH)
                    .id(tab)
                    .transition(DS.reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 24)),
                        removal: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width, height: height, alignment: .top)
        .animation(DS.motion(DS.spring), value: tab)
    }

    private func slideOffset(_ t: AppStore.Tab, distance: CGFloat) -> CGFloat {
        guard !DS.reduceMotion, t != store.tab else { return 0 }
        return t.order > store.tab.order ? distance : -distance
    }

    @ViewBuilder
    private func page(for t: AppStore.Tab, tabH: CGFloat) -> some View {
        switch t {
        case .today: scrollPage(TodayTab(), position: $todayScroll, tabH: tabH)
        case .board: scrollPage(BoardTab(), position: $boardScroll, tabH: tabH)
        case .neighbors: scrollPage(NeighborsTab(), position: $neighborsScroll, tabH: tabH)
        }
    }

    private func scrollPage<Content: View>(_ content: Content, position: Binding<ScrollPosition>, tabH: CGFloat) -> some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, DS.side)
                .padding(.top, DS.gap)
                .padding(.bottom, DS.gap * 3)
        }
        .scrollPosition(position)
        // 用安全区留出标签栏的位置（排行榜"我那行"固定在可见区底部，要停在标签栏之上）。
        // 内容仍可滚到标签栏的材质背景下面。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: tabH).allowsHitTesting(false)
        }
    }

    /// 再点当前标签：内容回到顶部（iOS 惯例）。场景不可操作，镜头不用复位。
    private func reselect(_ t: AppStore.Tab) {
        withAnimation(DS.motion(DS.spring)) {
            switch t {
            case .today: todayScroll.scrollTo(edge: .top)
            case .board: boardScroll.scrollTo(edge: .top)
            case .neighbors: neighborsScroll.scrollTo(edge: .top)
            }
        }
    }
}

// MARK: - 左上胶囊

/// 场景不可操作，所以只在散步中显示状态：「行緊 N 分鐘」（数字滚动）；在家时不显示。
private struct HomeChip: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let m = store.walk?.minutes {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(DS.accent)
                Text("行緊 \(m) 分鐘")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(m)))
            }
            .lineLimit(1)
            .ds(.caption)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
            .animation(DS.motion(DS.snappy), value: m)
            .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("行緊 \(m) 分鐘")
        } else {
            // 在家时：设置（改楼、楼层、小人、提醒时段、演示模式）。
            Button { store.showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("設定")
            .transition(.opacity)
        }
    }
}

// MARK: - 咪

/// 橙色大圆咪：圆心落在场景与内容交界、距右边 16。聆听时显示声波 + 外圈脉冲。
private struct MicButton: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let on = store.listening
        Button { store.micTapped() } label: {
            ZStack {
                if on && !DS.reduceMotion {
                    MicPulse()
                        .transition(.opacity)
                }
                Circle()
                    .fill(DS.accent)
                    .shadow(color: DS.accent.opacity(on ? 0.45 : 0.3), radius: on ? 16 : 10, y: 4)
                Image(systemName: on ? "waveform" : "mic.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.variableColor.iterative.reversing, isActive: on)
            }
            .frame(width: DS.micSize, height: DS.micSize)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 3))
            .contentShape(Circle())
        }
        .buttonStyle(MicPressStyle())
        .animation(DS.motion(DS.snappy), value: on)
        .accessibilityLabel("講嘢")
        .accessibilityValue(on ? "聽緊" : "")
        .accessibilityHint(on ? "再撳一下講完" : "撳一下開始講")
    }
}

/// 聆听时向外扩散的圆环（弹簧、无回弹）。
private struct MicPulse: View {
    var body: some View {
        PhaseAnimator([false, true]) { out in
            Circle()
                .stroke(DS.accent.opacity(0.7), lineWidth: 3)
                .scaleEffect(out ? 1.6 : 1)
                .opacity(out ? 0 : 0.9)
        } animation: { out in
            out ? .spring(duration: 1.25, bounce: 0) : nil
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MicPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(DS.motion(DS.snappy), value: configuration.isPressed)
    }
}

// MARK: - 底部标签栏

private struct MainTabBar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.displayScale) private var displayScale
    var onReselect: (AppStore.Tab) -> Void
    @State private var taps: [AppStore.Tab: Int] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppStore.Tab.ordered, id: \.self) { t in item(t) }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(height: 1 / max(displayScale, 1))
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .sensoryFeedback(.selection, trigger: store.tab)
        .animation(DS.motion(DS.snappy), value: store.tab)
    }

    private func item(_ t: AppStore.Tab) -> some View {
        let selected = store.tab == t
        return Button {
            if store.tab == t { onReselect(t) } else { store.tab = t }
            taps[t, default: 0] += 1
        } label: {
            VStack(spacing: 2) {
                Image(systemName: t.symbol)
                    .symbolVariant(selected ? .fill : .none)
                    .font(.system(size: 24, weight: .medium))
                    .symbolEffect(.bounce, options: .nonRepeating, value: taps[t, default: 0])
                    .frame(height: 28)
                Text(t.title)
                    .ds(selected ? .bodyBold : .body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? DS.accent : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityShowsLargeContentViewer {
            Label(t.title, systemImage: t.symbol)
        }
    }
}

// MARK: - 底部卡片容器

/// 卡片后面的暗层。点暗层 = 关掉（可以关的卡才关）。
/// 暗层一直在，只渐变透明度：以前用插入 / 移除做淡出，偶尔会卡住，留下一层没有卡片的暗色。
private struct BottomCardDim: View {
    @Environment(AppStore.self) private var store
    let size: CGSize
    let sceneHeight: CGFloat
    /// 淡出时保持上一张卡的范围（整屏 / 只盖场景以下）。
    @State private var covers = false

    var body: some View {
        let card = store.uiActiveCard
        let full = card?.coversScene ?? covers
        Color.black
            .opacity(card == nil ? 0 : 0.25)
            .frame(width: size.width, height: full ? size.height : max(0, size.height - sceneHeight))
            .contentShape(Rectangle())
            .onTapGesture { if let card { store.uiDismiss(card) } }
            .allowsHitTesting(card != nil)
            .accessibilityHidden(true)
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .animation(DS.motion(DS.spring), value: card)
            .onChange(of: card) { _, new in if let new { covers = new.coversScene } }
    }
}

/// 卡片本身：顶部圆角 24、系统底色、拉手；从底部弹上来，一次一张。
private struct BottomCardSlot: View {
    @Environment(AppStore.self) private var store
    let size: CGSize
    let bottomInset: CGFloat
    @State private var drag: CGFloat = 0
    /// 每种卡各自量高度（换卡时新旧两张同时在，共用一个值会互相覆盖）。
    @State private var heights: [MainBottomCard: CGFloat] = [:]

    var body: some View {
        let card = store.uiActiveCard
        ZStack(alignment: .bottom) {
            if let card {
                container(card)
                    .id(card)
                    .transition(DS.reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottom)
        .animation(DS.motion(DS.spring), value: card)
    }

    private func container(_ card: MainBottomCard) -> some View {
        let canDismiss = store.uiCanDismiss(card)
        let shape = UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
        let body = content(card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.side)
            .padding(.bottom, max(bottomInset, DS.side) + DS.gap)
        // 大字号时卡片可能高过屏幕：量出内容高度，超过上限才限高、可以上下滚。
        let limit = size.height * 0.86 - 24
        let h = heights[card] ?? 0
        return VStack(spacing: 0) {
            grabber(card, visible: canDismiss)
            ScrollView {
                body.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { heights[card] = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(h <= limit)
            .frame(height: h > 0 ? min(h, limit) : nil)
        }
        .frame(width: size.width)
        .background(Color(.systemBackground), in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.06)))
        .shadow(color: .black.opacity(0.14), radius: 24, y: -4)
        .offset(y: drag)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(card.coversScene ? .isModal : [])
        .accessibilityAction(.escape) { store.uiDismiss(card) }
    }

    @ViewBuilder
    private func grabber(_ card: MainBottomCard, visible: Bool) -> some View {
        if visible {
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                        .onChanged { v in
                            let dy = v.translation.height
                            drag = dy > 0 ? dy : dy / 8   // 向上拉有阻尼
                        }
                        .onEnded { v in
                            if v.translation.height > 90 || v.predictedEndTranslation.height > 240 {
                                store.uiDismiss(card)
                                drag = 0
                            } else {
                                withAnimation(DS.motion(DS.snappy)) { drag = 0 }
                            }
                        }
                )
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: 20)
        }
    }

    @ViewBuilder
    private func content(_ card: MainBottomCard) -> some View {
        switch card {
        case .voice: VoiceOverlay()
        case .remind: RemindPrompt()
        case .proposal: ProposalCard()
        case .findAsk: FindAskCard()
        case .info: InfoCard()
        }
    }
}
