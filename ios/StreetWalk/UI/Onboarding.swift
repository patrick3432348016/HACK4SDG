import SwiftUI

/// 首次使用 5 步（UX 报告第五节）：① 欢迎（讲用途）② 私隐三句 ③ 屋企（定位 → 估你住边座）④ 樓層同網名 ⑤ 試一次撳咪。
/// 每步屏幕最多两句话、大字；每步出现时只讲一句（≤ 8 秒），换步先停上一句（onbHush）。
/// 设定「改我住嘅樓」都用呢个流程，但只行 ③④。顶部「第几步，共几步」固定，内容按方向滑入淡出。
struct OnboardingFlow: View {
    @Environment(AppStore.self) private var store
    /// 往回走时新内容从左边进来。
    @State private var back = false
    /// 「我識用，跳過介紹」：唔使「試一次」，樓層同網名之后直接入主画面。
    @State private var skipIntro = false
    /// 选楼：撳咗「唔係，我揀」（或者估唔到）→ 全部住宅楼亮橙色，自己撳。
    @State private var pickManual = false

    private var step: AppStore.Step {
        if case .onboarding(let s) = store.phase { return s }
        return .tryMic
    }

    var body: some View {
        let s = step
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if s == .locate || s == .pickHome {
                DioramaView(controller: store.scene, onTap: sceneTapped)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityLabel(L.t("你附近嘅立體地圖", "你附近的立体地图", "3D map of your area"))
                    .accessibilityHint(L.t("用下面「用清單揀」都揀得到你住嗰座樓", "用下面「用清单选」也能选到你住的那栋楼", "You can also choose your block with \"Choose from list\" below"))
            }

            stepContent(s)
                .id(s)
                .transition(stepTransition)

            // 其他步骤的提示（例如地图说明）：放在进度点下面，不压住它；选楼页自己在说明卡下面显示。
            if s != .pickHome {
                ToastView()
                    .padding(.top, 8)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar(s) }
        .animation(DS.motion(DS.spring), value: s)
    }

    // MARK: 导航

    private var stepTransition: AnyTransition {
        if DS.reduceMotion { return .opacity }
        return .asymmetric(insertion: .offset(x: back ? -48 : 48).combined(with: .opacity),
                           removal: .opacity)
    }

    /// 换步：先停上一步讲紧嘅（新一步出现时自己讲一句）。
    private func go(back b: Bool = false, _ action: () -> Void) {
        back = b
        store.onbHush()
        action()
    }

    private func goBack(from s: AppStore.Step) {
        go(back: true) {
            switch s {
            case .consent: store.phase = .onboarding(.welcome)
            case .floor: store.backToPickHome()
            case .tryMic: store.phase = .onboarding(.floor)
            default: break
            }
        }
    }

    private func sceneTapped(_ hit: DioramaController.Hit?) {
        guard store.phase == .onboarding(.pickHome) else { return }
        guard case .building(let id)? = hit, store.isHomeCandidate(id) else {
            // 点空了、点中唔係住宅楼：转去自己揀（全部住宅楼亮橙色），讲点样揀。
            if !pickManual { pickManual = true; store.pickHomeManually() }
            store.toast(L.t("撳一座橙色嘅樓，或者用下面嘅清單揀", "点一栋橙色的楼，或者用下面的清单选", "Tap an orange block, or choose from the list below"))
            return
        }
        store.pickHome(id)
    }

    @ViewBuilder private func stepContent(_ s: AppStore.Step) -> some View {
        switch s {
        case .welcome:
            OnbWelcomeStep(onStart: { go { store.phase = .onboarding(.consent) } },
                           onSkip: { skipIntro = true; go { store.phase = .onboarding(.consent) } })
        case .consent: OnbConsentStep(onNext: { go { store.consent() } })
        case .locate: OnbLocateStep()
        case .pickHome: OnbPickHomeStep(manual: $pickManual, onNext: { go { store.confirmHome() } })
        case .floor:
            OnbFloorNameStep(onNext: {
                go {
                    // 改楼、或者话识用：唔使「試一次」
                    if store.changingHome || skipIntro { store.finishOnboarding() } else { store.phase = .onboarding(.tryMic) }
                }
            })
        case .tryMic: OnbTryMicStep(listener: store.listener, onDone: { go { store.finishOnboarding() } })
        }
    }

    /// 进度点：而家行紧边几步（改楼得 2 步；跳过介绍得 3 步）。
    private var stages: [[AppStore.Step]] {
        if store.changingHome { return [[.locate, .pickHome], [.floor]] }
        var f: [[AppStore.Step]] = [[.consent], [.locate, .pickHome], [.floor]]
        if !skipIntro { f.insert([.welcome], at: 0); f.append([.tryMic]) }
        return f
    }

