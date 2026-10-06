import SwiftUI

// 覆盖层：场景标签、灵动岛式横幅、提示、语音卡。

// MARK: - 场景标签

/// 跟随 3D 投影的标签。坐标 = 场景视图的本地坐标（OverlayItem.point，每秒 30 次）。
/// 位置不做动画，只在出现时弹一下；重叠时只留优先级高的。
struct SceneLabelsLayer: View {
    @Environment(AppStore.self) private var store
    /// 不放标签的区域（状态栏、左右上胶囊、咪）。
    var reserved: [CGRect] = []
    @ScaledMetric(relativeTo: .callout) private var fontSize: CGFloat = 20

    var body: some View {
        // 在 GeometryReader 闭包外读取状态，保证 Observation 能追踪到。
        let focus = focusIDs
        let items = store.scene.overlay.items
        GeometryReader { geo in
            let shown = placed(items, in: CGRect(origin: .zero, size: geo.size), focus: focus)
            ZStack(alignment: .topLeading) {
                ForEach(shown) { item in
                    SceneLabel(item: item,
                               emphasized: item.highlighted || focus.contains(item.id),
                               dot: dotColor(item),
                               action: action(for: item))
                        .fixedSize()
                        .frame(width: 0, height: 0, alignment: item.kind == .report ? .center : .bottom)
                        .position(item.point)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    /// 当前要露出名字的地标：选中的、约人提议的、找人目的地。
    private var focusIDs: Set<String> {
        var s: Set<String> = []
        if case .landmark(let id) = store.selection { s.insert("l:\(id)") }
        if let p = store.proposal, p.options.indices.contains(p.index) { s.insert("l:\(p.options[p.index].landmarkID)") }
        if let f = store.find { s.insert("l:\(f.landmarkID)") }
        return s
    }

    private func placed(_ items: [OverlayItem], in bounds: CGRect, focus: Set<String>) -> [OverlayItem] {
        let candidates = items
            .filter { $0.kind != .landmark || $0.highlighted || focus.contains($0.id) }
            .sorted { a, b in
                // 高亮的人（约的对象、找的人）最重要，其次是焦点地标。
                func rank(_ x: OverlayItem) -> Int { x.kind == .person && x.highlighted ? 5 : (focus.contains(x.id) ? 4 : x.priority) }
                let pa = rank(a), pb = rank(b)
                return pa != pb ? pa > pb : a.id < b.id
            }
        var taken = reserved
        var out: [OverlayItem] = []
        for item in candidates {
            let r = rect(for: item)
            guard r.intersects(bounds), !taken.contains(where: { $0.intersects(r) }) else { continue }
            taken.append(r.insetBy(dx: -3, dy: -3))
            out.append(item)
        }
        return out
    }

    /// 估算标签大小（只用来判断重叠）。
    private func rect(for item: OverlayItem) -> CGRect {
        let p = item.point
        if item.kind == .report { return CGRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32) }
        let textW = item.text.reduce(CGFloat(0)) { $0 + ($1.isASCII ? fontSize * 0.58 : fontSize) }
        let w = textW + 24 + fontSize + 6
        let h = max(36, fontSize * 1.25 + 10)
        return CGRect(x: p.x - w / 2, y: p.y - h, width: w, height: h)
    }

    private func dotColor(_ item: OverlayItem) -> Color? {
        guard item.kind == .person else { return nil }
        return store.resident(String(item.id.dropFirst(2)))?.color ?? DS.accent
    }

    private func action(for item: OverlayItem) -> (() -> Void)? {
        switch item.kind {
        case .landmark:
            let id = String(item.id.dropFirst(2))
            return { [store] in if store.uiSceneTapsEnabled { store.select(.landmark(id)) } }
        case .person:
            let id = String(item.id.dropFirst(2))
            guard id != "me" else { return nil }
            return { [store] in if store.uiSceneTapsEnabled { store.select(.person(id)) } }
        case .home, .report:
            return nil
        }
    }
}

private struct SceneLabel: View {
    let item: OverlayItem
    let emphasized: Bool
    let dot: Color?
    let action: (() -> Void)?
    @State private var appeared = false

    var body: some View {
        Group {
            if let action {
                Button(action: action) { face }
                    .buttonStyle(.plain)
                    .accessibilityHint("撳一下睇詳情")
            } else {
                face
            }
        }
        .scaleEffect(appeared ? 1 : 0.6, anchor: item.kind == .report ? .center : .bottom)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(DS.motion(DS.snappy)) { appeared = true } }
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var face: some View {
        if item.kind == .report {
            Image(systemName: Self.reportSymbol(item.text))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DS.accent)
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(DS.accent.opacity(0.55), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        } else {
            HStack(spacing: 6) {
                leading
                Text(item.text).lineLimit(1)
            }
            .ds(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(emphasized ? DS.accent : Color.primary.opacity(0.1), lineWidth: emphasized ? 2 : 1))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch item.kind {
        case .person:
            Circle().fill(dot ?? DS.accent).frame(width: 10, height: 10)
        case .landmark:
            Image(systemName: "mappin.circle.fill").foregroundStyle(DS.accent)
        case .home:
            Image(systemName: "eye.slash.fill").foregroundStyle(.secondary)
        case .report:
            EmptyView()
        }
    }

    private var accessibilityText: String {
        switch item.kind {
        case .person: return "街坊：\(item.text)"
        case .landmark: return "地標：\(item.text)"
        case .home: return item.text
        case .report: return "街坊反映：\(item.text)"
        }
    }

    static func reportSymbol(_ text: String) -> String {
        switch ReportKind(rawValue: text) {
        case .sunny: return "sun.max.fill"
        case .noSeat: return "chair"
        case .rough, .none: return "exclamationmark"
        }
    }
}

// MARK: - 灵动岛式横幅

/// 出门提醒、约会应承、天气提示。从顶部小胶囊（传感器位置）弹性展开成大卡片，收起时缩回胶囊。
/// 点卡片或向上扫 = 关掉；有按钮时按钮执行动作。
struct BannerView: View {
    @Environment(AppStore.self) private var store
    @State private var shown: BannerItem?
    @State private var expanded = false
    @State private var drag: CGFloat = 0

    private let pill = CGSize(width: 126, height: 37)
    private let edge: CGFloat = 11

    var body: some View {
        ZStack(alignment: .top) {
            if let b = shown {
                island(b)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { sync(store.banner) }
        .onChange(of: store.banner) { _, new in sync(new) }
    }

    private func sync(_ new: BannerItem?) {
        if let new {
            if shown != nil {
                withAnimation(DS.motion(DS.snappy)) { shown = new; expanded = true; drag = 0 }
                return
            }
            if DS.reduceMotion {
                withAnimation(DS.motion(DS.spring)) { shown = new; expanded = true; drag = 0 }
                return
            }
            // 先以胶囊出现（不做动画），下一帧弹开。
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { shown = new; expanded = false; drag = 0 }
            DispatchQueue.main.async {
                guard store.banner?.id == new.id else { return }
                withAnimation(DS.bouncy) { expanded = true }
            }
        } else {
            guard shown != nil else { return }
            if DS.reduceMotion {
                withAnimation(DS.motion(DS.spring)) { shown = nil; expanded = false; drag = 0 }
                return
            }
            withAnimation(DS.spring, completionCriteria: .logicallyComplete) {
                expanded = false
                drag = 0
            } completion: {
                guard store.banner == nil else { return }
                withAnimation(DS.snappy) { shown = nil }
            }
        }
    }

    private func island(_ b: BannerItem) -> some View {
        let shape = RoundedRectangle(cornerRadius: expanded ? 28 : pill.height / 2, style: .continuous)
        return content(b)
            .containerRelativeFrame(.horizontal) { w, _ in max(0, w - 2 * edge) }
            .fixedSize(horizontal: false, vertical: true)
            .opacity(expanded ? 1 : 0)
            .scaleEffect(expanded ? 1 : 0.4, anchor: .top)
            .blur(radius: expanded ? 0 : 8)
            .frame(width: expanded ? nil : pill.width, height: expanded ? nil : pill.height, alignment: .top)
            .background(Color.black, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(expanded ? 0.1 : 0), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(expanded ? 0.28 : 0), radius: 18, y: 8)
            .contentShape(shape)
            .onTapGesture { store.banner = nil }
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { v in
                        let dy = v.translation.height
                        drag = dy < 0 ? dy : dy * 0.15   // 向下拉有阻尼
                    }
                    .onEnded { v in
                        if v.translation.height < -24 || v.predictedEndTranslation.height < -80 {
                            store.banner = nil
                        } else {
                            withAnimation(DS.motion(DS.snappy)) { drag = 0 }
                        }
                    }
            )
            .offset(y: drag)
            .padding(.top, edge)
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "關閉") { store.banner = nil }
    }

    private func content(_ b: BannerItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: b.symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .symbolEffect(.bounce, options: .nonRepeating, value: expanded)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                Text(b.text)
                    .ds(.body)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let title = b.actionTitle, b.action != .none {
                Button { store.bannerAction() } label: {
                    Text(title).frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
            }
        }
        // 顶部留出摄像头（灵动岛）的位置：黑色外框包住它，文字从它下面开始。
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 46)
    }
}

// MARK: - 提示

/// 一句话的轻提示（位置由外层决定：主界面在标签栏之上）。
struct ToastView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            if let t = store.toast {
                Text(t)
                    .ds(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    .padding(.horizontal, DS.side)
                    .id(t)
                    .transition(DS.reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.9)).combined(with: .offset(y: 16)))
            }
        }
        .animation(DS.motion(DS.spring), value: store.toast)
    }
}

