import SwiftUI

/// 「查找」式找人画面（真街坊，store.find.live）：顶部「而家同〈網名〉分享緊位置」+ 停止；
/// 中间大箭咀 + 距离 + 大约几分钟（远：GPS + 指南针；近：超宽带，对正咗转绿）；底部同模拟找人同一条底栏（FindBottomBar）。
struct LiveFindOverlay: View {
    @Environment(AppStore.self) private var store
    @State private var arrowAngle: Double = 0

    var body: some View {
        if let f = store.find, let p = store.resident(f.partnerID) {
            let place = store.placeName(f.landmarkID) ?? L.t("附近", "附近")
            ZStack {
                VStack(spacing: 8) {
                    // 見到之后已经停咗分享：唔再显示「分享緊位置」
                    if f.stage != .met { sharingPill(p) }
                    ToastView()
                    Spacer(minLength: 0)
                    if f.stage != .met {
                        compass(f, p, place)
                            .transition(DS.slide(.bottom))
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
            .animation(DS.motion(DS.spring), value: f.liveMode)
            .onAppear { arrowAngle = f.bearing }
            .onChange(of: f.bearing) { old, new in
                // 走最短嘅方向转，跨过 ±180° 唔会成个圈咁转
                var d = (new - old).truncatingRemainder(dividingBy: 360)
                if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                withAnimation(DS.motion(DS.snappy)) { arrowAngle += d }
            }
        }
    }

    /// 「而家同〈網名〉分享緊位置」+ 停止（一撳两边都停）。
    private func sharingPill(_ p: Resident) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: .repeating)
                .frame(width: 44, height: 44)
                .background(DS.accent, in: Circle())
            Text(L.t("而家同\(p.name)分享緊位置", "正在和\(p.name)共享位置"))
                .ds(.bodyBold)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { store.endFind() } label: { Text(L.t("停止", "停止")) }
                .buttonStyle(.dsSecondary)
                .accessibilityLabel(L.t("停止分享位置", "停止共享位置"))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }

    private func title(_ f: FindSession, _ p: Resident, _ place: String) -> String {
        if f.incoming { return L.t("\(p.name)過緊嚟搵你", "\(p.name)正过来找你") }
        if !f.spontaneous { return L.t("約咗\(p.name)喺\(place)", "约了\(p.name)在\(place)") }
        return L.t("去搵\(p.name)", "去找\(p.name)")
    }

    private func compass(_ f: FindSession, _ p: Resident, _ place: String) -> some View {
        let meters = Int(f.distance.rounded())
        let near = f.liveMode == .near
        let color: Color = f.facing ? .green : DS.accent
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                AvatarBadge(p, size: 44)
                Text(title(f, p, place)).ds(.bodyBold).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if f.liveMode == .waiting {
                ProgressView().controlSize(.large).padding(.vertical, 8)
                Text(f.spontaneous ? L.t("等緊\(p.name)嘅位置…", "在等\(p.name)的位置…") : L.t("等緊\(p.name)出門…", "在等\(p.name)出门…"))
                    .ds(.body)
                    .foregroundStyle(.secondary)
            } else if near {
                // 近：大箭咀放中间（同苹果「查找」一样），对正咗转绿
                arrow(color, size: 120, frame: 160)
                distanceText(meters, size: 56)
                Text(subtitle(f, p))
                    .ds(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                hints(f, p)
            } else {
                // 远：箭咀同距离并排，留返位睇场景入面对方大概喺边
                HStack(spacing: 16) {
                    arrow(color, size: 80, frame: 128)
                    VStack(alignment: .leading, spacing: 2) {
                        distanceText(meters, size: 48)
                        Text(subtitle(f, p))
                            .ds(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                hints(f, p)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L.t("\(p.name)，大約 \(meters) 米。\(subtitle(f, p))", "\(p.name)，大约 \(meters) 米。\(subtitle(f, p))"))
    }

    private func arrow(_ color: Color, size: CGFloat, frame: CGFloat) -> some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
            .rotationEffect(.degrees(arrowAngle))
            .frame(width: frame, height: frame)
            .background(color.opacity(0.12), in: Circle())
            .animation(DS.motion(DS.snappy), value: color)
            .accessibilityHidden(true)
    }

    private func distanceText(_ meters: Int, size: CGFloat) -> some View {
        Text(L.t("\(meters) 米", "\(meters) 米"))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(meters)))
            .animation(DS.motion(DS.snappy), value: meters)
    }

    @ViewBuilder
    private func hints(_ f: FindSession, _ p: Resident) -> some View {
        if f.headingPoor && !f.precise {
            Label(L.t("請將手機放平", "请把手机放平"), systemImage: "iphone.gen3")
                .ds(.captionBold)
                .foregroundStyle(DS.accentInk)
        } else if f.sweep {
            Label(L.t("慢慢左右移動手機", "慢慢左右移动手机"), systemImage: "arrow.left.and.right")
                .ds(.captionBold)
                .foregroundStyle(DS.accentInk)
        }
        if f.partnerStale {
            Text(L.t("暫時收唔到\(p.name)嘅最新位置", "暂时收不到\(p.name)的最新位置")).ds(.caption).foregroundStyle(.secondary)
        }
    }

    private func subtitle(_ f: FindSession, _ p: Resident) -> String {
        if f.liveMode == .near {
            if f.facing { return L.t("就喺前面", "就在前面") }
            return f.precise ? L.t("就喺附近，跟住箭咀轉", "就在附近，跟着箭头转") : L.t("就喺附近，四圍望吓", "就在附近，四处看看")
        }
        return L.t("行路大約 \(max(1, f.etaMinutes)) 分鐘", "步行大约 \(max(1, f.etaMinutes)) 分钟")
    }

}

/// 两条找人流程（约会出发、过去搵佢 / 被搵）同一条底栏（UX 评审 22）：
/// 一个主按钮按阶段变「出發喇 → 我就到 → 見到喇」（被搵嗰边「我喺度等你 → 見到喇」），右边咪；「結束 / 停止」喺顶部角落。
struct FindBottomBar: View {
    @Environment(AppStore.self) private var store
    let f: FindSession
    let place: String

    var body: some View {
        let step = store.findStep(f)
        HStack(spacing: 8) {
            Button { store.findStepTapped() } label: {
                Label(store.findStepTitle(step), systemImage: step == .met ? "checkmark.circle.fill" : "speaker.wave.2.fill")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .symbolEffect(.bounce, value: f.broadcast)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
            .accessibilityHint(step == .met ? L.t("見到面就撳，兩邊一齊結束", "见到面就点，两边一起结束") : L.t("撳一下話俾對方知", "点一下告诉对方"))
            MicRoundButton(place: place)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius + 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radius + 4, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .animation(DS.motion(DS.snappy), value: step)
    }
}

/// 找人画面嘅咪（同主画面个咪一样：讲完复述再撳「好」）。
struct MicRoundButton: View {
    @Environment(AppStore.self) private var store
    var place: String

    var body: some View {
        let on = store.listening
        Button { store.micTapped() } label: {
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
        .accessibilityLabel(L.t("講嘢", "说话"))
        .accessibilityValue(on ? L.t("聽緊", "在听") : "")
        .accessibilityHint(on ? L.t("再撳一下講完", "再按一下结束") : L.t("撳一下開始講，例如「我喺\(place)」", "按一下开始说，例如「我在\(place)」"))
    }
}
