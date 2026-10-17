import SwiftUI

// 子代理 B：底部卡片的内容。圆角、拉手、背后变暗由 MainView 的底部卡容器负责，这里只出内容。

// MARK: - 约人提议

/// 约人：AI 给的时间 + 地点 + 理由；一个大「好」，「換個時間」「換個地方」各换一个。
/// 改约（editing）：一打开就揀好一个唔同嘅时间，时间用几个大选项直接揀；卡上只有「發俾XX」同「唔改喇」（UX 评审 12）。
struct ProposalCard: View {
    @Environment(AppStore.self) private var store
    @State private var taps = 0
    @State private var cancelling: Appointment?
    @State private var customizing = false

    var body: some View {
        if let p = store.proposal, p.options.indices.contains(p.index) {
            Group {
                if let id = p.editing, let a = store.appointments.first(where: { $0.id == id }) {
                    editingCard(p, a)
                } else {
                    newCard(p)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: taps)
            .cancelMeetupDialog($cancelling)
            .sheet(isPresented: $customizing) {
                CustomMeetupSheet(initial: p.options[p.index]).environment(store)
            }
        }
    }

    // MARK: 新约

    private func newCard(_ p: Proposal) -> some View {
        let current = p.options[p.index]
        let partner = store.resident(p.partnerID)
        let place = store.landmark(current.landmarkID)?.name ?? ""
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let partner { AvatarBadge(partner) }
                Text(L.t("約\(partner?.name ?? "街坊")一齊行", "约\(partner?.name ?? "邻居")一起走", "Invite \(partner?.name ?? "a neighbour") for a walk"))
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
                Text(current.reason)
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(DS.motion(DS.spring), value: current)
            .accessibilityElement(children: .combine)

            // 测试反馈：时间地点要可以撳入去自己揀，行几耐都可以喺度定
            Button { customizing = true } label: {
                Label(L.t("自己揀時間、地點、行幾耐", "自己选时间、地点、走多久", "Choose time, place, how long"), systemImage: "slider.horizontal.3")
                    .ds(.captionBold)
                    .foregroundStyle(DS.accentInk)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { store.confirmProposal() } label: {
                Text(L.t("好", "好", "OK")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { changeButtons }
                VStack(spacing: 12) { changeButtons }
            }

            closeLink(L.t("取消", "取消", "Cancel"))
        }
    }

    @ViewBuilder private var changeButtons: some View {
        Button { store.nextProposalTime() } label: {
            Text(L.t("換個時間", "换个时间", "Other time")).lineLimit(1).fixedSize().frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
        Button { store.nextProposalPlace() } label: {
            Text(L.t("換個地方", "换个地方", "Other place")).lineLimit(1).fixedSize().frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
    }

    // MARK: 改约 / 回覆邀请换时间

    private func editingCard(_ p: Proposal, _ a: Appointment) -> some View {
        let current = p.options[p.index]
        let partner = store.resident(p.partnerID)
        let name = partner?.name ?? L.t("街坊", "邻居", "Neighbour")
        let place = store.landmark(current.landmarkID)?.name ?? ""
        let replying = a.fromPartner && a.status == .waiting
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let partner { AvatarBadge(partner) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(replying ? L.t("同\(name)改時間", "和\(name)改时间", "New time with \(name)") : L.t("改約\(name)", "改约\(name)", "Change plan with \(name)"))
                        .ds(.bodyBold)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L.t("原本：\(store.dayTimeLabel(a.date)) · \(store.placeName(a.landmarkID) ?? "")", "原本：\(store.dayTimeLabel(a.date)) · \(store.placeName(a.landmarkID) ?? "")", "Was: \(store.dayTimeLabel(a.date)) · \(store.placeName(a.landmarkID) ?? "")"))
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("揀個新時間", "选个新时间", "Pick a new time")).ds(.captionBold)
                ForEach(Array(p.options.enumerated()), id: \.offset) { i, o in
                    timeOption(o, selected: i == p.index, original: o.date == a.date) { store.pickProposalOption(i) }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place).ds(.body).contentTransition(.opacity)
                        Text(current.reason).ds(.caption).foregroundStyle(.secondary).contentTransition(.opacity)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(DS.accent)
                }
                .ds(.body)
                Spacer(minLength: 0)
                Button { store.nextProposalPlace() } label: {
                    Text(L.t("換地方", "换地方", "Other place"))
                        .ds(.captionBold)
                        .foregroundStyle(DS.accentInk)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .animation(DS.motion(DS.spring), value: current)

            Button { store.confirmProposal() } label: {
                Label(L.t("發俾\(name)", "发给\(name)", "Send to \(name)"), systemImage: "paperplane.fill").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)

            closeLink(L.t("唔改喇", "不改了", "No change"))

            // 自己嘅约会：取消放最底、细字（回覆别人嘅邀请就用「唔去」，唔使喺呢度出）
            if !replying {
                Button { cancelling = a } label: {
                    Text(L.t("取消約會", "取消约会", "Cancel walk plan"))
                        .ds(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 一个时间选项：成行撳得，揀咗嘅有橙色框。
    private func timeOption(_ o: MeetProposal, selected: Bool, original: Bool, pick: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button(action: pick) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? DS.accent : Color.secondary)
                Text(original ? L.t("\(store.dayTimeLabel(o.date))（原本）", "\(store.dayTimeLabel(o.date))（原本）", "\(store.dayTimeLabel(o.date)) (was)") : store.dayTimeLabel(o.date))
                    .ds(selected ? .bodyBold : .body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(selected ? DS.accentSoft : Color.clear, in: shape)
            .overlay(shape.strokeBorder(selected ? DS.accent : Color.primary.opacity(0.18), lineWidth: selected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func closeLink(_ text: String) -> some View {
        Button {
            taps += 1
            store.cancelProposal()
        } label: {
            Text(text)
                .ds(.button)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 点场景里的地标 / 人

/// 点地标：名字、有冇櫈、而家有冇陰（普通文字，唔似掣）、「約街坊喺度」（主按钮）；点人：喺边、「約佢行」或「過去搵佢」。
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
        .accessibilityLabel(L.t("收埋", "收起", "Close"))
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

            // 测试反馈：「没凳子」「太阳下山了」做成胶囊似掣、以为撳得 → 改成普通说明文字，前面讲明「呢度而家」
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("呢度而家：", "这里现在：", "Here now:"))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                facts(lm, shade: shade)
                // B-4：测试员问「系咪真嘅？」→ 讲明两行点嚟
                Text(factSource)
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .accessibilityElement(children: .combine)

            if renaming {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.community.sharesLandmarkNames ? L.t("揀個新名，同圈街坊都會見到", "选个新名字，同圈邻居都会看到", "Pick a new name. Neighbours in your circle will see it") : L.t("揀個新名（暫時只喺你部手機）", "选个新名字（暂时只在你手机上）", "Pick a new name (only on your phone for now)"))
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
                            Text(store.listening ? L.t("聽緊，講完再撳", "在听，说完再按", "Listening, tap when done") : L.t("講新名", "说新名字", "Say a new name"))
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
                        Text(L.t("唔改喇", "不改了", "No change"))
                            .ds(.button)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .transition(DS.slide(.bottom))
            } else {
                // 测试反馈：「改名」唔知做咩用 → 拎走入口（讲「改名叫…」仍然得）
                meetHereButton(lm)
                .transition(.opacity)
            }
        }
        .animation(DS.motion(DS.spring), value: renaming)
        .animation(DS.motion(DS.spring), value: lm.name)
    }

    /// 主按钮：「約街坊喺度」（一个街坊就直接写佢个名；几个就先揀边个）；未有街坊：「出去行吓」。
    @ViewBuilder private func meetHereButton(_ lm: Landmark) -> some View {
        let ns = store.neighbors
        if ns.isEmpty {
            Button {
                taps += 1
                store.select(nil)
                if store.demoMode { store.startWalk() } else { store.toast(L.t("出門去\(lm.name)行吓啦，返到屋企會自動記低。", "出门去\(lm.name)走走吧，回到家会自动记下。", "Go out to \(lm.name) for a walk. It's saved when you get home.")) }
            } label: {
                Label(L.t("出去行吓", "出去走走", "Go for a walk"), systemImage: "figure.walk").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
        } else if ns.count == 1, let n = ns.first {
            Button {
                taps += 1
                store.select(nil)
                store.proposeMeetup(with: n.id, landmarkID: lm.id)
            } label: {
                Label(L.t("約\(n.name)喺度", "约\(n.name)在这里", "Meet \(n.name) here"), systemImage: "calendar").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
        } else {
            Menu {
                ForEach(ns) { n in
                    Button(n.name) {
                        taps += 1
                        store.select(nil)
                        store.proposeMeetup(with: n.id, landmarkID: lm.id)
                    }
                }
            } label: {
                Label(L.t("約街坊喺度", "约邻居在这里", "Meet a neighbour here"), systemImage: "calendar").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
            }
            .menuStyle(.button)
            .buttonStyle(.dsPrimary)
        }
    }

    /// 「有冇櫈」「曬唔曬」点嚟：櫈系地图资料（OpenStreetMap 标咗凳、涼亭、公园等），曬唔曬系按太阳位置同模型入面嘅楼影即时计。
    /// 示例屋邨、演示时间都讲明。
    private var factSource: String {
        let sample = store.mapSource == .fallback ? L.t("示範資料：示例屋邨，唔係你附近。", "示范数据：示例屋邨，不是你家附近。", "Demo data: a sample estate, not near you.") : ""
        let sun = store.demoHour != nil ? L.t("按演示時間太陽位置", "按演示时间太阳位置", "sun position at demo time") : L.t("按而家太陽位置", "按现在太阳位置", "sun position now")
        return sample + L.t("櫈：睇地圖資料；曬唔曬：\(sun)同樓影推算，大約準。",
                            "凳子：看地图资料；晒不晒：\(sun)和楼影推算，大概准。", "Seats: from map data. Sun: \(sun) and building shadows, roughly right.")
    }

    @ViewBuilder private func facts(_ lm: Landmark, shade: Int) -> some View {
        CardFact(symbol: lm.hasSeat ? "chair.lounge.fill" : "chair.lounge", text: lm.hasSeat ? L.t("有櫈可以坐", "有凳子可以坐", "Seats here") : L.t("冇櫈坐", "没有凳子坐", "No seats"))
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
                    Text(r.todayLine)
                        .ds(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if walking && r.isOut {
                    Button {
                        store.select(nil)
                        store.goFind(r.id)
                    } label: {
                        Label(L.t("過去搵佢", "过去找他", "Go and find them"), systemImage: "figure.walk").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsPrimary)
                } else {
                    Button {
                        store.select(nil)
                        store.proposeMeetup(with: r.id)
                    } label: {
                        Label(L.t("約佢行", "约他散步", "Invite for a walk"), systemImage: "calendar").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsPrimary)
                }
            } else if !r.isMe {
                Text(L.t("見到面碰一碰做咗街坊，先可以約佢。", "见面碰一碰成了邻居，才可以约他。", "Tap phones when you meet to become neighbours, then you can invite them."))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 网名；街坊加座数楼层（非街坊永远唔出座数楼层，2026-10-10 定）。
    private func title(for r: Resident) -> String { r.listName }

    private func whereText(for r: Resident) -> String {
        if r.isMe { return store.walk != nil ? L.t("行緊", "在散步", "Out for a walk") : L.t("喺屋企（街坊睇唔到你）", "在家（邻居看不到你）", "At home (neighbours can't see you)") }
        guard r.isNeighbor else { return L.t("仲未係你街坊", "还不是你的邻居", "Not your neighbour yet") }
        if r.isOut, let place = store.placeName(r.atLandmarkID) { return L.t("喺\(place)附近", "在\(place)附近", "Near \(place)") }
        return L.t("冇出門消息", "没有出门消息", "No out-and-about news")   // 不断言「喺屋企」
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
                    Text(L.t("你同\(r.floorLabel)\(r.name)而家係街坊", "你和\(r.floorLabel)\(r.name)现在是邻居了", "You and \(r.name)\(r.floorLabel.isEmpty ? "" : " (\(r.floorLabel))") are neighbours now"))
                        .ds(.bodyBold)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                Text(L.t("開唔開出門提醒？開咗之後，佢出門你會知，你出門佢都會知（只講地標）。", "要开出门提醒吗？开了之后，他出门你会知道，你出门他也会知道（只说地标）。", "Turn on out-and-about alerts? Then you'll know when they go out, and they'll know when you do (landmark only)."))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    choice += 1
                    store.createNeighbor(id, remind: true)
                } label: {
                    Label(L.t("開", "开", "Turn on"), systemImage: "bell.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)

                Button {
                    choice += 1
                    store.createNeighbor(id, remind: false)
                } label: {
                    Text(L.t("遲啲先", "以后再说", "Later")).frame(maxWidth: .infinity)
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
        .ds(.body)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}


// MARK: - 自己揀时间地点

/// 约人卡「自己揀」：日期时间（15 分钟一格，由而家到两个星期后）、地点（附近地标）、一齐行几耐。
struct CustomMeetupSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var landmarkID: String
    @State private var minutes = 30
    private static let durations = [15, 30, 45, 60, 90]

    init(initial: MeetProposal) {
        _date = State(initialValue: initial.date)
        _landmarkID = State(initialValue: initial.landmarkID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(L.t("時間", "时间", "Time"), selection: $date,
                               in: store.now...store.now.addingTimeInterval(14 * 86400),
                               displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .tint(DS.accent)
                } header: { Text(L.t("幾時", "什么时候", "When")).ds(.caption) }

                Section {
                    Picker(L.t("地點", "地点", "Place"), selection: $landmarkID) {
                        ForEach(store.landmarks) { lm in
                            Text(lm.hasSeat ? L.t("\(lm.name)（有櫈）", "\(lm.name)（有凳子）", "\(lm.name) (seats)") : lm.name).tag(lm.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: { Text(L.t("喺邊度等", "在哪里见", "Where to meet")).ds(.caption) }

                Section {
                    Picker(L.t("行幾耐", "走多久", "How long"), selection: $minutes) {
                        ForEach(Self.durations, id: \.self) { m in Text(L.t("\(m) 分鐘", "\(m) 分钟", "\(m) min")).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 6)
                } header: { Text(L.t("一齊行幾耐", "一起走多久", "Walk together for")).ds(.caption) }
            }
            .navigationTitle(L.t("自己揀", "自己选", "Choose"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("取消", "取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("用呢個", "用这个", "Use this")) {
                        store.setCustomProposal(date: date, landmarkID: landmarkID, minutes: minutes)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.large])
    }
}
