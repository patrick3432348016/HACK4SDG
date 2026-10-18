import SwiftUI

// 子代理 B：三个标签页的内容。外层 ScrollView、标题行、16pt 侧边距由 MainView 负责，这里只出内容。

// MARK: - 今日

/// 今日：最上面一张「主角卡」（一次只一张，按紧急程度揀，有一个主按钮），其余缩成一行一行嘅次要信息（UX 评审 9）。
/// 次序：别人约你 / 想过来找你 > 今日约会（出發）> 同街坊一齐行紧 / 街坊在外面（約佢）> 散步中 > 天气建议出门 > 未有街坊（碰一碰）。
struct TodayTab: View {
    @Environment(AppStore.self) private var store
    @State private var reported: ReportKind?
    @State private var reportToken = 0
    @State private var taps = 0
    @State private var cancelling: Appointment?

    /// 主角卡嘅种类。
    enum Hero: Equatable {
        case incomingFind
        case invitation(Appointment)
        case appointment(Appointment)
        case together(String)
        case out(String)
        case walking
        case walkTip
        case noNeighbors
    }

    /// 按紧急程度揀主角卡。
    static func hero(_ store: AppStore) -> Hero {
        if let ask = store.incomingFind, store.resident(ask.fromID) != nil { return .incomingFind }
        if let a = store.invitations.sorted(by: { $0.date < $1.date }).first { return .invitation(a) }
        if let a = store.todaysAppointments.first(where: { $0.status == .accepted }) { return .appointment(a) }
        if let id = store.walkingWith, store.find == nil, store.resident(id) != nil { return .together(id) }
        if let n = store.outNeighbors.first(where: { $0.id != store.walkingWith }) { return .out(n.id) }
        if store.walk != nil { return .walking }
        if !store.neighbors.isEmpty { return .walkTip }
        return .noNeighbors
    }

