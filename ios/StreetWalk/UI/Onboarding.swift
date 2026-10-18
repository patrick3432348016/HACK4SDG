import SwiftUI

/// UX section 5: welcome, three privacy statements, location/home suggestion, floor/nickname, microphone trial.
/// At most two large-text sentences per step; speak one sentence within 8 seconds and stop previous output on navigation.
/// Settings home changes reuse only steps 3–4; fixed step count and directional slide/fade transitions.
struct OnboardingFlow: View {
    @Environment(AppStore.self) private var store
    /// Backward navigation brings new content from the left.
    @State private var back = false
    /// Skipping the introduction also skips the trial and enters the main screen after floor/nickname.
    @State private var skipIntro = false
    /// Rejecting or lacking a home suggestion highlights all residences for manual selection.
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
                    // Home selection allows one-finger panning and a local-only GPS marker.
                    .onAppear { store.scene.oneFingerPan = true; store.startHere("pick") }
                    .onDisappear { store.stopHere("pick") }
                HereMarkerLayer(overlay: store.scene.overlay)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            stepContent(s)
                .id(s)
                .transition(stepTransition)

            // Place general notices below progress without overlap; home selection uses its own position below the explanation card.
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

    // MARK: Navigation

    private var stepTransition: AnyTransition {
        if DS.reduceMotion { return .opacity }
        return .asymmetric(insertion: .offset(x: back ? -48 : 48).combined(with: .opacity),
                           removal: .opacity)
    }

    /// Stop the prior step's output before changing steps; the new step announces itself.
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
            // Tapping empty space or a non-residence switches to manual selection, highlights residences and explains how to choose.
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
                    // Skip the trial for home changes or experienced-user setup.
                    if store.changingHome || skipIntro { store.finishOnboarding() } else { store.phase = .onboarding(.tryMic) }
                }
            })
        case .tryMic: OnbTryMicStep(listener: store.listener, onDone: { go { store.finishOnboarding() } })
        }
    }

    /// Active progress steps: two for home changes, three when skipping the introduction.
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
                // A80: permit exiting home changes midway.
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

// MARK: - Stop speech before step changes

extension AppStore {
    /// Stop current and queued onboarding speech; phase changes hush automatically, while within-step changes use this helper. Leave listening untouched.
    func onbHush() {
        guard !listening else { return }
        hush()
    }

    /// On appearance, replace prior speech with one sentence of at most 8 seconds rather than queueing behind it.
    func onbSay(_ s: String) {
        onbHush()
        say(s)
    }
}

// MARK: - Text progress

/// A-1: explicit step counts replace dots that older testers mistook for swipeable pages.
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

/// Subtle press-scale feedback for background-free buttons.
private struct OnbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(DS.motion(DS.snappy), value: configuration.isPressed)
    }
}

/// Large bottom button fixed above the safe area.
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

/// Shared large circular icon with pale orange background and a top-right badge for welcome, privacy and trial.
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

// MARK: - 1 Welcome: explain purpose

private struct OnbWelcomeStep: View {
    @Environment(AppStore.self) private var store
    var onStart: () -> Void
    var onSkip: () -> Void
    @State private var appeared = false

    static var spoken: String { L.t("街坊行幫你記錄每日散步，約隔籬街坊一齊行；上面幅地圖幫你哋搵到對方。", "街坊行帮你记录每天散步，约隔壁邻居一起走；上面的地图帮你们找到对方。", "StreetWalk records your daily walks and helps you walk with neighbours. The map at the top helps you find each other.") }

