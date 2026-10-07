import SwiftUI

// MARK: - 碰一碰等待画面

/// MainView 在 bumpStage == .searching 时全屏显示；找到对方后由 MainView 关掉。
struct BumpView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            LinearGradient(colors: [Color(.systemBackground), DS.accent.opacity(0.10)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer(minLength: 0)

                FSBumpIllustration()
                    .frame(height: 280)
                    .accessibilityElement()
                    .accessibilityLabel("碰一碰：將你部手機貼近對方部手機，就會加做街坊")

                VStack(spacing: 16) {
                    Text("將手機貼近對方手機")
                        .ds(.title)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("搵緊附近嘅人…")
                            .ds(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                Spacer(minLength: 0)

                Button { store.cancelBump() } label: {
                    Text("取消").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsSecondary)
            }
            .padding(.horizontal, DS.side)
            .padding(.bottom, 16)
        }
        .onAppear { store.speaker.speak("將手機貼近對方手機。") }
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
                    AvatarBadge(color: p.color, mobility: p.mobility, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("問緊\(p.name)").ds(.bodyBold)
                        Text("「\(store.me.floorLabel)想過嚟搵你，喺\(place)等陣？」")
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if agreed {
                    Label {
                        Text("\(p.name)話好：喺\(place)等你").ds(.bodyBold)
                    } icon: {
                        FSPopSymbol(name: "checkmark.circle.fill", size: 26, color: DS.accent)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
        if let f = store.find, let p = store.resident(f.partnerID) {
            let place = store.landmark(f.landmarkID)?.name ?? "約定地方"
            ZStack {
                VStack(spacing: 8) {
                    topCard(f, p, place)
                    Spacer(minLength: 0)
                    if f.latePrompt && f.stage != .met {
                        lateCard(p)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if f.stage != .met {
                        if f.stage == .near {
                            nearPill(f, p)
                                .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                        }
                        bottomBar(f, place)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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
                AvatarBadge(color: p.color, mobility: p.mobility, size: 52)
                Group {
                    if f.stage == .met {
                        Text("見到\(p.name)喇")
                    } else if f.spontaneous {
                        Text("\(p.name)喺\(place)等你 · 大約 \(eta) 分鐘")
                    } else {
                        Text("\(p.name)出咗門 · 大約 \(eta) 分鐘到\(place)")
                    }
                }
                .ds(.bodyBold)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText(value: Double(eta)))
                .animation(DS.motion(DS.snappy), value: eta)
                Spacer(minLength: 0)
            }
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
                .transition(.move(edge: .top).combined(with: .opacity))
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

    private func bottomBar(_ f: FindSession, _ place: String) -> some View {
        HStack(spacing: 8) {
            Button { store.endFind() } label: { Text("結束") }
                .buttonStyle(.dsSecondary)
            Button { store.broadcastHere() } label: {
                Label(f.spontaneous ? "我就到" : "我喺\(place)", systemImage: "speaker.wave.2.fill")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .symbolEffect(.bounce, value: f.broadcast)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.radius + 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radius + 4, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

/// 相遇：对勾弹一下 + "見到喇！"。store 3 秒后自动结束。
private struct FSMetCelebration: View {
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
