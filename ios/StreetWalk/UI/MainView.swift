import SwiftUI

// MARK: - Prioritized bottom-card slot, one card at a time

/// Card content belongs to its own view; MainView supplies only the container.
enum MainBottomCard: Hashable {
    case voice, incomingFind, remind, proposal, findAsk, info

    /// Voice, incoming finding consent and outing-alert questions dim the whole screen because they need a response first.
    /// Invitation, finding and information cards dim only below the scene so context remains visible.
    var coversScene: Bool { self == .voice || self == .remind || self == .incomingFind }

    /// VoiceOver announces the new card's name first.
    var spokenName: String {
        switch self {
        case .voice: return L.t("語音卡", "语音卡")
        case .incomingFind: return L.t("街坊想過嚟搵你", "邻居想过来找你")
        case .remind: return L.t("出門提醒", "出门提醒")
        case .proposal: return L.t("約人卡", "约人卡")
        case .findAsk: return L.t("搵人卡", "找人卡")
        case .info: return L.t("資料卡", "资料卡")
        }
    }
}

extension AppStore {
    /// Priority: voice, incoming finding request, outing alert, invitation, outgoing finding request, information. Full-screen finding keeps only voice cards.
    /// Show cards only with valid data, avoiding empty handles and dimmed overlays.
    var uiActiveCard: MainBottomCard? {
        if listening || phrasePicker || voiceCard != nil { return .voice }
        if findFullScreen { return nil }
        if let ask = incomingFind, resident(ask.fromID) != nil { return .incomingFind }
        if let id = remindPromptFor, resident(id) != nil { return .remind }
        if let p = proposal, p.options.indices.contains(p.index) { return .proposal }
        if let f = find, resident(f.partnerID) != nil { return .findAsk }
        switch selection {
        case .landmark(let id)?: if landmark(id) != nil { return .info }
        case .person(let id)?: if resident(id) != nil { return .info }
        case nil: break
        }
        return nil
    }

    /// Respond to scene selection only without a higher-priority card, preserving invitation / finding highlights.
    var uiSceneTapsEnabled: Bool {
        guard !findFullScreen else { return false }
        let c = uiActiveCard
        return c == nil || c == .info
    }

    func uiCanDismiss(_ c: MainBottomCard) -> Bool {
        switch c {
        case .voice: return !listening
        case .proposal, .info: return true
        case .remind, .findAsk, .incomingFind: return false
        }
    }

    func uiDismiss(_ c: MainBottomCard) {
        guard uiCanDismiss(c) else { return }
        hush()   // Stop the card's speech when it is dismissed.
        switch c {
        case .voice:
            if voiceCard != nil {
                if voiceCard?.needsConfirm == true { rejectVoice() } else { voiceCard = nil }
            } else {
                phrasePicker = false
            }
        case .proposal: cancelProposal()
        case .info: select(nil)
        case .remind, .findAsk, .incomingFind: break
        }
    }
}

