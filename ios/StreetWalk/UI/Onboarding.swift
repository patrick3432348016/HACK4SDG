import SwiftUI

/// 首次使用：6 步（同意、定位、揀樓、樓層、小人、網名），每步一个大按钮。顶部进度点固定，内容按方向滑入淡出。
struct OnboardingFlow: View {
    @Environment(AppStore.self) private var store
    /// 往回走时新内容从左边进来。
    @State private var back = false

    private var step: AppStore.Step {
        if case .onboarding(let s) = store.phase { return s }
        return .avatar
    }

    var body: some View {
        let s = step
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if s == .locate || s == .pickHome {
                DioramaView(controller: store.scene, onTap: { hit in
                    guard store.phase == .onboarding(.pickHome) else { return }
                    // 点空了也要有回应（以前没反应）。
                    guard case .building(let id)? = hit else { store.toast(L.t("撳近啲你住嗰座樓，或者用下面嘅清單揀", "点近一点你住的那栋楼，或者用下面的清单选")); return }
                    store.pickHome(id)
                })
                .ignoresSafeArea()
                .transition(.opacity)
                .accessibilityLabel(L.t("你附近嘅立體地圖", "你附近的立体地图"))
                .accessibilityHint(L.t("用下面「用清單揀」都揀得到你住嗰座樓", "用下面「用清单选」也能选到你住的那栋楼"))
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

    private func forward(_ action: () -> Void) {
        back = false
        action()
    }

    private func goBack(from s: AppStore.Step) {
        back = true
        if s == .floor { store.backToPickHome() } else if s == .nickname { store.phase = .onboarding(.avatar) } else { store.phase = .onboarding(.floor) }
    }

    @ViewBuilder private func stepContent(_ s: AppStore.Step) -> some View {
        switch s {
        case .consent: OnbConsentStep(onNext: { forward { store.consent() } })
        case .locate: OnbLocateStep()
        case .pickHome: OnbPickHomeStep(onNext: { forward { store.confirmHome() } })
        case .floor: OnbFloorStep(onNext: { forward { store.phase = .onboarding(.avatar) } })
        case .avatar: OnbAvatarStep(onNext: { forward { store.phase = .onboarding(.nickname) } })
        case .nickname: OnbNicknameStep(onNext: { forward { store.finishOnboarding() } })
        }
    }

    private func topBar(_ s: AppStore.Step) -> some View {
        let canGoBack = s == .floor || s == .avatar || s == .nickname
        let onScene = s == .locate || s == .pickHome
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
                    .accessibilityLabel(L.t("返上一步", "返回上一步"))
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .frame(width: 48, height: 48)
            Spacer()
            OnbProgressDots(current: s.rawValue, total: 6)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    if onScene { Capsule().fill(.regularMaterial) }
                }
            Spacer()
            if store.changingHome {
                // 改楼途中可以退返出去（A80）
                Button { store.cancelChangeHome() } label: {
                    Text(L.t("唔改", "不改")).ds(.captionBold).foregroundStyle(.primary)
                        .padding(.horizontal, 14).frame(minHeight: 48)
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(OnbPressStyle())
                .accessibilityLabel(L.t("唔改，返主畫面", "不改，回主画面"))
            } else {
                Color.clear.frame(width: 48, height: 48)
            }
        }
        .padding(.horizontal, DS.side)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

// MARK: - 进度点

private struct OnbProgressDots: View {
    var current: Int
    var total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? DS.accent : Color.primary.opacity(0.18))
                    .opacity(i < current ? 0.45 : 1)
                    .frame(width: i == current ? 28 : 8, height: 8)
            }
        }
        .animation(DS.motion(DS.spring), value: current)
        .accessibilityElement()
        .accessibilityLabel("第 \(current + 1) 步，共 \(total) 步")
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

// MARK: - 1 同意

/// 「谁能看到什么」：按受众逐行讲（规格 §4 知情同意）。设置页「私隱說明」也可以用 PrivacyRows 重看。
struct PrivacyRows: View {
    static var rows: [(symbol: String, text: String)] { [
        ("figure.walk", L.t("你行街嘅時候自動記錄，唔使撳掣；定位揀「始終允許」，鎖咗機出門都會記。行過嘅路線同屋企位置只留喺你部手機。", "你散步时自动记录，不用按按钮；定位选「始终允许」，锁屏出门也会记。走过的路线和家的位置只留在你的手机里。")),
        ("building.2", L.t("同區嘅人（未碰過）：只見到你嘅網名、小人同連續日數；唔會見到你住邊座、幾樓。", "同区的人（没碰过）：只看到你的网名、形象和连续天数；看不到你住哪栋、几楼。")),
        ("person.2.fill", L.t("碰過一碰嘅街坊：仲會見到你住邊座幾樓、今日一句，同埋你出門時喺邊個地標附近。對外只講地標，唔顯示地圖坐標。", "碰过一碰的邻居：还能看到你住哪栋几楼、今日一句，以及你出门时在哪个地标附近。对外只说地标，不显示地图坐标。")),
        ("doc.text.magnifyingglass", L.t("你嘅反映會匿名，夠 10 人先交俾社工同屋邨管理。", "你的反馈会匿名，满 10 人才交给社工和屋邨管理。")),
        ("network", L.t("地圖資料向 OpenStreetMap 攞你附近一格；講嘢可能要經 Apple 辨認。", "地图数据从 OpenStreetMap 获取你附近一格；说话可能要经 Apple 识别。")),
    ] }
    /// 读出来的一段（和上面几行内容一致）。
    static var spoken: String { L.t("歡迎嚟到街坊行。你行街會自動記錄，定位揀始終允許，鎖咗機出門都會記，路線同屋企位置只留喺你部手機。同區嘅人只見到你嘅網名、小人同連續日數，唔見到你住邊座幾樓。碰過一碰嘅街坊先見到你住邊座幾樓、今日一句，同你出門時喺邊個地標附近。反映會匿名，夠十個人先交俾社工同屋邨管理。", "欢迎来到街坊行。你散步会自动记录，定位选始终允许，锁屏出门也会记，路线和家的位置只留在你的手机里。同区的人只看到你的网名、形象和连续天数，看不到你住哪栋几楼。碰过一碰的邻居才能看到你住哪栋几楼、今日一句，和你出门时在哪个地标附近。反馈会匿名，满十个人才交给社工和屋邨管理。") }

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
    /// 选了「唔同意」：不记录、不进圈，讲清楚之后怎么办。
    @State private var declined = UIPreview.is("declined")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                    .frame(maxWidth: .infinity)
                    .scaleEffect(appeared || DS.reduceMotion ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)
                    .animation(DS.motion(DS.bouncy), value: appeared)