    private func topBar(_ s: AppStore.Step) -> some View {
        let canGoBack = (s == .consent && !skipIntro) || s == .floor || s == .tryMic
        let onScene = s == .locate || s == .pickHome
        let st = stages
        return HStack {
            ZStack {
                if canGoBack {
                    Button { goBack(from: s) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 48, height: 48)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(OnbPressStyle())
                    .accessibilityLabel(L.t("返上一步", "返回上一步", "Back"))
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .frame(width: 48, height: 48)
            Spacer()
            OnbProgressDots(current: st.firstIndex { $0.contains(s) } ?? 0, total: st.count)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    if onScene { Capsule().fill(.regularMaterial) }
                }
            Spacer()
            if store.changingHome {
                // 改楼途中可以退返出去（A80）
                topPill(L.t("唔改", "不改", "Don't change"), a11y: L.t("唔改，返主畫面", "不改，回主画面", "Don't change, back to main screen")) { store.onbHush(); store.cancelChangeHome() }
            } else if s == .tryMic {
                topPill(L.t("跳過", "跳过", "Skip"), a11y: L.t("跳過，入主畫面", "跳过，进入主画面", "Skip, go to main screen")) { go { store.finishOnboarding() } }
            } else {
                Color.clear.frame(width: 48, height: 48)
            }
        }
        .padding(.horizontal, DS.side)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func topPill(_ title: String, a11y: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ds(.captionBold).foregroundStyle(.primary)
                .padding(.horizontal, 14).frame(minHeight: 48)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(OnbPressStyle())
        .accessibilityLabel(a11y)
    }
}

// MARK: - 讲嘢：换步先停

extension AppStore {
    /// 引导换步：停掉上一步讲紧、排紧嘅句子（换 phase 时 AppStore 已经自动 hush；同一步入面换画面靠呢个）。聆听中唔郁。
    func onbHush() {
        guard !listening else { return }
        hush()
    }

    /// 每步出现时讲嘅一句（≤ 8 秒）：先停上一句再讲，唔会排喺旧句后面。
    func onbSay(_ s: String) {
        onbHush()
        say(s)
    }
}

// MARK: - 进度（文字）

/// 「第 1 步，共 5 步」：测试反馈 A-1，以前一排小圆点似翻页点，长者以为可以左右扫；改成直接讲第几步。
private struct OnbProgressDots: View {
    var current: Int
    var total: Int

    var body: some View {
        Text(L.t("第 \(current + 1) 步，共 \(total) 步", "第 \(current + 1) 步，共 \(total) 步", "Step \(current + 1) of \(total)"))
            .ds(.captionBold)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
            .animation(DS.motion(DS.spring), value: current)
            .animation(DS.motion(DS.spring), value: total)
    }
}

/// 按下微缩回弹（无底色的按钮用）。
private struct OnbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(DS.motion(DS.snappy), value: configuration.isPressed)
    }
}

/// 底部大按钮（固定在安全区上方）。
private struct OnbBottomPrimary: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsPrimary)
        .padding(.horizontal, DS.side)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground).opacity(0.94))
    }
}

/// 圆形大图标（底色淡橙）+ 右上角小徽章：欢迎页、私隐、试一次共用。
private struct OnbBadgeIcon: View {
    var symbol: String
    var badge: String?
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle().fill(DS.accentSoft).frame(width: size, height: size)
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(DS.accent)
            if let badge {
                Image(systemName: badge)
                    .font(.system(size: size * 0.17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.4, height: size * 0.4)
                    .background(DS.accent, in: Circle())
                    .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 3))
                    .offset(x: size * 0.34, y: -size * 0.32)
            }
        }
        .frame(width: size + 16, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 1 欢迎：讲用途

private struct OnbWelcomeStep: View {
    @Environment(AppStore.self) private var store
    var onStart: () -> Void
    var onSkip: () -> Void
    @State private var appeared = false

    static var spoken: String { L.t("街坊行幫你記錄每日散步，約隔籬街坊一齊行；上面幅地圖幫你哋搵到對方。", "街坊行帮你记录每天散步，约隔壁邻居一起走；上面的地图帮你们找到对方。", "Kaifong Walk records your daily walks and helps you walk with neighbours. The map at the top helps you find each other.") }

    /// 测试反馈：做成卡片似可以撳嘅掣 → 改成普通介绍列表（细图标、冇卡片底、多一行解释），一眼睇得出系「介绍」唔系「功能入口」。
    /// 10-18 测试反馈：「今日」页第一次唔知有咩、散步时报「冇櫈 / 好曬」好似盲盒 → 每条写短，加「今日」页有咩同报地标两条。
    private var features: [(symbol: String, text: String, detail: String)] { [
        ("figure.walk", L.t("自動記錄散步", "自动记录散步", "Records walks for you"),
         L.t("出門行就會記，唔使撳嘢。", "出门走路就会记，不用点。", "Just go out and walk.")),
        ("person.2.fill", L.t("碰一碰做街坊", "碰一碰成为邻居", "Tap phones to add a neighbour"),
         L.t("見面時兩部手機並排擺，隔一個拳頭。", "见面时两台手机并排放，隔一个拳头。", "When you meet, hold the phones side by side, a fist apart.")),
        ("map.fill", L.t("「今日」頁有咩", "「今天」页有什么", "What's on the Today tab"),
         L.t("今日三件事、附近地圖、右邊橙色講嘢掣。", "今天三件事、附近地图、右边橙色说话按钮。", "3 things to do, a map nearby, the orange talk button.")),
        ("mic.fill", L.t("講一句就約到人", "说一句就能约人", "Say one line to invite"),
         L.t("撳橙色個咪，講「約佢聽日行」。", "点橙色麦克风，说「约他明天一起走」。", "Tap the orange mic and say \"Walk with her tomorrow\".")),
        ("chair.fill", L.t("幫街坊記低邊度冇櫈、好曬", "帮邻居记下哪里没凳子、太晒", "Note no-seat and sunny spots"),
         L.t("散步時講「呢度冇櫈」「呢度好曬」，會記喺地圖上。", "散步时说「这里没有凳子」「这里太晒」，会记在地图上。", "While walking, say \"No seats here\" or \"Too sunny here\". It goes on the map.")),
    ] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 语言：放最顶，长者一眼见到；三种语言自己嘅写法，撳一下成页即时转、读返一次欢迎
                VStack(alignment: .leading, spacing: 8) {
                    Label("語言 · 语言 · Language", systemImage: "globe")
                        .ds(.captionBold)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    LanguageChooser(short: true) { store.onbSay(Self.spoken) }
                }
                Text(L.t("歡迎嚟到街坊行", "欢迎来到街坊行", "Welcome to Kaifong Walk"))
                    .ds(.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(L.t("街坊行可以幫你：", "街坊行可以帮你：", "Kaifong Walk can help you:"))
                    .ds(.body)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(features.enumerated()), id: \.offset) { i, f in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: f.symbol)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(DS.accent)
                                .frame(width: 32, height: 32)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(f.text).ds(.bodyBold)
                                Text(f.detail).ds(.caption).foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared || DS.reduceMotion ? 0 : 16)
                        .animation(DS.motion(DS.spring).delay(0.1 + Double(i) * 0.12), value: appeared)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, DS.side)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Button(action: onStart) {
                    Text(L.t("開始", "开始", "Start")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
                // 后生啲、识用嘅人：跳过介绍同「試一次」
                Button(action: onSkip) {
                    Text(L.t("我識用，跳過介紹", "我会用，跳过介绍", "I know how. Skip intro"))
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .underline()
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.side)
            .padding(.top, 8)
            .background(Color(.systemGroupedBackground).opacity(0.94))
        }
        .onAppear {
            appeared = true
            store.onbSay(Self.spoken)
        }
    }
}

