import SwiftUI

// MARK: - 底部卡片槽（一次只显示一张，按优先级）

/// 底部卡片槽里显示哪一类卡。卡片内容由各自的视图提供，MainView 只提供容器。
enum MainBottomCard: Hashable {
    case voice, incomingFind, remind, proposal, findAsk, info

    /// 语音、街坊问「方唔方便」、出门提醒是"要先答"的卡，整个屏幕变暗；
    /// 约人、找人、地标/街坊信息要配合场景看，只把场景以下变暗。
    var coversScene: Bool { self == .voice || self == .remind || self == .incomingFind }

    /// 读屏：新卡出现时先读卡名。
    var spokenName: String {
        switch self {
        case .voice: return L.t("語音卡", "语音卡", "Voice card")
        case .incomingFind: return L.t("街坊想過嚟搵你", "邻居想过来找你", "A neighbour wants to come and find you")
        case .remind: return L.t("出門提醒", "出门提醒", "Out-and-about alert")
        case .proposal: return L.t("約人卡", "约人卡", "Walk plan card")
        case .findAsk: return L.t("搵人卡", "找人卡", "Find card")
        case .info: return L.t("資料卡", "资料卡", "Info card")
        }
    }
}

extension AppStore {
    /// 优先级：语音 > 街坊问「方唔方便」> 出门提醒 > 约人提议 > 找人询问 > 信息卡。找人全屏时只保留语音卡。
    /// 卡的数据有效才出卡（否则会出一张只有拉手的空白卡和暗层）。
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
        case .remind, .findAsk, .incomingFind: return false
        }
    }

    func uiDismiss(_ c: MainBottomCard) {
        guard uiCanDismiss(c) else { return }
        hush()   // 用户拉走 / 关咗张卡：卡上嗰句唔好再讲落去
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
        case .today: return L.t("今日", "今天", "Today")
        case .board: return L.t("排行榜", "排行榜", "Leaderboard")
        case .neighbors: return L.t("街坊", "邻居", "Neighbours")
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
///
/// 界面跟状态（审核 A10）：
/// - GeometryReader 闭包里只算尺寸、不读 store；每一块（内容区、场景、胶囊、底部卡）都是独立 View，在自己 body 读状态，
///   Observation 一定追踪得到。
/// - 切标签即时换页（和系统标签栏一样），不做插入 / 移除转场，内容不会停在旧页。
/// - 根因是演示脚本的 step 在后台线程改 store（见 DemoScript），已改为 @MainActor。
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
        // 真后端要网名先上得排行榜：旧用户关咗演示模式、未有网名就补填一次
        .sheet(isPresented: Binding(get: { store.needsNickname && !store.showSettings && store.bumpStage == .idle }, set: { _ in })) {
            NicknameSheet().environment(store)
        }
        .sheet(isPresented: $store.showTimeSlider) {
            TimeSliderSheet()
                .environment(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                // 实色底：iOS 26 半屏默认是玻璃，会透出下面的橙色按钮，「完成」看不清。
                .presentationBackground(Color(.systemBackground))
                // 拉时间时仍然看得到上面场景的阴影移动。
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }
}

/// 主界面各层。尺寸由 MainView 量好传入；状态在这里和各子视图自己读。
private struct MainLayout: View {
    @Environment(AppStore.self) private var store
    let size: CGSize
    let safe: EdgeInsets
    @State private var scroll = MainScrolls()
    /// 测试反馈：向下拉地图以为会放大 → 向下拉 / 撳「睇大啲」放大到约 2/3 屏，向上拉 / 撳「收細」返原位。
    @State private var sceneExpanded = UIPreview.is("sceneExpanded")   // 截图自检：-uiPreview sceneExpanded

    var body: some View {
        let full = store.findFullScreen
        // 场景只喺「今日」页；排行榜、街坊只留顶部一条放设定掣，成页俾内容（UX 报告 6）
        let band = safe.top + DS.gap + 44 + 8
        let todayH = sceneExpanded ? (size.height * 0.66).rounded() : max(band + 60, (size.height * DS.sceneFraction).rounded())
        let sceneH = full ? size.height : store.tab == .today ? todayH : band
        // 模型由灵动岛下面开始画（测试反馈：灵动岛遮住）。模型大细同场景高度无关（高度变只裁上下）；
        // 模型画面高度 ≈ 屏幕高 × k（k 越大模型越大）。以前 k = 0.42；测试反馈话太细 → 平时 0.45（成个模型刚好放得落），
        // 放大时 0.62（再大约 1.4 倍，左右裁少少，以屋企为中心）。
        let sceneArea = full ? sceneH : sceneH - safe.top
        let viewportScale = full ? Float(1) : Float(sceneArea / (size.height * (sceneExpanded ? 0.62 : 0.45)))
        let showScene = full || store.tab == .today
        let tabH = max(DS.tabBarHeight, safe.bottom + 49)
        let micCenter = CGPoint(x: size.width - DS.side - DS.micSize / 2, y: sceneH)
        let island = IslandGeometry.make(screen: size, safeTop: safe.top, isPhone: UIDevice.current.userInterfaceIdiom == .phone)

        ZStack(alignment: .topLeading) {
            Color(.systemGroupedBackground)

            // 内容区（在场景之下；找人全屏时被场景盖住，保留状态不销毁）
            MainContent(scroll: $scroll, tabH: tabH)
                .frame(width: size.width, height: max(0, size.height - sceneH), alignment: .top)
                .offset(y: sceneH)
                .opacity(full ? 0 : 1)
                .allowsHitTesting(!full)
                .accessibilityHidden(full)

            // 场景 + 标签（唔喺「今日」页时收起，但保留 SceneKit 状态唔销毁）
            MainScene(width: size.width, height: sceneH, safe: safe, micCenter: micCenter, full: full, expanded: $sceneExpanded)
                .onChange(of: viewportScale, initial: true) { _, v in store.scene.viewportScale = v }
                .opacity(showScene ? 1 : 0)
                .allowsHitTesting(showScene)
                .accessibilityHidden(!showScene)

            // 左上 / 右上胶囊
            MainTopChips(safeTop: safe.top, hasIsland: island.hasIsland)
                .frame(width: size.width, alignment: .topLeading)
                .opacity(full ? 0 : 1)
                .allowsHitTesting(!full)
                .accessibilityHidden(full)

            // 底部三个大标签
            MainTabBar(onReselect: { scroll.toTop($0) })
                .frame(width: size.width, height: tabH)
                .offset(y: size.height - tabH + (full ? tabH : 0))
                .opacity(full ? 0 : 1)
                .allowsHitTesting(!full)
                .accessibilityHidden(full)

            // 找人全屏（提示框由 FindOverlay 自己放在顶卡下面）
            if full {
                // 这一层忽略了安全区，FindOverlay 按安全区排版，所以把安全区补回去。
                FindOverlay()
                    .padding(.top, safe.top)
                    .padding(.bottom, safe.bottom)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }

            // 底部卡片：暗层 → 咪 → 卡片（咪在暗层之上、卡片之下）。三者由同一个视图按同一个状态画。
            BottomLayer(size: size, sceneHeight: sceneH, micCenter: micCenter, bottomInset: safe.bottom, full: full)

            // 提示：在标签栏之上（找人全屏时由 FindOverlay 显示）
            if !full {
                ToastView()
                    .padding(.bottom, tabH + 12)
                    .frame(width: size.width, height: size.height, alignment: .bottom)
                    .allowsHitTesting(false)
            }

            // 录视频字幕（-captions）：顶部胶囊行之下（找人全屏时在顶卡之下）；横幅出现时让开
            CaptionView()
                .padding(.top, safe.top + (full ? 140 : 56))   // 找人顶卡加咗「示範」一行，字幕要再低啲
                .frame(width: size.width, height: size.height, alignment: .top)
                .allowsHitTesting(false)

            // 灵动岛（最上层）：横幅由岛长出嚟、收埋后两侧显示进行紧嘅事（Island.swift）
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

/// 三页各自的滚动位置（再点当前标签 = 回到顶部）。
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

// MARK: - 场景

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
        // 标签不放进状态栏和左右上胶囊那一条，也不压咪。
        var reserved = [CGRect(x: 0, y: 0, width: width, height: safe.top + DS.gap + 44)]
        if !full {
            reserved.append(CGRect(x: micCenter.x - DS.micSize / 2 - 4, y: micCenter.y - DS.micSize / 2 - 4,
                                   width: DS.micSize + 8, height: DS.micSize / 2 + 4))
            reserved.append(CGRect(x: width / 2 - 90, y: height - 48, width: 180, height: 48))   // 「睇大啲」掣
            if store.mapSource == .fallback { reserved.append(CGRect(x: 0, y: safe.top + DS.gap + 44, width: width, height: 40)) }   // 示例屋邨说明
        }
        return ZStack(alignment: .topLeading) {
            DioramaView(controller: store.scene, onTap: handleSceneTap)
                .accessibilityLabel(L.t("你附近嘅立體地圖", "你附近的立体地图", "3D map of your area"))
                .accessibilityHint(L.t("地標喺「今日」頁嘅「附近地標」都揀得到", "地标在「今天」页的「附近地标」也能选", "You can also pick landmarks under “Nearby landmarks” on the Today page"))
                // 由灵动岛 / 状态栏下面开始画，唔俾灵动岛遮住模型（找人全屏照旧铺满）
                .padding(.top, full ? 0 : safe.top)
            // 状态栏可读：顶部一层很淡的渐变（浅色白、深色黑）。
            LinearGradient(colors: [Color(.systemBackground).opacity(0.55), Color(.systemBackground).opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: safe.top + 28)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            SceneLabelsLayer(reserved: reserved)
            // 地图署名（OpenStreetMap 协议要求可见）：左下角一行小字，跟动态字体放大。
            Text("© OpenStreetMap")
                .font(.system(size: creditSize))
                .dynamicTypeSize(...DynamicTypeSize.large)   // 字大时唔好压到模型底座
                .foregroundStyle(.secondary)
                .padding(.leading, DS.side)
                .padding(.bottom, 6)
                .frame(width: width, height: height, alignment: .bottomLeading)
                .allowsHitTesting(false)
            if !full { expandHandle }
            if store.mapSource == .fallback && !full { sampleBadge }
        }
        .frame(width: width, height: height)
        .background(Color(uiColor: SceneStyle.background))
        .clipped()
        // 向下拉放大、向上拉收细（同其他 App 一样）；同撳地标唔撞（要拉过 30pt 先算）。
        // 双指捏合 / 拖动系郁镜头（DioramaView），啱啱双指郁过就唔当系拉。
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    guard !full, abs(v.translation.height) > abs(v.translation.width),
                          CACurrentMediaTime() - store.scene.lastMultiTouch > 0.5 else { return }
                    if v.translation.height > 40, !expanded { expanded = true; Haptics.select() }
                    else if v.translation.height < -40, expanded { expanded = false; Haptics.select() }
                }
        )
        // 「睇大啲 / 收細」：手指放大、平移都还原
        .onChange(of: expanded) { _, _ in store.scene.resetUserCamera() }
    }

    /// 用紧内置示例屋邨（攞唔到你附近嘅地图）：一直讲明，唔好当系你附近（B-3）。
    private var sampleBadge: some View {
        Label(L.t("示例屋邨（\(store.map?.placeName ?? "皇后山邨")），唔係你附近", "示例屋邨（\(store.map?.placeName ?? "皇后山邨")），不是你家附近", "Sample estate (\(store.map?.placeName ?? "Queen's Hill Estate")), not your area"),
              systemImage: "info.circle")
            .font(.system(size: creditSize, weight: .semibold))
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .lineLimit(2)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .padding(.leading, DS.side)
            .padding(.top, safe.top + DS.gap + 44 + 6)
            .frame(width: width, height: height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityLabel(L.t("而家顯示緊示例屋邨，唔係你附近。可以去設定重新揀樓。", "现在显示的是示例屋邨，不是你家附近。可以到设置里重新选楼。", "This is a sample estate, not your area. You can pick your block again in Settings."))
    }

    /// 底部中间一粒细掣：「向下拉睇大啲」/「收細」，话俾人知幅地图拉得大。
    private var expandHandle: some View {
        Button {
            expanded.toggle()
            Haptics.select()
        } label: {
            Label(expanded ? L.t("收細地圖", "收小地图", "Smaller map") : L.t("睇大啲", "看大一点", "Bigger map"),
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
        .accessibilityHint(L.t("地圖亦可以向下拉放大", "地图也可以往下拉放大", "You can also pull the map down to enlarge it"))
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
            // 「演示」放左边：右上角留俾咪（排行榜、街坊冇场景，咪就喺顶部右边）
            if store.demoMode { DemoMenu() }
            if store.backendOffline { OfflineChip().transition(.opacity) }
            Spacer(minLength: DS.gap)
        }
        .animation(DS.motion(DS.spring), value: store.backendOffline)
        .padding(.horizontal, DS.side)
        .padding(.top, safeTop + DS.gap)
    }
}

// MARK: - 内容

/// 标题行 + 当前页。在自己 body 读 store.tab；换页即时（不做转场）。
private struct MainContent: View {
    @Environment(AppStore.self) private var store
    @Binding var scroll: MainScrolls
    let tabH: CGFloat

    var body: some View {
        let tab = store.tab
        VStack(alignment: .leading, spacing: 0) {
            // 标题行：左对齐，右边让出咪的位置。
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
        // 切标签不要动画（即使外面是 withAnimation）：新页直接出，不会叠住旧页。
        .animation(nil, value: tab)
        .task {
            // 截图自检：今日页滚到底
            guard UIPreview.is("todayBottom") else { return }
            try? await Task.sleep(for: .seconds(4))
            scroll.today.scrollTo(edge: .bottom)
        }
    }

    /// bottom：固定在可见区底部、标签栏之上的一行（排行榜"我那行"），任何字号都看得到。
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
        // 用安全区留出标签栏的位置；内容仍可滚到标签栏的材质背景下面。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                bottom()
                Color.clear.frame(height: tabH).allowsHitTesting(false)
            }
        }
    }
}

// MARK: - 左上胶囊

/// 场景不可操作，所以只在散步中显示状态：「行緊 N 分鐘」（数字滚动）；在家时不显示。
/// 有灵动岛嘅机：散步分钟数喺岛两侧显示（IslandLayer），呢度一直係设置齿轮（散步中都改得设定）。
private struct HomeChip: View {
    @Environment(AppStore.self) private var store
    let hasIsland: Bool

    var body: some View {
        if !hasIsland, let m = store.walk?.minutes {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(DS.accent)
                // 大字号放不下就只出分钟数（不截断成「行緊 3…」）。
                ViewThatFits(in: .horizontal) {
                    Text(L.t("行緊 \(m) 分鐘", "已走 \(m) 分钟", "Walking \(m) min"))
                    Text(L.t("\(m) 分鐘", "\(m) 分钟", "\(m) min"))
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
            .accessibilityLabel(L.t("行緊 \(m) 分鐘", "已走 \(m) 分钟", "Walking \(m) min"))
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
            .accessibilityLabel(L.t("設定", "设置", "Settings"))
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
        // 咪要带字（UX 报告 8）：长者唔知个橙色圆系乜；只系标签，唔阻点按
        .overlay(alignment: .bottom) {
            Text(on ? (store.conversing ? L.t("傾緊", "对话中", "Chatting") : L.t("聽緊", "在听", "Listening")) : L.t("講嘢", "说话", "Speak"))
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
        .accessibilityLabel(L.t("講嘢", "说话", "Speak"))
        .accessibilityValue(on ? L.t("聽緊", "在听", "Listening") : "")
        .accessibilityHint(on ? L.t("再撳一下講完", "再按一下结束", "Tap again when done") : L.t("撳一下開始講", "按一下开始说", "Tap to start speaking"))
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
        // 读屏：当一组标签（「第 1 個，共 3 個」）。
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
                    // 等你回覆（有人约你、街坊想过嚟）：「街坊」标签出红点同数字（UX 报告 5）
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
                            ? L.t("\(t.title)，\(store.pendingReplies) 件等你回覆", "\(t.title)，\(store.pendingReplies) 件等你回复", "\(t.title), \(store.pendingReplies) waiting for your reply") : t.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityShowsLargeContentViewer {
            Label(t.title, systemImage: t.symbol)
        }
    }
}

// MARK: - 底部卡片容器

/// 底部一层：暗层、咪、卡片。只读一次 uiActiveCard，三者一定一致。
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

/// 卡片后面的暗层。点暗层 = 关掉（可以关的卡才关）。透明度直接跟 card，没有其他状态。
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

/// 卡片本身：顶部圆角 24、系统底色、拉手；从底部弹上来，一次一张。
/// 出唔出卡直接跟 card（store.uiActiveCard，已校验数据）。卡槽常驻、只做位移 / 透明度动画：
/// 插入 / 移除转场偶尔会卡住（合并时横幅实测三次有两次冇出；以前亦试过暗层 + 空白卡留喺度），
/// 所以内容换卡时用 .identity（即刻换、冇转场状态），滑上滑落靠整个卡槽嘅位移。
private struct BottomCardSlot: View {
    @Environment(AppStore.self) private var store
    let card: MainBottomCard?
    let size: CGSize
    let bottomInset: CGFloat
    @State private var drag: CGFloat = 0
    /// 每种卡各自量高度（换卡时新旧两张同时在，共用一个值会互相覆盖）。
    @State private var heights: [MainBottomCard: CGFloat] = [:]
    /// 新卡出现时读屏焦点跳到卡顶（审核 A43）。
    @AccessibilityFocusState private var focus: MainBottomCard?
    /// 滑走途中仍然画住上一张卡（滑出屏幕后先清走）。
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
            // 等卡滑上来再移焦点，否则读屏会读到半路的位置。
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

    /// 拉手（可以关的卡才有）+ 读屏用的卡名（焦点落在这里）。
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
                                drag = dy > 0 ? dy : dy / 8   // 向上拉有阻尼
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
        .accessibilityHint(visible ? L.t("用兩隻手指扒「Z」字可以收埋", "用两根手指划「Z」字可以收起", "Draw a “Z” with two fingers to close") : "")
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

// MARK: - 演示字幕

/// 录演示视频时的字幕（中文一句 + 英文一句）。只在启动参数 -captions 时出现。
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
