import SwiftUI

// 子代理 B：三个标签页的内容。外层 ScrollView、标题行、16pt 侧边距由 MainView 负责，这里只出内容。

// MARK: - 今日

/// 今日：先看谁在外面，再看自己；今天的约会、天气遮荫、散步中的快捷反映。
struct TodayTab: View {
    @Environment(AppStore.self) private var store
    @State private var reported: ReportKind?
    @State private var reportToken = 0
    @State private var taps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            outNowSection
            myCard
            ForEach(store.todaysAppointments) { a in
                appointmentCard(a).transition(.tabsInsert)
            }
            if let tip = store.weatherTip {
                weatherCard(tip).transition(.tabsInsert)
            }
            if store.walk != nil {
                reportCard.transition(.tabsInsert)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(DS.motion(DS.spring), value: store.outNeighbors.map(\.id))
        .animation(DS.motion(DS.spring), value: store.walk == nil)
        .animation(DS.motion(DS.spring), value: store.todaysAppointments)
        .animation(DS.motion(DS.spring), value: store.weatherTip)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }

    // ① 而家喺外面嘅街坊

    @ViewBuilder private var outNowSection: some View {
        let out = store.outNeighbors
        if out.isEmpty {
            quietCard.transition(.tabsInsert)
        } else {
            ForEach(out) { n in outCard(n).transition(.tabsInsert) }
        }
    }

    /// 没有街坊在外面：只给匿名的人数，不出名字、不出按钮。
    private var quietCard: some View {
        let place = store.landmarks.first?.name ?? "樓下"
        let count = 9 + place.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 9
        return HStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .ds(.body)
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .background(Color(.tertiarySystemFill), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("而家冇街坊喺外面").ds(.caption).foregroundStyle(.secondary)
                Text("今朝 \(count) 人經過\(place)").ds(.body)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .combine)
    }