// MARK: - 2 私隐：三句，「詳細」展开原来 5 段

/// 「谁能看到什么」：按受众逐行讲（规格 §4 知情同意）。设置页「私隱說明」也可以用 PrivacyRows 重看；首次使用喺「詳細」入面。
struct PrivacyRows: View {
    static var rows: [(symbol: String, text: String)] { [
        ("figure.walk", L.t("你行街嘅時候自動記錄，唔使撳掣；定位揀「始終允許」，鎖咗機出門都會記。行過嘅路線同屋企位置只留喺你部手機。", "你散步时自动记录，不用按按钮；定位选「始终允许」，锁屏出门也会记。走过的路线和家的位置只留在你的手机里。", "Walks are recorded when you go out, no buttons. Choose \"Always Allow\" for location and it records even when the phone is locked. Your routes and home location stay on your phone.")),
        ("building.2", L.t("同區嘅人（未加做街坊）：只見到你嘅網名、小人同連續日數；唔會見到你住邊座、幾樓。", "附近还没加为邻居的人：只看到你的网名、卡通小人和连续天数，看不到你住哪栋、几楼。", "People nearby you have not added: they only see your nickname, figure and streak. Not your block or floor.")),
        ("person.2.fill", L.t("用碰一碰加咗嘅街坊：仲會見到你住邊座幾樓、今日一句，同埋你出門時喺邊個地標附近。對外只講地標，唔顯示地圖坐標。", "用碰一碰加过的邻居：还能看到你住哪栋、几楼，今天走过哪些地方，还有你出门时正在哪个地标附近。对外只说地标，不显示地图坐标。", "Neighbours added by tapping phones: they also see your block and floor, your line for today, and which landmark you are near when you are out. Others only see landmarks, never map coordinates.")),
        ("doc.text.magnifyingglass", L.t("你嘅反映會匿名，夠 10 人先交俾社工同屋邨管理。", "你对地点的反馈是匿名的，同一个地方有 10 个人反馈了，才会交给社工和屋邨管理处。", "Your reports about places are anonymous. Only when 10 people report the same place is it passed to social workers and estate management.")),
        ("network", L.t("地圖資料向 OpenStreetMap 攞你附近一格；講嘢可能要經 Apple 辨認。", "地图数据来自 OpenStreetMap，只下载你家附近一格；说话时可能要经过苹果的语音识别。", "Map data comes from OpenStreetMap, only the area near your home. When you speak, Apple may help recognise your voice.")),
    ] }
    /// 读出来的一段（和上面几行内容一致；设定页「讀出嚟」用）。
    static var spoken: String { L.t("你行街會自動記錄，定位揀始終允許，鎖咗機出門都會記，路線同屋企位置只留喺你部手機。同區嘅人只見到你嘅網名、小人同連續日數，唔見到你住邊座幾樓。用碰一碰加咗嘅街坊先見到你住邊座幾樓、今日一句，同你出門時喺邊個地標附近。反映會匿名，夠十個人先交俾社工同屋邨管理。", "你散步会自动记录，定位选始终允许，锁屏出门也会记，路线和家的位置只留在你的手机里。附近的人只看到你的网名、卡通小人和连续天数，看不到你住哪栋、几楼。用碰一碰加过的邻居，才能看到你住哪栋几楼、今天走过哪些地方，和你出门时在哪个地标附近。地点反馈是匿名的，同一个地方有十个人反馈了，才会交给社工和屋邨管理处。", "Walks are recorded when you go out. Choose Always Allow for location and it records even when the phone is locked. Your routes and home location stay on your phone. People nearby only see your nickname, figure and streak, not your block or floor. Only neighbours added by tapping phones see your block, floor, your line for today, and which landmark you are near when out. Reports are anonymous. Only when 10 people report the same place is it passed to social workers and estate management.") }

