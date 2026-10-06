import SwiftUI

/// 首次使用：5 步，每步一个大按钮。顶部进度点固定，内容按方向滑入淡出。
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
                    guard store.phase == .onboarding(.pickHome), case .building(let id)? = hit else { return }
                    store.pickHome(id)
                })
                .ignoresSafeArea()
                .transition(.opacity)
                .accessibilityLabel("你附近嘅立體地圖")
            }

            stepContent(s)
                .id(s)
                .transition(stepTransition)
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
        store.phase = .onboarding(s == .avatar ? .floor : .pickHome)
    }

    @ViewBuilder private func stepContent(_ s: AppStore.Step) -> some View {
        switch s {
        case .consent: OnbConsentStep(onNext: { forward { store.consent() } })
        case .locate: OnbLocateStep()
        case .pickHome: OnbPickHomeStep(onNext: { forward { store.confirmHome() } })
        case .floor: OnbFloorStep(onNext: { forward { store.phase = .onboarding(.avatar) } })
        case .avatar: OnbAvatarStep(onNext: { forward { store.finishOnboarding() } })
        }
    }

    private func topBar(_ s: AppStore.Step) -> some View {
        let canGoBack = s == .floor || s == .avatar
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
                    .accessibilityLabel("返上一步")
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .frame(width: 48, height: 48)
            Spacer()
            OnbProgressDots(current: s.rawValue, total: 5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    if onScene { Capsule().fill(.regularMaterial) }
                }
            Spacer()
            Color.clear.frame(width: 48, height: 48)
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

private struct OnbConsentStep: View {
    @Environment(AppStore.self) private var store
    var onNext: () -> Void
    @State private var appeared = false

    private let rows: [(symbol: String, text: String)] = [
        ("figure.walk", "你行街嘅時候自動記錄，唔使撳掣"),
        ("mappin.and.ellipse", "位置只會用地標講，例如「公園附近」，唔顯示地圖坐標"),
        ("person.2.fill", "只有你碰過一碰嘅街坊，先見到你喺邊"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                    .frame(maxWidth: .infinity)
                    .scaleEffect(appeared || DS.reduceMotion ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)
                    .animation(DS.motion(DS.bouncy), value: appeared)

                Text("歡迎嚟到街坊行")
                    .ds(.title)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: row.symbol)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(DS.accent)
                                .frame(width: 48, height: 48)
                                .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .padding(.horizontal, DS.side)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnbBottomPrimary(title: "好", action: onNext)
        }
        .onAppear {
            appeared = true
            store.speaker.speak("歡迎嚟到街坊行。你行街會自動記錄，位置只用地標講，只有碰過一碰嘅街坊先見到你喺邊。")
        }
    }

    private var hero: some View {
        ZStack {
            Circle()
                .strokeBorder(DS.accent.opacity(0.16), lineWidth: 2)
                .frame(width: 208, height: 208)
            Circle()
                .fill(DS.accentSoft)
                .frame(width: 168, height: 168)
            Image(systemName: "figure.2")
                .font(.system(size: 76, weight: .semibold))
                .foregroundStyle(DS.accent)
                .symbolEffect(.bounce, value: appeared)
            Image(systemName: "location.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.breathe)
                .frame(width: 52, height: 52)
                .background(DS.accent, in: Circle())
                .overlay(Circle().strokeBorder(Color(.systemGroupedBackground), lineWidth: 4))
                .offset(x: 64, y: -60)
        }
        .frame(height: 212)
        .accessibilityHidden(true)
    }
}

// MARK: - 2 定位、生成场景

private struct OnbLocateStep: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                Image(systemName: "location.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .symbolEffect(.pulse)
                    .frame(width: 52, height: 52)
                    .background(DS.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("搵緊你附近嘅樓…").ds(.bodyBold)
                    Text("用你而家嘅位置砌一個小模型")
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
    }
}

// MARK: - 3 选住的楼

private struct OnbPickHomeStep: View {
    @Environment(AppStore.self) private var store
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            instruction
            if let t = store.toast {
                Label(t, systemImage: "exclamationmark.circle.fill")
                    .ds(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            sourceCaption
            if let id = store.pendingHome {
                confirmCard(id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, DS.side)
        .padding(.bottom, 8)
        .animation(DS.motion(DS.spring), value: store.pendingHome)
        .animation(DS.motion(DS.snappy), value: store.toast)
        .onAppear { store.speaker.speak("撳一下你住嗰座樓。") }
    }

    private var instruction: some View {
        HStack(spacing: 16) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(DS.accent)
                .symbolEffect(.breathe)
                .frame(width: 52, height: 52)
                .background(DS.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("撳一下你住嗰座樓").ds(.bodyBold)
                Text("住宅樓已經亮咗橙色").ds(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var sourceCaption: some View {
        let place = store.map?.placeName ?? ""
        return HStack(spacing: 6) {
            Image(systemName: store.mapSource == .live ? "antenna.radiowaves.left.and.right" : "map")
            Text(place.isEmpty ? store.mapSource.rawValue : "\(store.mapSource.rawValue) · \(place)")
            Text("© OpenStreetMap").foregroundStyle(.secondary)
        }
        .ds(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
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
                    Text(b?.name ?? "你揀咗呢座樓")
                        .ds(.bodyBold)
                        .contentTransition(.interpolate)
                    if let levels = b?.levels {
                        Text("\(levels) 層高")
                            .ds(.caption)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(value: Double(levels)))
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            Button(action: onNext) {
                Text("就係呢座").frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
    }
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
                Text("你住幾樓？")
                    .ds(.title)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .ds(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 16) {
                OnbFloorTower(floor: min(store.floorChoice, top), levels: top)
                    .frame(width: 88, height: 300)

                VStack(spacing: 8) {
                    Text("\(store.floorChoice) 樓")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(store.floorChoice)))
                        .animation(DS.motion(DS.snappy), value: store.floorChoice)
                        .accessibilityHidden(true)

                    Picker("樓層", selection: $store.floorChoice) {
                        ForEach(1...top, id: \.self) { n in
                            Text("\(n)")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .tag(n)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 216)
                    .accessibilityLabel("樓層")
                    .accessibilityValue("\(store.floorChoice) 樓")
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
            store.speaker.speak("你住幾樓？轉個轆揀。")
        }
    }

    private var subtitle: String {
        guard let b = building else { return "轉個轆揀，唔使打字" }
        if let name = b.name { return "\(name) · 共 \(b.levels) 層" }
        return "呢座樓共 \(b.levels) 層"
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
    var onNext: () -> Void
    @Namespace private var swatchNS

    private func colorName(_ i: Int) -> String {
        let names = ["綠色", "紫色", "藍色", "粉紅色", "啡色", "灰色", "橙色"]
        return names.indices.contains(i) ? names[i] : "顏色"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("揀你嘅小人")
                    .ds(.title)
                    .accessibilityAddTraits(.isHeader)

                preview.frame(maxWidth: .infinity)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Mobility.allCases, id: \.self) { m in tile(m) }
                }

                swatches

                Text("排行榜同地圖都會用呢個小人，唔會用相片")
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
            OnbBottomPrimary(title: "完成", action: onNext)
        }
        .sensoryFeedback(.selection, trigger: store.mobilityChoice)
        .sensoryFeedback(.selection, trigger: store.colorChoice)
        .onAppear { store.speaker.speak("揀你嘅小人同顏色。") }
    }

    private var changeKey: String { "\(store.mobilityChoice.rawValue)-\(store.colorChoice)" }

    private var preview: some View {
        let color = Palette.person(store.colorChoice)
        return VStack(spacing: 8) {
            AvatarBadge(color: color, mobility: store.mobilityChoice, size: 120)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: store.mobilityChoice)
                .shadow(color: color.opacity(0.35), radius: 16, y: 6)
                .keyframeAnimator(initialValue: 1.0, trigger: changeKey) { content, scale in
                    content.scaleEffect(DS.reduceMotion ? 1 : scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(1.1, duration: 0.14, spring: .snappy)
                        SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
                    }
                }
            Text(store.mobilityChoice.label)
                .ds(.bodyBold)
                .contentTransition(.interpolate)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("預覽：\(colorName(store.colorChoice))\(store.mobilityChoice.label)小人")
    }

    private func tile(_ m: Mobility) -> some View {
        let selected = store.mobilityChoice == m
        let shape = RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
        return Button {
            withAnimation(DS.motion(DS.spring)) { store.mobilityChoice = m }
        } label: {
            HStack(spacing: 12) {
                AvatarBadge(color: Palette.person(store.colorChoice), mobility: m, size: 56)
                Text(m.label)
                    .ds(.bodyBold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
                    withAnimation(DS.motion(DS.snappy)) { store.colorChoice = i }
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
    }
}
