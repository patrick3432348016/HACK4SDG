import SwiftUI

// MARK: - 碰一碰全屏画面

/// MainView 在 bumpStage == .searching 时全屏显示；找到对方后由 MainView 关掉。
/// 真机（2026-10-10）：搵緊身邊部手機 → 靠近啲 → 再近啲 → 成功，中间一个进度环显示距离（组员 B 原型嘅进度环）；
/// 失败讲清楚原因，提供「用二維碼」「再試」「去設定」。二维码画面见 BumpQRViews.swift。
/// 2026-10-17：教人并排、隔一拳（顶部对顶部会弹「隔空投送」，D-4；10-18 背对背会叫出 Siri，删咗）；搵咗 12 秒都未搵到对方，
/// 「用二維碼」变大掣、提示开 Wi-Fi 同蓝牙（D-5 / D-6）；系统唔俾用流量就讲去设定开（D-5）。
struct BumpView: View {
    @Environment(AppStore.self) private var store
    /// 搵咗 BumpTuning.slowSearch 秒都未搵到对方部手机。
    @State private var slow = false

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
                DemoBadge(text: L.t("示範：距離係模擬", "演示：距离是模拟的", "Demo: distance is simulated"))
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
                Text(hintText(p))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .animation(DS.motion(DS.snappy), value: Self.title(p))
            .animation(DS.motion(DS.snappy), value: slow)

            Spacer(minLength: 0)