    var appeared = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { i, row in
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DS.accent)
                        .frame(width: 48, height: 48)
                        .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)
                    Text(row.text)
                        .ds(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || DS.reduceMotion ? 0 : 16)
                .animation(DS.motion(DS.spring).delay(0.12 + Double(i) * 0.08), value: appeared)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct OnbConsentStep: View {
    @Environment(AppStore.self) private var store
    var onNext: () -> Void
    @State private var appeared = false
    @State private var showDetail = UIPreview.is("privacyDetail")
    /// 选了「唔同意」：不记录、不进圈，讲清楚之后怎么办。
    @State private var declined = UIPreview.is("declined")

    /// 三句话（UX 报告第五节）；「詳細」入面先係原来 5 段。
    private var points: [(symbol: String, text: String)] { [
        ("lock.fill", L.t("行過嘅路只留喺你部手機。", "走过的路只留在你的手机里。", "Where you walk stays on your phone.")),
        ("eye.slash.fill", L.t("唔識你嘅人，只見到你個網名。", "不认识你的人，只看到你的网名。", "People who don't know you only see your nickname.")),
        ("person.2.fill", L.t("用碰一碰加咗嘅街坊，先知你住邊座。", "用碰一碰加过的邻居，才知道你住哪栋。", "Only neighbours added by tapping phones know your block.")),
    ] }

    static var spoken: String { L.t("你行過嘅路只留喺手機。用碰一碰加咗嘅街坊先知你住邊座。", "你走过的路只留在手机里。用碰一碰加过的邻居，才知道你住哪栋。", "Where you walk stays on your phone. Only neighbours added by tapping phones know your block.") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L.t("你嘅私隱", "你的隐私", "Your privacy"))
                    .ds(.title)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .center, spacing: 16) {
                            Image(systemName: p.symbol)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(DS.accent)
                                .frame(width: 56, height: 56)
                                .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .accessibilityHidden(true)
                            Text(p.text)
                                .ds(.bodyBold)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared || DS.reduceMotion ? 0 : 16)
                        .animation(DS.motion(DS.spring).delay(0.1 + Double(i) * 0.1), value: appeared)
                        .accessibilityElement(children: .combine)
                    }
                }

                // 「詳細」：原来 5 段（谁见到乜、反映、地图同语音资料去边）
                Button {
                    withAnimation(DS.motion(DS.spring)) { showDetail.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Text(L.t("詳細", "详细", "Details")).ds(.bodyBold)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .rotationEffect(.degrees(showDetail ? 180 : 0))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(DS.accentInk)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showDetail ? L.t("已展開", "已展开", "Open") : L.t("已收起", "已收起", "Closed"))

                if showDetail {
                    PrivacyRows()
                        .dsCard()
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, DS.side)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if declined { declinedNote.transition(DS.slide(.bottom)) }
                // 「唔同意」和「同意」并排（同复述卡「唔係 / 好」）；大字号放不下就上下排。
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { consentButtons(stacked: false) }
                    VStack(spacing: 8) { consentButtons(stacked: true) }
                }
                .padding(.horizontal, DS.side)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .top) { Divider() }
        }
        .onAppear {
            appeared = true
            store.onbSay(Self.spoken)
        }
    }

    @ViewBuilder private func consentButtons(stacked: Bool) -> some View {
        if !declined {
            Button { withAnimation(DS.motion(DS.spring)) { declined = true } } label: {
                Text(L.t("唔同意", "不同意", "No thanks")).frame(maxWidth: stacked ? .infinity : nil)
            }
            .buttonStyle(.dsSecondary)
        }
        Button(action: onNext) {
            Text(declined ? L.t("我諗清楚，同意", "我想清楚了，同意", "OK, I agree") : L.t("同意", "同意", "Agree")).frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsPrimary)
    }

    /// 不同意：什么都不记录、不进圈；想用时回来按「同意」。
    private var declinedNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(L.t("冇問題，乜都唔會記錄。想用嘅時候返嚟撳「同意」就得。", "没问题，什么都不会记录。想用的时候回来点「同意」就行。", "No problem. Nothing will be recorded. Come back and tap \"Agree\" when you want to use it."))
                .ds(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .padding(.horizontal, DS.side)
        .accessibilityElement(children: .combine)
        .onAppear { store.onbSay(L.t("冇問題，乜都唔會記錄。想用嘅時候返嚟撳同意就得。", "没问题，什么都不会记录。想用的时候回来点同意就行。", "No problem. Nothing will be recorded. Come back and tap Agree when you want to use it.")) }
    }
}

// MARK: - 3a 屋企：先讲点解要定位，再弹系统框；之后等地图

private struct OnbLocateStep: View {
    @Environment(AppStore.self) private var store
    /// 撳咗「好」（系统定位框弹紧 / 等紧位置）。
    @State private var asked = false
    /// 等咗 10 秒仲未有地图：讲明等紧网络，俾个「用示例屋邨」出路（A28；地图最多等 30 秒、定位最多 120 秒）。
    @State private var waitedLong = false

