import SwiftUI

// 子代理 B：底部卡片的内容。圆角、拉手、背后变暗由 MainView 的底部卡容器负责，这里只出内容。

// MARK: - 约人提议

/// 约人：AI 给的时间 + 地点 + 理由；一个大「好」，「換個時間」「換個地方」各换一个。
struct ProposalCard: View {
    @Environment(AppStore.self) private var store
    @State private var taps = 0
    @State private var cancelling: Appointment?

    var body: some View {
        if let p = store.proposal, p.options.indices.contains(p.index) {
            let current = p.options[p.index]
            let partner = store.resident(p.partnerID)
            let place = store.landmark(current.landmarkID)?.name ?? ""
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    if let partner { AvatarBadge(partner) }
                    Text(p.editing == nil ? "約\(partner?.name ?? "街坊")一齊行" : "改約\(partner?.name ?? "街坊")")
                        .ds(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("\(store.dayTimeLabel(current.date)) · \(place)")
                            .contentTransition(.numericText())
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "calendar").foregroundStyle(DS.accent)
                    }
                    .ds(.bodyBold)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        CardAITag()
                        Text(current.reason)
                            .ds(.caption)
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .animation(DS.motion(DS.spring), value: current)
                .accessibilityElement(children: .combine)

                Button { store.confirmProposal() } label: {
                    Text(p.editing == nil ? "好" : "就咁改").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { changeButtons }
                    VStack(spacing: 12) { changeButtons }
                }

                if let id = p.editing, let a = store.appointments.first(where: { $0.id == id }) {
                    Button { cancelling = a } label: {
                        Text("取消約會").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsSecondary)
                }

                Button {
                    taps += 1
                    store.cancelProposal()
                } label: {
                    Text(p.editing == nil ? "取消" : "唔改喇")
                        .ds(.button)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: taps)
            .cancelMeetupDialog($cancelling)
        }
    }

    @ViewBuilder private var changeButtons: some View {
        Button { store.nextProposalTime() } label: {
            Text("換個時間").frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
        Button { store.nextProposalPlace() } label: {
            Text("換個地方").frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
    }
}

// MARK: - 点场景里的地标 / 人

/// 点地标：名字、有冇櫈、而家遮蔭几成、「改名」；点人：喺边、「約佢行」或「過去搵佢」。
struct InfoCard: View {
    @Environment(AppStore.self) private var store
    @State private var taps = 0

    var body: some View {
        Group {
            switch store.selection {
            case .landmark(let id):
                if let lm = store.landmark(id) { landmarkView(lm) }
            case .person(let id):
                if let r = store.resident(id) { personView(r) }
            case nil:
                EmptyView()
            }
        }
        .sensoryFeedback(.selection, trigger: taps)
    }

    private var closeButton: some View {
        Button { store.select(nil) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("收埋")
    }

    // 地标

    private func landmarkView(_ lm: Landmark) -> some View {
        let renaming = store.renaming == lm.id
        let shade = Int(((store.shade?.shade(landmarkID: lm.id, at: store.now) ?? 0) * 100).rounded())
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Text(lm.name)
                    .ds(.title)
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                closeButton
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { facts(lm, shade: shade) }
                VStack(alignment: .leading, spacing: 8) { facts(lm, shade: shade) }
            }

            if renaming {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.community.sharesLandmarkNames ? "揀個新名，同圈街坊都會見到" : "揀個新名（暫時只喺你部手機）")
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(store.ai.alternativeNames(for: lm), id: \.self) { name in
                        Button { store.rename(lm.id, to: name) } label: {
                            Text(name).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dsSecondary)
                    }
                    Button { store.micTapped() } label: {
                        Label {
                            Text(store.listening ? "聽緊，講完再撳" : "講新名")
                        } icon: {
                            Image(systemName: store.listening ? "waveform" : "mic.fill")
                                .foregroundStyle(DS.accent)
                                .symbolEffect(.variableColor.iterative, isActive: store.listening)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsSecondary)
                    Button {
                        taps += 1
                        store.renaming = nil
                    } label: {
                        Text("唔改喇")
                            .ds(.button)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .transition(DS.slide(.bottom))
            } else {
                Button {
                    taps += 1
                    store.renaming = lm.id
                } label: {
                    Label("改名", systemImage: "pencil").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
                .transition(.opacity)
            }
        }
        .animation(DS.motion(DS.spring), value: renaming)
        .animation(DS.motion(DS.spring), value: lm.name)
    }

    @ViewBuilder private func facts(_ lm: Landmark, shade: Int) -> some View {
        CardFact(symbol: lm.hasSeat ? "chair.lounge.fill" : "chair.lounge", text: lm.hasSeat ? "有櫈" : "冇櫈")
        let fact = store.shadeFact(lm.id)
        CardFact(symbol: fact.symbol, text: fact.text)
            .contentTransition(.numericText(value: Double(shade)))
            .animation(DS.motion(DS.snappy), value: shade)
    }

    // 人

    private func personView(_ r: Resident) -> some View {
        let walking = store.walk != nil
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                AvatarBadge(r, size: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(for: r))
                        .ds(.bodyBold)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(whereText(for: r))
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                closeButton
            }

            if r.isNeighbor && !r.isMe {
                if !r.todayLine.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        CardAITag()
                        Text(r.todayLine)
                            .ds(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if walking && r.isOut {
                    Button {
                        store.select(nil)
                        store.goFind(r.id)
                    } label: {
                        Label("過去搵佢", systemImage: "figure.walk").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsPrimary)
                } else {
                    Button {
                        store.select(nil)
                        store.proposeMeetup(with: r.id)
                    } label: {
                        Label("約佢行", systemImage: "calendar").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsPrimary)
                }
            } else if !r.isMe {
                Text("見到面碰一碰做咗街坊，先可以約佢。")
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 网名；街坊加座数楼层（非街坊永远唔出座数楼层，2026-10-10 定）。
    private func title(for r: Resident) -> String { r.listName }

    private func whereText(for r: Resident) -> String {
        if r.isMe { return store.walk != nil ? "行緊" : "喺屋企 · 已隱身" }
        guard r.isNeighbor else { return "仲未係你街坊" }
        if r.isOut, let place = store.placeName(r.atLandmarkID) { return "喺\(place)附近" }
        return "冇出門消息"   // 不断言「喺屋企」
    }
}

// MARK: - 碰一碰后：开唔开出门提醒

/// 碰一碰成功：庆祝一下，只问一次「開唔開出門提醒」。
struct RemindPrompt: View {
    @Environment(AppStore.self) private var store
    @State private var appeared = false
    @State private var bounce = 0
    @State private var choice = 0

    var body: some View {
        if let id = store.remindPromptFor, let r = store.resident(id) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    AvatarBadge(r, size: 64)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, DS.accent)
                                .font(.system(size: 28, weight: .bold))
                                .background(Circle().fill(Color(.systemBackground)).padding(2))
                                .symbolEffect(.bounce, value: bounce)
                                .scaleEffect(appeared ? 1 : 0.2)
                                .opacity(appeared ? 1 : 0)
                                .offset(x: 6, y: 6)
                                .accessibilityHidden(true)
                        }
                    Text("你同\(r.floorLabel)\(r.name)而家係街坊")
                        .ds(.bodyBold)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                Text("開唔開出門提醒？開咗之後，佢出門你會知，你出門佢都會知（只講地標）。")
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    choice += 1
                    store.createNeighbor(id, remind: true)
                } label: {
                    Label("開", systemImage: "bell.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)

                Button {
                    choice += 1
                    store.createNeighbor(id, remind: false)
                } label: {
                    Text("遲啲先").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsSecondary)
            }
            .sensoryFeedback(.selection, trigger: choice)
            .onAppear {
                appeared = false
                withAnimation(DS.motion(DS.bouncy).delay(0.1)) { appeared = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    bounce += 1
                }
            }
        }
    }
}

// MARK: - 本文件用的小部件

/// 地标小事实：图标 + 一句，胶囊底。
private struct CardFact: View {
    let symbol: String
    let text: String
    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(DS.accent)
        }
        .ds(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// 小小的「AI」标签：表示这句是 AI 写的（共用 AIBadge，辅助字号 20）。
private struct CardAITag: View {
    var body: some View { AIBadge() }
}