                Text(L.t("歡迎嚟到街坊行", "欢迎来到街坊行"))
                    .ds(.title)
                    .accessibilityAddTraits(.isHeader)

                Text(L.t("用之前，講清楚邊個睇到乜：", "使用前，先说清楚谁能看到什么："))
                    .ds(.caption)
                    .foregroundStyle(.secondary)

                PrivacyRows(appeared: appeared)

                Button { store.sayAgain(PrivacyRows.spoken) } label: {
                    Label(L.t("再聽一次", "再听一次"), systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsSecondary)
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
            store.say(PrivacyRows.spoken)
        }
    }

    @ViewBuilder private func consentButtons(stacked: Bool) -> some View {
        if !declined {
            Button { withAnimation(DS.motion(DS.spring)) { declined = true } } label: {
                Text(L.t("唔同意", "不同意")).frame(maxWidth: stacked ? .infinity : nil)
            }
            .buttonStyle(.dsSecondary)
        }
        Button(action: onNext) {
            Text(declined ? L.t("我諗清楚，同意", "我想清楚了，同意") : "同意").frame(maxWidth: .infinity)
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
            Text(L.t("冇問題。唔同意就乜都唔會記錄，亦唔會加入圈。你可以而家離開 App；想用嘅時候返嚟撳「同意」就得。", "没问题。不同意就什么都不会记录，也不会加入圈子。你可以现在离开 App；想用的时候回来点「同意」就行。"))
                .ds(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .padding(.horizontal, DS.side)
        .accessibilityElement(children: .combine)
        .onAppear { store.say(L.t("冇問題。唔同意就乜都唔會記錄。想用嘅時候返嚟撳同意就得。", "没问题。不同意就什么都不会记录。想用的时候回来点同意就行。")) }
    }

    private var hero: some View {
        ZStack {
            Circle()
                .strokeBorder(DS.accent.opacity(0.16), lineWidth: 2)
                .frame(width: 168, height: 168)
            Circle()
                .fill(DS.accentSoft)
                .frame(width: 136, height: 136)
            Image(systemName: "figure.2")
                .font(.system(size: 60, weight: .semibold))
                .foregroundStyle(DS.accent)
                .symbolEffect(.bounce, value: appeared)
            Image(systemName: "location.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.breathe, isActive: !DS.reduceMotion)
                .frame(width: 44, height: 44)
                .background(DS.accent, in: Circle())
                .overlay(Circle().strokeBorder(Color(.systemGroupedBackground), lineWidth: 4))
                .offset(x: 52, y: -48)
        }
        .frame(height: 172)
        .accessibilityHidden(true)
    }
}

// MARK: - 2 定位、生成场景

private struct OnbLocateStep: View {
    @Environment(AppStore.self) private var store
    /// 等咗 10 秒仲未有地图：讲明等紧网络，俾个「用示例屋邨」出路（A28；地图最多等 30 秒、定位最多 120 秒）。
    @State private var waitedLong = false

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            if waitedLong && !store.changingHome && (store.loadingMap || store.map == nil) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("網絡慢，仲搵緊。可以再等等，或者先用示例屋邨睇吓。", "网络慢，还在找。可以再等等，或者先用示例屋邨看看。"))
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("用示例屋邨") { store.useSampleMap() }
                        .buttonStyle(.dsSecondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
                .padding(.horizontal, DS.side)
                .transition(.opacity)
            }
            HStack(spacing: 16) {
                Image(systemName: "location.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .symbolEffect(.pulse)
                    .frame(width: 52, height: 52)
                    .background(DS.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("搵緊你附近嘅樓…", "正在找你附近的楼…")).ds(.bodyBold)
                    Text(L.t("用你而家嘅位置砌一個小模型", "用你现在的位置搭一个小模型"))
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            .padding(.horizontal, DS.side)
            .padding(.bottom, 16)
        }
        .animation(DS.motion(DS.spring), value: waitedLong)
        .task {
            try? await Task.sleep(for: .seconds(10))
            waitedLong = true
        }
    }
}

// MARK: - 3 选住的楼

private struct OnbPickHomeStep: View {
    @Environment(AppStore.self) private var store
    var onNext: () -> Void
    @State private var showList = UIPreview.is("buildingList")

    var body: some View {
        VStack(spacing: 8) {
            instruction
            if let t = store.toast {
                Label(t, systemImage: "exclamationmark.circle.fill")
                    .ds(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .transition(DS.slide(.top))
            }
            Spacer(minLength: 0)
            sourceCaption
            if let id = store.pendingHome {
                confirmCard(id)
                    .transition(DS.slide(.bottom))
            } else {
                // 3D 里的楼很小、读屏也点不到：用清单也能选。
                Button { showList = true } label: {
                    Label(L.t("揀唔到？用清單揀", "选不到？用清单选"), systemImage: "list.bullet").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsSecondary)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.side)
        .padding(.bottom, 8)
        .animation(DS.motion(DS.spring), value: store.pendingHome)
        .animation(DS.motion(DS.snappy), value: store.toast)
        .onAppear { store.say(L.t("撳一下你住嗰座樓，或者用清單揀。", "点一下你住的那栋楼，或者用清单选。")) }
        .sheet(isPresented: $showList) {
            OnbBuildingList { id in
                showList = false
                store.pickHome(id)
            }
            .environment(store)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("撳一下你住嗰座樓", "点一下你住的那栋楼")).ds(.bodyBold)
                Text(L.t("住宅樓已經亮咗橙色", "住宅楼已经亮成橙色")).ds(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var sourceCaption: some View {
        let place = store.map?.placeName ?? ""
        let icon = Image(systemName: store.mapSource == .live ? "antenna.radiowaves.left.and.right" : "map")
        let source = place.isEmpty ? store.mapSource.label : "\(store.mapSource.label) · \(place)"
        // 拼成一段字：大字号时整句换行，不缩字、不拆成几栏
        return (Text("\(icon) \(source) ") + Text("©\u{00A0}OpenStreetMap").foregroundStyle(.secondary))
        .ds(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func confirmCard(_ id: Int64) -> some View {
        let b = store.map?.building(id: id)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "house.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .symbolEffect(.bounce, value: id)
                    .frame(width: 52, height: 52)
                    .background(DS.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(b?.name ?? L.t("你揀咗呢座樓", "你选了这栋楼"))
                        .ds(.bodyBold)
                        .contentTransition(.interpolate)
                    if let levels = b?.levels {
                        Text(L.t("\(levels) 層高", "\(levels) 层高"))
                            .ds(.caption)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(value: Double(levels)))
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            Button(action: onNext) {
                Text(L.t("就係呢座", "就是这栋")).frame(maxWidth: .infinity)
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
                    Text(L.t("近嘅排先", "近的排前面")).ds(.caption).foregroundStyle(.secondary)
                    ForEach(list, id: \.id) { b in
                        Button { onPick(b.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "building.2.fill")
                                    .foregroundStyle(DS.accent)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.name ?? L.t("住宅樓", "住宅楼")).ds(.body)
                                    Text(L.t("\(b.levels) 層 · 大約 \(Self.meters(b.centroid.length))", "\(b.levels) 层 · 大约 \(Self.meters(b.centroid.length))"))
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
                        Text(L.t("附近搵唔到住宅樓。", "附近找不到住宅楼。")).ds(.body).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, DS.side)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .principal) { Text(L.t("揀你住嗰座", "选你住的那栋")).ds(.bodyBold) }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    static func meters(_ m: Double) -> String { m < 1000 ? "\(Int((m / 10).rounded()) * 10) 米" : String(format: "%.1f 公里", m / 1000) }
}

// MARK: - 4 楼层

private struct OnbFloorStep: View {
    @Environment(AppStore.self) private var store
    var onNext: () -> Void

    private var building: Building? { store.pendingHome.flatMap { store.map?.building(id: $0) } }
    private var maxFloor: Int { max(1, min(50, building?.levels ?? 30)) }

    var body: some View {
        @Bindable var store = store
        let top = maxFloor
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("你住幾樓？", "你住几楼？"))
                    .ds(.title)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                Label(L.t("只有碰過一碰嘅街坊先見到你住邊座、幾樓（唔會見到門牌）", "只有碰过一碰的邻居才能看到你住哪栋、几楼（看不到门牌）"), systemImage: "eye")
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .center, spacing: 16) {
                OnbFloorTower(floor: min(store.floorChoice, top), levels: top)
                    .frame(width: 88, height: 300)

                VStack(spacing: 8) {
                    Text(L.t("\(store.floorChoice) 樓", "\(store.floorChoice) 楼"))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(store.floorChoice)))
                        .animation(DS.motion(DS.snappy), value: store.floorChoice)
                        .accessibilityHidden(true)

                    Picker(L.t("樓層", "楼层"), selection: $store.floorChoice) {
                        ForEach(1...top, id: \.self) { n in
                            Text("\(n)")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .tag(n)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 216)
                    .accessibilityLabel(L.t("樓層", "楼层"))
                    .accessibilityValue(L.t("\(store.floorChoice) 樓", "\(store.floorChoice) 楼"))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.side)
        .padding(.top, 8)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnbBottomPrimary(title: "下一步", action: onNext)
        }
        .onAppear {
            if store.floorChoice > top { store.floorChoice = top }
            if store.floorChoice < 1 { store.floorChoice = 1 }
            store.say(L.t("你住幾樓？轉個轆揀。只有碰過一碰嘅街坊先見到。", "你住几楼？转动滚轮选。只有碰过一碰的邻居才能看到。"))
        }
    }

    private var subtitle: String {
        guard let b = building else { return L.t("轉個轆揀，唔使打字", "转动滚轮选，不用打字") }
        if let name = b.name { return L.t("\(name) · 共 \(b.levels) 層", "\(name) · 共 \(b.levels) 层") }
        return L.t("呢座樓共 \(b.levels) 層", "这栋楼共 \(b.levels) 层")
    }
}

/// 楼的剖面小图：所选楼层亮橙色，随滚轮弹簧移动。
private struct OnbFloorTower: View {
    var floor: Int
    var levels: Int

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 8
            let h = geo.size.height - inset * 2
            let band = h / CGFloat(max(levels, 1))
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                Canvas { ctx, size in
                    guard levels > 1 else { return }
                    let every = band < 4 ? 2 : 1
                    for i in stride(from: every, to: levels, by: every) {
                        let y = size.height - inset - CGFloat(i) * band
                        ctx.fill(Path(CGRect(x: 10, y: y - 0.5, width: size.width - 20, height: 1)),
                                 with: .color(Color.primary.opacity(0.12)))
                    }
                }
                RoundedRectangle(cornerRadius: min(5, band / 2), style: .continuous)
                    .fill(DS.accent)
                    .frame(height: max(band - 2, 4))
                    .padding(.horizontal, 8)
                    .offset(y: -inset - CGFloat(max(floor, 1) - 1) * band - 1)
                    .shadow(color: DS.accent.opacity(0.4), radius: 6)
            }
        }
        .animation(DS.motion(DS.snappy), value: floor)
        .accessibilityHidden(true)
    }
}

// MARK: - 5 形象

private struct OnbAvatarStep: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    var onNext: () -> Void
    @Namespace private var swatchNS

    private func colorName(_ i: Int) -> String { Palette.name(i) }

    var body: some View {
        // 大字号时一行一个，不会截断成「推…」。
        let columns = typeSize.isAccessibilitySize ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L.t("揀你嘅小人", "选你的形象"))
                    .ds(.title)
                    .accessibilityAddTraits(.isHeader)

                preview.frame(maxWidth: .infinity)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Mobility.allCases, id: \.self) { m in tile(m) }
                }
                .animation(DS.motion(DS.spring), value: store.mobilityChoice)

                OnbChoiceRow(title: L.t("年紀", "年龄"), options: AgeGroup.allCases, selected: store.ageChoice, label: \.label) {
                    store.setLook(age: $0)
                    store.say($0.label)
                }

                skinRow

                swatches

                Text(L.t("排行榜同地圖都會用呢個小人，唔會用相片", "排行榜和地图都会用这个形象，不会用照片"))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.side)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnbBottomPrimary(title: "下一步", action: onNext)
        }
        .sensoryFeedback(.selection, trigger: store.mobilityChoice)
        .sensoryFeedback(.selection, trigger: store.colorChoice)
        .sensoryFeedback(.selection, trigger: store.skinChoice)
        .sensoryFeedback(.selection, trigger: store.ageChoice)
        .onAppear { store.say(L.t("揀你嘅小人：行動方式、年紀、膚色同衫嘅顏色。", "选你的形象：行动方式、年龄、肤色和衣服颜色。")) }
    }

    private var changeKey: String { "\(store.mobilityChoice.rawValue)-\(store.colorChoice)-\(store.skinChoice)-\(store.ageChoice.rawValue)" }

    private var preview: some View {
        let color = Palette.person(store.colorChoice)
        return VStack(spacing: 8) {
            AvatarBadge(color: color, mobility: store.mobilityChoice, size: 120, skin: store.skinChoice, age: store.ageChoice)
                .shadow(color: color.opacity(0.35), radius: 16, y: 6)
                .keyframeAnimator(initialValue: 1.0, trigger: changeKey) { content, scale in
                    content.scaleEffect(DS.reduceMotion ? 1 : scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(1.1, duration: 0.14, spring: .snappy)
                        SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
                    }
                }
            Text("\(store.ageChoice.label) · \(store.mobilityChoice.label)")
                .ds(.bodyBold)
                .contentTransition(.interpolate)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("預覽：\(store.ageChoice.label)、\(Palette.skinName(store.skinChoice))、\(colorName(store.colorChoice))衫、\(store.mobilityChoice.label)嘅小人", "预览：\(store.ageChoice.label)、\(Palette.skinName(store.skinChoice))、\(colorName(store.colorChoice))衣服、\(store.mobilityChoice.label)的形象"))
    }

    /// 肤色四档：圆点 + 读屏名。
    private var skinRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("膚色", "肤色")).ds(.caption).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(0..<Palette.skins.count, id: \.self) { i in
                    let selected = store.skinChoice == i
                    Button {
                        store.setLook(skin: i)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Palette.skin(i))
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                                .frame(width: 40, height: 40)
                            if selected {
                                Circle().strokeBorder(DS.accent, lineWidth: 3).frame(width: 52, height: 52)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(i >= 2 ? Color.white : Color.black.opacity(0.7))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(OnbPressStyle())
                    .accessibilityLabel(Palette.skinName(i))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .animation(DS.motion(DS.snappy), value: store.skinChoice)
        }
    }

    private func tile(_ m: Mobility) -> some View {
        let selected = store.mobilityChoice == m
        let shape = RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
        return Button {
            store.mobilityChoice = m
        } label: {
            HStack(spacing: 10) {
                AvatarBadge(color: Palette.person(store.colorChoice), mobility: m, size: 52, skin: store.skinChoice, age: store.ageChoice)
                // 两列时一行放下（「推BB車」不断开）；大字号一列，可以换行，不缩字。
                Text(m.label)
                    .ds(.bodyBold)
                    .foregroundStyle(.primary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(selected ? DS.accentSoft : Color(.secondarySystemGroupedBackground), in: shape)
            .overlay(shape.strokeBorder(selected ? DS.accent : Color.primary.opacity(0.06), lineWidth: selected ? 3 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(DS.accent)
                        .padding(6)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(OnbPressStyle())
        .accessibilityLabel(m.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var swatches: some View {
        HStack(spacing: 0) {
            ForEach(0..<Palette.people.count, id: \.self) { i in
                let selected = store.colorChoice == i
                Button {
                    store.colorChoice = i
                } label: {
                    ZStack {
                        if selected {
                            Circle()
                                .strokeBorder(Palette.person(i), lineWidth: 3)
                                .matchedGeometryEffect(id: "ring", in: swatchNS)
                        }
                        Circle()
                            .fill(Palette.person(i))
                            .frame(width: 34, height: 34)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                    .frame(width: 48, height: 48)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(OnbPressStyle())
                .accessibilityLabel(colorName(i))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(DS.motion(DS.snappy), value: store.colorChoice)
    }
}

/// 一行几个大按钮选一样（例如年纪：長者 / 中年 / 後生）；大字号放不下就上下排。
private struct OnbChoiceRow<T: Hashable>: View {
    let title: String
    let options: [T]
    let selected: T
    let label: KeyPath<T, String>
    let onPick: (T) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).ds(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(spacing: 8) { buttons }
            }
            .animation(DS.motion(DS.snappy), value: selected)
        }
    }

    @ViewBuilder private var buttons: some View {
        ForEach(options, id: \.self) { o in
            let on = o == selected
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            Button { onPick(o) } label: {
                Text(o[keyPath: label])
                    .ds(.bodyBold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(on ? DS.accentSoft : Color(.secondarySystemGroupedBackground), in: shape)
                    .overlay(shape.strokeBorder(on ? DS.accent : Color.primary.opacity(0.06), lineWidth: on ? 3 : 1))
                    .contentShape(shape)
            }
            .buttonStyle(OnbPressStyle())
            .accessibilityLabel("\(title)：\(o[keyPath: label])")
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}