    /// 未问过定位、仲未开始搵：先解释（consent 冇自动开始，见 AppStore+Map.consent）。
    private var needsAsk: Bool { !asked && !store.loadingMap && store.mapService.locationUndetermined }

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            if needsAsk {
                askCard.transition(DS.slide(.bottom))
            } else {
                if waitedLong && !store.changingHome && (store.loadingMap || store.map == nil) {
                    slowCard.transition(.opacity)
                }
                loadingCard.transition(.opacity)
            }
        }
        .padding(.horizontal, DS.side)
        .padding(.bottom, 16)
        .animation(DS.motion(DS.spring), value: waitedLong)
        .animation(DS.motion(DS.spring), value: needsAsk)
        .onAppear {
            if needsAsk { store.onbSay(L.t("要知道你喺邊，先搵到你住嗰座樓。", "要知道你在哪里，才能找到你住的那栋楼。", "I need your location to find your block.")) }
        }
        .task(id: needsAsk) {
            guard !needsAsk else { return }
            try? await Task.sleep(for: .seconds(10))
            waitedLong = true
        }
    }

    /// 一句解释 + 「好」：撳咗先弹系统定位框（使用 App 期間）。
    private var askCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                OnbBadgeIcon(symbol: "house.fill", badge: "location.fill", size: 72)
                Text(L.t("你住邊座？", "你住哪栋？", "Which block do you live in?"))
                    .ds(.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            Text(L.t("撳「好」，再揀「使用 App 時允許」，我就搵到你附近嘅樓。", "点「好」，再选「使用 App 时允许」，我就能找到你附近的楼。", "Tap \"OK\", then choose \"Allow While Using App\". Then I can find the blocks near you."))
                .ds(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                asked = true
                store.onbHush()
                store.startLocating()
            } label: {
                Text(L.t("好", "好", "OK")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
    }

    private var loadingCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "location.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(DS.accent)
                .symbolEffect(.pulse)
                .frame(width: 52, height: 52)
                .background(DS.accentSoft, in: Circle())
            Text(L.t("搵緊你附近嘅樓…", "正在找你附近的楼…", "Finding blocks near you…"))
                .ds(.bodyBold)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if store.loadingMap || store.map == nil {
                ProgressView()
                    .controlSize(.large)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var slowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("網絡慢，仲搵緊。可以再等等，或者先用示例屋邨睇吓。", "网络慢，还在找。可以再等等，或者先用示例屋邨看看。", "The network is slow. Still looking. Wait a bit, or try the sample estate first."))
                .ds(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L.t("用示例屋邨", "用示例屋邨", "Use sample estate")) { store.useSampleMap() }
                .buttonStyle(.dsSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
    }
}

// MARK: - 3b 屋企：「你係咪住XX樓？」唔係先自己揀

private struct OnbPickHomeStep: View {
    @Environment(AppStore.self) private var store
    @Binding var manual: Bool
    var onNext: () -> Void
    @State private var showList = UIPreview.is("buildingList")

    private func name(_ id: Int64) -> String? { store.map?.building(id: id)?.shownName }

    var body: some View {
        VStack(spacing: 8) {
            if manual { instruction.transition(DS.slide(.top)) }
            // 冇估到点解（示例屋邨、唔喺屋企）已经一直写喺说明卡，提示唔使再叠一次
            if let t = store.toast, !(manual && t == store.mapNotice) {
                Label(t, systemImage: "exclamationmark.circle.fill")
                    .ds(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .transition(DS.slide(.top))
            }
            Spacer(minLength: 0)
            attribution
            if let id = store.pendingHome {
                Group {
                    if manual { confirmCard(id) } else { guessCard(id) }
                }
                .transition(DS.slide(.bottom))
            } else {
                // 3D 里的楼很小、读屏也点不到：用清单也能选。
                Button { showList = true } label: {
                    Label(L.t("揀唔到？用清單揀", "选不到？用清单选", "Can't tap it? Choose from list"), systemImage: "list.bullet").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsSecondary)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.side)
        .padding(.bottom, 8)
        .animation(DS.motion(DS.spring), value: store.pendingHome)
        .animation(DS.motion(DS.spring), value: manual)
        .animation(DS.motion(DS.snappy), value: store.toast)
        .onAppear {
            // 估唔到（冇定位、示例屋邨、附近冇住宅楼）就直接自己揀
            manual = store.pendingHome == nil
            speak()
        }
        .onChange(of: store.pendingHome) { _, id in
            if id != nil { speak() }
        }
        .sheet(isPresented: $showList) {
            OnbBuildingList { id in
                showList = false
                manual = true
                store.pickHome(id)
            }
            .environment(store)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func speak() {
        if let id = store.pendingHome {
            let n = name(id) ?? L.t("呢座樓", "这栋楼", "this block")
            store.onbSay(manual ? L.t("\(n)。啱就撳「就係呢座」。", "\(n)。对就点「就是这栋」。", "\(n). If right, tap \"This one\".") : L.t("你係咪住\(n)？", "你是不是住在\(n)？", "Do you live in \(n)?"))
        } else {
            store.onbSay(L.t("撳一下你住嗰座橙色嘅樓。", "点一下你住的那栋橙色的楼。", "Tap the orange block you live in."))
        }
    }

    private var instruction: some View {
        HStack(spacing: 16) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(DS.accent)
                .symbolEffect(.breathe, isActive: !DS.reduceMotion)
                .frame(width: 52, height: 52)
                .background(DS.accentSoft, in: Circle())
            // 揀咗之后提示跟住变（以前一直写「撳一下」，唔知揀咗未）
            VStack(alignment: .leading, spacing: 4) {
                if store.pendingHome == nil {
                    Text(L.t("撳一下你住嗰座樓", "点一下你住的那栋楼", "Tap the block you live in")).ds(.bodyBold)
                    Text(L.t("橙色嘅係住宅樓", "橙色的是住宅楼", "Orange ones are homes")).ds(.caption).foregroundStyle(.secondary)
                    // 点解冇幫你估（攞唔到位置 / 地图、唔喺屋企）：一直显示，唔好一闪就冇（A-2）
                    if let n = store.mapNotice {
                        Text(n).ds(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(L.t("唔係呢座？撳第二座就得", "不是这栋？点另一栋就行", "Not this one? Tap another")).ds(.bodyBold)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// 地图资料来源（OpenStreetMap 授权要求注明）；唔再显示「快取 / 即時」呢类技术字眼。
    private var attribution: some View {
        Text("©\u{00A0}OpenStreetMap")
            .ds(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buildingIcon(_ id: Int64) -> some View {
        Image(systemName: "house.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(DS.accent)
            .symbolEffect(.bounce, value: id)
            .frame(width: 52, height: 52)
            .background(DS.accentSoft, in: Circle())
            .accessibilityHidden(true)
    }

    private func detail(_ b: Building?) -> String? {
        guard let b else { return nil }
        let d = b.centroid.length       // 选楼画面以你个位置为原点
        let far = d < 30 ? L.t("就喺你度", "就在你这里", "Right where you are") : L.t("離你大約 \(OnbBuildingList.meters(d))", "离你大约 \(OnbBuildingList.meters(d))", "About \(OnbBuildingList.meters(d)) away")
        return L.t("\(b.levels) 層 · \(far)", "\(b.levels) 层 · \(far)", "\(b.levels) floors · \(far)")
    }

    /// 估中嘅楼：「你係咪住XX樓？」[唔係，我揀] [係]
    private func guessCard(_ id: Int64) -> some View {
        let b = store.map?.building(id: id)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                buildingIcon(id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("你係咪住\(b?.shownName ?? "呢座樓")？", "你是不是住在\(b?.shownName ?? "这栋楼")？", "Do you live in \(b?.shownName ?? "this block")?"))
                        .ds(.bodyBold)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.interpolate)
                    if let d = detail(b) { Text(d).ds(.caption).foregroundStyle(.secondary) }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { guessButtons(stacked: false) }
                VStack(spacing: 8) { guessButtons(stacked: true) }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
    }

    @ViewBuilder private func guessButtons(stacked: Bool) -> some View {
        Button {
            manual = true
            store.pickHomeManually()
            store.onbSay(L.t("撳一下你住嗰座橙色嘅樓。", "点一下你住的那栋橙色的楼。", "Tap the orange block you live in."))
        } label: {
            Text(L.t("唔係，我揀", "不是，我来选", "No, I'll choose")).frame(maxWidth: stacked ? .infinity : nil)
        }
        .buttonStyle(.dsSecondary)
        Button(action: onNext) {
            Text(L.t("係", "是", "Yes")).frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsPrimary)
    }

    /// 自己揀咗：显示名同层数，「就係呢座」。
    private func confirmCard(_ id: Int64) -> some View {
        let b = store.map?.building(id: id)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                buildingIcon(id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(b?.shownName ?? L.t("你揀咗呢座樓", "你选了这栋楼", "You chose this block"))
                        .ds(.bodyBold)
                        .contentTransition(.interpolate)
                    if let levels = b?.levels {
                        Text(L.t("\(levels) 層高", "\(levels) 层高", "\(levels) floors high"))
                            .ds(.caption)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(value: Double(levels)))
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            Button(action: onNext) {
                Text(L.t("就係呢座", "就是这栋", "This one")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
    }
}

/// 选楼清单：附近住宅楼按距离排（近的先），每座一个大按钮；读屏、切换控制都能用。
private struct OnbBuildingList: View {
    @Environment(AppStore.self) private var store
    var onPick: (Int64) -> Void

    var body: some View {
        // pickView 的坐标以定位点为原点：centroid.length 就是和你的距离。
        let list = store.residentialBuildings().sorted { $0.centroid.length < $1.centroid.length }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("近嘅排先", "近的排前面", "Nearest first")).ds(.caption).foregroundStyle(.secondary)
                    ForEach(list, id: \.id) { b in
                        Button { onPick(b.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "building.2.fill")
                                    .foregroundStyle(DS.accent)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.shownName ?? L.t("住宅樓", "住宅楼", "Housing block")).ds(.body)
                                    Text(L.t("\(b.levels) 層 · 大約 \(Self.meters(b.centroid.length))", "\(b.levels) 层 · 大约 \(Self.meters(b.centroid.length))", "\(b.levels) floors · about \(Self.meters(b.centroid.length))"))
                                        .ds(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }
                    if list.isEmpty {
                        Text(L.t("附近搵唔到住宅樓。", "附近找不到住宅楼。", "No housing blocks found nearby.")).ds(.body).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, DS.side)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .principal) { Text(L.t("揀你住嗰座", "选你住的那栋", "Choose your block")).ds(.bodyBold) }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    static func meters(_ m: Double) -> String { m < 1000 ? L.t("\(Int((m / 10).rounded()) * 10) 米", "\(Int((m / 10).rounded()) * 10) 米", "\(Int((m / 10).rounded()) * 10) m") : String(format: L.t("%.1f 公里", "%.1f 公里", "%.1f km"), m / 1000) }
}

// MARK: - 4 樓層同網名（同一页）

private struct OnbFloorNameStep: View {
    @Environment(AppStore.self) private var store
    var onNext: () -> Void
    @State private var name = ""

    private var building: Building? { store.pendingHome.flatMap { store.map?.building(id: $0) } }
    private var maxFloor: Int { max(1, min(80, building?.levels ?? 30)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("你住幾樓？", "你住几楼？", "Which floor do you live on?"))
                        .ds(.title)
                        .accessibilityAddTraits(.isHeader)
                    floorStepper
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("大家點叫你？", "大家怎么称呼你？", "What should people call you?"))
                        .ds(.title)
                        .accessibilityAddTraits(.isHeader)
                    NicknameEditor(text: $name)
                }
            }
            .padding(.horizontal, DS.side)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnbBottomPrimary(title: L.t("好", "好", "OK"), action: next)
        }
        .onAppear {
            if store.floorChoice > maxFloor { store.floorChoice = maxFloor }
            if store.floorChoice < 1 { store.floorChoice = 1 }
            // 网名先填一个现成嘅（撳「好」就用得），想改可以撳第二个或者自己打。
            if name.isEmpty { name = store.nickname.isEmpty ? (store.nicknameSuggestions.first ?? "") : store.nickname }
            store.onbSay(L.t("你住幾樓？大家點叫你？", "你住几楼？大家怎么称呼你？", "Which floor do you live on? What should people call you?"))
        }
        .onChange(of: store.nickname) { _, n in if !n.isEmpty { name = n } }   // 自动脚本 / 启动参数填咗
    }

    private func next() {
        guard store.setNickname(name) else {
            store.toast(L.t("網名要 1 至 20 個字，或者撳一個現成嘅。", "网名要 1 到 20 个字，或者点一个现成的。", "Nicknames need 1 to 20 characters, or tap a ready-made one."))
            return
        }
        onNext()
    }

    /// 大 − / + 按钮（撳住会连续跳），中间大数字；读屏当一个可调元件（上下扫）。
    private var floorStepper: some View {
        let f = store.floorChoice
        let top = maxFloor
        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                OnbStepButton(symbol: "minus", enabled: f > 1, label: L.t("低一層", "低一层", "One floor down")) { change(-1) }
                Text(L.t("\(f) 樓", "\(f) 楼", "\(f)/F"))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: Double(f)))
                    .animation(DS.motion(DS.snappy), value: f)
                    .frame(maxWidth: .infinity)
                OnbStepButton(symbol: "plus", enabled: f < top, label: L.t("高一層", "高一层", "One floor up")) { change(+1) }
            }
            if let b = building {
                Text(L.t("\(b.shownName ?? "呢座樓")共 \(b.levels) 層", "\(b.shownName ?? "这栋楼")共 \(b.levels) 层", "\(b.shownName ?? "This block") has \(b.levels) floors"))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .sensoryFeedback(.selection, trigger: f)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("樓層", "楼层", "Floor"))
        .accessibilityValue(L.t("\(f) 樓", "\(f) 楼", "\(f)/F"))
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: change(+1)
            case .decrement: change(-1)
            @unknown default: break
            }
        }
    }

    private func change(_ d: Int) {
        store.floorChoice = max(1, min(maxFloor, store.floorChoice + d))
    }
}

/// 楼层 − / + 大圆钮（72 pt）：撳一下跳一层，撳住半秒之后连续跳。
private struct OnbStepButton: View {
    var symbol: String
    var enabled: Bool
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(enabled ? DS.accent : Color.secondary.opacity(0.5))
                .frame(width: 72, height: 72)
                .background(enabled ? DS.accentSoft : Color(.tertiarySystemFill), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(RepeatPressStyle(onRepeat: action))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// 撳住连续触发（楼层高嘅唔使撳几十下）。
private struct RepeatPressStyle: ButtonStyle {
    var onRepeat: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        Pressing(configuration: configuration, onRepeat: onRepeat)
    }

    private struct Pressing: View {
        let configuration: Configuration
        let onRepeat: () -> Void
        @State private var task: Task<Void, Never>?

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .animation(DS.motion(DS.snappy), value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, pressed in
                    task?.cancel()
                    task = nil
                    guard pressed else { return }
                    task = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        while !Task.isCancelled {
                            onRepeat()
                            try? await Task.sleep(for: .milliseconds(110))
                        }
                    }
                }
                .onDisappear { task?.cancel() }
        }
    }
}

// MARK: - 5 試一次：撳咪讲「今日天氣點」

private struct OnbTryMicStep: View {
    @Environment(AppStore.self) private var store
    @ObservedObject var listener: Listener
    var onDone: () -> Void
    /// 听到 / 撳咗嘅句子，同答案（有答案先出「做完」）。
    @State private var heard: String?
    @State private var answer: String?
    /// 讲完停顿 2 秒自动停（唔记得再撳都得）。
    @State private var autoStop: Task<Void, Never>?
    /// 上一次听唔到 / 用唔到咪：画面同声音讲同一句。
    @State private var missed: String?

    private var phrase: String { L.t("今日天氣點", "今天天气怎么样", "What's the weather today?") }

    private var hint: String {
        if store.listening { return L.t("聽緊…講完再撳一下。", "在听…说完再按一下。", "Listening… Tap again when done.") }
        return missed ?? L.t("撳下面個咪，講「\(phrase)」。", "按下面的麦克风，说「\(phrase)」。", "Tap the mic below and say \"\(phrase)\"")
    }

    var body: some View {
        let on = store.listening
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("試吓撳咪講嘢", "试试按麦克风说话", "Try speaking to the mic"))
                        .ds(.title)
                        .accessibilityAddTraits(.isHeader)
                    Text(hint)
                        .ds(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }

                OnbBigMic(on: on) { micTapped() }
                    .frame(maxWidth: .infinity)

                if on {
                    Text(listener.transcript.isEmpty ? "…" : L.t("「\(listener.transcript)」", "「\(listener.transcript)」", "“\(listener.transcript)”"))
                        .ds(.body)
                        .foregroundStyle(listener.transcript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                } else if let answer {
                    answerCard(answer).transition(DS.slide(.bottom))
                } else {
                    // 冇咪 / 唔想讲：撳呢句都得
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t("或者撳呢句：", "或者点这句：", "Or tap this line:")).ds(.caption).foregroundStyle(.secondary)
                        Button { usePhrase() } label: {
                            Label(L.t("「\(phrase)」", "「\(phrase)」", "“\(phrase)”"), systemImage: "text.bubble.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dsSecondary)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, DS.side)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if answer != nil && !on {
                OnbBottomPrimary(title: L.t("做完", "完成", "Done"), action: onDone)
                    .transition(DS.slide(.bottom))
            }
        }
        .animation(DS.motion(DS.spring), value: on)
        .animation(DS.motion(DS.spring), value: answer)
        .onAppear {
            store.refreshLiveWeather()      // 答「今日天氣點」用（天文台实时）
            store.onbSay(L.t("試吓撳咪講嘢。", "试试按麦克风说话。", "Try speaking to the mic."))
        }
        .onDisappear {
            autoStop?.cancel()
            store.tryMicStop()
        }
        .onChange(of: listener.transcript) { _, t in
            guard store.listening, !t.isEmpty else { return }
            autoStop?.cancel()
            autoStop = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, store.listening else { return }
                finish(store.tryMicStop())
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onbTryPhrase)) { _ in usePhrase() }
    }

    private func micTapped() {
        autoStop?.cancel()
        if store.listening { finish(store.tryMicStop()); return }
        Task { @MainActor in
            store.onbHush()
            if await store.tryMicStart() {
                heard = nil
                answer = nil
                missed = nil
                // 一直冇讲嘢：15 秒后自动停
                autoStop = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled, store.listening else { return }
                    finish(store.tryMicStop())
                }
            } else {
                missed = L.t("用唔到咪，可以撳下面嗰句。", "用不了麦克风，可以点下面那句。", "Can't use the mic. Tap the line below instead.")
                store.onbSay(missed ?? "")
            }
        }
    }

    private func finish(_ text: String) {
        autoStop?.cancel()
        guard !text.isEmpty else {
            missed = L.t("聽唔清楚，再講一次，或者撳下面嗰句。", "没听清楚，再说一次，或者点下面那句。", "Didn't catch that. Say it again, or tap the line below.")
            store.onbSay(missed ?? "")
            return
        }
        reply(to: text)
    }

    private func usePhrase() {
        autoStop?.cancel()
        store.tryMicStop()
        reply(to: phrase)
    }

    /// 答：天气（同「今日」页一样嘅一句）。答完先出「做完」。
    private func reply(to text: String) {
        missed = nil
        heard = text
        let a = store.tryAnswer
        answer = a
        store.onbHush()
        store.say(a, prompt: true)
    }

    private func answerCard(_ a: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let heard {
                Text(L.t("你：「\(heard)」", "你：「\(heard)」", "You: \"\(heard)\""))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 44, height: 44)
                    .background(DS.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                Text(a)
                    .ds(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { store.sayAgain(a) } label: {
                Label(L.t("再聽一次", "再听一次", "Hear again"), systemImage: "arrow.counterclockwise")
                    .ds(.captionBold)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.accentInk)
        }
        .dsCard()
        .accessibilityElement(children: .contain)
    }
}

/// 「試一次」嘅大咪：同主画面个咪一样嘅橙色圆，大啲；聆听时显示声波 + 外圈脉冲。
private struct OnbBigMic: View {
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if on && !DS.reduceMotion {
                    PhaseAnimator([false, true]) { out in
                        Circle()
                            .stroke(DS.accent.opacity(0.7), lineWidth: 4)
                            .scaleEffect(out ? 1.45 : 1)
                            .opacity(out ? 0 : 0.9)
                    } animation: { out in
                        out ? .spring(duration: 1.25, bounce: 0) : nil
                    }
                    .allowsHitTesting(false)
                }
                Circle()
                    .fill(DS.accent)
                    .shadow(color: DS.accent.opacity(on ? 0.45 : 0.3), radius: on ? 18 : 12, y: 5)
                Image(systemName: on ? "waveform" : "mic.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.variableColor.iterative.reversing, isActive: on)
            }
            .frame(width: 136, height: 136)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 4))
            .contentShape(Circle())
        }
        .buttonStyle(OnbPressStyle())
        .padding(.vertical, 8)
        .accessibilityLabel(L.t("講嘢", "说话", "Speak"))
        .accessibilityValue(on ? L.t("聽緊", "在听", "Listening") : "")
        .accessibilityHint(on ? L.t("再撳一下講完", "再按一下结束", "Tap again to finish") : L.t("撳一下開始講", "按一下开始说", "Tap to start speaking"))
    }
}
