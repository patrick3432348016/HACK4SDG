import SwiftUI

// MARK: - 碰一碰全屏画面

/// MainView 在 bumpStage == .searching 时全屏显示；找到对方后由 MainView 关掉。
/// 真机（2026-10-10）：搵緊身邊部手機 → 靠近啲 → 再近啲 → 成功，中间一个进度环显示距离（组员 B 原型嘅进度环）；
/// 失败讲清楚原因，提供「用二維碼」「再試」「去設定」。二维码画面见 BumpQRViews.swift。
struct BumpView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let progress = store.bumpProgress
        let qr = store.bumpQR
        let demo = store.community.isSimulated
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            LinearGradient(colors: [Color(.systemBackground), DS.accent.opacity(0.10)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if let qr {
                BumpQRContent(qr: qr, demo: demo)
                    .transition(.opacity)
            } else {
                bumpContent(progress, demo: demo)
                    .transition(.opacity)
            }
        }
        .animation(DS.motion(DS.spring), value: qr == nil)
    }

    private func bumpContent(_ p: BumpUpdate, demo: Bool) -> some View {
        VStack(spacing: 24) {
            if demo {
                DemoBadge(text: "示範：距離係模擬")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)

            BumpRing(progress: p)
                .frame(height: 280)

            VStack(spacing: 12) {
                Text(Self.title(p))
                    .ds(.title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
                Text(Self.hint(p))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .animation(DS.motion(DS.snappy), value: Self.title(p))

            Spacer(minLength: 0)

            buttons(p)
        }
        .padding(.horizontal, DS.side)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func buttons(_ p: BumpUpdate) -> some View {
        switch p {
        case .paired:
            Color.clear.frame(height: 56)   // 成功：等画面自己关，唔好俾人撳取消
        case .failed(let f):
            VStack(spacing: 8) {
                Button { store.bumpUseQR() } label: {
                    Label("用二維碼", systemImage: "qrcode").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
                HStack(spacing: 8) {
                    if f.needsSettings {
                        Button { openSettings() } label: { Text("去設定").frame(maxWidth: .infinity) }
                            .buttonStyle(.dsSecondary)
                    } else if f.canRetry {
                        Button { store.beginBumpSearch() } label: { Text("再試").frame(maxWidth: .infinity) }
                            .buttonStyle(.dsSecondary)
                    }
                    Button { store.cancelBump() } label: { Text("取消").frame(maxWidth: .infinity) }
                        .buttonStyle(.dsSecondary)
                }
            }
        case .linking:
            Button { store.cancelBump() } label: { Text("取消").frame(maxWidth: .infinity) }
                .buttonStyle(.dsSecondary)
        default:
            VStack(spacing: 8) {
                Button { store.bumpUseQR() } label: {
                    Label("用二維碼", systemImage: "qrcode").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsSecondary)
                Button { store.cancelBump() } label: { Text("取消").frame(maxWidth: .infinity) }
                    .buttonStyle(.dsSecondary)
            }
        }
    }

    static func title(_ p: BumpUpdate) -> String {
        switch p {
        case .searching: return "搵緊身邊部手機…"
        case .needsLocalNetwork: return "要允許「本地網絡」"
        case .ranging(let d): return BumpTuning.hint(d)
        case .nearMe: return "等緊對方部手機…"
        case .linking: return "配對緊…"
        case .paired: return "成功！"
        case .failed(let f): return f.title
        }
    }

    static func hint(_ p: BumpUpdate) -> String {
        switch p {
        case .searching: return "兩部手機都要開住呢頁，慢慢貼埋一齊。"
        case .needsLocalNetwork: return "彈出問你嗰陣撳「允許」。撳錯咗就去「設定」打開，或者用二維碼。"
        case .ranging: return "兩部手機慢慢貼埋，拎穩一陣。"
        case .nearMe: return "你部已經夠近，等對方部都量到。"
        case .linking: return "唔好走開，就快好。"
        case .paired: return "你哋而家係街坊。"
        case .failed(let f): return f.hint
        }
    }
}

/// 进度环（组员 B 原型嘅意念）：越近填得越满，中间大字显示距离（厘米）。
/// 未连上时显示原本两部手机慢慢靠近、一圈圈涟漪嘅插图。
private struct BumpRing: View {
    var progress: BumpUpdate

    var body: some View {
        let fill = Self.fill(progress)
        ZStack {
            switch progress {
            case .searching, .needsLocalNetwork:
                FSBumpIllustration()
                    .accessibilityElement()
                    .accessibilityLabel("碰一碰：將你部手機貼近對方部手機，就會加做街坊")
            default:
                Circle()
                    .stroke(DS.accent.opacity(0.15), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(DS.accent, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(DS.motion(.easeOut(duration: 0.25)), value: fill)
                center
                    .padding(36)
            }
        }
        .frame(width: 260, height: 260)
    }

    @ViewBuilder private var center: some View {
        switch progress {
        case .ranging(let d?):
            let cm = max(0, Int((d * 100).rounded()))
            VStack(spacing: 0) {
                Text("\(cm)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(cm)))
                    .animation(DS.motion(DS.snappy), value: cm)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("厘米").ds(.bodyBold).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("相距 \(cm) 厘米")
        case .ranging(nil):
            ProgressView().controlSize(.large)
                .accessibilityLabel("量緊距離")
        case .nearMe, .linking:
            ProgressView().controlSize(.large)
                .accessibilityLabel(progress == .linking ? "配對緊" : "等緊對方")
        case .paired:
            BumpPopSymbol(name: "checkmark.circle.fill", size: 110, color: DS.accent)
                .accessibilityLabel("成功")
        case .failed(let f):
            Image(systemName: Self.symbol(f))
                .font(.system(size: 76, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        default:
            EmptyView()
        }
    }

    static func fill(_ p: BumpUpdate) -> Double {
        switch p {
        case .ranging(let d): return BumpTuning.progress(d)
        case .nearMe, .linking, .paired: return 1
        default: return 0
        }
    }

    static func symbol(_ f: BumpFailure) -> String {
        switch f {
        case .unsupported: return "iphone.slash"
        case .localNetworkDenied, .network, .noServer: return "wifi.exclamationmark"
        case .nearbyDenied: return "hand.raised.fill"
        case .timeout: return "clock.badge.exclamationmark"
        default: return "exclamationmark.triangle.fill"
        }
    }
}

/// 出现时弹一下的 SF Symbol（成功剔号）。
struct BumpPopSymbol: View {
    var name: String
    var size: CGFloat
    var color: Color
    @State private var pop = 0

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, color)
            .symbolEffect(.bounce, value: pop)
            .task {
                try? await Task.sleep(for: .milliseconds(120))
                pop += 1
            }
    }
}

/// 两部手机慢慢靠近，中间一圈圈涟漪。
private struct FSBumpIllustration: View {
    var body: some View {
        ZStack {
            FSRipples()
            if DS.reduceMotion {
                phones(close: false)
            } else {
                PhaseAnimator([false, true]) { close in
                    phones(close: close)
                } animation: { close in
                    close ? .spring(response: 0.9, dampingFraction: 0.7).delay(0.5)
                          : .spring(response: 1.1, dampingFraction: 0.9).delay(0.8)
                }
            }
        }
    }

    private func phones(close: Bool) -> some View {
        ZStack {
            FSPhoneOutline(tint: DS.accent)
                .rotationEffect(.degrees(close ? 9 : -3))
                .offset(x: close ? -42 : -100, y: close ? -4 : 0)
            FSPhoneOutline(tint: Palette.person(0))
                .rotationEffect(.degrees(close ? -9 : 3))
                .offset(x: close ? 42 : 100, y: close ? -4 : 0)
        }
    }
}

private struct FSPhoneOutline: View {
    var tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        shape
            .fill(Color(.systemBackground))
            .overlay(shape.strokeBorder(tint, lineWidth: 4))
            .overlay(alignment: .top) {
                Capsule().fill(tint.opacity(0.55)).frame(width: 22, height: 6).padding(.top, 10)
            }
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 74, height: 140)
            .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
    }
}

private struct FSRipples: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: DS.reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let p = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(DS.accent.opacity(0.55 * (1 - p)), lineWidth: 3)
                        .frame(width: 40 + 250 * p, height: 40 + 250 * p)
                }
            }
        }
    }
}