    /// Feedback: replace button-like introduction cards with plain icon/text rows and explanations.
    /// 10-18: shorten each introduction and explain Today and landmark reports, which testers found unpredictable.
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
                // Place language selection first using each language's own name; switch immediately and repeat the welcome.
                VStack(alignment: .leading, spacing: 8) {
                    Label("語言 · 语言 · Language", systemImage: "globe")
                        .ds(.captionBold)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    LanguageChooser(short: true) { store.onbSay(Self.spoken) }
                }
                .onAppear { if LaunchArgs.value("-videoShot") == "lang" { store.runVideoShotIfNeeded() } }   // Promotional recording: language switching.
                Text(L.t("歡迎嚟到街坊行", "欢迎来到街坊行", "Welcome to StreetWalk"))
                    .ds(.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(L.t("街坊行可以幫你：", "街坊行可以帮你：", "StreetWalk can help you:"))
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
                // Experienced users can skip the introduction and trial.
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

// MARK: - 2 Privacy: three statements with five detailed sections

/// Section 4: explain visibility by audience; reuse PrivacyRows in Settings and onboarding details.
struct PrivacyRows: View {
    static var rows: [(symbol: String, text: String)] { [
        ("figure.walk", L.t("你行街嘅時候自動記錄，唔使撳掣；定位揀「始終允許」，鎖咗機出門都會記。行過嘅路線同屋企位置只留喺你部手機。", "你散步时自动记录，不用按按钮；定位选「始终允许」，锁屏出门也会记。走过的路线和家的位置只留在你的手机里。", "Walks are recorded when you go out, no buttons. Choose \"Always Allow\" for location and it records even when the phone is locked. Your routes and home location stay on your phone.")),
        ("building.2", L.t("同區嘅人（未加做街坊）：只見到你嘅網名、小人同連續日數；唔會見到你住邊座、幾樓。", "附近还没加为邻居的人：只看到你的网名、卡通小人和连续天数，看不到你住哪栋、几楼。", "People nearby you have not added: they only see your nickname, figure and streak. Not your block or floor.")),
        ("person.2.fill", L.t("用碰一碰加咗嘅街坊：仲會見到你住邊座幾樓、今日一句，同埋你出門時喺邊個地標附近。對外只講地標，唔顯示地圖坐標。", "用碰一碰加过的邻居：还能看到你住哪栋、几楼，今天走过哪些地方，还有你出门时正在哪个地标附近。对外只说地标，不显示地图坐标。", "Neighbours added by tapping phones: they also see your block and floor, your line for today, and which landmark you are near when you are out. Others only see landmarks, never map coordinates.")),
        ("doc.text.magnifyingglass", L.t("你嘅反映會匿名，幾位街坊都反映先會整理好轉交社工同屋邨管理。", "你对地点的反馈是匿名的，同一个地方有几位邻居都反映了，才会整理好转交社工和屋邨管理处。", "Your reports about places are anonymous. When several neighbours report the same place, we pass it on to social workers and estate management.")),
        ("network", L.t("地圖資料向 OpenStreetMap 攞你附近一格；講嘢可能要經 Apple 辨認。", "地图数据来自 OpenStreetMap，只下载你家附近一格；说话时可能要经过苹果的语音识别。", "Map data comes from OpenStreetMap, only the area near your home. When you speak, Apple may help recognise your voice.")),
    ] }
    /// Spoken version matches the visible explanation, reused by Settings' read-aloud action.
    static var spoken: String { L.t("你行街會自動記錄，定位揀始終允許，鎖咗機出門都會記，路線同屋企位置只留喺你部手機。同區嘅人只見到你嘅網名、小人同連續日數，唔見到你住邊座幾樓。用碰一碰加咗嘅街坊先見到你住邊座幾樓、今日一句，同你出門時喺邊個地標附近。反映會匿名，幾位街坊都反映先會轉交社工同屋邨管理。", "你散步会自动记录，定位选始终允许，锁屏出门也会记，路线和家的位置只留在你的手机里。附近的人只看到你的网名、卡通小人和连续天数，看不到你住哪栋、几楼。用碰一碰加过的邻居，才能看到你住哪栋几楼、今天走过哪些地方，和你出门时在哪个地标附近。地点反馈是匿名的，同一个地方有几位邻居都反映了，才会转交社工和屋邨管理处。", "Walks are recorded when you go out. Choose Always Allow for location and it records even when the phone is locked. Your routes and home location stay on your phone. People nearby only see your nickname, figure and streak, not your block or floor. Only neighbours added by tapping phones see your block, floor, your line for today, and which landmark you are near when out. Reports are anonymous. When several neighbours report the same place, we pass it on to social workers and estate management.") }

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
    /// On refusal, do not record or join a circle; explain the next step.
    @State private var declined = UIPreview.is("declined")

    /// UX section 5: three summary statements, with the original five sections under Details.
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

                // Details cover audience visibility, reports and map / speech data destinations.
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
                // Place refusal and consent side-by-side, stacking when larger text cannot fit.
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

    /// Refusal prevents recording / circle entry; users may return and consent later.
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

// MARK: - 3a Home: explain location before the system prompt, then load the map

private struct OnbLocateStep: View {
    @Environment(AppStore.self) private var store
    /// Consent given; system authorization or location retrieval is pending.
    @State private var asked = false
    /// A28: after 10 seconds explain network waiting and offer the sample estate; map attempts may take 75 seconds, location up to 120.
    @State private var waitedLong = false

    /// When location has not been requested, explain first; AppStore+Map.consent does not start automatically.
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

    /// One explanation and consent button before requesting While Using location.
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

// MARK: - 3b Home: confirm a suggested building or select manually

private struct OnbPickHomeStep: View {
    @Environment(AppStore.self) private var store
    @Binding var manual: Bool
    var onNext: () -> Void
    @State private var showList = UIPreview.is("buildingList")

    private func name(_ id: Int64) -> String? { store.map?.building(id: id)?.shownName }

    var body: some View {
        VStack(spacing: 8) {
            if manual { instruction.transition(DS.slide(.top)) }
            // The explanation card already states why no suggestion exists; avoid duplicating the notice.
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
            HStack(alignment: .bottom) {
                attribution
                // Show Reset after manual camera changes, equivalent to double-tap.
                if store.scene.overlay.userMoved {
                    MapResetButton { store.scene.resetUserCamera() }.transition(.opacity)
                }
            }
            .animation(DS.motion(DS.snappy), value: store.scene.overlay.userMoved)
            if let id = store.pendingHome {
                Group {
                    if manual { confirmCard(id) } else { guessCard(id) }
                }
                .transition(DS.slide(.bottom))
            } else {
                // Provide a list because small 3D buildings are hard to tap and inaccessible to VoiceOver selection.
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
            // Without a suggestion due to location, sample map or missing residences, enter manual selection directly.
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
            // Update guidance after selection instead of continuing to ask for a tap.
            VStack(alignment: .leading, spacing: 4) {
                if store.pendingHome == nil {
                    Text(L.t("撳一下你住嗰座樓", "点一下你住的那栋楼", "Tap the block you live in")).ds(.bodyBold)
                    Text(L.t("橙色嘅係住宅樓", "橙色的是住宅楼", "Orange ones are homes")).ds(.caption).foregroundStyle(.secondary)
                    // A-2: keep the reason for missing suggestions visible instead of flashing briefly.
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

    /// Show required OpenStreetMap attribution, omitting technical cache/live jargon.
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
        let d = b.centroid.length       // Home-selection coordinates originate at the user's position.
        let far = d < 30 ? L.t("就喺你度", "就在你这里", "Right where you are") : L.t("離你大約 \(OnbBuildingList.meters(d))", "离你大约 \(OnbBuildingList.meters(d))", "About \(OnbBuildingList.meters(d)) away")
        return L.t("\(b.levels) 層 · \(far)", "\(b.levels) 层 · \(far)", "\(b.levels) floors · \(far)")
    }

    /// Suggested-building card offers confirmation or manual choice.
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

    /// After manual selection show name, floors and a confirmation action.
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

/// Accessible building list sorts residences nearest-first with large buttons supporting VoiceOver and Switch Control.
private struct OnbBuildingList: View {
    @Environment(AppStore.self) private var store
    var onPick: (Int64) -> Void

    var body: some View {
        // pickView is centered on location, so centroid.length equals distance from the user.
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

// MARK: - 4 Floor and nickname on one page

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
            // Prefill a usable nickname, with alternative suggestions and free text.
            if name.isEmpty, LaunchArgs.videoClean, let n = LaunchArgs.value("-nickname") { name = n }
            if name.isEmpty { name = store.nickname.isEmpty ? (store.nicknameSuggestions.first ?? "") : store.nickname }
            store.onbSay(L.t("你住幾樓？大家點叫你？", "你住几楼？大家怎么称呼你？", "Which floor do you live on? What should people call you?"))
        }
        .onChange(of: store.nickname) { _, n in if !n.isEmpty { name = n } }   // Already populated by the script or launch argument.
    }

    private func next() {
        guard store.setNickname(name) else {
            store.toast(L.t("網名要 1 至 20 個字，或者撳一個現成嘅。", "网名要 1 到 20 个字，或者点一个现成的。", "Nicknames need 1 to 20 characters, or tap a ready-made one."))
            return
        }
        onNext()
    }

    /// Large minus/plus controls repeat on hold; expose the central value as one adjustable VoiceOver element.
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

/// 72 pt floor buttons change one level per tap and repeat after half a second held.
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

/// Hold-repeat avoids dozens of taps for high floors.
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

// MARK: - 5 Trial: ask about today's weather

private struct OnbTryMicStep: View {
    @Environment(AppStore.self) private var store
    @ObservedObject var listener: Listener
    var onDone: () -> Void
    /// Show the recognized / selected sentence and answer; reveal completion only after an answer.
    @State private var heard: String?
    @State private var answer: String?
    /// Stop automatically after two seconds of silence without requiring another tap.
    @State private var autoStop: Task<Void, Never>?
    /// Use matching visible and spoken explanations after recognition or microphone failure.
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
                    // Offer a tappable sentence without requiring speech or a microphone.
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
            store.refreshLiveWeather()      // Answer the trial weather question using live HKO data.
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
                // Stop after 15 seconds with no speech.
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

    /// Use Today's weather sentence, then expose completion.
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

/// Trial microphone matches the main orange design at a larger size, with waveform and pulse while listening.
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