    private func outCard(_ n: Resident) -> some View {
        let place = store.landmark(n.atLandmarkID)?.name
        let walking = store.walk != nil
        return TabActionRow {
            HStack(spacing: 12) {
                AvatarBadge(color: n.color, mobility: n.mobility)
                VStack(alignment: .leading, spacing: 4) {
                    Text("而家喺外面").ds(.caption).foregroundStyle(.secondary)
                    Text(place.map { "\(n.floorLabel)\(n.name) · \($0)附近" } ?? "\(n.floorLabel)\(n.name)")
                        .ds(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        } action: { stacked in
            Button {
                taps += 1
                if walking { store.goFind(n.id) } else { store.proposeMeetup(with: n.id) }
            } label: {
                Text(walking ? "過去搵佢" : "約佢").frame(maxWidth: stacked ? .infinity : nil)
            }
            .buttonStyle(.dsPrimary)
        }
        .dsCard()
    }

    // ② 我

    private var myCard: some View {
        let me = store.me
        return VStack(alignment: .leading, spacing: 12) {
            if let w = store.walk {
                walkingStats(w)
            } else {
                Text("今日行咗 \(store.todayMinutes) 分鐘 · 連續 \(me.streakDays) 日")
                    .ds(.bodyBold)
                    .contentTransition(.numericText(value: Double(store.todayMinutes * 1000 + me.streakDays)))
                    .fixedSize(horizontal: false, vertical: true)
                if !me.todayLine.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TabAITag()
                        TypeInText(text: me.todayLine).ds(.body)
                    }
                }
                Divider()
                leaveRow(me)
            }
        }
        .dsCard()
        .animation(DS.motion(DS.spring), value: me.onLeave)
        .animation(DS.motion(DS.spring), value: store.paceTip)
        .animation(DS.motion(DS.snappy), value: store.todayMinutes)
        .animation(DS.motion(DS.snappy), value: me.streakDays)
    }

    @ViewBuilder private func walkingStats(_ w: WalkSession) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.walk").foregroundStyle(DS.accent).accessibilityHidden(true)
            Text("行緊 · \(w.minutes) 分鐘")
                .contentTransition(.numericText(value: Double(w.minutes)))
        }
        .ds(.bodyBold)
        .animation(DS.motion(DS.snappy), value: w.minutes)
        Text("經過 \(w.passed.count) 個地方")
            .ds(.caption)
            .foregroundStyle(.secondary)
            .contentTransition(.numericText(value: Double(w.passed.count)))
            .animation(DS.motion(DS.snappy), value: w.passed.count)
        if let tip = store.paceTip {
            Label {
                Text(tip).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "chair.lounge.fill").foregroundStyle(DS.accent)
            }
            .ds(.body)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.tabsInsert)
        }
    }

    private func leaveRow(_ me: Resident) -> some View {
        HStack(spacing: 12) {
            if me.onLeave {
                Label("今日已請假，連續日數保留", systemImage: "moon.zzz.fill")
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else {
                Text("今日唔想行？")
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            Button(me.onLeave ? "撤回" : "請假") { store.toggleLeave() }
                .buttonStyle(.dsSecondary)
                .fixedSize()
        }
    }

    // ③ 今日约会

    private func appointmentCard(_ a: Appointment) -> some View {
        let p = store.resident(a.partnerID)
        let name = p?.name ?? "街坊"
        let place = store.landmark(a.landmarkID)?.name ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let p { AvatarBadge(color: p.color, mobility: p.mobility) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("約咗\(name)").ds(.caption).foregroundStyle(.secondary)
                    Text("\(store.dayTimeLabel(a.date)) · \(place)")
                        .ds(.bodyBold)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Text(a.reason)
                .ds(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if a.status == .accepted {
                TabActionRow {
                    Label("\(name)應承咗", systemImage: "checkmark.circle.fill")
                        .ds(.captionBold)
                        .foregroundStyle(DS.accent)
                } action: { stacked in
                    Button {
                        taps += 1
                        store.departForAppointment(a)
                    } label: {
                        Label("出發", systemImage: "figure.walk").frame(maxWidth: stacked ? .infinity : nil)
                    }
                    .buttonStyle(.dsSecondary)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("等緊\(name)確認").ds(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
        }
        .dsCard()
        .animation(DS.motion(DS.spring), value: a.status)
    }

    // ④ 天气遮荫

    private func weatherCard(_ tip: String) -> some View {
        let rain = store.weather == .rain
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: rain ? "cloud.heavyrain.fill" : "sun.max.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(rain ? Color.secondary : DS.accent)
                .ds(.body)
                .accessibilityHidden(true)
            Text(tip)
                .ds(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    // ⑤ 散步中：快捷反映

    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("呢度點樣？").ds(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let k = reported {
                    Label("記低咗", systemImage: "checkmark.circle.fill")
                        .ds(.captionBold)
                        .foregroundStyle(DS.accent)
                        .id(reportToken)
                        .transition(.scale(scale: 0.5, anchor: .trailing).combined(with: .opacity))
                        .accessibilityLabel("記低咗：\(k.rawValue)")
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { reportButtons }
                VStack(spacing: 12) { reportButtons }
            }
        }
        .dsCard()
        .animation(DS.motion(DS.bouncy), value: reportToken)
        .animation(DS.motion(DS.bouncy), value: reported)
    }

    @ViewBuilder private var reportButtons: some View {
        ForEach(ReportKind.allCases) { k in
            Button { send(k) } label: {
                VStack(spacing: 4) {
                    Image(systemName: k.symbol)
                    Text(k.rawValue)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsSecondary)
            .accessibilityLabel("呢度\(k.rawValue)")
        }
    }

    private func send(_ k: ReportKind) {
        store.report(k)
        reportToken += 1
        reported = k
        let token = reportToken
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if reportToken == token { reported = nil }
        }
    }
}

// MARK: - 排行榜

/// 排行榜：圈对圈 + 本圈名次（按连续天数，不显示步数）；非街坊只显示楼层；我那行固定在底部。
struct BoardTab: View {
    @Environment(AppStore.self) private var store
    @State private var barProgress: CGFloat = 0

    private struct Row: Identifiable {
        let rank: Int
        let resident: Resident
        let first: Bool
        var id: String { resident.id }
    }

    var body: some View {
        let ranking = store.ranking
        let me = store.me
        let myRank = (ranking.firstIndex { $0.isMe } ?? ranking.count) + 1
        let others = ranking.enumerated().filter { !$0.element.isMe }
        let rows = others.enumerated().map { i, e in Row(rank: e.offset + 1, resident: e.element, first: i == 0) }

        LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionFooters]) {
            circleCard
            Section {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        VStack(spacing: 0) {
                            if !row.first { Divider().padding(.leading, 100) }
                            rankRow(row.rank, row.resident)
                        }
                    }
                }
            } footer: {
                myRow(rank: myRank, me)
            }
        }
        .animation(DS.motion(DS.spring), value: rows.map(\.id))
    }

    private var circleCard: some View {
        let place = store.map?.placeName ?? "我哋"
        return VStack(alignment: .leading, spacing: 12) {
            Text("本月 \(place)圈 領先對面圈 3 萬步")
                .ds(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { g in
                let w = max(0, g.size.width - 4)
                HStack(spacing: 4) {
                    Capsule().fill(DS.accent).frame(width: w * 41 / 79 * barProgress)
                    Capsule().fill(Color.secondary.opacity(0.3))
                }
            }
            .frame(height: 16)
            .accessibilityHidden(true)
            HStack {
                Text("\(place)圈").foregroundStyle(DS.accent)
                Spacer(minLength: 8)
                Text("對面圈").foregroundStyle(.secondary)
            }
            .ds(.captionBold)
            .accessibilityHidden(true)
        }
        .dsCard()
        .accessibilityElement(children: .combine)
        .onAppear {
            barProgress = 0
            withAnimation(DS.motion(DS.bouncy).delay(0.15)) { barProgress = 1 }
        }
    }

    @ViewBuilder private func rankRow(_ rank: Int, _ r: Resident) -> some View {
        let content = HStack(spacing: 12) {
            Text("\(rank)")
                .monospacedDigit()
                .ds(.body)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
            AvatarBadge(color: r.color, mobility: r.mobility, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.listName).ds(.body)
                if !r.todayLine.isEmpty {
                    Text(r.todayLine)
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if r.isNeighbor {
                Image(systemName: "chevron.right")
                    .ds(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if r.isNeighbor {
            Button { store.select(.person(r.id)) } label: { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("第 \(rank)，\(r.listName)，\(r.todayLine)")
                .accessibilityHint("睇吓佢喺邊")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("第 \(rank)，\(r.listName)，\(r.todayLine)")
        }
    }

    private func myRow(rank: Int, _ me: Resident) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
        return HStack(spacing: 12) {
            Text("\(rank)")
                .monospacedDigit()
                .ds(.bodyBold)
                .foregroundStyle(DS.accent)
                .contentTransition(.numericText(value: Double(rank)))
                .frame(minWidth: 28, alignment: .trailing)
            AvatarBadge(color: me.color, mobility: me.mobility, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(me.floorLabel) · 你").ds(.bodyBold)
                if !me.todayLine.isEmpty {
                    Text(me.todayLine)
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(Color(.secondarySystemGroupedBackground))
                .overlay(shape.fill(DS.accentSoft))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
        .overlay(shape.strokeBorder(DS.accent, lineWidth: 1.5))
        .padding(.top, 8)
        .animation(DS.motion(DS.spring), value: rank)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("你排第 \(rank)，\(me.todayLine)")
    }
}

// MARK: - 街坊

/// 街坊：碰一碰大按钮、别人约我的邀请、以后的约会、街坊列表（约佢行 + 出门提醒）。
struct NeighborsTab: View {
    @Environment(AppStore.self) private var store
    @State private var taps = 0
    @State private var toggles = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                guard store.bumpStage == .idle else { return }
                taps += 1
                store.startBump()
            } label: {
                Label {
                    Text("碰一碰加街坊")
                } icon: {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)

            if !store.invitations.isEmpty {
                TabSectionHeader(text: "約你嘅")
                ForEach(store.invitations) { a in
                    invitationCard(a).transition(.tabsInsert)
                }
            }

            if !store.upcomingAppointments.isEmpty {
                TabSectionHeader(text: "我嘅約會")
                VStack(spacing: 0) {
                    ForEach(Array(store.upcomingAppointments.enumerated()), id: \.element.id) { i, a in
                        VStack(spacing: 0) {
                            if i > 0 { Divider() }
                            upcomingRow(a)
                        }
                    }
                }
                .dsCard(padding: 16)
                .transition(.tabsInsert)
            }

            TabSectionHeader(text: "我嘅街坊")
            if store.neighbors.isEmpty {
                emptyState.transition(.opacity)
            } else {
                ForEach(store.neighbors) { n in
                    neighborCard(n).transition(.tabsInsert)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(DS.motion(DS.spring), value: store.invitations)
        .animation(DS.motion(DS.spring), value: store.upcomingAppointments)
        .animation(DS.motion(DS.spring), value: store.neighbors)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .sensoryFeedback(.selection, trigger: toggles)
    }

    private func invitationCard(_ a: Appointment) -> some View {
        let p = store.resident(a.partnerID)
        let name = p?.name ?? "街坊"
        let place = store.landmark(a.landmarkID)?.name ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let p { AvatarBadge(color: p.color, mobility: p.mobility) }
                Text("\(name)約你\(store.dayTimeLabel(a.date)) · \(place)")
                    .ds(.bodyBold)
                    .contentTransition(.numericText())
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TabAITag()
                Text(a.reason)
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { invitationButtons(a) }
                VStack(spacing: 12) { invitationButtons(a) }
            }
        }
        .dsCard()
        .animation(DS.motion(DS.spring), value: a.date)
    }

    @ViewBuilder private func invitationButtons(_ a: Appointment) -> some View {
        Button { store.acceptInvitation(a.id) } label: {
            Text("好").frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsPrimary)
        Button { store.rescheduleInvitation(a.id) } label: {
            Text("換個時間").frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
    }

    private func upcomingRow(_ a: Appointment) -> some View {
        let name = store.resident(a.partnerID)?.name ?? "街坊"
        let place = store.landmark(a.landmarkID)?.name ?? ""
        let status: String = {
            switch a.status {
            case .waiting: return "等緊\(name)確認"
            case .accepted: return "約好咗"
            case .done: return "行咗"
            }
        }()
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: a.status == .accepted ? "calendar.badge.checkmark" : "calendar")
                .ds(.body)
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.dayTimeLabel(a.date)) · \(name)").ds(.body)
                Text("\(place) · \(status)")
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func neighborCard(_ n: Resident) -> some View {
        let status: String = {
            if n.isOut, let lm = store.landmark(n.atLandmarkID) { return "出咗門 · \(lm.name)附近" }
            return "喺屋企"
        }()
        let remind = Binding<Bool>(
            get: { store.resident(n.id)?.receiveRemind ?? false },
            set: { on in
                toggles += 1
                store.setRemind(n.id, on)
            }
        )
        return VStack(alignment: .leading, spacing: 12) {
            TabActionRow {
                HStack(spacing: 12) {
                    AvatarBadge(color: n.color, mobility: n.mobility)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(n.floorLabel) \(n.name)").ds(.bodyBold)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(n.isOut ? DS.accent : Color.secondary.opacity(0.5))
                                .frame(width: 8, height: 8)
                            Text(status)
                                .ds(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            } action: { stacked in
                Button {
                    taps += 1
                    store.proposeMeetup(with: n.id)
                } label: {
                    Text("約佢行").frame(maxWidth: stacked ? .infinity : nil)
                }
                .buttonStyle(.dsSecondary)
            }
            Divider()
            Toggle(isOn: remind) {
                Label("出門提醒", systemImage: "bell.fill").ds(.caption)
            }
            .tint(DS.accent)
        }
        .dsCard()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.wave.2")
                .ds(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("仲未有街坊。見到面碰一碰，就會喺呢度出現。")
                .ds(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - 本文件用的小部件

private extension AnyTransition {
    static var tabsInsert: AnyTransition { .move(edge: .top).combined(with: .opacity) }
}

/// 内容 + 一个按钮：放得下就按钮在右边，放不下（大字号、长名字）就叠成两行、按钮占满宽度。
private struct TabActionRow<Content: View, Action: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var action: (_ stacked: Bool) -> Action

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                content
                Spacer(minLength: 0)
                action(false).fixedSize()
            }
            VStack(alignment: .leading, spacing: 16) {
                content
                action(true)
            }
        }
    }
}

private struct TabSectionHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .ds(.captionBold)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 小小的「AI」标签：表示这句是 AI 写的。
private struct TabAITag: View {
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 16
    var body: some View {
        Text("AI")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(DS.accentSoft, in: Capsule())
            .accessibilityLabel("AI 寫嘅")
    }
}

/// AI 今日一句：逐字淡入；句子一变就重新播一次。减少动态效果时直接显示。
private struct TypeInText: View {
    let text: String
    var body: some View { TypeInLine(text: text).id(text) }
}

private struct TypeInLine: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0

    var body: some View {
        Text(text)
            .textRenderer(TypeInRenderer(progress: progress))
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                if reduceMotion { progress = 1 } else { withAnimation(.smooth(duration: 1.4)) { progress = 1 } }
            }
    }
}

private struct TypeInRenderer: TextRenderer {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var slices: [Text.Layout.RunSlice] = []
        for line in layout { for run in line { for slice in run { slices.append(slice) } } }
        let n = Double(max(1, slices.count))
        let window = 0.35
        for (i, slice) in slices.enumerated() {
            let start = Double(i) / n * (1 - window)
            let t = min(1, max(0, (progress - start) / window))
            var c = ctx
            c.opacity = t
            c.translateBy(x: 0, y: (1 - t) * 4)
            c.draw(slice)
        }
    }
}