fileprivate extension AppStore.Tab {
    static let ordered: [AppStore.Tab] = [.today, .board, .neighbors]
    var order: Int { Self.ordered.firstIndex(of: self) ?? 0 }
    var title: String {
        switch self {
        case .today: return L.t("今日", "今天")
        case .board: return L.t("排行榜", "排行榜")
        case .neighbors: return L.t("街坊", "邻居")
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

// MARK: - Main screen

/// Top scene extends under the status area; microphone straddles scene/content at right; current tab fills below, with three large bottom tabs.
///
/// A10: derive interface directly from state.
/// GeometryReader computes dimensions only; independent content, scene, capsule and card views read store state in their bodies,
/// ensuring Observation tracks each dependency.
/// Switch tabs immediately without insertion/removal transitions that can retain old content.
/// The root cause was DemoScript.step mutating state off-main; it now uses @MainActor.
struct MainView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            MainLayout(size: CGSize(width: geo.size.width + safe.leading + safe.trailing,
                                    height: geo.size.height + safe.top + safe.bottom),
                       safe: safe)
                .ignoresSafeArea()
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
        // Prompt legacy users for a nickname when leaving demo mode, before joining the real leaderboard.
        .sheet(isPresented: Binding(get: { store.needsNickname && !store.showSettings && store.bumpStage == .idle }, set: { _ in })) {
            NicknameSheet().environment(store)
        }
        .sheet(isPresented: $store.showTimeSlider) {
            TimeSliderSheet()
                .environment(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                // Use an opaque sheet background; iOS 26 glass exposed underlying orange buttons and reduced Done readability.
                .presentationBackground(Color(.systemBackground))
                // Keep scene shadows visible while dragging the time slider.
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }
}

/// MainView passes measured sizes; each layer and child reads its own state.
private struct MainLayout: View {
    @Environment(AppStore.self) private var store
    let size: CGSize
    let safe: EdgeInsets
    @State private var scroll = MainScrolls()
    /// Feedback: drag down / expand enlarges the map to roughly two-thirds height; drag up / collapse restores it.
    @State private var sceneExpanded = UIPreview.is("sceneExpanded")   // Screenshot check: -uiPreview sceneExpanded.

    var body: some View {
        let full = store.findFullScreen
        // UX 6: show the scene only on Today; Leaderboard and Neighbors use full-height content with a narrow Settings strip.
        let band = safe.top + DS.gap + 44 + 8
        let todayH = sceneExpanded ? (size.height * 0.66).rounded() : max(band + 60, (size.height * DS.sceneFraction).rounded())
        let sceneH = full ? size.height : store.tab == .today ? todayH : band
        // Start below the island; scene height clips vertically without independently resizing the model.
        // Model height is screen height times k; feedback increased normal k from 0.42 to 0.45 to fit the full model.
        // Expanded k=0.62 is roughly 1.4x larger, slightly cropping the sides around home.
        let sceneArea = full ? sceneH : sceneH - safe.top
        let viewportScale = full ? Float(1) : Float(sceneArea / (size.height * (sceneExpanded ? 0.62 : 0.45)))
        let showScene = full || store.tab == .today
        let tabH = max(DS.tabBarHeight, safe.bottom + 49)
        let micCenter = CGPoint(x: size.width - DS.side - DS.micSize / 2, y: sceneH)
        let island = IslandGeometry.make(screen: size, safeTop: safe.top, isPhone: UIDevice.current.userInterfaceIdiom == .phone)

        ZStack(alignment: .topLeading) {
            Color(.systemGroupedBackground)

            // Keep content mounted beneath full-screen finding to preserve state.
            MainContent(scroll: $scroll, tabH: tabH)
                .frame(width: size.width, height: max(0, size.height - sceneH), alignment: .top)
                .offset(y: sceneH)
                .opacity(full ? 0 : 1)
                .allowsHitTesting(!full)
                .accessibilityHidden(full)

            // Hide scene and labels outside Today without destroying SceneKit state.
            MainScene(width: size.width, height: sceneH, safe: safe, micCenter: micCenter, full: full, expanded: $sceneExpanded)
                .onChange(of: viewportScale, initial: true) { _, v in store.scene.viewportScale = v }
                .opacity(showScene ? 1 : 0)
                .allowsHitTesting(showScene)
                .accessibilityHidden(!showScene)

            // Top-left / top-right capsules.
            MainTopChips(safeTop: safe.top, hasIsland: island.hasIsland)
                .frame(width: size.width, alignment: .topLeading)
                .opacity(full ? 0 : 1)
                .allowsHitTesting(!full)
                .accessibilityHidden(full)

            // Three large bottom tabs.
            MainTabBar(onReselect: { scroll.toTop($0) })
                .frame(width: size.width, height: tabH)
                .offset(y: size.height - tabH + (full ? tabH : 0))
                .opacity(full ? 0 : 1)
                .allowsHitTesting(!full)
                .accessibilityHidden(full)

            // Full-screen finding positions its own toast below the top card.
            if full {
                // Restore safe-area insets for FindOverlay because this layer ignores them.
                FindOverlay()
                    .padding(.top, safe.top)
                    .padding(.bottom, safe.bottom)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }

            // Bottom layer order: dimming, microphone, card; draw all three from one state read.
            BottomLayer(size: size, sceneHeight: sceneH, micCenter: micCenter, bottomInset: safe.bottom, full: full)

            // Toast above the tab bar, or inside FindOverlay during full-screen finding.
            if !full {
                ToastView()
                    .padding(.bottom, tabH + 12)
                    .frame(width: size.width, height: size.height, alignment: .bottom)
                    .allowsHitTesting(false)
            }

            // -captions subtitles sit below top capsules or the finding card and avoid visible banners.
            CaptionView()
                .padding(.top, safe.top + (full ? 140 : 56))   // Move captions lower to accommodate the finding card's Demo row.
                .frame(width: size.width, height: size.height, alignment: .top)
                .allowsHitTesting(false)

            // Topmost Island layer expands banners and shows active side status afterward.
            IslandLayer(geo: island)
        }
        .frame(width: size.width, height: size.height)
        .animation(DS.motion(DS.spring), value: full)
        .animation(DS.motion(DS.snappy), value: store.tab)
        .animation(DS.motion(DS.spring), value: sceneExpanded)
        .onChange(of: store.tab) { _, _ in sceneExpanded = false }
        .onChange(of: full) { _, _ in sceneExpanded = false }
    }
}

/// Separate scroll position for each tab; tapping the active tab scrolls to top.
private struct MainScrolls {
    var today = ScrollPosition(edge: .top)
    var board = ScrollPosition(edge: .top)
    var neighbors = ScrollPosition(edge: .top)

    mutating func toTop(_ t: AppStore.Tab) {
        withAnimation(DS.motion(DS.spring)) {
            switch t {
            case .today: today.scrollTo(edge: .top)
            case .board: board.scrollTo(edge: .top)
            case .neighbors: neighbors.scrollTo(edge: .top)
            }
        }
    }
}

// MARK: - Scene

private struct MainScene: View {
    @Environment(AppStore.self) private var store
    let width: CGFloat
    let height: CGFloat
    let safe: EdgeInsets
    let micCenter: CGPoint
    let full: Bool
    @Binding var expanded: Bool
    @ScaledMetric(relativeTo: .caption2) private var creditSize: CGFloat = 13

    var body: some View {
        // Keep labels out of the status bar, top capsules and microphone areas.
        var reserved = [CGRect(x: 0, y: 0, width: width, height: safe.top + DS.gap + 44)]
        if !full {
            reserved.append(CGRect(x: micCenter.x - DS.micSize / 2 - 4, y: micCenter.y - DS.micSize / 2 - 4,
                                   width: DS.micSize + 8, height: DS.micSize / 2 + 4))
            reserved.append(CGRect(x: width / 2 - 90, y: height - 48, width: 180, height: 48))   // Map expansion button.
        }
        return ZStack(alignment: .topLeading) {
            DioramaView(controller: store.scene, onTap: handleSceneTap)
                .accessibilityLabel(L.t("你附近嘅立體地圖", "你附近的立体地图"))
                .accessibilityHint(L.t("地標喺「今日」頁嘅「附近地標」都揀得到", "地标在「今天」页的「附近地标」也能选"))
                // Render below the island / status bar to avoid occlusion; full-screen finding still fills the screen.
                .padding(.top, full ? 0 : safe.top)
            // A subtle white / black top gradient preserves status-bar readability.
            LinearGradient(colors: [Color(.systemBackground).opacity(0.55), Color(.systemBackground).opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: safe.top + 28)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            SceneLabelsLayer(reserved: reserved)
            // Visible OpenStreetMap attribution at bottom-left, scaling with Dynamic Type.
            Text("© OpenStreetMap")
                .font(.system(size: creditSize))
                .dynamicTypeSize(...DynamicTypeSize.large)   // Keep large text from covering the model base.
                .foregroundStyle(.secondary)
                .padding(.leading, DS.side)
                .padding(.bottom, 6)
                .frame(width: width, height: height, alignment: .bottomLeading)
                .allowsHitTesting(false)
            if !full { expandHandle }
        }
        .frame(width: width, height: height)
        .background(Color(uiColor: SceneStyle.background))
        .clipped()
        // Drag down to expand and up to collapse; require 30 pt of movement to avoid conflicting with landmark taps.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    guard !full, abs(v.translation.height) > abs(v.translation.width) else { return }
                    if v.translation.height > 40, !expanded { expanded = true; Haptics.select() }
                    else if v.translation.height < -40, expanded { expanded = false; Haptics.select() }
                }
        )
    }

    /// Small bottom-center expand / collapse control makes the map's resizing discoverable.
    private var expandHandle: some View {
        Button {
            expanded.toggle()
            Haptics.select()
        } label: {
            Label(expanded ? L.t("收細地圖", "收小地图") : L.t("睇大啲", "看大一点"),
                  systemImage: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: creditSize + 2, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(.thinMaterial, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .padding(.bottom, 6)
        .frame(width: width, height: height, alignment: .bottom)
        .accessibilityHint(L.t("地圖亦可以向下拉放大", "地图也可以往下拉放大"))
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
}

private struct MainTopChips: View {
    @Environment(AppStore.self) private var store
    let safeTop: CGFloat
    let hasIsland: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.gap) {
            HomeChip(hasIsland: hasIsland)
            // Place Demo at left to reserve top-right for the microphone on tabs without a scene.
            if store.demoMode { DemoMenu() }
            if store.backendOffline { OfflineChip().transition(.opacity) }
            Spacer(minLength: DS.gap)
        }
        .animation(DS.motion(DS.spring), value: store.backendOffline)
        .padding(.horizontal, DS.side)
        .padding(.top, safeTop + DS.gap)
    }
}

// MARK: - Content

/// Read store.tab in this view body and replace the title/page immediately without transitions.
private struct MainContent: View {
    @Environment(AppStore.self) private var store
    @Binding var scroll: MainScrolls
    let tabH: CGFloat

    var body: some View {
        let tab = store.tab
        VStack(alignment: .leading, spacing: 0) {
            // Left-align the title and reserve microphone space at right.
            HStack(spacing: 0) {
                Text(tab.title)
                    .ds(.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DS.micSize + DS.side + DS.gap)
            }
            .padding(.leading, DS.side)
            .padding(.top, 12)
            .padding(.bottom, DS.gap)

            Group {
                switch tab {
                case .today: scrollPage(TodayTab(), position: $scroll.today)
                case .board: scrollPage(BoardTab(), position: $scroll.board) { BoardMyRow() }
                case .neighbors: scrollPage(NeighborsTab(), position: $scroll.neighbors)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Disable tab animation even under an external withAnimation, preventing overlap with the old page.
        .animation(nil, value: tab)
        .task {
            // Screenshot check: Today scrolled to the bottom.
            guard UIPreview.is("todayBottom") else { return }
            try? await Task.sleep(for: .seconds(4))
            scroll.today.scrollTo(edge: .bottom)
        }
    }

    /// bottom is fixed above the tab bar, such as my leaderboard row, and remains visible at every text size.
    private func scrollPage<Content: View, Bottom: View>(_ content: Content, position: Binding<ScrollPosition>,
                                                          @ViewBuilder bottom: () -> Bottom = { EmptyView() }) -> some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, DS.side)
                .padding(.top, DS.gap)
                .padding(.bottom, DS.gap * 3)
        }
        .scrollPosition(position)
        // Reserve tab space through the safe area while allowing content to scroll beneath its material background.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                bottom()
                Color.clear.frame(height: tabH).allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Top-left capsule

/// Show elapsed walking status only during walks, with animated numbers; otherwise omit the status.
/// On island devices, IslandLayer owns walking minutes; retain the Settings gear even during walks.
private struct HomeChip: View {
    @Environment(AppStore.self) private var store
    let hasIsland: Bool

    var body: some View {
        if !hasIsland, let m = store.walk?.minutes {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(DS.accent)
                // At large sizes, show minutes alone instead of truncating the phrase.
                ViewThatFits(in: .horizontal) {
                    Text(L.t("行緊 \(m) 分鐘", "已走 \(m) 分钟"))
                    Text(L.t("\(m) 分鐘", "\(m) 分钟"))
                }
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
            .accessibilityLabel(L.t("行緊 \(m) 分鐘", "已走 \(m) 分钟"))
        } else {
            // At home, show Settings for building, floor, avatar, alert hours and demo mode.
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
            .accessibilityLabel(L.t("設定", "设置"))
            .transition(.opacity)
        }
    }
}

// MARK: - Microphone

/// Large orange microphone centered on the scene/content boundary, inset 16 pt from right; waveform and pulsing ring while listening.
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
        // UX 8: add a non-intercepting text label so older residents understand the orange circle.
        .overlay(alignment: .bottom) {
            Text(on ? (store.conversing ? L.t("傾緊", "对话中") : L.t("聽緊", "在听")) : L.t("講嘢", "说话"))
                .ds(.captionBold)
                .foregroundStyle(DS.accentInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
                .fixedSize()
                .offset(y: 34)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .animation(DS.motion(DS.snappy), value: on)
        .accessibilityLabel(L.t("講嘢", "说话"))
        .accessibilityValue(on ? L.t("聽緊", "在听") : "")
        .accessibilityHint(on ? L.t("再撳一下講完", "再按一下结束") : L.t("撳一下開始講", "按一下开始说"))
    }
}

/// Listening ring expands with a non-bouncing spring.
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

// MARK: - Bottom tabs

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
        // Expose a VoiceOver tab group with ordinal position.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
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
                    // UX 5: show a red badge and count on Neighbors for unanswered invitations or finding requests.
                    .overlay(alignment: .topTrailing) {
                        if t == .neighbors, store.pendingReplies > 0 {
                            Text("\(store.pendingReplies)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 22, minHeight: 22)
                                .background(Color.red, in: Capsule())
                                .offset(x: 14, y: -6)
                                .accessibilityHidden(true)
                        }
                    }
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
        .accessibilityLabel(t == .neighbors && store.pendingReplies > 0
                            ? L.t("\(t.title)，\(store.pendingReplies) 件等你回覆", "\(t.title)，\(store.pendingReplies) 件等你回复") : t.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityShowsLargeContentViewer {
            Label(t.title, systemImage: t.symbol)
        }
    }
}

// MARK: - Bottom-card container

/// Read uiActiveCard once to keep dimming, microphone and card consistent.
private struct BottomLayer: View {
    @Environment(AppStore.self) private var store
    let size: CGSize
    let sceneHeight: CGFloat
    let micCenter: CGPoint
    let bottomInset: CGFloat
    let full: Bool

    var body: some View {
        let card = store.uiActiveCard
        ZStack(alignment: .topLeading) {
            BottomCardDim(card: card, size: size, sceneHeight: sceneHeight)
            MicButton()
                .scaleEffect(full ? 0.4 : 1)
                .opacity(full ? 0 : 1)
                .allowsHitTesting(!full)
                .accessibilityHidden(full)
                .position(micCenter)
            BottomCardSlot(card: card, size: size, bottomInset: bottomInset)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// Backdrop opacity follows card directly; tapping dismisses only dismissible cards.
private struct BottomCardDim: View {
    @Environment(AppStore.self) private var store
    let card: MainBottomCard?
    let size: CGSize
    let sceneHeight: CGFloat

    var body: some View {
        let covers = card?.coversScene ?? false
        Color.black
            .opacity(card == nil ? 0 : 0.25)
            .frame(width: size.width, height: covers ? size.height : max(0, size.height - sceneHeight))
            .contentShape(Rectangle())
            .onTapGesture { if let card { store.uiDismiss(card) } }
            .allowsHitTesting(card != nil)
            .accessibilityHidden(true)
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .animation(DS.motion(DS.spring), value: card)
    }
}

/// One card with 24 pt top corners, system background and handle slides from below.
/// Drive visibility from validated uiActiveCard; keep the slot mounted and animate offset / opacity only.
/// Insertion/removal transitions previously stalled, producing missing banners or blank cards with dimming.
/// Use identity content replacement and animate the whole slot's movement instead.
private struct BottomCardSlot: View {
    @Environment(AppStore.self) private var store
    let card: MainBottomCard?
    let size: CGSize
    let bottomInset: CGFloat
    @State private var drag: CGFloat = 0
    /// Measure each card's height separately because old/new cards can coexist during replacement.
    @State private var heights: [MainBottomCard: CGFloat] = [:]
    /// A43: move VoiceOver focus to the new card's top.
    @AccessibilityFocusState private var focus: MainBottomCard?
    /// Retain the prior card until it has slid offscreen.
    @State private var shown: MainBottomCard?

    var body: some View {
        let visible = card ?? shown
        ZStack(alignment: .bottom) {
            if let visible {
                container(visible)
                    .id(visible)
                    .transition(.identity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottom)
        .offset(y: card == nil && !DS.reduceMotion ? size.height : 0)
        .opacity(card == nil && DS.reduceMotion ? 0 : 1)
        .allowsHitTesting(card != nil)
        .accessibilityHidden(card == nil)
        .animation(DS.motion(DS.spring), value: card)
        .onChange(of: card) { _, new in
            if let new { shown = new; return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                if store.uiActiveCard == nil { shown = nil }
            }
        }
        .task(id: card) {
            drag = 0
            guard let card else { return }
            // Wait until the card arrives before moving focus, avoiding intermediate-position announcements.
            try? await Task.sleep(for: .milliseconds(450))
            if !Task.isCancelled { focus = card }
        }
    }

    private func container(_ card: MainBottomCard) -> some View {
        let canDismiss = store.uiCanDismiss(card)
        let shape = UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
        let body = content(card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.side)
            .padding(.bottom, max(bottomInset, DS.side) + DS.gap)
        // Measure natural height; constrain and enable scrolling only when large text exceeds available space.
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

    /// Dismissible-card handle plus the accessible card name serving as the focus target.
    private func grabber(_ card: MainBottomCard, visible: Bool) -> some View {
        ZStack {
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
                                drag = dy > 0 ? dy : dy / 8   // Apply resistance to upward dragging.
                            }
                            .onEnded { v in
                                if v.translation.height > 90 || v.predictedEndTranslation.height > 240 {
                                    store.uiDismiss(card)
                                } else {
                                    withAnimation(DS.motion(DS.snappy)) { drag = 0 }
                                }
                            }
                    )
            } else {
                Color.clear.frame(height: 20)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(card.spokenName)
        .accessibilityHint(visible ? L.t("用兩隻手指扒「Z」字可以收埋", "用两根手指划「Z」字可以收起") : "")
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($focus, equals: card)
    }

    @ViewBuilder
    private func content(_ card: MainBottomCard) -> some View {
        switch card {
        case .voice: VoiceOverlay()
        case .incomingFind: IncomingFindCard()
        case .remind: RemindPrompt()
        case .proposal: ProposalCard()
        case .findAsk: FindAskCard()
        case .info: InfoCard()
        }
    }
}

// MARK: - Demo captions

/// Chinese and English recording subtitles shown only with -captions.
private struct CaptionView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            if let c = store.caption {
                VStack(spacing: 2) {
                    Text(c.zh).font(.system(size: 19, weight: .semibold))
                    Text(c.en).font(.system(size: 13)).opacity(0.8)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, DS.side)
                .id(c.zh)
                .transition(.opacity.combined(with: .offset(y: 8)))
                .accessibilityHidden(true)
            }
        }
        .opacity(store.banner == nil ? 1 : 0)
        .animation(DS.motion(DS.snappy), value: store.caption?.zh)
    }
}
