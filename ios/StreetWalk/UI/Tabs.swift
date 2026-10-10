import SwiftUI

// 子代理 B：三个标签页的内容。外层 ScrollView、标题行、16pt 侧边距由 MainView 负责，这里只出内容。

// MARK: - 今日

/// 今日：先看谁在外面，再看自己；今天的约会、天气遮荫、散步中的快捷反映。
struct TodayTab: View {
    @Environment(AppStore.self) private var store
    @State private var reported: ReportKind?
    @State private var reportToken = 0
    @State private var taps = 0
    @State private var cancelling: Appointment?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            outNowSection
            ForEach(store.todaysAppointments) { a in
                appointmentCard(a).transition(.tabsInsert)
            }
            myCard
            ForEach(store.answeredReports) { r in
                followUpCard(r).transition(.tabsInsert)
            }
            if let tip = store.weatherTip {
                weatherCard(tip).transition(.tabsInsert)
            }
            if store.walk != nil {
                reportCard.transition(.tabsInsert)
            }
            landmarksCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(DS.motion(DS.spring), value: store.outNeighbors.map(\.id))
        .animation(DS.motion(DS.spring), value: store.walk == nil)
        .animation(DS.motion(DS.spring), value: store.todaysAppointments)
        .animation(DS.motion(DS.spring), value: store.weatherTip)
        .animation(DS.motion(DS.spring), value: store.answeredReports)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .cancelMeetupDialog($cancelling)
    }

    // ① 而家喺外面嘅街坊

    @ViewBuilder private var outNowSection: some View {
        let out = store.outNeighbors
        if out.isEmpty {
            quietCard.transition(.tabsInsert)
        } else {
            // 一屏只一个橙色主按钮：第一个人用主按钮，其余用次按钮。
            ForEach(Array(out.enumerated()), id: \.element.id) { i, n in outCard(n, primary: i == 0).transition(.tabsInsert) }
        }
    }

    /// 没有街坊在外面：只给匿名的人数（全邨汇总，单机演示时是示範数据），不出名字、不出按钮。
    /// 人数少于 10 不出数字（和 F10 门槛一致）；中午前讲「今朝」，之后讲「今日」。
    private var quietCard: some View {
        let lm = store.landmarks.first
        let passers = lm.flatMap { store.community.passersToday(at: $0) }.flatMap { $0.count >= 10 ? $0 : nil }
        let when = AppStore.hk.component(.hour, from: store.now) < 12 ? "今朝" : "今日"
        return HStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .ds(.body)
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .background(Color(.tertiarySystemFill), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("而家冇街坊喺外面").ds(.caption).foregroundStyle(.secondary)
                if let lm, let passers {
                    Text("\(when) \(passers.count) 人經過\(lm.name)").ds(.body)
                } else {
                    Text("出門行吓，見到面碰一碰就係街坊").ds(.body)
                }
                if passers?.isDemo == true { DemoBadge() }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .combine)
    }

    private func outCard(_ n: Resident, primary: Bool) -> some View {
        let place = store.placeName(n.atLandmarkID)
        let walking = store.walk != nil
        return TabActionRow {
            HStack(spacing: 12) {
                AvatarBadge(n)
                VStack(alignment: .leading, spacing: 4) {
                    Text("而家喺外面").ds(.caption).foregroundStyle(.secondary)
                    Text(place.map { "\(n.name) · \($0)附近" } ?? n.name)
                        .ds(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    if n.isDemo { DemoBadge() }
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
            .tabButtonStyle(primary: primary)
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
                if store.streakHasDemo { DemoBadge(text: "含示範紀錄") }
                if !me.todayLine.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        AIBadge()
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
            if let leave = store.leaveSummary {
                Label(leave, systemImage: "moon.zzz.fill")
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
            if me.onLeave {
                Button("撤回") { store.withdrawLeave() }.buttonStyle(.dsSecondary).fixedSize()
            } else {
                // 今日 / 聽日 / 幾日（A56）；之后请咗假：选单入面撤回
                Menu {
                    ForEach(store.leaveMenuChoices, id: \.self) { r in Button(store.leaveMenuLabel(r)) { store.requestLeave(days: r.days, startOffset: r.startOffset) } }
                    if let w = store.withdrawLeaveLabel {
                        Divider()
                        Button(w, role: .destructive) { store.withdrawLeave() }
                    }
                } label: { Text("請假") }
                .menuStyle(.button).buttonStyle(.dsSecondary).fixedSize()
            }
        }
    }

    // ③ 今日约会

    private func appointmentCard(_ a: Appointment) -> some View {
        let p = store.resident(a.partnerID)
        let name = p?.name ?? "街坊"
        let place = store.placeName(a.landmarkID) ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let p { AvatarBadge(p) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("約咗\(name)").ds(.caption).foregroundStyle(.secondary)
                    Text("\(store.dayTimeLabel(a.date)) · \(place)")
                        .ds(.bodyBold)
                        .fixedSize(horizontal: false, vertical: true)
                    if p?.isDemo == true { DemoBadge(text: "示範街坊") }
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
                    .buttonStyle(.dsSecondary)   // 草图：「出發」是次按钮
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                changeRow(a)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("等緊\(name)確認").ds(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
                changeRow(a)
            }
        }
        .dsCard()
        .animation(DS.motion(DS.spring), value: a.status)
    }

    /// 约好之后都可以改时间 / 地点或者取消（改了要对方再确认，取消会通知对方）。
    private func changeRow(_ a: Appointment) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { changeButtons(a) }
            VStack(spacing: 12) { changeButtons(a) }
        }
    }

    @ViewBuilder private func changeButtons(_ a: Appointment) -> some View {
        Button { store.startEditing(a.id) } label: {
            Text("改時間地點").lineLimit(1).frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
        Button { cancelling = a } label: {
            Text("取消約會").lineLimit(1).frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
    }

    // ④ 反映有回覆（F10 落实后告诉居民）

    private func followUpCard(_ r: Report) -> some View {
        let place = store.landmark(r.landmarkID)?.name ?? "呢度"
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(DS.accent)
                .ds(.body)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("你反映過「\(place)\(r.kind.rawValue)」").ds(.caption).foregroundStyle(.secondary)
                Text(r.followUp ?? "").ds(.body).fixedSize(horizontal: false, vertical: true)
                if r.followUpDemo == true { DemoBadge() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .combine)
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

    // ⑥ 附近地標：场景里的地标很小、读屏摸不到，这里逐个列出；点一下打开资料卡（有没有櫈、遮蔭、改名）。

    private var landmarksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TabSectionHeader(text: "附近地標")
            VStack(spacing: 0) {
                ForEach(Array(store.landmarks.enumerated()), id: \.element.id) { i, lm in
                    if i > 0 { Divider().padding(.leading, 40) }
                    landmarkRow(lm)
                }
            }
            .dsCard(padding: 16)
        }
    }

    private func landmarkRow(_ lm: Landmark) -> some View {
        // 日落后不讲遮荫（会算成 100%）：同地标信息卡一样用 shadeValue（太阳落山返回 nil）
        let v = store.shade == nil ? 0 : store.shadeValue(lm.id, at: store.now)
        let sun = v.map { "而家大約 \(Int(($0 * 100).rounded()))% 有樓遮" } ?? "太陽落咗山"
        return Button { store.select(.landmark(lm.id)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.name).ds(.body)
                    Text("\(lm.hasSeat ? "有櫈" : "冇櫈") · \(sun)")
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").ds(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("撳一下睇詳情，可以改名")
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

/// 排行榜：本圈总步数 + 本圈名次（按连续天数，不显示步数）；人人显示网名 + 小人 + 连续日数，街坊另加座数楼层同今日一句
/// （非街坊永远唔出座数楼层，2026-10-10 定）；
/// 「我那行」由 MainView 固定在可见区底部（BoardMyRow），任何字号都看得到。
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
        let others = ranking.enumerated().filter { !$0.element.isMe }
        let rows = others.enumerated().map { i, e in Row(rank: e.offset + 1, resident: e.element, first: i == 0) }

        VStack(alignment: .leading, spacing: 16) {
            if store.backendOffline {
                DemoNote(text: "未連線：而家顯示上次嘅排行榜，連返網會自動更新。")
            } else if !store.community.isSimulated && rows.isEmpty {
                DemoNote(text: "附近暫時未有其他人用街坊行。同區有人用，就會喺呢度出現。")
            }
            circleCard
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    VStack(spacing: 0) {
                        if !row.first { Divider().padding(.leading, 100) }
                        rankRow(row.rank, row.resident)
                    }
                }
            }
            // 说明放在名次下面，不再把名次推出首屏。
            if store.community.isSimulated {
                DemoNote(text: "單機演示：圈入面其他人係示範街坊，連續日數同獎牌係模擬嘅。")
            }
        }
        .animation(DS.motion(DS.spring), value: rows.map(\.id))
    }

    /// 圈对圈：本月圈内总步数（我的由散步分钟估算，其他人和对面圈是示範数据）+ 上个月结果。
    private var circleCard: some View {
        let race = store.community.circleRace(placeName: store.map?.placeName ?? "我哋", myMonthSteps: store.myMonthSteps)
        let total = max(1, race.ourSteps + race.rivalSteps)
        let share = CGFloat(race.ourSteps) / CGFloat(total)
        let diff = race.ourSteps - race.rivalSteps
        let last = store.lastMonthResult
        // 未有对面圈嘅真数据：只讲本圈行咗几多，唔画对比条（唔造假）
        let versus = race.rivalSteps > 0 || race.isDemo
        return VStack(alignment: .leading, spacing: 12) {
            Text(race.rivalSteps == 0 ? "本月 \(race.ourName) 一齊行咗 \(store.myMonthStepsEstimated ? "約 " : "")\(Self.steps(race.ourSteps))"
                 : "本月 \(race.ourName) \(diff >= 0 ? "領先" : "落後")\(race.rivalName) \(Self.steps(abs(diff)))")
                .ds(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if versus {
                GeometryReader { g in
                    let w = max(0, g.size.width - 4)
                    HStack(spacing: 4) {
                        Capsule().fill(DS.accent).frame(width: w * share * barProgress)
                        Capsule().fill(Color.secondary.opacity(0.3))
                    }
                }
                .frame(height: 14)
                .accessibilityHidden(true)
            }
            // 上个月结果（F4 月末公布）：赢了的圈全员头像有奖牌。示範标签放同一行，卡片矮一点，第 1 名在首屏完整可见。
            if last != nil || race.isDemo {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { resultLine(last); Spacer(minLength: 0); if race.isDemo { DemoBadge() } }
                    VStack(alignment: .leading, spacing: 8) { resultLine(last); if race.isDemo { DemoBadge() } }
                }
            }
        }
        .dsCard()
        .accessibilityElement(children: .combine)
        .onAppear {
            barProgress = 0
            withAnimation(DS.motion(DS.bouncy).delay(0.15)) { barProgress = 1 }
        }
    }

    @ViewBuilder private func resultLine(_ last: MonthResult?) -> some View {
        if let last {
            Label {
                Text(last.weWon ? "\(last.month) 月\(last.ourName)贏咗" : "\(last.month) 月\(last.rivalName)贏咗")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "rosette").foregroundStyle(Color(red: 0.80, green: 0.55, blue: 0.0))
            }
            .ds(.captionBold)
            .accessibilityLabel(last.weWon ? "上個月 \(last.month) 月，\(last.ourName)贏咗，全圈有獎牌" : "上個月 \(last.month) 月，\(last.rivalName)贏咗")
        }
    }

    /// 例如「3.2 萬步」「8,400 步」。
    static func steps(_ n: Int) -> String {
        n >= 10_000 ? String(format: "%.1f 萬步", Double(n) / 10_000).replacingOccurrences(of: ".0 萬", with: " 萬") : "\(n) 步"
    }

    @ViewBuilder private func rankRow(_ rank: Int, _ r: Resident) -> some View {
        let content = HStack(spacing: 12) {
            Text("\(rank)")
                .monospacedDigit()
                .ds(.body)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
            AvatarBadge(r, size: 48, medal: r.hasMedal)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.listName).ds(.body).fixedSize(horizontal: false, vertical: true)
                // 今日一句只俾街坊睇（佢可能讲到地标同楼层）
                if r.isNeighbor && !r.todayLine.isEmpty {
                    Text(r.todayLine)
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            BoardStreak(days: r.streakDays)
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
        let label = "第 \(rank) 名，\(r.listName)，連續 \(r.streakDays) 日\(r.hasMedal ? "，有獎牌" : "")\(r.isNeighbor && !r.todayLine.isEmpty ? "，\(r.todayLine)" : "")"

        if r.isNeighbor {
            Button { store.select(.person(r.id)) } label: { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
                .accessibilityHint("睇吓佢喺邊")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
        }
    }
}

/// 排行榜「我那行」：固定在排行榜可见区底部、标签栏之上（MainView 放入安全区）。
struct BoardMyRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let ranking = store.ranking
        let me = store.me
        let rank = (ranking.firstIndex { $0.isMe } ?? ranking.count) + 1
        let shape = RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
        HStack(spacing: 12) {
            Text("\(rank)")
                .monospacedDigit()
                .ds(.bodyBold)
                .foregroundStyle(DS.accent)
                .contentTransition(.numericText(value: Double(rank)))
                .frame(minWidth: 28, alignment: .trailing)
            AvatarBadge(me, size: 48, medal: me.hasMedal)
            VStack(alignment: .leading, spacing: 2) {
                Text(me.listName).ds(.bodyBold).fixedSize(horizontal: false, vertical: true)
                // 大字号时只留名次和名，固定行不要占掉半个列表（今日一句读屏照读）
                if !me.todayLine.isEmpty && !typeSize.isAccessibilitySize {
                    Text(me.todayLine)
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            BoardStreak(days: me.streakDays)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(Color(.secondarySystemGroupedBackground))
                .overlay(shape.fill(DS.accentSoft))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
        .overlay(shape.strokeBorder(DS.accent, lineWidth: 1.5))
        .padding(.horizontal, DS.side)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .animation(DS.motion(DS.spring), value: rank)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("你排第 \(rank) 名，\(me.listName)，連續 \(me.streakDays) 日，\(me.todayLine)")
    }
}

/// 排行榜每行右边：连续日数（排名就系按呢个）。
private struct BoardStreak: View {
    let days: Int
    var body: some View {
        VStack(spacing: 0) {
            Text("\(days)")
                .ds(.bodyBold)
                .monospacedDigit()
                .foregroundStyle(days > 0 ? DS.accentInk : .secondary)
                .contentTransition(.numericText(value: Double(days)))
            Text("日").ds(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 44)
        .accessibilityHidden(true)
    }
}

// MARK: - 街坊

/// 街坊：碰一碰大按钮、别人约我的邀请、以后的约会、街坊列表（约佢行 + 出门提醒）。
struct NeighborsTab: View {
    @Environment(AppStore.self) private var store
    @State private var taps = 0
    @State private var toggles = 0
    @State private var unlinking: Resident?

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

            if store.community.isSimulated {
                DemoNote(text: "單機演示：碰一碰係模擬嘅，會碰到示範街坊。真機用超寬頻（兩部 iPhone 11 或之後）。")
            } else if store.backendOffline {
                DemoNote(text: "未連線：街坊出門、約會要連返網先收到。你做嘅改動會留住，連返網就送出。")
            }

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
        .confirmationDialog(unlinking.map { "唔再同\($0.name)做街坊？" } ?? "", isPresented: Binding(get: { unlinking != nil }, set: { if !$0 { unlinking = nil } }), titleVisibility: .visible) {
            if let r = unlinking {
                Button("唔再做街坊", role: .destructive) { store.unlinkNeighbor(r.id); unlinking = nil }
            }
            Button("保留", role: .cancel) { unlinking = nil }
        } message: {
            Text(unlinkMessage(unlinking))
        }
    }

    /// 解除街坊的说明：有未完成的约会就讲清楚对方会收到「約會取消」（审核 A70）。
    private func unlinkMessage(_ r: Resident?) -> String {
        let open = r.map { r in store.appointments.filter { $0.partnerID == r.id && $0.isOpen }.count } ?? 0
        let base = "佢唔會收到解除通知。之後佢出門你唔會知，佢亦見唔到你。"
        let meet = open > 0 ? "你哋 \(open) 個未完成嘅約會會取消，佢會收到「約會取消」。" : ""
        return base + meet + "想再做街坊，要見面再碰一碰。"
    }

    private func invitationCard(_ a: Appointment) -> some View {
        let p = store.resident(a.partnerID)
        let name = p?.name ?? "街坊"
        let place = store.placeName(a.landmarkID) ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let p { AvatarBadge(p) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(name)約你\(store.dayTimeLabel(a.date)) · \(place)")
                        .ds(.bodyBold)
                        .contentTransition(.numericText())
                        .fixedSize(horizontal: false, vertical: true)
                    if p?.isDemo == true { DemoBadge(text: "示範街坊") }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AIBadge()
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
        Button { store.declineInvitation(a.id) } label: {
            Text("唔去").frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
    }

    private func upcomingRow(_ a: Appointment) -> some View {
        let name = store.resident(a.partnerID)?.name ?? "街坊"
        let place = store.placeName(a.landmarkID) ?? ""
        let status: String = {
            switch a.status {
            case .waiting: return "等緊\(name)確認"
            case .accepted: return "約好咗"
            case .done: return "行咗"
            case .cancelled: return "取消咗"
            case .expired: return "過咗期"
            }
        }()
        return Button { store.startEditing(a.id) } label: { HStack(alignment: .top, spacing: 12) {
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
            Image(systemName: "chevron.right").ds(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle()) }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("改時間、地點或者取消")
    }

    private func neighborCard(_ n: Resident) -> some View {
        // 没有出门消息不等于在家（对方可能关了发送，或回家后隐身），不要说死。
        let status: String = {
            if n.isOut, let place = store.placeName(n.atLandmarkID) { return "出咗門 · \(place)附近" }
            return "冇出門消息"
        }()
        // F6：接收、发送分开开关。
        let receive = Binding<Bool>(
            get: { store.resident(n.id)?.receiveRemind ?? false },
            set: { on in toggles += 1; store.setRemind(n.id, receive: on) }
        )
        let send = Binding<Bool>(
            get: { store.resident(n.id)?.sendRemind ?? false },
            set: { on in toggles += 1; store.setRemind(n.id, send: on) }
        )
        return VStack(alignment: .leading, spacing: 12) {
            TabActionRow {
                HStack(spacing: 12) {
                    AvatarBadge(n)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(n.listName).ds(.bodyBold).fixedSize(horizontal: false, vertical: true)
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
            Toggle(isOn: receive) {
                Label("佢出門話我知", systemImage: "bell.fill").ds(.caption)
            }
            .tint(DS.accent)
            Toggle(isOn: send) {
                Label("我出門話佢知", systemImage: "figure.walk").ds(.caption)
            }
            .tint(DS.accent)
            Button { unlinking = n } label: {
                Text("唔再做街坊")
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("佢唔會收到解除通知")
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
    /// 新卡由上面滑入；减少动态效果时只淡入。
    static var tabsInsert: AnyTransition { DS.slide(.top) }
}

private extension View {
    /// 一屏只一个主按钮：primary 为 false 时用次按钮。
    @ViewBuilder func tabButtonStyle(primary: Bool) -> some View {
        if primary { buttonStyle(.dsPrimary) } else { buttonStyle(.dsSecondary) }
    }
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

/// 取消约会前确认一次（会通知对方）。
private struct CancelMeetupDialog: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var target: Appointment?

    func body(content: Content) -> some View {
        let name = target.flatMap { store.resident($0.partnerID)?.name } ?? "街坊"
        content.confirmationDialog(target.map { "取消同\(name)\(store.dayTimeLabel($0.date))嘅約？" } ?? "",
                                   isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }), titleVisibility: .visible) {
            if let a = target {
                Button("取消約會", role: .destructive) { store.cancelMeetup(a.id); target = nil }
            }
            Button("唔取消", role: .cancel) { target = nil }
        } message: {
            Text("會話俾\(name)知。")
        }
    }
}

extension View {
    func cancelMeetupDialog(_ target: Binding<Appointment?>) -> some View { modifier(CancelMeetupDialog(target: target)) }
}