// MARK: - 问对方（底部卡片内容）

/// MainView 在 find != nil && !findFullScreen 时放进底部卡片容器。只有内容，没有外框。
struct FindAskCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let f = store.find, let p = store.resident(f.partnerID) {
            let place = store.landmark(f.landmarkID)?.name ?? "附近"
            let agreed = store.partnerAgreed && f.stage != .declined
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    AvatarBadge(p, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("問緊\(p.name)").ds(.bodyBold)
                        // 真后端对方见到我嘅网名（演示模式冇网名就照用楼层）
                        Text("「\(store.nickname.isEmpty ? store.me.floorLabel : store.nickname)想過嚟搵你，喺\(place)等陣？」")
                            .ds(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if f.stage == .asking && !store.partnerAgreed {
                        ProgressView()
                            .controlSize(.large)
                            .transition(.opacity)
                            .accessibilityLabel("等緊\(p.name)回覆")
                    }
                }
                .accessibilityElement(children: .combine)

                if f.stage == .declined {
                    Label {
                        Text("\(p.name)而家唔方便").ds(.bodyBold)
                    } icon: {
                        Image(systemName: "moon.zzz.fill").foregroundStyle(.secondary)
                    }
                    .transition(DS.slide(.bottom))
                } else if agreed {
                    Label {
                        Text("\(p.name)話好：喺\(place)等你").ds(.bodyBold)
                    } icon: {
                        FSPopSymbol(name: "checkmark.circle.fill", size: 26, color: DS.accent)
                    }
                    .transition(DS.slide(.bottom))
                }

                HStack(spacing: 8) {
                    if agreed {
                        Button { store.endFind() } label: { Text("取消") }
                            .buttonStyle(.dsSecondary)
                        Button { store.startGoing() } label: {
                            Label("去", systemImage: "figure.walk").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dsPrimary)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        Button { store.endFind() } label: { Text("取消").frame(maxWidth: .infinity) }
                            .buttonStyle(.dsSecondary)
                    }
                }
            }
            .animation(DS.motion(DS.spring), value: agreed)
            .animation(DS.motion(DS.spring), value: f.stage)
            .sensoryFeedback(.warning, trigger: f.stage == .declined) { _, now in now }
        }
    }
}