            buttons(p)
        }
        .padding(.horizontal, DS.side)
        .padding(.bottom, 16)
        // 未搵到对方部手机：计时，够钟就提示（再试 / 静静重新搵返到「搵緊」会重新计）。
        .task(id: Self.finding(p)) {
            slow = false
            guard Self.finding(p) else { return }
            try? await Task.sleep(for: .seconds(BumpTuning.slowSearch))
            guard !Task.isCancelled else { return }
            slow = true
            store.bumpSearchSlow()
        }
    }

    /// 仲未搵到对方部手机（未连上）。
    static func finding(_ p: BumpUpdate) -> Bool { p == .searching || p == .needsLocalNetwork }

    /// 系统唔俾用流量而配对因网络失败：要去设定。
    private func cellularBlocked(_ p: BumpUpdate) -> Bool { p == .failed(.network) && store.cellularDenied }

    private func hintText(_ p: BumpUpdate) -> String {
        if slow, p == .searching {
            return L.t("仲未搵到對方部手機。兩部手機都要開住 Wi-Fi 同藍牙（唔使連網絡），都停喺呢頁。亦可以改用二維碼。",
                       "还没找到对方的手机。两台手机都要打开 Wi-Fi 和蓝牙（不用连网络），都停在这一页。也可以改用二维码。", "Can't find the other phone yet. Both phones need Wi-Fi and Bluetooth on (no internet needed), and both stay on this page. Or use a QR code.")
        }
        if cellularBlocked(p) { return store.cellularDeniedHint }
        return Self.hint(p)
    }

    @ViewBuilder
    private func buttons(_ p: BumpUpdate) -> some View {
        switch p {
        case .paired:
            Color.clear.frame(height: 56)   // 成功：等画面自己关，唔好俾人撳取消
        case .failed(let f):
            VStack(spacing: 8) {
                Button { store.bumpUseQR() } label: {
                    Label(L.t("用二維碼", "用二维码", "Use QR code"), systemImage: "qrcode").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
                HStack(spacing: 8) {
                    if f.needsSettings || cellularBlocked(p) {
                        Button { openSettings() } label: { Text(L.t("去設定", "去设置", "Open Settings")).frame(maxWidth: .infinity) }
                            .buttonStyle(.dsSecondary)
                    } else if f.canRetry {
                        Button { store.beginBumpSearch() } label: { Text(L.t("再試", "再试", "Try again")).frame(maxWidth: .infinity) }
                            .buttonStyle(.dsSecondary)
                    }
                    Button { store.cancelBump() } label: { Text(L.t("取消", "取消", "Cancel")).frame(maxWidth: .infinity) }
                        .buttonStyle(.dsSecondary)
                }
            }
        case .linking:
            Button { store.cancelBump() } label: { Text(L.t("取消", "取消", "Cancel")).frame(maxWidth: .infinity) }
                .buttonStyle(.dsSecondary)
        default:
            VStack(spacing: 8) {
                // 搵咗一阵都未搵到：「用二維碼」变大掣，唔使等到失败（D-6）。
                if slow && Self.finding(p) {
                    Button { store.bumpUseQR() } label: {
                        Label(L.t("用二維碼", "用二维码", "Use QR code"), systemImage: "qrcode").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsPrimary)
                    .transition(.opacity)
                } else {
                    Button { store.bumpUseQR() } label: {
                        Label(L.t("用二維碼", "用二维码", "Use QR code"), systemImage: "qrcode").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsSecondary)
                }
                Button { store.cancelBump() } label: { Text(L.t("取消", "取消", "Cancel")).frame(maxWidth: .infinity) }
                    .buttonStyle(.dsSecondary)
            }
            .animation(DS.motion(DS.snappy), value: slow)
        }
    }

    static func title(_ p: BumpUpdate) -> String {
        switch p {
        case .searching: return L.t("搵緊身邊部手機…", "正在找身边的手机…", "Finding the phone…")
        case .needsLocalNetwork: return L.t("要允許「本地網絡」", "要允许「本地网络」", "Allow Local Network")
        case .ranging(let d): return BumpTuning.hint(d)
        case .nearMe: return L.t("等緊對方部手機…", "在等对方的手机…", "Waiting for them…")
        case .linking: return L.t("配對緊…", "正在配对…", "Pairing…")
        case .paired: return L.t("成功！", "成功！", "Done!")
        case .failed(let f): return f.title
        }
    }

    static func hint(_ p: BumpUpdate) -> String {
        switch p {
        case .searching: return L.t("兩部手機都開住呢頁，並排擺、隔一個拳頭就得。唔好頂部對頂部；彈出「隔空投送」就撳「取消」。",
                                    "两台手机都打开这一页，并排放、隔一个拳头就行。不要顶部对顶部；弹出「隔空投送」就点「取消」。", "Open this page on both phones. Hold them side by side, a fist apart. If AirDrop pops up, tap “Cancel”.")
        case .needsLocalNetwork: return L.t("彈出問你嗰陣撳「允許」。撳錯咗就去「設定」打開，或者用二維碼。", "弹窗询问时点「允许」。点错了就去「设置」打开，或者用二维码。", "When asked, tap “Allow”. If you tapped wrong, turn it on in Settings, or use a QR code.")
        case .ranging: return L.t("兩部手機並排擺、隔一個拳頭，拎穩一秒。唔使貼埋。", "两台手机并排放、隔一个拳头，拿稳一秒。不用贴在一起。", "Side by side, a fist apart. Hold still for a second. No need to touch.")
        case .nearMe: return L.t("你部已經夠近，等對方部都量到。", "你的已经够近了，等对方的也测到。", "Your phone is close enough. Waiting for the other one.")
        case .linking: return L.t("唔好走開，就快好。", "别走开，马上就好。", "Don't move away. Almost done.")
        case .paired: return L.t("你哋而家係街坊。", "你们现在是邻居了。", "You're now neighbours.")
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
                    .accessibilityLabel(L.t("碰一碰：兩部手機並排擺、隔一個拳頭，就會加做街坊", "碰一碰：两台手机并排放、隔一个拳头，就能加为邻居", "Tap phones: hold two phones side by side, a fist apart, to add a neighbour"))
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
                Text(L.t("厘米", "厘米", "cm")).ds(.bodyBold).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("相距 \(cm) 厘米", "相距 \(cm) 厘米", "\(cm) cm apart"))
        case .ranging(nil):
            ProgressView().controlSize(.large)
                .accessibilityLabel(L.t("量緊距離", "正在测距离", "Measuring distance"))
        case .nearMe, .linking:
            ProgressView().controlSize(.large)
                .accessibilityLabel(progress == .linking ? L.t("配對緊", "正在配对", "Pairing") : L.t("等緊對方", "在等对方", "Waiting for them"))
        case .paired:
            BumpPopSymbol(name: "checkmark.circle.fill", size: 110, color: DS.accent)
                .accessibilityLabel(L.t("成功", "成功", "Done"))
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

/// 两部手机并排慢慢靠近、停喺隔一拳（唔係顶部对顶部，唔使贴埋：D-4），中间一圈圈涟漪；下面一粒字讲「並排 · 隔一拳」。
private struct FSBumpIllustration: View {
    var body: some View {
        ZStack {
            FSRipples()
            if DS.reduceMotion {
                phones(close: true)
            } else {
                PhaseAnimator([false, true]) { close in
                    phones(close: close)
                } animation: { close in
                    close ? .spring(response: 0.9, dampingFraction: 0.8).delay(0.5)
                          : .spring(response: 1.1, dampingFraction: 0.9).delay(1.0)
                }
            }
            Label(L.t("並排 · 隔一個拳頭", "并排 · 隔一个拳头", "Side by side, fist apart"), systemImage: "arrow.left.and.right")
                .ds(.captionBold)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .offset(y: 112)
        }
    }

    /// 两部都企直、平排；靠近之后中间留一拳位，有个左右箭咀。
    private func phones(close: Bool) -> some View {
        ZStack {
            FSPhoneOutline(tint: DS.accent)
                .offset(x: close ? -52 : -104, y: -14)
            FSPhoneOutline(tint: Palette.person(0))
                .offset(x: close ? 52 : 104, y: -14)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DS.accent)
                .offset(y: -14)
                .opacity(close ? 1 : 0)
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
            let place = store.landmark(f.landmarkID)?.name ?? L.t("附近", "附近", "nearby")
            let agreed = store.partnerAgreed && f.stage != .declined
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    AvatarBadge(p, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("問緊\(p.name)", "正在问\(p.name)", "Asking \(p.name)")).ds(.bodyBold)
                        // 真后端对方见到我嘅网名（演示模式冇网名就照用楼层）
                        Text(L.t("「\(store.nickname.isEmpty ? L.t("街坊", "邻居", "A neighbour") : store.nickname)想過嚟搵你，喺\(place)等陣？」", "「\(store.nickname.isEmpty ? L.t("街坊", "邻居", "A neighbour") : store.nickname)想过来找你，在\(place)等一下？」", "“\(store.nickname.isEmpty ? L.t("街坊", "邻居", "A neighbour") : store.nickname) wants to come and find you. Wait at \(place)?”"))
                            .ds(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if f.stage == .asking && !store.partnerAgreed {
                        ProgressView()
                            .controlSize(.large)
                            .transition(.opacity)
                            .accessibilityLabel(L.t("等緊\(p.name)回覆", "在等\(p.name)回复", "Waiting for \(p.name) to reply"))
                    }
                }
                .accessibilityElement(children: .combine)

                if f.stage == .declined {
                    Label {
                        Text(L.t("\(p.name)而家唔方便", "\(p.name)现在不方便", "\(p.name) can't right now")).ds(.bodyBold)
                    } icon: {
                        Image(systemName: "moon.zzz.fill").foregroundStyle(.secondary)
                    }
                    .transition(DS.slide(.bottom))
                } else if agreed {
                    Label {
                        Text(L.t("\(p.name)話好：喺\(place)等你", "\(p.name)说好：在\(place)等你", "\(p.name) said yes: waiting at \(place)")).ds(.bodyBold)
                    } icon: {
                        FSPopSymbol(name: "checkmark.circle.fill", size: 26, color: DS.accent)
                    }
                    .transition(DS.slide(.bottom))
                }

                HStack(spacing: 8) {
                    if agreed {
                        Button { store.endFind() } label: { Text(L.t("取消", "取消", "Cancel")) }
                            .buttonStyle(.dsSecondary)
                        Button { store.startGoing() } label: {
                            Label(L.t("去", "去", "Go"), systemImage: "figure.walk").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dsPrimary)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        Button { store.endFind() } label: { Text(L.t("取消", "取消", "Cancel")).frame(maxWidth: .infinity) }
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
            let place = store.landmark(f.landmarkID)?.name ?? L.t("約定地方", "约定地点", "meeting place")
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
                        // 远近都有大箭咀（以前要近先有，UX 评审 19）
                        arrowPill(f, p, place)
                            .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                        FindBottomBar(f: f, place: place)
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
                        Text(L.t("見到\(p.name)喇", "见到\(p.name)了", "Found \(p.name)!"))
                    } else if f.spontaneous {
                        Text(L.t("\(p.name)喺\(place)等你 · 你大約 \(eta) 分鐘到", "\(p.name)在\(place)等你 · 你大约 \(eta) 分钟到", "\(p.name) is waiting at \(place) · you're about \(eta) min away"))
                    } else if !f.partnerOut {
                        // 未收到对方出门通知，唔好讲佢出咗门（A19）。
                        Text(L.t("約咗\(p.name)喺\(place) · 等緊佢出門", "约了\(p.name)在\(place) · 等对方出门", "Meeting \(p.name) at \(place) · waiting for them to set off"))
                    } else if f.etaMinutes == 0 {
                        Text(L.t("\(p.name)已經喺\(place)等你", "\(p.name)已经在\(place)等你", "\(p.name) is already waiting at \(place)"))
                    } else {
                        // 对方仲要几耐到约定地方（按佢剩低嘅路，A67）。
                        Text(L.t("\(p.name)出咗門 · 大約 \(eta) 分鐘到\(place)", "\(p.name)出门了 · 大约 \(eta) 分钟到\(place)", "\(p.name) is out · about \(eta) min to \(place)"))
                    }
                }
                .ds(.bodyBold)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText(value: Double(eta)))
                .animation(DS.motion(DS.snappy), value: eta)
                Spacer(minLength: 0)
                // 「結束」放角落（同「查找」式找人嘅「停止」一样位置，UX 评审 22）
                if f.stage != .met {
                    Button { store.endFind() } label: { Text(L.t("結束", "结束", "End")).lineLimit(1).fixedSize() }
                        .buttonStyle(.dsSecondary)
                }
            }
            if p.isDemo { DemoBadge(text: L.t("示範：對方位置係模擬", "演示：对方位置是模拟的", "Demo: their location is simulated")) }
            if let b = f.broadcast {
                Label {
                    Text(L.t("已話俾\(p.name)知：\(b)", "已告诉\(p.name)：\(b)", "Told \(p.name): \(b)"))
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

    /// 大箭咀 + 距离：近（50 米内）讲「就喺附近」，远讲行路几耐 / 跟住箭咀去约定地方。
    private func arrowPill(_ f: FindSession, _ p: Resident, _ place: String) -> some View {
        let meters = Int(f.distance)
        let near = f.stage == .near
        let sub: String = near ? L.t("\(p.name)就喺附近，跟住箭咀行", "\(p.name)就在附近，跟着箭头走", "\(p.name) is close by. Follow the arrow")
            : !f.spontaneous && !f.partnerOut ? L.t("跟住箭咀去\(place)", "跟着箭头去\(place)", "Follow the arrow to \(place)")
            : L.t("跟住箭咀行，大約 \(max(1, Int((f.distance / 70).rounded(.up)))) 分鐘", "跟着箭头走，大约 \(max(1, Int((f.distance / 70).rounded(.up)))) 分钟", "Follow the arrow, about \(max(1, Int((f.distance / 70).rounded(.up)))) min")
        return HStack(spacing: 16) {
            Image(systemName: "location.north.fill")
                .font(.system(size: near ? 56 : 48, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(arrowAngle))
                .frame(width: near ? 112 : 96, height: near ? 112 : 96)
                .background(DS.accent, in: Circle())
                .shadow(color: DS.accent.opacity(0.4), radius: 10, y: 4)
                .animation(DS.motion(DS.snappy), value: near)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("\(meters) 米", "\(meters) 米", "\(meters) m"))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(meters)))
                    .animation(DS.motion(DS.snappy), value: meters)
                Text(sub)
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .padding(.trailing, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 60, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 60, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("\(p.name)，大約 \(meters) 米。\(sub)", "\(p.name)，大约 \(meters) 米。\(sub)", "\(p.name), about \(meters) metres. \(sub)"))
    }

    private func lateCard(_ p: Resident) -> some View {
        // 冇对方电话号码就唔出「打電話」（撳咗只会话未有号码），叫佢喺附近搵吓。
        let canCall = PhoneBook.number(for: p.id) != nil
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                FSPopSymbol(name: "clock.fill", size: 26, color: DS.accent)
                Text(L.t("過咗約定時間 10 分鐘，仲未見到\(p.name)。", "过了约定时间 10 分钟，还没见到\(p.name)。", "10 minutes past the time and no sign of \(p.name). ")
                     + (canCall ? L.t("要唔要打電話俾佢？", "要不要给对方打电话？", "Give them a call?") : L.t("喺附近搵吓。", "在附近找找。", "Have a look around.")))
                    .ds(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                Button {
                    withAnimation(DS.motion(DS.spring)) { store.find?.latePrompt = false }
                } label: {
                    Text(L.t("再等等", "再等等", "Wait a bit")).frame(maxWidth: canCall ? nil : .infinity)
                }
                .buttonStyle(.dsSecondary)
                if canCall {
                    Button {
                        store.call(p.id)
                        withAnimation(DS.motion(DS.spring)) { store.find?.latePrompt = false }
                    } label: {
                        Label(L.t("打電話", "打电话", "Call"), systemImage: "phone.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsPrimary)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
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
            Text(L.t("見到喇！", "见到了！", "Found them!")).ds(.title)
            Text(L.t("你同\(name)喺\(place)見到面", "你和\(name)在\(place)见面了", "You met \(name) at \(place)"))
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