    var body: some View {
        let hero = Self.hero(store)
        // 测试反馈 J-3：由上到下一条主线 —— ① 今日三件事（第一日）→ ② 最急嘅主角卡
        // → ③ 今日行咗几耐 · 连续几日（次要信息卡第一行；全页只出一次，散步中由主角卡讲）→ ④ 其他。
        VStack(alignment: .leading, spacing: 16) {
            FirstDayCard()      // 第一日「今日三件事」（自己判断显唔显示；做完三件由用户撳「收起」）
            // 「今日三件事」已经有「見到街坊碰一碰」：唔再叠多张「第一步 · 仲未有街坊」（两张待办讲同一件事）
            if !(hero == .noNeighbors && store.showsFirstDay) {
                heroCard(hero)
                    .id(heroKey(hero))
                    .transition(.tabsInsert)
            }
            minorRows(hero)
            LocationCards()     // 係咪搬咗屋、自动记录未开齐（LocationViews）：以前夹喺主角卡同「今日行咗」中间
            if store.walk != nil {
                reportCard.transition(.tabsInsert)
            }
            landmarksCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if DEBUG
        .task { if UIPreview.is("firstDay") { store.startFirstDay() } }   // 截图自检：-uiPreview firstDay（出「今日三件事」）
        #endif
        .animation(DS.motion(DS.spring), value: heroKey(hero))
        .animation(DS.motion(DS.spring), value: store.outNeighbors.map(\.id))
        .animation(DS.motion(DS.spring), value: store.walk == nil)
        .animation(DS.motion(DS.spring), value: store.todaysAppointments)
        .animation(DS.motion(DS.spring), value: store.upcomingAppointments)
        .animation(DS.motion(DS.spring), value: store.weatherTip)
        .animation(DS.motion(DS.spring), value: store.answeredReports)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .cancelMeetupDialog($cancelling)
    }

    private func heroKey(_ h: Hero) -> String {
        switch h {
        case .incomingFind: return "find"
        case .invitation(let a): return "invite-\(a.id)"
        case .appointment(let a): return "appt-\(a.id)"
        case .together(let id): return "together-\(id)"
        case .out(let id): return "out-\(id)"
        case .walking: return "walking"
        case .walkTip: return "tip"
        case .noNeighbors: return "none"
        }
    }

    // MARK: 主角卡

    @ViewBuilder private func heroCard(_ h: Hero) -> some View {
        switch h {
        case .incomingFind: incomingFindHero
        case .invitation(let a): invitationHero(a)
        case .appointment(let a): appointmentHero(a)
        case .together(let id): togetherHero(id)
        case .out(let id): outHero(id)
        case .walking: walkingHero
        case .walkTip: walkTipHero
        case .noNeighbors: noNeighborsHero
        }
    }

    /// 主角卡外框：大少少（内距 20）、橙色描边，顶上一行小标签讲呢张卡系乜。
    private func heroFrame<Content: View>(_ tag: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(tag, systemImage: symbol)
                .ds(.captionBold)
                .foregroundStyle(DS.accentInk)
            content()
        }
        .dsCard(padding: 20)
        .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(DS.accent.opacity(0.45), lineWidth: 2))
    }

    /// 人 + 两行字（第一行粗体）。
    private func personLine(_ p: Resident?, _ title: String, _ detail: String? = nil, demo: Bool = false) -> some View {
        HStack(spacing: 12) {
            if let p { AvatarBadge(p, size: 60) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).ds(.bodyBold).fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail).ds(.body).fixedSize(horizontal: false, vertical: true)
                }
                if demo { DemoBadge(text: L.t("示範街坊", "示范邻居", "Demo neighbour")) }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // 街坊想过来找你（底部卡都有；呢度保证喺今日页最上面都见到）

    @ViewBuilder private var incomingFindHero: some View {
        if let ask = store.incomingFind, let p = store.resident(ask.fromID) {
            heroFrame(L.t("等你回覆", "等你回复", "Waiting for your reply"), symbol: "bell.badge.fill") {
                personLine(p, L.t("\(p.name)想過嚟搵你，方唔方便？", "\(p.name)想过来找你，方便吗？", "\(p.name) wants to come and find you. OK?"),
                           store.placeName(ask.landmarkID).map { L.t("佢會過去\($0)附近搵你。", "他会去\($0)附近找你。", "They'll find you near \($0).") })
                replyButtons {
                    Button { taps += 1; store.answerIncomingFind(true) } label: { Text(L.t("好", "好", "OK")).lineLimit(1).frame(maxWidth: .infinity) }
                        .buttonStyle(.dsPrimary)
                } rest: {
                    Button { taps += 1; store.answerIncomingFind(false) } label: { Text(L.t("唔方便", "不方便", "Not now")).lineLimit(1).fixedSize() }
                        .buttonStyle(.dsSecondary)
                }
            }
        }
    }

    // 别人约你：卡上直接回覆（好 / 改時間 / 唔去）

    private func invitationHero(_ a: Appointment) -> some View {
        let p = store.resident(a.partnerID)
        let name = p?.name ?? L.t("街坊", "邻居", "Neighbour")
        let place = store.placeName(a.landmarkID) ?? ""
        let more = store.invitations.count - 1
        return heroFrame(more > 0 ? L.t("等你回覆（仲有 \(more) 個）", "等你回复（还有 \(more) 个）", "Waiting for your reply (\(more) more)") : L.t("等你回覆", "等你回复", "Waiting for your reply"), symbol: "envelope.fill") {
            personLine(p, L.t("\(name)約你一齊行", "\(name)约你一起走", "\(name) invited you for a walk"), "\(store.dayTimeLabel(a.date)) · \(place)", demo: p?.isDemo == true)
            if !store.meetupReason(a).isEmpty {
                Text(TemplateAI.whyHere(store.meetupReason(a))).ds(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            InvitationButtons(a: a)
        }
    }

    // 今日约会：约会前 30 分钟内「出發」系橙色主按钮；改 / 取消收埋喺一个掣（UX 评审 13）

    private func appointmentHero(_ a: Appointment) -> some View {
        let p = store.resident(a.partnerID)
        let name = p?.name ?? L.t("街坊", "邻居", "Neighbour")
        let place = store.placeName(a.landmarkID) ?? ""
        let left = a.date.timeIntervalSince(store.now)
        let soon = left <= 30 * 60 && left > -3600
        return heroFrame(L.t("今日約會", "今天的约会", "Today's walk plan"), symbol: "calendar.badge.checkmark") {
            personLine(p, L.t("約咗\(name)", "约了\(name)", "Walk with \(name)"), "\(store.dayTimeLabel(a.date)) · \(place)", demo: p?.isDemo == true)
            // 两部手机都见到呢张卡（应承嗰个都系）：唔讲边个应承，只讲约好咗
            Label(L.t("約好咗", "约好了", "All set"), systemImage: "checkmark.circle.fill")
                .ds(.captionBold)
                .foregroundStyle(DS.accentInk)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { departButton(a, primary: soon); changeMenu(a, stacked: false) }
                VStack(spacing: 12) { departButton(a, primary: soon); changeMenu(a, stacked: true) }
            }
        }
    }

    private func departButton(_ a: Appointment, primary: Bool) -> some View {
        Button {
            taps += 1
            store.departForAppointment(a)
        } label: {
            Label(L.t("出發", "出发", "Set off"), systemImage: "figure.walk").lineLimit(1).frame(maxWidth: .infinity)
        }
        .tabButtonStyle(primary: primary)
    }

    /// 「改 / 取消」：一个掣，入面先揀改时间地点定取消（取消会再问一次）。
    private func changeMenu(_ a: Appointment, stacked: Bool) -> some View {
        Menu {
            Button { store.startEditing(a.id) } label: { Label(L.t("改時間地點", "改时间地点", "Change time or place"), systemImage: "calendar") }
            Button(role: .destructive) { cancelling = a } label: { Label(L.t("取消約會", "取消约会", "Cancel walk plan"), systemImage: "xmark.circle") }
        } label: {
            Text(L.t("改 / 取消", "改 / 取消", "Change / Cancel")).lineLimit(1).fixedSize().frame(maxWidth: stacked ? .infinity : nil)
        }
        .menuStyle(.button)
        .buttonStyle(.dsSecondary)
        .accessibilityHint(L.t("改時間地點，或者取消約會", "改时间地点，或者取消约会", "Change time or place, or cancel the walk plan"))
    }

    // 找完人：同XX一齐行紧（唔再叫你過去搵佢，UX 评审 23）

    @ViewBuilder private func togetherHero(_ id: String) -> some View {
        if let p = store.resident(id) {
            heroFrame(L.t("一齊行緊", "一起走着", "Walking together"), symbol: "figure.2") {
                personLine(p, L.t("同\(p.name)一齊行緊", "和\(p.name)一起走着", "Walking with \(p.name)"), L.t("慢慢行，攰就坐低唞吓。", "慢慢走，累了就坐下歇歇。", "Go slowly. Sit and rest if tired."))
                Button {
                    taps += 1
                    store.walkingWith = nil
                } label: {
                    Text(L.t("行完喇", "走完了", "Finished")).lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
            }
        }
    }

    // 街坊而家喺外面：約佢（散步中：過去搵佢）

    @ViewBuilder private func outHero(_ id: String) -> some View {
        if let n = store.resident(id) {
            let place = store.placeName(n.atLandmarkID)
            let walking = store.walk != nil
            heroFrame(L.t("而家喺外面", "现在在外面", "Out now"), symbol: "figure.walk") {
                personLine(n, place.map { L.t("\(n.name)而家喺\($0)附近", "\(n.name)现在在\($0)附近", "\(n.name) is near \($0) now") } ?? L.t("\(n.name)出咗門", "\(n.name)出门了", "\(n.name) is out"), nil, demo: n.isDemo)
                Button {
                    taps += 1
                    if walking { store.goFind(n.id) } else { store.proposeMeetup(with: n.id) }
                } label: {
                    Label(walking ? L.t("過去搵佢", "过去找他", "Go and find them") : L.t("約佢一齊行", "约他一起走", "Invite for a walk"), systemImage: walking ? "figure.walk" : "calendar")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
            }
        }
    }

    // 散步中、冇街坊喺外面：行紧几耐、经过边度、要唔要唞

    private var walkingHero: some View {
        heroFrame(L.t("行緊", "散步中", "Walking"), symbol: "figure.walk") {
            if let w = store.walk {
                Text(L.t("行緊 \(w.minutes) 分鐘 · 經過 \(w.passed.count) 個地方", "已走 \(w.minutes) 分钟 · 经过 \(w.passed.count) 个地方", "\(w.minutes) min · passed \(w.passed.count) place\(w.passed.count == 1 ? "" : "s")"))
                    .ds(.bodyBold)
                    .contentTransition(.numericText(value: Double(w.minutes)))
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(DS.motion(DS.snappy), value: w.minutes)
                if let tip = store.paceTip {
                    Label {
                        Text(tip).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "chair.lounge.fill").foregroundStyle(DS.accent)
                    }
                    .ds(.body)
                    .transition(.tabsInsert)
                }
                Text(L.t("返到屋企會自動記低。", "回到家会自动记下。", "It's saved when you get home.")).ds(.caption).foregroundStyle(.secondary)
                // 10-18 测试：「结束散步」放喺散步卡入面，唔使碌落去搵
                endWalkButton
            }
        }
        .animation(DS.motion(DS.spring), value: store.paceTip)
    }

    /// 「结束散步」（A-3）：自动开始、手动开始都得。橙底白字。
    private var endWalkButton: some View {
        Button { taps += 1; store.endWalkByUser() } label: {
            Label(L.t("結束散步", "结束散步", "End walk"), systemImage: "stop.circle.fill").lineLimit(1).frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsPrimary)
    }

    // 有街坊、冇人喺外面：天气 / 遮荫建议 + 約街坊一齐行

    private var walkTipHero: some View {
        let rain = store.weather == .rain
        return heroFrame(L.t("今日去唔去行？", "今天去走走吗？", "Go for a walk today?"), symbol: rain ? "cloud.heavyrain.fill" : "sun.max.fill") {
            Text(store.weatherTip ?? L.t("約個街坊一齊出去行吓？", "约个邻居一起出去走走？", "Invite a neighbour for a walk?"))
                .ds(.body)
                .fixedSize(horizontal: false, vertical: true)
            inviteNeighborButton(primary: !rain)
        }
    }

    /// 「約XX一齊行」：一个街坊就直接约；几个就先揀边个。
    @ViewBuilder private func inviteNeighborButton(primary: Bool) -> some View {
        let ns = store.neighbors
        if ns.count == 1, let n = ns.first {
            Button { taps += 1; store.proposeMeetup(with: n.id) } label: {
                Label(L.t("約\(n.name)一齊行", "约\(n.name)一起走", "Invite \(n.name)"), systemImage: "calendar").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
            }
            .tabButtonStyle(primary: primary)
        } else {
            Menu {
                ForEach(ns) { n in Button(n.name) { taps += 1; store.proposeMeetup(with: n.id) } }
            } label: {
                Label(L.t("約街坊一齊行", "约邻居一起走", "Invite a neighbour"), systemImage: "calendar").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
            }
            .menuStyle(.button)
            .tabButtonStyle(primary: primary)
        }
    }

    // 未有街坊：出去行，见到面碰一碰

    private var noNeighborsHero: some View {
        heroFrame(L.t("第一步", "第一步", "First step"), symbol: "person.2.wave.2") {
            Text(L.t("仲未有街坊", "还没有邻居", "No neighbours yet")).ds(.bodyBold)
            Text(L.t("出門行吓，見到面碰一碰，就係街坊。", "出门走走，见面碰一碰，就是邻居。", "Go out for a walk. Meet someone, tap phones, and you're neighbours."))
                .ds(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                guard store.bumpStage == .idle else { return }
                taps += 1
                store.startBump()
            } label: {
                Label(L.t("碰一碰加街坊", "碰一碰加邻居", "Add a neighbour"), systemImage: "iphone.radiowaves.left.and.right").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
        }
    }

    // MARK: 次要信息：一行一行

    private func minorRows(_ hero: Hero) -> some View {
        let heroAppt: UUID? = { if case .appointment(let a) = hero { return a.id }; return nil }()
        let heroOut: String? = { if case .out(let id) = hero { return id }; return nil }()
        let heroInvite: UUID? = { if case .invitation(let a) = hero { return a.id }; return nil }()
        let otherInvites = store.invitations.filter { $0.id != heroInvite }
        let appts = store.todaysAppointments.filter { $0.id != heroAppt }
        let others = store.outNeighbors.filter { $0.id != heroOut && $0.id != store.walkingWith }
        let showTip = hero != .walkTip && store.weatherTip != nil
        let showQuiet = store.outNeighbors.isEmpty && store.walk == nil
        return VStack(alignment: .leading, spacing: 0) {
            if hero != .walking {
                minorRow { statusRow }
            }
            if showTip, let tip = store.weatherTip {
                Divider()
                minorRow { weatherRow(tip) }
            }
            ForEach(otherInvites) { a in
                Divider()
                minorRow { inviteRow(a) }
            }
            ForEach(appts) { a in
                Divider()
                minorRow { appointmentRow(a) }
            }
            // 测试反馈：约咗聽日之后「今日」页乜都冇 → 之后几日约好 / 等紧确认嘅都列出（最多 3 个）
            ForEach(store.upcomingAppointments.prefix(3)) { a in
                Divider()
                minorRow { appointmentRow(a) }
            }
            ForEach(others) { n in
                Divider()
                minorRow { outRow(n) }
            }
            ForEach(store.answeredReports) { r in
                Divider()
                minorRow { followUpRow(r) }
            }
            if showQuiet, let q = quietLine {
                Divider()
                minorRow { q }
            }
        }
        .dsCard(padding: 16)
    }

    private func minorRow<Content: View>(@ViewBuilder _ c: () -> Content) -> some View {
        c()
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.vertical, 4)
    }

    /// 今日行咗几耐 · 连续几日；今日一句；「今日唔行」。
    private var statusRow: some View {
        let me = store.me
        return VStack(alignment: .leading, spacing: 8) {
            if let w = store.walk {
                Label(L.t("行緊 \(w.minutes) 分鐘 · 經過 \(w.passed.count) 個地方", "已走 \(w.minutes) 分钟 · 经过 \(w.passed.count) 个地方", "\(w.minutes) min · passed \(w.passed.count) place\(w.passed.count == 1 ? "" : "s")"), systemImage: "figure.walk")
                    .ds(.body)
                    .contentTransition(.numericText(value: Double(w.minutes)))
                    .fixedSize(horizontal: false, vertical: true)
                if let tip = store.paceTip {
                    Label(tip, systemImage: "chair.lounge.fill").ds(.caption).fixedSize(horizontal: false, vertical: true)
                }
                // A-3：自己结束散步（主角卡唔係散步卡时喺呢度，紧跟主角卡）
                endWalkButton
            } else {
                Text(L.t("今日行咗 \(store.todayMinutes) 分鐘 · 連續 \(me.streakDays) 日", "今天走了 \(store.todayMinutes) 分钟 · 连续 \(me.streakDays) 天", "Today \(store.todayMinutes) min · \(me.streakDays) days in a row"))
                    .ds(.body)
                    .contentTransition(.numericText(value: Double(store.todayMinutes * 1000 + me.streakDays)))
                    .fixedSize(horizontal: false, vertical: true)
                if store.streakHasDemo { DemoBadge(text: L.t("含示範紀錄", "含示范记录", "Includes demo records")) }
                if !me.todayLine.isEmpty {
                    TypeInText(text: me.todayLine).ds(.caption).foregroundStyle(.secondary)
                }
                // A-3：自己撳开始散步（即刻记录、播报）；出门自动认唔到时都可以用
                if store.find == nil {
                    Button { taps += 1; store.startManualWalk() } label: {
                        Label(L.t("而家出去行吓（開始記錄）", "现在出去走走（开始记录）", "Go for a walk now (start recording)"), systemImage: "figure.walk")
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsPrimary)     // 10-18 测试：撳得嘅主要掣一律橙底白字
                }
                leaveRow(me)
            }
        }
        .animation(DS.motion(DS.spring), value: me.onLeave)
        .animation(DS.motion(DS.snappy), value: store.todayMinutes)
    }

    /// 「今日唔行（日數照計）」：以前叫「請假」，似返工（UX 评审 16）。
    private func leaveRow(_ me: Resident) -> some View {
        HStack(spacing: 12) {
            if let leave = store.leaveSummary {
                Label(leave, systemImage: "moon.zzz.fill")
                    .ds(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                Spacer(minLength: 0)
                Button { store.withdrawLeave() } label: {
                    Text(L.t("撤回", "撤回", "Undo")).ds(.captionBold).lineLimit(1).fixedSize().padding(.horizontal, 14).frame(minHeight: 44)
                }
                .buttonStyle(SoftChipStyle())
            } else {
                Menu {
                    ForEach(store.leaveMenuChoices, id: \.self) { r in Button(store.leaveMenuLabel(r)) { store.requestLeave(days: r.days, startOffset: r.startOffset) } }
                    if let w = store.withdrawLeaveLabel {
                        Divider()
                        Button(w, role: .destructive) { store.withdrawLeave() }
                    }
                } label: {
                    // 10-18 测试：「哪天不走」睇唔明有咩用 → 直接讲用途
                    Label(L.t("呢幾日唔方便出門？（連續日數唔會斷）", "这几天不方便出门？（连续天数不会断）", "Can't go out for a few days? (Streak won't break)"), systemImage: "moon.zzz")
                        .ds(.caption)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(SoftChipStyle())
                .accessibilityHint(L.t("揀邊幾日唔出門，連續日數會保留", "选哪几天不出门，连续天数会保留", "Pick the days you won't go out. Your streak is kept."))
            }
        }
    }

    private func weatherRow(_ tip: String) -> some View {
        let rain = store.weather == .rain
        return Label {
            Text(tip).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: rain ? "cloud.heavyrain.fill" : "sun.max.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(rain ? Color.secondary : DS.accent)
        }
        .ds(.caption)
    }

    private func inviteRow(_ a: Appointment) -> some View {
        let name = store.resident(a.partnerID)?.name ?? L.t("街坊", "邻居", "Neighbour")
        return Button { store.tab = .neighbors } label: {
            HStack(spacing: 12) {
                Label(L.t("\(name)約你\(store.dayTimeLabel(a.date))", "\(name)约你\(store.dayTimeLabel(a.date))", "\(name) invited you: \(store.dayTimeLabel(a.date))"), systemImage: "envelope.fill")
                    .ds(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(L.t("回覆", "回复", "Reply")).ds(.captionBold).foregroundStyle(DS.accentInk)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L.t("去「街坊」頁回覆", "去「邻居」页回复", "Reply on the Neighbours page"))
    }

    /// 今日其他约会（等对方确认、或者第二个约会）：撳一下改 / 取消。
    private func appointmentRow(_ a: Appointment) -> some View {
        let name = store.resident(a.partnerID)?.name ?? L.t("街坊", "邻居", "Neighbour")
        let place = store.placeName(a.landmarkID) ?? ""
        let status = a.status == .waiting ? L.t("等緊\(name)確認", "等\(name)确认", "Waiting for \(name)") : L.t("約好咗\(name)", "约好了\(name)", "All set with \(name)")
        return Button { store.startEditing(a.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: a.status == .waiting ? "hourglass" : "calendar.badge.checkmark").foregroundStyle(DS.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.dayTimeLabel(a.date)) · \(place)").ds(.caption)
                    Text(status).ds(.caption).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").ds(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(L.t("改時間、地點或者取消", "改时间、地点或取消", "Change time, place or cancel"))
    }

    /// 其他喺外面嘅街坊：一行，一个细掣。
    private func outRow(_ n: Resident) -> some View {
        let place = store.placeName(n.atLandmarkID)
        let walking = store.walk != nil
        return HStack(spacing: 12) {
            AvatarBadge(n, size: 40)
            Text(place.map { L.t("\(n.name) · \($0)附近", "\(n.name) · \($0)附近", "\(n.name) · near \($0)") } ?? n.name)
                .ds(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                taps += 1
                if walking { store.goFind(n.id) } else { store.proposeMeetup(with: n.id) }
            } label: {
                Text(walking ? L.t("過去搵佢", "过去找他", "Find them") : L.t("約佢", "约他", "Invite")).lineLimit(1).fixedSize()
            }
            .buttonStyle(.dsSecondary)
        }
    }

    private func followUpRow(_ r: Report) -> some View {
        let place = store.landmark(r.landmarkID)?.name ?? L.t("呢度", "这里", "here")
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(DS.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("你反映過「\(place)\(r.kind.label)」", "你反映过「\(place)\(r.kind.label)」", "You reported: \(place), \(r.kind.label)")).ds(.caption).foregroundStyle(.secondary)
                Text(r.followUp ?? "").ds(.caption).fixedSize(horizontal: false, vertical: true)
                if r.followUpDemo == true { DemoBadge() }
            }
        }
        .ds(.caption)
        .accessibilityElement(children: .combine)
    }

    /// 冇街坊喺外面：只讲匿名人数（全邨汇总；人数少于 10 唔出）。中午前讲「今朝」，之后讲「今日」。
    private var quietLine: AnyView? {
        guard let lm = store.landmarks.first,
              let passers = store.community.passersToday(at: lm), passers.count >= 10 else { return nil }
        let when = AppStore.hk.component(.hour, from: store.now) < 12 ? L.t("今朝", "今早", "this morning") : L.t("今日", "今天", "today")
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Label(L.t("\(when) \(passers.count) 人經過\(lm.name)", "\(when) \(passers.count) 人经过\(lm.name)", "\(passers.count) people passed \(lm.name) \(when)"), systemImage: "person.3")
                    .ds(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if passers.isDemo { DemoBadge() }
            }
        )
    }

    // MARK: 散步中：快捷反映

    private var reportCard: some View {
        // 「结束散步」喺散步主角卡 / 今日行紧嗰行（10-18：唔再放喺下面呢张卡）
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(L.t("呢度點樣？", "这里怎么样？", "How is it here?")).ds(.captionBold)
                Spacer(minLength: 0)
                if let k = reported {
                    Label(L.t("記低咗", "记下了", "Saved"), systemImage: "checkmark.circle.fill")
                        .ds(.captionBold)
                        .foregroundStyle(DS.accent)
                        .id(reportToken)
                        .transition(.scale(scale: 0.5, anchor: .trailing).combined(with: .opacity))
                        .accessibilityLabel(L.t("記低咗：\(k.label)", "记下了：\(k.label)", "Saved: \(k.label)"))
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
                    Text(k.label)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsSecondary)
            .accessibilityLabel(L.t("呢度\(k.label)", "这里\(k.label)", "\(k.label) here"))
        }
    }

    // MARK: 附近地標：场景里的地标很小、读屏摸不到，这里逐个列出；点一下打开资料卡（约街坊喺度、有冇櫈、有冇陰）。

    private var landmarksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TabSectionHeader(text: L.t("散步貼士", "散步贴心提醒", "Walk tips"))
            Text(L.t("附近可以唞腳嘅地方：有冇櫈、曬唔曬、夜晚有冇燈", "附近可以歇脚的地方：有没有凳子、晒不晒、晚上有没有灯", "Places nearby to rest: seats, sun or shade, lights after dark"))
                .ds(.caption).foregroundStyle(.secondary)
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
        let sun = v.map(AppStore.shadeWords) ?? store.lampWords(lm.id)
        return Button { store.select(.landmark(lm.id)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.name).ds(.body)
                    Text("\(lm.hasSeat ? L.t("有櫈", "有凳子", "Seats here") : L.t("冇櫈", "没凳子", "No seats")) · \(sun)")
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
        .accessibilityHint(L.t("撳一下睇詳情，可以約街坊喺度", "点一下看详情，可以约邻居在这里", "Tap for details. You can meet a neighbour here."))
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

    /// 回覆掣：主按钮占满，其余跟喺右边；放唔落（大字号）就上下排。
    private func replyButtons<P: View, R: View>(@ViewBuilder primary: () -> P, @ViewBuilder rest: () -> R) -> some View {
        let p = primary(), r = rest()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { p; r }
            VStack(spacing: 12) { p; r.frame(maxWidth: .infinity) }
        }
    }
}

/// 今日页细掣（撤回、唔出門选单）：淡橙底 + 橙框 + 深橙字，一睇就知撳得（10-18 测试）。
private struct SoftChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .foregroundStyle(DS.accentInk)
            .background(DS.accentSoft, in: shape)
            .overlay(shape.strokeBorder(DS.accent.opacity(0.55), lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DS.motion(DS.snappy), value: configuration.isPressed)
    }
}

/// 回覆别人嘅邀请：好（主按钮）/ 改時間 / 唔去。今日页主角卡同街坊页共用。
/// 「改時間」以前叫「換個時間」，会折成两行（UX 评审 27）；按咗即刻出一个唔同嘅时间（评审 12）。
struct InvitationButtons: View {
    @Environment(AppStore.self) private var store
    let a: Appointment

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                accept
                reschedule.fixedSize()
                decline.fixedSize()
            }
            VStack(spacing: 12) {
                accept
                HStack(spacing: 12) {
                    reschedule
                    decline
                }
            }
            VStack(spacing: 12) {
                accept
                reschedule
                decline
            }
        }
    }

    private var accept: some View {
        Button { store.acceptInvitation(a.id) } label: {
            Text(L.t("好", "好的", "OK")).lineLimit(1).frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsPrimary)
    }

    private var reschedule: some View {
        Button { store.rescheduleInvitation(a.id) } label: {
            Text(L.t("改時間", "改时间", "Other time")).lineLimit(1).fixedSize().frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
    }

    private var decline: some View {
        Button { store.declineInvitation(a.id) } label: {
            Text(L.t("唔去", "不去", "Can't go")).lineLimit(1).fixedSize().frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
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
                DemoNote(text: L.t("未連線：而家顯示上次嘅排行榜，連返網會自動更新。", "未联网：现在显示上次的排行榜，联网后会自动更新。", "Offline: showing the last leaderboard. It updates when you're back online."))
            } else if !store.community.isSimulated && rows.isEmpty {
                DemoNote(text: L.t("附近暫時未有其他人用街坊行。同區有人用，就會喺呢度出現。", "附近暂时没有其他人用街坊行。同区有人用，就会出现在这里。", "No one else nearby uses StreetWalk yet. When someone in your area does, they'll show here."))
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
                DemoNote(text: L.t("單機演示：排行榜上其他人係示範街坊，連續日數同獎牌係模擬嘅。", "单机演示：排行榜上其他人是示范邻居，连续天数和奖牌是模拟的。", "Demo: others on the leaderboard are demo neighbours. Streaks and medals are simulated."))
            }
        }
        .animation(DS.motion(DS.spring), value: rows.map(\.id))
    }

    /// 圈对圈：本月圈内总步数（我的由散步分钟估算，其他人和对面圈是示範数据）+ 上个月结果。
    private var circleCard: some View {
        let race = store.community.circleRace(placeName: store.map?.placeName ?? L.t("我哋", "我们", "Us"), myMonthSteps: store.myMonthSteps)
        let total = max(1, race.ourSteps + race.rivalSteps)
        let share = CGFloat(race.ourSteps) / CGFloat(total)
        let diff = race.ourSteps - race.rivalSteps
        let last = store.lastMonthResult
        // 未有对面圈嘅真数据：只讲本圈行咗几多，唔画对比条（唔造假）
        let versus = race.rivalSteps > 0 || race.isDemo
        return VStack(alignment: .leading, spacing: 12) {
            Text(race.rivalSteps == 0 ? L.t("本月\(race.ourName)一齊行咗 \(store.myMonthStepsEstimated ? "約 " : "")\(Self.steps(race.ourSteps))", "本月\(race.ourName)一起走了 \(store.myMonthStepsEstimated ? "约 " : "")\(Self.steps(race.ourSteps))", "This month our area walked \(store.myMonthStepsEstimated ? "about " : "")\(Self.steps(race.ourSteps)) together")
                 : L.t("本月\(race.ourName)\(diff >= 0 ? "領先" : "落後")\(race.rivalName) \(Self.steps(abs(diff)))", "本月\(race.ourName)\(diff >= 0 ? "领先" : "落后")\(race.rivalName) \(Self.steps(abs(diff)))", (diff >= 0 ? "This month our area is \(Self.steps(abs(diff))) ahead of next door" : "This month our area is \(Self.steps(abs(diff))) behind next door")))
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
                Text(last.weWon ? L.t("\(last.month) 月\(last.ourName)贏咗", "\(last.month) 月\(last.ourName)赢了", "\(enMonthName(last.month)): \(last.ourName) won") : L.t("\(last.month) 月\(last.rivalName)贏咗", "\(last.month) 月\(last.rivalName)赢了", "\(enMonthName(last.month)): \(last.rivalName) won"))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "rosette").foregroundStyle(Color(red: 0.80, green: 0.55, blue: 0.0))
            }
            .ds(.captionBold)
            .accessibilityLabel(last.weWon ? L.t("上個月 \(last.month) 月，\(last.ourName)贏咗，大家都有獎牌", "上个月 \(last.month) 月，\(last.ourName)赢了，大家都有奖牌", "Last month (\(enMonthName(last.month))), \(last.ourName) won. Everyone gets a medal") : L.t("上個月 \(last.month) 月，\(last.rivalName)贏咗", "上个月 \(last.month) 月，\(last.rivalName)赢了", "Last month (\(enMonthName(last.month))), \(last.rivalName) won"))
        }
    }

    /// 例如「3.2 萬步」「8,400 步」。
    static func steps(_ n: Int) -> String {
        if L.isEn { return n >= 10_000 ? "\(Int((Double(n) / 1000).rounded()))k steps" : "\(n) steps" }   // 英文：「32k steps」「8400 steps」
        return n >= 10_000 ? String(format: L.t("%.1f 萬步", "%.1f 万步", "%.1f 万步"), Double(n) / 10_000).replacingOccurrences(of: ".0 ", with: " ") : "\(n) 步"
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
        let label = L.t("第 \(rank) 名，\(r.listName)，連續 \(r.streakDays) 日\(r.hasMedal ? "，有獎牌" : "")\(r.isNeighbor && !r.todayLine.isEmpty ? "，\(r.todayLine)" : "")", "第 \(rank) 名，\(r.listName)，连续 \(r.streakDays) 天\(r.hasMedal ? "，有奖牌" : "")\(r.isNeighbor && !r.todayLine.isEmpty ? "，\(r.todayLine)" : "")", "No. \(rank), \(r.listName), \(r.streakDays) days in a row\(r.hasMedal ? ", has a medal" : "")\(r.isNeighbor && !r.todayLine.isEmpty ? ", \(r.todayLine)" : "")")

        if r.isNeighbor {
            Button { store.select(.person(r.id)) } label: { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
                .accessibilityHint(L.t("睇吓佢喺邊", "看看他在哪", "See where they are"))
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
            // 测试反馈 J-3：唔再出自己嘅今日一句（「今天走了 N 分钟」/「今天走到…」），今日页已经有，呢行只讲名次同连续日数
            Text(me.listName).ds(.bodyBold).fixedSize(horizontal: false, vertical: true)
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
        .accessibilityLabel(L.t("你排第 \(rank) 名，\(me.listName)，連續 \(me.streakDays) 日", "你排第 \(rank) 名，\(me.listName)，连续 \(me.streakDays) 天", "You're No. \(rank), \(me.listName), \(me.streakDays) days in a row"))
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
            Text(L.t("日", "天", "days")).ds(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 44)
        .accessibilityHidden(true)
    }
}

// MARK: - 街坊

/// 街坊：碰一碰（大掣，永远喺最上面）→ 约你嘅（卡上直接回覆）→ 我嘅约会 → 我嘅街坊（可收埋、可搜索）。
/// 测试反馈 D-3：以前有街坊时碰一碰放最底，100 个街坊就要划过 100 张卡先见到 → 改放最上面。
/// 一屏只一个橙色主按钮：有人约你时「好」系主按钮，碰一碰就用淡橙底 + 橙框（照样够醒目）。
struct NeighborsTab: View {
    @Environment(AppStore.self) private var store
    @State private var taps = 0
    @State private var toggles = 0
    @State private var unlinking: Resident?
    /// 「我的邻居」展开 / 收起：nil = 未撳过，按人数揀（≤ 3 个展开，多过 3 个收埋）。
    @State private var listOpen: Bool?
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @ScaledMetric(relativeTo: .body) private var bumpIcon: CGFloat = 34

    var body: some View {
        let lonely = store.neighbors.isEmpty
        let open = listOpen ?? (store.neighbors.count <= 3)
        VStack(alignment: .leading, spacing: 16) {
            bumpButton(primary: store.invitations.isEmpty)
            bumpNote

            if !store.invitations.isEmpty {
                TabSectionHeader(text: L.t("約你嘅（\(store.invitations.count)）", "约你的（\(store.invitations.count)）", "Invitations (\(store.invitations.count))"))
                ForEach(store.invitations) { a in
                    invitationCard(a).transition(.tabsInsert)
                }
            }

            if !store.myAppointments.isEmpty {
                TabSectionHeader(text: L.t("我嘅約會", "我的约会", "My walk plans"))
                VStack(spacing: 0) {
                    ForEach(Array(store.myAppointments.enumerated()), id: \.element.id) { i, a in
                        VStack(spacing: 0) {
                            if i > 0 { Divider() }
                            upcomingRow(a)
                        }
                    }
                }
                .dsCard(padding: 16)
                .transition(.tabsInsert)
            }

            neighborsHeader(open: open)
            if lonely {
                emptyState.transition(.opacity)
            } else if searching {
                searchField
                let found = store.neighbors(matching: query)
                if found.isEmpty {
                    Text(L.t("搵唔到「\(query)」。試吓打網名，或者座數、樓層。", "没找到「\(query)」。试试输入网名，或者楼栋、楼层。", "Can't find \"\(query)\". Try a name, block or floor."))
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(found) { n in neighborCard(n) }
                }
            } else if open {
                ForEach(store.neighbors) { n in
                    neighborCard(n).transition(.tabsInsert)
                }
            } else {
                collapsedRow.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(DS.motion(DS.spring), value: store.invitations)
        .animation(DS.motion(DS.spring), value: store.myAppointments)
        .animation(DS.motion(DS.spring), value: store.neighbors)
        .animation(DS.motion(DS.spring), value: open)
        .animation(DS.motion(DS.spring), value: searching)
        .onChange(of: store.neighbors.isEmpty) { _, empty in if empty { searching = false; query = "" } }
        #if DEBUG
        .task { previewSetup() }
        #endif
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .sensoryFeedback(.selection, trigger: toggles)
        .confirmationDialog(unlinking.map { L.t("唔再同\($0.name)做街坊？", "不再和\($0.name)做邻居？", "Stop being neighbours with \($0.name)?") } ?? "", isPresented: Binding(get: { unlinking != nil }, set: { if !$0 { unlinking = nil } }), titleVisibility: .visible) {
            if let r = unlinking {
                Button(L.t("唔再做街坊", "不再做邻居", "Stop being neighbours"), role: .destructive) { store.unlinkNeighbor(r.id); unlinking = nil }
            }
            Button(L.t("保留", "保留", "Keep"), role: .cancel) { unlinking = nil }
        } message: {
            Text(unlinkMessage(unlinking))
        }
    }

    /// 碰一碰大掣（最少 88 高，字跟设定嘅字体大小）：图标 + 两行字。
    private func bumpButton(primary: Bool) -> some View {
        Button {
            guard store.bumpStage == .idle else { return }
            taps += 1
            store.startBump()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: bumpIcon, weight: .semibold))
                    .frame(minWidth: bumpIcon * 1.3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("碰一碰加街坊", "碰一碰加邻居", "Tap phones to add a neighbour")).ds(.bodyBold)
                    Text(L.t("見到面，手機碰一下", "见面时，手机碰一下", "When you meet, tap phones")).ds(.caption).opacity(0.9)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(BumpButtonStyle(primary: primary))
        .accessibilityElement(children: .combine)
        .accessibilityHint(L.t("見到面，兩部手機碰一下就做街坊", "见面时两部手机碰一下就成为邻居", "When you meet, tap two phones together to become neighbours"))
    }

    /// 「我的邻居（N）⌄」：撳标题收埋 / 展开；右边🔍搜索（网名、座数、楼层）。冇街坊就只出标题。
    private func neighborsHeader(open: Bool) -> some View {
        let count = store.neighbors.count
        return HStack(spacing: 8) {
            if count == 0 {
                TabSectionHeader(text: L.t("我嘅街坊", "我的邻居", "My neighbours"))
            } else {
                Button {
                    toggles += 1
                    if searching { searching = false; query = ""; listOpen = true } else { listOpen = !open }
                } label: {
                    HStack(spacing: 8) {
                        Text(L.t("我嘅街坊（\(count)）", "我的邻居（\(count)）", "My neighbours (\(count))"))
                            .ds(.bodyBold)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.down")
                            .ds(.captionBold)
                            .foregroundStyle(DS.accentInk)
                            .rotationEffect(.degrees(open || searching ? 0 : -90))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(open || searching ? L.t("展開咗", "已展开", "Expanded") : L.t("收埋咗", "已收起", "Collapsed"))
                .accessibilityHint(open || searching ? L.t("撳一下收埋", "点一下收起", "Tap to collapse") : L.t("撳一下展開", "点一下展开", "Tap to expand"))
                Spacer(minLength: 8)
                Button {
                    toggles += 1
                    if searching {
                        searching = false
                        query = ""
                    } else {
                        searching = true
                    }
                } label: {
                    Image(systemName: searching ? "xmark" : "magnifyingglass")
                        .ds(.bodyBold)
                        .foregroundStyle(DS.accentInk)
                        .frame(minWidth: 52, minHeight: 52)
                        .background(Color(.tertiarySystemFill), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(searching ? L.t("唔搵喇", "关闭搜索", "Close search") : L.t("搵街坊", "搜索邻居", "Find neighbour"))
            }
        }
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(L.t("打網名或者座數", "输入网名或楼栋", "Type a name or block"), text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("清除", "清除", "Clear"))
            }
        }
        .ds(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DS.accent.opacity(0.5), lineWidth: 1.5))
        .transition(.opacity)
        .task { searchFocused = true }   // 一打开就出键盘
    }

    /// 收埋咗：一行小人头像 +「展開 N 位街坊」，成行撳得。
    private var collapsedRow: some View {
        let ns = store.neighbors
        return Button {
            toggles += 1
            listOpen = true
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: -14) {
                    ForEach(ns.prefix(3)) { n in
                        AvatarBadge(n, size: 44)
                            .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                    }
                }
                .accessibilityHidden(true)
                Text(L.t("展開 \(ns.count) 位街坊", "展开 \(ns.count) 位邻居", "Show \(ns.count) neighbours"))
                    .ds(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").ds(.captionBold).foregroundStyle(DS.accentInk).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .dsCard()
            .contentShape(RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    #if DEBUG
    /// 截图自检：-uiPreview neighborsMany（全部示範居民变街坊，睇收埋）/ neighborsSearch（再打开搜索）。配 -debugCommands「tab neighbors」。
    private func previewSetup() {
        guard UIPreview.is("neighborsMany") || UIPreview.is("neighborsSearch") else { return }
        for i in store.residents.indices where !store.residents[i].isMe { store.residents[i].isNeighbor = true }
        if UIPreview.is("neighborsSearch") { searching = true; query = "陈" }   // 简体打都搵到繁体名（AppStore.neighbors(matching:)）
    }
    #endif

    @ViewBuilder private var bumpNote: some View {
        if store.community.isSimulated {
            DemoNote(text: L.t("單機演示：碰一碰係模擬嘅，會碰到示範街坊。真機用超寬頻（兩部 iPhone 11 或之後）。", "单机演示：碰一碰是模拟的，会碰到示范邻居。真机用超宽带（两部 iPhone 11 或更新机型）。", "Demo: Tap phones is simulated and finds demo neighbours. Real phones use Ultra Wideband (two iPhone 11 or newer)."))
        } else if store.backendOffline {
            DemoNote(text: L.t("未連線：街坊出門、約會要連返網先收到。你做嘅改動會留住，連返網就送出。", "未联网：邻居出门、约会要联网才收得到。你的改动会保留，联网后就发送。", "Offline: neighbours going out and walk plans arrive when you're online. Your changes are kept and sent when you're back online."))
        }
    }

    /// 解除街坊的说明：有未完成的约会就讲清楚对方会收到「約會取消」（审核 A70）。
    private func unlinkMessage(_ r: Resident?) -> String {
        let open = r.map { r in store.appointments.filter { $0.partnerID == r.id && $0.isOpen }.count } ?? 0
        let base = L.t("佢唔會收到解除通知。之後佢出門你唔會知，佢亦見唔到你。", "对方不会收到解除通知。之后对方出门你不会知道，对方也看不到你。", "They won't be told. After this you won't know when they go out, and they can't see you.")
        let meet = open > 0 ? L.t("你哋 \(open) 個未完成嘅約會會取消，佢會收到「約會取消」。", "你们 \(open) 个未完成的约会会取消，对方会收到「约会取消」。", " Your \(open) open walk plan(s) will be cancelled, and they'll be told.") : ""
        return base + meet + L.t("想再做街坊，要見面再碰一碰。", "想再做邻居，要见面再碰一碰。", " To be neighbours again, meet and tap phones again.")
    }

    private func invitationCard(_ a: Appointment) -> some View {
        let p = store.resident(a.partnerID)
        let name = p?.name ?? L.t("街坊", "邻居", "Neighbour")
        let place = store.placeName(a.landmarkID) ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let p { AvatarBadge(p) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("\(name)約你\(store.dayTimeLabel(a.date)) · \(place)", "\(name)约你\(store.dayTimeLabel(a.date)) · \(place)", "\(name) invited you: \(store.dayTimeLabel(a.date)) · \(place)"))
                        .ds(.bodyBold)
                        .contentTransition(.numericText())
                        .fixedSize(horizontal: false, vertical: true)
                    if p?.isDemo == true { DemoBadge(text: L.t("示範街坊", "示范邻居", "Demo neighbour")) }
                }
            }
            if !store.meetupReason(a).isEmpty {
                Text(TemplateAI.whyHere(store.meetupReason(a)))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InvitationButtons(a: a)
        }
        .dsCard()
        .animation(DS.motion(DS.spring), value: a.date)
    }

    private func upcomingRow(_ a: Appointment) -> some View {
        let name = store.resident(a.partnerID)?.name ?? L.t("街坊", "邻居", "Neighbour")
        let place = store.placeName(a.landmarkID) ?? ""
        let status: String = {
            switch a.status {
            case .waiting: return L.t("等緊\(name)確認", "等\(name)确认", "Waiting for \(name)")
            case .accepted: return L.t("約好咗", "约好了", "All set")
            case .done: return L.t("行咗", "走过了", "Walked")
            case .cancelled: return L.t("取消咗", "取消了", "Cancelled")
            case .expired: return L.t("過咗期", "过期了", "Expired")
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
        .accessibilityHint(L.t("改時間、地點或者取消", "改时间、地点或取消", "Change time, place or cancel"))
    }

    private func neighborCard(_ n: Resident) -> some View {
        // 没有出门消息不等于在家（对方可能关了发送，或回家后隐身），不要说死。
        let status: String = {
            if n.isOut, let place = store.placeName(n.atLandmarkID) { return L.t("出咗門 · \(place)附近", "出门了 · \(place)附近", "Out · near \(place)") }
            return L.t("冇出門消息", "没有出门消息", "No out-and-about news")
        }()
        // F6：接收、发送分开开关。
        let receive = store.resident(n.id)?.receiveRemind ?? false
        let send = store.resident(n.id)?.sendRemind ?? false
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
                    Text(L.t("約佢行", "约他散步", "Invite for a walk")).frame(maxWidth: stacked ? .infinity : nil)
                }
                .buttonStyle(.dsSecondary)
            }
            Divider()
            RemindRow(text: L.t("佢出門話我知", "他出门告诉我", "Tell me when they go out"), symbol: "bell.fill", on: receive) {
                toggles += 1
                store.setRemind(n.id, receive: !receive)
            }
            RemindRow(text: L.t("我出門話佢知", "我出门告诉他", "Tell them when I go out"), symbol: "figure.walk", on: send) {
                toggles += 1
                store.setRemind(n.id, send: !send)
            }
            Button { unlinking = n } label: {
                Text(L.t("唔再做街坊", "不再做邻居", "Stop being neighbours"))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L.t("佢唔會收到解除通知", "对方不会收到解除通知", "They won't be told"))
        }
        .dsCard()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.wave.2")
                .ds(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(L.t("仲未有街坊。見到面碰一碰，就會喺呢度出現。", "还没有邻居。见面碰一碰，就会出现在这里。", "No neighbours yet. Meet someone and tap phones, and they'll show here."))
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

/// 英文月份（排行榜上个月结果）：10 → "October"。
fileprivate func enMonthName(_ m: Int) -> String {
    let names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    return (1...12).contains(m) ? names[m - 1] : "month \(m)"
}

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

/// 邻居页碰一碰大掣：主按钮 = 橙底白字；唔系主按钮（有人约你时）= 淡橙底 + 橙框 + 深橙字，照样醒目。
private struct BumpButtonStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
        configuration.label
            .foregroundStyle(primary ? Color.white : DS.accentInk)
            .background(primary ? AnyShapeStyle(DS.accent) : AnyShapeStyle(DS.accentSoft), in: shape)
            .overlay(shape.strokeBorder(primary ? Color.clear : DS.accent, lineWidth: 2))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DS.motion(DS.snappy), value: configuration.isPressed)
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

/// 栏目标题：黑色粗体 24（以前灰色小字，分唔出呢段讲乜，UX 评审 26）。
private struct TabSectionHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .ds(.bodyBold)
            .foregroundStyle(.primary)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 出门提醒一行：成行都撳得（最少 56 高），右边大掣写「開 / 閂」（以前系 51×31 嘅系统开关，UX 评审 28）。
private struct RemindRow: View {
    let text: String
    let symbol: String
    let on: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Label(text, systemImage: symbol)
                    .ds(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                // 唔用实心橙（一屏只一个橙色主按钮）：开 = 淡橙底 + 橙框，閂 = 灰底
                Label(on ? L.t("開", "开", "On") : L.t("閂", "关", "Off"), systemImage: on ? "checkmark" : "xmark")
                    .labelStyle(.titleAndIcon)
                    .ds(.button)
                    .foregroundStyle(on ? DS.accentInk : .secondary)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 96, minHeight: 48)
                    .background(on ? DS.accentSoft : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? DS.accent : Color.clear, lineWidth: 2))
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DS.motion(DS.snappy), value: on)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityValue(on ? L.t("開咗", "已开", "On") : L.t("閂咗", "已关", "Off"))
        .accessibilityHint(L.t("撳一下\(on ? "閂" : "開")", "点一下\(on ? "关" : "开")", "Tap to turn \(on ? "off" : "on")"))
        .accessibilityAddTraits(.isToggle)
    }
}

/// 今日一句：逐字淡入；句子一变就重新播一次。减少动态效果时直接显示。
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
        let name = target.flatMap { store.resident($0.partnerID)?.name } ?? L.t("街坊", "邻居", "Neighbour")
        content.confirmationDialog(target.map { L.t("取消同\(name)\(store.dayTimeLabel($0.date))嘅約？", "取消和\(name)\(store.dayTimeLabel($0.date))的约？", "Cancel the walk with \(name), \(store.dayTimeLabel($0.date))?") } ?? "",
                                   isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }), titleVisibility: .visible) {
            if let a = target {
                Button(L.t("取消約會", "取消约会", "Cancel walk plan"), role: .destructive) { store.cancelMeetup(a.id); target = nil }
            }
            Button(L.t("唔取消", "不取消", "Keep"), role: .cancel) { target = nil }
        } message: {
            Text(L.t("會話俾\(name)知。", "会告诉\(name)。", "\(name) will be told."))
        }
    }
}

extension View {
    func cancelMeetupDialog(_ target: Binding<Appointment?>) -> some View { modifier(CancelMeetupDialog(target: target)) }
}