// MARK: - 找人全屏控件

/// 画在全高 3D 场景上面（findFullScreen 时）。空白处不挡手势。
struct FindOverlay: View {
    @Environment(AppStore.self) private var store
    @State private var arrowAngle: Double = 0

    var body: some View {
        if let f = store.find, f.live {
            LiveFindOverlay()
        } else if let f = store.find, let p = store.resident(f.partnerID) {
            let place = store.landmark(f.landmarkID)?.name ?? "約定地方"
            ZStack {
                VStack(spacing: 8) {
                    // 演示：约会找人时都撳得到演示菜单（「遲到」= 将时间拨到约定后 11 分钟）。
                    if store.demoMode && !f.spontaneous {
                        HStack { Spacer(minLength: 0); DemoMenu() }
                    }
                    topCard(f, p, place)
                    ToastView()   // 提示放在顶卡下面（全屏时 MainView 不画自己那个）
                    Spacer(minLength: 0)
                    if f.latePrompt && f.stage != .met {
                        lateCard(p)
                            .transition(DS.slide(.bottom))
                    } else if f.stage != .met {
                        if f.stage == .near {
                            nearPill(f, p)
                                .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                        }
                        bottomBar(f, place)
                            .transition(DS.slide(.bottom))
                    }
                }
                .padding(.horizontal, DS.side)
                .padding(.bottom, 8)

                if f.stage == .met {
                    FSMetCelebration(name: p.name, place: place)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(DS.motion(DS.spring), value: f.stage)
            .animation(DS.motion(DS.spring), value: f.latePrompt)
            .animation(DS.motion(DS.spring), value: f.broadcast)
            .sensoryFeedback(.warning, trigger: f.latePrompt) { _, now in now }
            .onAppear { arrowAngle = f.bearing }
            .onChange(of: f.bearing) { old, new in
                // 走最短的方向转，避免跨过 ±180° 时整圈打转。
                var d = (new - old).truncatingRemainder(dividingBy: 360)
                if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                withAnimation(DS.motion(DS.snappy)) { arrowAngle += d }
            }
        }
    }

    private func topCard(_ f: FindSession, _ p: Resident, _ place: String) -> some View {
        let eta = max(1, f.etaMinutes)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                AvatarBadge(p, size: 52)
                Group {
                    if f.stage == .met {
                        Text("見到\(p.name)喇")
                    } else if f.spontaneous {
                        Text("\(p.name)喺\(place)等你 · 你大約 \(eta) 分鐘到")
                    } else if !f.partnerOut {
                        // 未收到对方出门通知，唔好讲佢出咗门（A19）。
                        Text("約咗\(p.name)喺\(place) · 等緊佢出門")
                    } else if f.etaMinutes == 0 {
                        Text("\(p.name)已經喺\(place)等你")
                    } else {
                        // 对方仲要几耐到约定地方（按佢剩低嘅路，A67）。
                        Text("\(p.name)出咗門 · 大約 \(eta) 分鐘到\(place)")
                    }
                }
                .ds(.bodyBold)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText(value: Double(eta)))
                .animation(DS.motion(DS.snappy), value: eta)
                Spacer(minLength: 0)
            }
            if p.isDemo { DemoBadge(text: "示範：對方位置係模擬") }
            if let b = f.broadcast {
                Label {
                    Text("已話俾\(p.name)知：\(b)")
                } icon: {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(DS.accent)
                        .symbolEffect(.bounce, value: b)
                }
                .ds(.caption)
                .foregroundStyle(.secondary)
                .transition(DS.slide(.top))
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }

    private func nearPill(_ f: FindSession, _ p: Resident) -> some View {
        let meters = Int(f.distance)
        return HStack(spacing: 16) {
            Image(systemName: "arrow.up")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(arrowAngle))
                .frame(width: 76, height: 76)
                .background(DS.accent, in: Circle())
                .shadow(color: DS.accent.opacity(0.4), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(meters) 米")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(meters)))
                    .animation(DS.motion(DS.snappy), value: meters)
                Text("\(p.name)就喺附近，跟住箭咀行")
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .padding(.trailing, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 50, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 50, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(p.name)喺附近，大約 \(meters) 米")
    }

    private func lateCard(_ p: Resident) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                FSPopSymbol(name: "clock.fill", size: 26, color: DS.accent)
                Text("過咗約定時間 10 分鐘，仲未見到\(p.name)。要唔要打電話俾佢？")
                    .ds(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                Button {
                    withAnimation(DS.motion(DS.spring)) { store.find?.latePrompt = false }
                } label: {
                    Text("再等等")
                }
                .buttonStyle(.dsSecondary)
                Button {
                    store.call(p.id)
                    withAnimation(DS.motion(DS.spring)) { store.find?.latePrompt = false }
                } label: {
                    Label("打電話", systemImage: "phone.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }

    /// 结束、播送、讲嘢（咪）。放得落就一行；大字号放唔落就播送占一行、其余排第二行（唔截字，A41）。
    private func bottomBar(_ f: FindSession, _ place: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                endButton(expand: false)
                broadcastButton(f, place)
                micButton(place)
            }
            VStack(spacing: 8) {
                broadcastButton(f, place)
                HStack(spacing: 8) {
                    endButton(expand: true)
                    micButton(place)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius + 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radius + 4, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

extension FindOverlay {
    fileprivate func endButton(expand: Bool) -> some View {
        Button { store.endFind() } label: { Text("結束").frame(maxWidth: expand ? .infinity : nil) }
            .buttonStyle(.dsSecondary)
    }

    fileprivate func broadcastButton(_ f: FindSession, _ place: String) -> some View {
        Button { store.broadcastHere() } label: {
            Label(f.spontaneous ? "我就到" : "我喺\(place)", systemImage: "speaker.wave.2.fill")
                .symbolEffect(.bounce, value: f.broadcast)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsPrimary)
    }

    /// 找人途中都可以讲（例如「我喺涼亭」）：同主画面个咪一样，讲完照样复述再撳「好」（A21）。
    fileprivate func micButton(_ place: String) -> some View {
        let on = store.listening
        return Button { store.micTapped() } label: {
            Image(systemName: on ? "waveform" : "mic.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.variableColor.iterative.reversing, isActive: on)
                .frame(width: DS.micSize, height: DS.micSize)
                .background(DS.accent, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 3))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("講嘢")
        .accessibilityValue(on ? "聽緊" : "")
        .accessibilityHint(on ? "再撳一下講完" : "撳一下開始講，例如「我喺\(place)」")
    }
}

/// 相遇：对勾弹一下 + "見到喇！"。store 3 秒后自动结束。
struct FSMetCelebration: View {
    var name: String
    var place: String
    @State private var pop = 0

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 96, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, DS.accent)
                .symbolEffect(.bounce, value: pop)
            Text("見到喇！").ds(.title)
            Text("你同\(name)喺\(place)見到面")
                .ds(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
        .padding(.horizontal, DS.side)
        .accessibilityElement(children: .combine)
        .task {
            try? await Task.sleep(for: .milliseconds(180))
            pop += 1
        }
    }
}

/// 出现时弹一下的 SF Symbol（卡片新插入时 value 型 symbolEffect 不会触发，所以自己触发一次）。
private struct FSPopSymbol: View {
    var name: String
    var size: CGFloat
    var color: Color
    @State private var pop = 0

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .symbolEffect(.bounce, value: pop)
            .task {
                try? await Task.sleep(for: .milliseconds(150))
                pop += 1
            }
    }
}