// MARK: - 语音卡（放在底部卡片槽里）

/// 三种状态：聽緊（实时字幕）→ 我聽到（复述 + 确认/撤回）；听不明白或没权限时「揀一句」。
struct VoiceOverlay: View {
    @Environment(AppStore.self) private var store

    private enum Mode: Equatable { case listening, picker, heard(UUID), none }

    private var mode: Mode {
        if store.listening { return .listening }
        if store.phrasePicker { return .picker }
        if let c = store.voiceCard { return .heard(c.id) }
        return .none
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch mode {
            case .listening:
                ListeningCard(listener: store.listener)
                    .transition(.opacity)
            case .picker:
                PhrasePickerCard()
                    .transition(.opacity)
            case .heard:
                if let card = store.voiceCard {
                    HeardCard(card: card)
                        .id(card.id)
                        .transition(.opacity)
                }
            case .none:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(DS.motion(DS.spring), value: mode)
    }
}

fileprivate extension AppStore {
    /// 按常用说法 = 讲了那句。如果正在听，先停咪。
    func pickPhrase(_ phrase: String) {
        if listening { listener.stop() }
        handle(phrase)
    }
}

private struct ListeningCard: View {
    @Environment(AppStore.self) private var store
    @ObservedObject var listener: Listener

    var body: some View {
        let phrases = store.suggestedPhrases
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text("聽緊…").ds(.title)
                Spacer(minLength: 0)
                VoiceBars()
            }
            Text(listener.transcript.isEmpty ? "講啦，例如「\(phrases.first ?? "今日請假")」" : "「\(listener.transcript)」")
                .ds(.body)
                .foregroundStyle(listener.transcript.isEmpty ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                .contentTransition(.opacity)
                .animation(DS.motion(DS.snappy), value: listener.transcript)
                .accessibilityAddTraits(.updatesFrequently)
            Button { store.stopListening() } label: {
                Label("講完", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
            if !phrases.isEmpty {
                Text("或者揀一句").ds(.caption).foregroundStyle(.secondary)
                ChipFlow(spacing: DS.gap) {
                    ForEach(phrases, id: \.self) { p in
                        Button { store.pickPhrase(p) } label: {
                            Text(p)
                                .ds(.caption)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(minHeight: 44)
                                .background(DS.accentSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// 聆听时跳动的声波条。
private struct VoiceBars: View {
    private let count = 5

    var body: some View {
        Group {
            if DS.reduceMotion {
                bars(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                    bars(at: ctx.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(height: 40)
        .accessibilityHidden(true)
    }

    private func bars(at t: Double) -> some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                let wave = abs(sin(t * 3.4 + Double(i) * 0.9)) * 0.7 + abs(sin(t * 1.7 + Double(i) * 1.6)) * 0.3
                Capsule()
                    .fill(DS.accent)
                    .frame(width: 6, height: 10 + 28 * CGFloat(t == 0 ? 0.5 : wave))
            }
        }
    }
}

private struct PhrasePickerCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("揀一句").ds(.title)
                Spacer(minLength: 0)
                Button { store.phrasePicker = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("關閉")
            }
            Text("撳一句，等於講咗嗰句").ds(.caption).foregroundStyle(.secondary)
            ForEach(store.suggestedPhrases, id: \.self) { p in
                Button { store.pickPhrase(p) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "quote.bubble").foregroundStyle(DS.accent)
                        Text(p).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.dsSecondary)
            }
        }
    }
}

private struct HeardCard: View {
    @Environment(AppStore.self) private var store
    let card: VoiceCard
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("我聽到").ds(.caption).foregroundStyle(.secondary)
            Text("「\(card.heard)」").ds(.body)
            HStack(alignment: .firstTextBaseline, spacing: DS.gap) {
                if !card.needsConfirm {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.accent)
                        .symbolEffect(.bounce, options: .nonRepeating, value: appeared)
                        .accessibilityLabel("做咗")
                }
                Text(card.title).ds(.bodyBold)
                AITag()
            }
            if let d = card.detail, !d.isEmpty {
                Text(d).ds(.caption).foregroundStyle(.secondary)
            }
            if card.needsConfirm {
                HStack(spacing: 12) {
                    Button("唔係") { store.rejectVoice() }
                        .buttonStyle(.dsSecondary)
                    Button { store.confirmVoice() } label: {
                        Text("好").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsPrimary)
                }
                .padding(.top, 4)
            } else {
                HStack {
                    Spacer(minLength: 0)
                    Button { store.rejectVoice() } label: {
                        Label("撤回", systemImage: "arrow.uturn.backward")
                            .ds(.captionBold)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.22)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: card.id) {
            appeared = true
            guard !card.needsConfirm else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled, store.voiceCard?.id == card.id { store.voiceCard = nil }
        }
    }
}

/// 标明这段内容由 AI 得出。
private struct AITag: View {
    var body: some View {
        Text("AI")
            .ds(.captionBold)
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(DS.accentSoft, in: Capsule())
            .accessibilityLabel("AI 理解")
    }
}

/// 自动换行的胶囊排列。
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
            if x > 0, x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(sz.width, bounds.width), height: sz.height))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
