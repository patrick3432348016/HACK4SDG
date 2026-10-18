import SwiftUI

// Three-tab content only; MainView supplies ScrollView, title and 16 pt side margins.

// MARK: - Today

/// UX 9: one urgency-selected hero card with one primary action; reduce other information to secondary rows.
/// Priority: incoming requests, today's departure, walking companion/outside neighbor, active walk, weather invitation, first pairing.
struct TodayTab: View {
    @Environment(AppStore.self) private var store
    @State private var reported: ReportKind?
    @State private var reportToken = 0
    @State private var taps = 0
    @State private var cancelling: Appointment?

    /// Hero-card types.
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

    /// Select the most urgent hero card.
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
        VStack(alignment: .leading, spacing: 16) {
            FirstDayCard()      // FirstDayCard controls its own visibility and remains until manually dismissed after completion.
            heroCard(hero)
                .id(heroKey(hero))
                .transition(.tabsInsert)
            LocationCards()     // Check for a moved home or incomplete automatic-recording permissions (LocationViews).
            minorRows(hero)
            if store.walk != nil {
                reportCard.transition(.tabsInsert)
            }
            landmarksCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: Hero card

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

    /// Hero container uses 20 pt padding, orange outline and a small category label above.
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

    /// Person plus two text lines, with a bold first line.
    private func personLine(_ p: Resident?, _ title: String, _ detail: String? = nil, demo: Bool = false) -> some View {
        HStack(spacing: 12) {
            if let p { AvatarBadge(p, size: 60) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).ds(.bodyBold).fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail).ds(.body).fixedSize(horizontal: false, vertical: true)
                }
                if demo { DemoBadge(text: L.t("示範街坊", "示范邻居")) }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // Incoming finding request also appears atop Today, in addition to the bottom card.

    @ViewBuilder private var incomingFindHero: some View {
        if let ask = store.incomingFind, let p = store.resident(ask.fromID) {
            heroFrame(L.t("等你回覆", "等你回复"), symbol: "bell.badge.fill") {
                personLine(p, L.t("\(p.name)想過嚟搵你，方唔方便？", "\(p.name)想过来找你，方便吗？"),
                           store.placeName(ask.landmarkID).map { L.t("佢會過去\($0)附近搵你。", "他会去\($0)附近找你。") })
                replyButtons {
                    Button { taps += 1; store.answerIncomingFind(true) } label: { Text(L.t("好", "好")).lineLimit(1).frame(maxWidth: .infinity) }
                        .buttonStyle(.dsPrimary)
                } rest: {
                    Button { taps += 1; store.answerIncomingFind(false) } label: { Text(L.t("唔方便", "不方便")).lineLimit(1).fixedSize() }
                        .buttonStyle(.dsSecondary)
                }
            }
        }
    }

    // Incoming invitations allow direct accept, reschedule or decline.

    private func invitationHero(_ a: Appointment) -> some View {
        let p = store.resident(a.partnerID)
        let name = p?.name ?? L.t("街坊", "邻居")
        let place = store.placeName(a.landmarkID) ?? ""
        let more = store.invitations.count - 1
        return heroFrame(more > 0 ? L.t("等你回覆（仲有 \(more) 個）", "等你回复（还有 \(more) 个）") : L.t("等你回覆", "等你回复"), symbol: "envelope.fill") {
            personLine(p, L.t("\(name)約你一齊行", "\(name)约你一起走"), "\(store.dayTimeLabel(a.date)) · \(place)", demo: p?.isDemo == true)
            if !a.reason.isEmpty {
                Text(a.reason).ds(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            InvitationButtons(a: a)
        }
    }

    // UX 13: within 30 minutes of a meeting, Departure is primary; combine edit/cancel behind one control.

    private func appointmentHero(_ a: Appointment) -> some View {
        let p = store.resident(a.partnerID)
        let name = p?.name ?? L.t("街坊", "邻居")
        let place = store.placeName(a.landmarkID) ?? ""
        let left = a.date.timeIntervalSince(store.now)
        let soon = left <= 30 * 60 && left > -3600
        return heroFrame(L.t("今日約會", "今天的约会"), symbol: "calendar.badge.checkmark") {
            personLine(p, L.t("約咗\(name)", "约了\(name)"), "\(store.dayTimeLabel(a.date)) · \(place)", demo: p?.isDemo == true)
            // Both phones use neutral confirmed wording without attributing who accepted.
            Label(L.t("約好咗", "约好了"), systemImage: "checkmark.circle.fill")
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
            Label(L.t("出發", "出发"), systemImage: "figure.walk").lineLimit(1).frame(maxWidth: .infinity)
        }
        .tabButtonStyle(primary: primary)
    }

    /// One edit/cancel menu offers rescheduling or cancellation, with a further cancellation confirmation.
    private func changeMenu(_ a: Appointment, stacked: Bool) -> some View {
        Menu {
            Button { store.startEditing(a.id) } label: { Label(L.t("改時間地點", "改时间地点"), systemImage: "calendar") }
            Button(role: .destructive) { cancelling = a } label: { Label(L.t("取消約會", "取消约会"), systemImage: "xmark.circle") }
        } label: {
            Text(L.t("改 / 取消", "改 / 取消")).lineLimit(1).fixedSize().frame(maxWidth: stacked ? .infinity : nil)
        }
        .menuStyle(.button)
        .buttonStyle(.dsSecondary)
        .accessibilityHint(L.t("改時間地點，或者取消約會", "改时间地点，或者取消约会"))
    }

    // UX 23: after meeting, show walking together rather than prompting finding again.

    @ViewBuilder private func togetherHero(_ id: String) -> some View {
        if let p = store.resident(id) {
            heroFrame(L.t("一齊行緊", "一起走着"), symbol: "figure.2") {
                personLine(p, L.t("同\(p.name)一齊行緊", "和\(p.name)一起走着"), L.t("慢慢行，攰就坐低唞吓。", "慢慢走，累了就坐下歇歇。"))
                Button {
                    taps += 1
                    store.walkingWith = nil
                } label: {
                    Text(L.t("行完喇", "走完了")).lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsSecondary)
            }
        }
    }

    // For an outside neighbor, offer invitation or, during a walk, finding.

    @ViewBuilder private func outHero(_ id: String) -> some View {
        if let n = store.resident(id) {
            let place = store.placeName(n.atLandmarkID)
            let walking = store.walk != nil
            heroFrame(L.t("而家喺外面", "现在在外面"), symbol: "figure.walk") {
                personLine(n, place.map { L.t("\(n.name)而家喺\($0)附近", "\(n.name)现在在\($0)附近") } ?? L.t("\(n.name)出咗門", "\(n.name)出门了"), nil, demo: n.isDemo)
                Button {
                    taps += 1
                    if walking { store.goFind(n.id) } else { store.proposeMeetup(with: n.id) }
                } label: {
                    Label(walking ? L.t("過去搵佢", "过去找他") : L.t("約佢一齊行", "约他一起走"), systemImage: walking ? "figure.walk" : "calendar")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
            }
        }
    }

    // With no outside neighbor during a walk, show minutes, passed places and rest guidance.

    private var walkingHero: some View {
        heroFrame(L.t("行緊", "散步中"), symbol: "figure.walk") {
            if let w = store.walk {
                Text(L.t("行緊 \(w.minutes) 分鐘 · 經過 \(w.passed.count) 個地方", "已走 \(w.minutes) 分钟 · 经过 \(w.passed.count) 个地方"))
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
                Text(L.t("返到屋企會自動記低。", "回到家会自动记下。")).ds(.caption).foregroundStyle(.secondary)
            }
        }
        .animation(DS.motion(DS.spring), value: store.paceTip)
    }

    // With neighbors but none outside, show weather/shade guidance and a shared-walk invitation.

    private var walkTipHero: some View {
        let rain = store.weather == .rain
        return heroFrame(L.t("今日去唔去行？", "今天去走走吗？"), symbol: rain ? "cloud.heavyrain.fill" : "sun.max.fill") {
            Text(store.weatherTip ?? L.t("約個街坊一齊出去行吓？", "约个邻居一起出去走走？"))
                .ds(.body)
                .fixedSize(horizontal: false, vertical: true)
            inviteNeighborButton(primary: !rain)
        }
    }

    /// Invite the sole neighbor directly, otherwise ask which neighbor.
    @ViewBuilder private func inviteNeighborButton(primary: Bool) -> some View {
        let ns = store.neighbors
        if ns.count == 1, let n = ns.first {
            Button { taps += 1; store.proposeMeetup(with: n.id) } label: {
                Label(L.t("約\(n.name)一齊行", "约\(n.name)一起走"), systemImage: "calendar").lineLimit(1).frame(maxWidth: .infinity)
            }
            .tabButtonStyle(primary: primary)
        } else {
            Menu {
                ForEach(ns) { n in Button(n.name) { taps += 1; store.proposeMeetup(with: n.id) } }
            } label: {
                Label(L.t("約街坊一齊行", "约邻居一起走"), systemImage: "calendar").lineLimit(1).frame(maxWidth: .infinity)
            }
            .menuStyle(.button)
            .tabButtonStyle(primary: primary)
        }
    }

    // Without neighbors, suggest going out and pairing in person.

    private var noNeighborsHero: some View {
        heroFrame(L.t("第一步", "第一步"), symbol: "person.2.wave.2") {
            Text(L.t("仲未有街坊", "还没有邻居")).ds(.bodyBold)
            Text(L.t("出門行吓，見到面碰一碰，就係街坊。", "出门走走，见面碰一碰，就是邻居。"))
                .ds(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                guard store.bumpStage == .idle else { return }
                taps += 1
                store.startBump()
            } label: {
                Label(L.t("碰一碰加街坊", "碰一碰加邻居"), systemImage: "iphone.radiowaves.left.and.right").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
        }
    }

    // MARK: Secondary information rows

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
            // Feedback: list up to three future confirmed or pending meetings so tomorrow's invitation remains visible on Today.
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

    /// Daily minutes/streak, greeting and staying-home controls.
    private var statusRow: some View {
        let me = store.me
        return VStack(alignment: .leading, spacing: 8) {
            if let w = store.walk {
                Label(L.t("行緊 \(w.minutes) 分鐘 · 經過 \(w.passed.count) 個地方", "已走 \(w.minutes) 分钟 · 经过 \(w.passed.count) 个地方"), systemImage: "figure.walk")
                    .ds(.body)
                    .contentTransition(.numericText(value: Double(w.minutes)))
                    .fixedSize(horizontal: false, vertical: true)
                if let tip = store.paceTip {
                    Label(tip, systemImage: "chair.lounge.fill").ds(.caption).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(L.t("今日行咗 \(store.todayMinutes) 分鐘 · 連續 \(me.streakDays) 日", "今天走了 \(store.todayMinutes) 分钟 · 连续 \(me.streakDays) 天"))
                    .ds(.body)
                    .contentTransition(.numericText(value: Double(store.todayMinutes * 1000 + me.streakDays)))
                    .fixedSize(horizontal: false, vertical: true)
                if store.streakHasDemo { DemoBadge(text: L.t("含示範紀錄", "含示范记录")) }
                if !me.todayLine.isEmpty {
                    TypeInText(text: me.todayLine).ds(.caption).foregroundStyle(.secondary)
                }
                leaveRow(me)
            }
        }
        .animation(DS.motion(DS.spring), value: me.onLeave)
        .animation(DS.motion(DS.snappy), value: store.todayMinutes)
    }

    /// UX 16: staying-home wording explains streak preservation without work-like leave terminology.
    private func leaveRow(_ me: Resident) -> some View {
        HStack(spacing: 12) {
            if let leave = store.leaveSummary {
                Label(leave, systemImage: "moon.zzz.fill")
                    .ds(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                Spacer(minLength: 0)
                Button(L.t("撤回", "撤回")) { store.withdrawLeave() }
                    .ds(.captionBold)
                    .foregroundStyle(DS.accentInk)
                    .frame(minHeight: 44)
                    .fixedSize()
            } else {
                Menu {
                    ForEach(store.leaveMenuChoices, id: \.self) { r in Button(store.leaveMenuLabel(r)) { store.requestLeave(days: r.days, startOffset: r.startOffset) } }
                    if let w = store.withdrawLeaveLabel {
                        Divider()
                        Button(w, role: .destructive) { store.withdrawLeave() }
                    }
                } label: {
                    Label(L.t("今日唔行（日數照計）", "今天不走（天数照算）"), systemImage: "moon.zzz")
                        .ds(.caption)
                        .foregroundStyle(DS.accentInk)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityHint(L.t("揀邊日唔行，連續日數會保留", "选哪天不走，连续天数会保留"))
                Spacer(minLength: 0)
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
        let name = store.resident(a.partnerID)?.name ?? L.t("街坊", "邻居")
        return Button { store.tab = .neighbors } label: {
            HStack(spacing: 12) {
                Label(L.t("\(name)約你\(store.dayTimeLabel(a.date))", "\(name)约你\(store.dayTimeLabel(a.date))"), systemImage: "envelope.fill")
                    .ds(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(L.t("回覆", "回复")).ds(.captionBold).foregroundStyle(DS.accentInk)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L.t("去「街坊」頁回覆", "去「邻居」页回复"))
    }

    /// Other meetings today, including pending/second meetings, open edit/cancel on tap.
    private func appointmentRow(_ a: Appointment) -> some View {
        let name = store.resident(a.partnerID)?.name ?? L.t("街坊", "邻居")
        let place = store.placeName(a.landmarkID) ?? ""
        let status = a.status == .waiting ? L.t("等緊\(name)確認", "等\(name)确认") : L.t("約好咗\(name)", "约好了\(name)")
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
        .accessibilityHint(L.t("改時間、地點或者取消", "改时间、地点或取消"))
    }

    /// Other outside neighbors use one compact row and action each.
    private func outRow(_ n: Resident) -> some View {
        let place = store.placeName(n.atLandmarkID)
        let walking = store.walk != nil
        return HStack(spacing: 12) {
            AvatarBadge(n, size: 40)
            Text(place.map { "\(n.name) · \($0)附近" } ?? n.name)
                .ds(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                taps += 1
                if walking { store.goFind(n.id) } else { store.proposeMeetup(with: n.id) }
            } label: {
                Text(walking ? L.t("過去搵佢", "过去找他") : L.t("約佢", "约他")).lineLimit(1).fixedSize()
            }
            .buttonStyle(.dsSecondary)
        }
    }

    private func followUpRow(_ r: Report) -> some View {
        let place = store.landmark(r.landmarkID)?.name ?? L.t("呢度", "这里")
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(DS.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("你反映過「\(place)\(r.kind.label)」", "你反映过「\(place)\(r.kind.label)」")).ds(.caption).foregroundStyle(.secondary)
                Text(r.followUp ?? "").ds(.caption).fixedSize(horizontal: false, vertical: true)
                if r.followUpDemo == true { DemoBadge() }
            }
        }
        .ds(.caption)
        .accessibilityElement(children: .combine)
    }

    /// With no outside neighbors, show only an estate aggregate of at least 10; use morning wording before noon, today afterward.
    private var quietLine: AnyView? {
        guard let lm = store.landmarks.first,
              let passers = store.community.passersToday(at: lm), passers.count >= 10 else { return nil }
        let when = AppStore.hk.component(.hour, from: store.now) < 12 ? L.t("今朝", "今早") : L.t("今日", "今天")
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Label(L.t("\(when) \(passers.count) 人經過\(lm.name)", "\(when) \(passers.count) 人经过\(lm.name)"), systemImage: "person.3")
                    .ds(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if passers.isDemo { DemoBadge() }
            }
        )
    }

    // MARK: Quick reports during walks

    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(L.t("呢度點樣？", "这里怎么样？")).ds(.captionBold)
                Spacer(minLength: 0)
                if let k = reported {
                    Label(L.t("記低咗", "记下了"), systemImage: "checkmark.circle.fill")
                        .ds(.captionBold)
                        .foregroundStyle(DS.accent)
                        .id(reportToken)
                        .transition(.scale(scale: 0.5, anchor: .trailing).combined(with: .opacity))
                        .accessibilityLabel(L.t("記低咗：\(k.label)", "记下了：\(k.label)"))
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
            .accessibilityLabel(L.t("呢度\(k.label)", "这里\(k.label)"))
        }
    }

    // MARK: Nearby landmarks listed accessibly; tap for invitations, seating and shade details

    private var landmarksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TabSectionHeader(text: L.t("附近地標", "附近地标"))
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
        // Use shadeValue after sunset, returning nil instead of the misleading computed 100% shade.
        let v = store.shade == nil ? 0 : store.shadeValue(lm.id, at: store.now)
        let sun = v.map(AppStore.shadeWords) ?? L.t("太陽落咗山", "太阳下山了")
        return Button { store.select(.landmark(lm.id)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.name).ds(.body)
                    Text("\(lm.hasSeat ? L.t("有櫈", "有凳子") : L.t("冇櫈", "没凳子")) · \(sun)")
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
        .accessibilityHint(L.t("撳一下睇詳情，可以約街坊喺度", "点一下看详情，可以约邻居在这里"))
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

    /// Primary reply fills available width; secondary actions follow at right or stack when text grows.
    private func replyButtons<P: View, R: View>(@ViewBuilder primary: () -> P, @ViewBuilder rest: () -> R) -> some View {
        let p = primary(), r = rest()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { p; r }
            VStack(spacing: 12) { p; r.frame(maxWidth: .infinity) }
        }
    }
}

/// Shared Today/Neighbors incoming-invitation controls: accept primary, change time, decline.
/// UX 27 / 12: shorter reschedule wording avoids wrapping and immediately suggests a different time.
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
            Text(L.t("好", "好的")).lineLimit(1).frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsPrimary)
    }

    private var reschedule: some View {
        Button { store.rescheduleInvitation(a.id) } label: {
            Text(L.t("改時間", "改时间")).lineLimit(1).fixedSize().frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
    }

    private var decline: some View {
        Button { store.declineInvitation(a.id) } label: {
            Text(L.t("唔去", "不去")).lineLimit(1).fixedSize().frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
    }
}


// MARK: - Leaderboard

/// Show circle total steps and rankings by streak, with nickname/avatar for everyone and extra details for neighbors only.
/// Never show non-neighbors' building or floor (2026-10-10).
/// MainView pins BoardMyRow above the tab bar at every text size.
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
                DemoNote(text: L.t("未連線：而家顯示上次嘅排行榜，連返網會自動更新。", "未联网：现在显示上次的排行榜，联网后会自动更新。"))
            } else if !store.community.isSimulated && rows.isEmpty {
                DemoNote(text: L.t("附近暫時未有其他人用街坊行。同區有人用，就會喺呢度出現。", "附近暂时没有其他人用街坊行。同区有人用，就会出现在这里。"))
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
            // Put explanations below rankings so ranks remain on the first screen.
            if store.community.isSimulated {
                DemoNote(text: L.t("單機演示：排行榜上其他人係示範街坊，連續日數同獎牌係模擬嘅。", "单机演示：排行榜上其他人是示范邻居，连续天数和奖牌是模拟的。"))
            }
        }
        .animation(DS.motion(DS.spring), value: rows.map(\.id))
    }

    /// Circle comparison combines local/estimated own steps and labeled demo opponents, plus prior-month results.
    private var circleCard: some View {
        let race = store.community.circleRace(placeName: store.map?.placeName ?? L.t("我哋", "我们"), myMonthSteps: store.myMonthSteps)
        let total = max(1, race.ourSteps + race.rivalSteps)
        let share = CGFloat(race.ourSteps) / CGFloat(total)
        let diff = race.ourSteps - race.rivalSteps
        let last = store.lastMonthResult
        // Without actual opposing-circle data, show only my circle's total and omit the comparison bar.
        let versus = race.rivalSteps > 0 || race.isDemo
        return VStack(alignment: .leading, spacing: 12) {
            Text(race.rivalSteps == 0 ? L.t("本月\(race.ourName)一齊行咗 \(store.myMonthStepsEstimated ? "約 " : "")\(Self.steps(race.ourSteps))", "本月\(race.ourName)一起走了 \(store.myMonthStepsEstimated ? "约 " : "")\(Self.steps(race.ourSteps))")
                 : L.t("本月\(race.ourName)\(diff >= 0 ? "領先" : "落後")\(race.rivalName) \(Self.steps(abs(diff)))", "本月\(race.ourName)\(diff >= 0 ? "领先" : "落后")\(race.rivalName) \(Self.steps(abs(diff)))"))
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
            // F4: winning-circle avatars receive demo medals; keep the Demo label inline and the card short enough to show first place.
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
                Text(last.weWon ? L.t("\(last.month) 月\(last.ourName)贏咗", "\(last.month) 月\(last.ourName)赢了") : L.t("\(last.month) 月\(last.rivalName)贏咗", "\(last.month) 月\(last.rivalName)赢了"))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "rosette").foregroundStyle(Color(red: 0.80, green: 0.55, blue: 0.0))
            }
            .ds(.captionBold)
            .accessibilityLabel(last.weWon ? L.t("上個月 \(last.month) 月，\(last.ourName)贏咗，大家都有獎牌", "上个月 \(last.month) 月，\(last.ourName)赢了，大家都有奖牌") : L.t("上個月 \(last.month) 月，\(last.rivalName)贏咗", "上个月 \(last.month) 月，\(last.rivalName)赢了"))
        }
    }

    /// Localized compact step counts.
    static func steps(_ n: Int) -> String {
        n >= 10_000 ? String(format: L.t("%.1f 萬步", "%.1f 万步"), Double(n) / 10_000).replacingOccurrences(of: ".0 ", with: " ") : "\(n) 步"
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
                // Daily greetings are visible only to neighbors because they may reveal landmarks or floors.
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
        let label = L.t("第 \(rank) 名，\(r.listName)，連續 \(r.streakDays) 日\(r.hasMedal ? "，有獎牌" : "")\(r.isNeighbor && !r.todayLine.isEmpty ? "，\(r.todayLine)" : "")", "第 \(rank) 名，\(r.listName)，连续 \(r.streakDays) 天\(r.hasMedal ? "，有奖牌" : "")\(r.isNeighbor && !r.todayLine.isEmpty ? "，\(r.todayLine)" : "")")

        if r.isNeighbor {
            Button { store.select(.person(r.id)) } label: { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
                .accessibilityHint(L.t("睇吓佢喺邊", "看看他在哪"))
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
        }
    }
}

/// MainView pins my leaderboard row in the safe area above the tab bar.
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
                // At large text sizes, keep only rank and name in the pinned row; accessibility still reads the daily summary.
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
        .accessibilityLabel(L.t("你排第 \(rank) 名，\(me.listName)，連續 \(me.streakDays) 日，\(me.todayLine)", "你排第 \(rank) 名，\(me.listName)，连续 \(me.streakDays) 天，\(me.todayLine)"))
    }
}

/// Right-side streak count determines rank.
private struct BoardStreak: View {
    let days: Int
    var body: some View {
        VStack(spacing: 0) {
            Text("\(days)")
                .ds(.bodyBold)
                .monospacedDigit()
                .foregroundStyle(days > 0 ? DS.accentInk : .secondary)
                .contentTransition(.numericText(value: Double(days)))
            Text(L.t("日", "天")).ds(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 44)
        .accessibilityHidden(true)
    }
}

// MARK: - Neighbors

/// Neighbors order: received invitations with inline replies, my meetups, my neighbors with invitation/outing controls, then pairing.
/// With no neighbors, put pairing first as the primary orange action; otherwise place it last as a secondary action (UX finding 5 / section 4).
struct NeighborsTab: View {
    @Environment(AppStore.self) private var store
    @State private var taps = 0
    @State private var toggles = 0
    @State private var unlinking: Resident?

    var body: some View {
        let lonely = store.neighbors.isEmpty
        VStack(alignment: .leading, spacing: 16) {
            if !store.invitations.isEmpty {
                TabSectionHeader(text: L.t("約你嘅（\(store.invitations.count)）", "约你的（\(store.invitations.count)）"))
                ForEach(store.invitations) { a in
                    invitationCard(a).transition(.tabsInsert)
                }
            }

            if lonely {
                bumpButton(primary: store.invitations.isEmpty)
                bumpNote
            }

            if !store.myAppointments.isEmpty {
                TabSectionHeader(text: L.t("我嘅約會", "我的约会"))
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

            TabSectionHeader(text: L.t("我嘅街坊", "我的邻居"))
            if lonely {
                emptyState.transition(.opacity)
            } else {
                ForEach(store.neighbors) { n in
                    neighborCard(n).transition(.tabsInsert)
                }
                bumpButton(primary: false)
                bumpNote
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(DS.motion(DS.spring), value: store.invitations)
        .animation(DS.motion(DS.spring), value: store.myAppointments)
        .animation(DS.motion(DS.spring), value: store.neighbors)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .sensoryFeedback(.selection, trigger: toggles)
        .confirmationDialog(unlinking.map { L.t("唔再同\($0.name)做街坊？", "不再和\($0.name)做邻居？") } ?? "", isPresented: Binding(get: { unlinking != nil }, set: { if !$0 { unlinking = nil } }), titleVisibility: .visible) {
            if let r = unlinking {
                Button(L.t("唔再做街坊", "不再做邻居"), role: .destructive) { store.unlinkNeighbor(r.id); unlinking = nil }
            }
            Button("保留", role: .cancel) { unlinking = nil }
        } message: {
            Text(unlinkMessage(unlinking))
        }
    }

    private func bumpButton(primary: Bool) -> some View {
        Button {
            guard store.bumpStage == .idle else { return }
            taps += 1
            store.startBump()
        } label: {
            Label {
                Text(L.t("碰一碰加街坊", "碰一碰加邻居"))
            } icon: {
                Image(systemName: "iphone.radiowaves.left.and.right")
            }
            .padding(.vertical, primary ? 8 : 0)
            .frame(maxWidth: .infinity)
        }
        .tabButtonStyle(primary: primary)
    }

    @ViewBuilder private var bumpNote: some View {
        if store.community.isSimulated {
            DemoNote(text: L.t("單機演示：碰一碰係模擬嘅，會碰到示範街坊。真機用超寬頻（兩部 iPhone 11 或之後）。", "单机演示：碰一碰是模拟的，会碰到示范邻居。真机用超宽带（两部 iPhone 11 或更新机型）。"))
        } else if store.backendOffline {
            DemoNote(text: L.t("未連線：街坊出門、約會要連返網先收到。你做嘅改動會留住，連返網就送出。", "未联网：邻居出门、约会要联网才收得到。你的改动会保留，联网后就发送。"))
        }
    }

    /// A70: explain that unlinking with unfinished meetings sends meeting-cancellation notices.
    private func unlinkMessage(_ r: Resident?) -> String {
        let open = r.map { r in store.appointments.filter { $0.partnerID == r.id && $0.isOpen }.count } ?? 0
        let base = L.t("佢唔會收到解除通知。之後佢出門你唔會知，佢亦見唔到你。", "对方不会收到解除通知。之后对方出门你不会知道，对方也看不到你。")
        let meet = open > 0 ? L.t("你哋 \(open) 個未完成嘅約會會取消，佢會收到「約會取消」。", "你们 \(open) 个未完成的约会会取消，对方会收到「约会取消」。") : ""
        return base + meet + L.t("想再做街坊，要見面再碰一碰。", "想再做邻居，要见面再碰一碰。")
    }

    private func invitationCard(_ a: Appointment) -> some View {
        let p = store.resident(a.partnerID)
        let name = p?.name ?? L.t("街坊", "邻居")
        let place = store.placeName(a.landmarkID) ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let p { AvatarBadge(p) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("\(name)約你\(store.dayTimeLabel(a.date)) · \(place)", "\(name)约你\(store.dayTimeLabel(a.date)) · \(place)"))
                        .ds(.bodyBold)
                        .contentTransition(.numericText())
                        .fixedSize(horizontal: false, vertical: true)
                    if p?.isDemo == true { DemoBadge(text: L.t("示範街坊", "示范邻居")) }
                }
            }
            if !a.reason.isEmpty {
                Text(a.reason)
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
        let name = store.resident(a.partnerID)?.name ?? L.t("街坊", "邻居")
        let place = store.placeName(a.landmarkID) ?? ""
        let status: String = {
            switch a.status {
            case .waiting: return L.t("等緊\(name)確認", "等\(name)确认")
            case .accepted: return L.t("約好咗", "约好了")
            case .done: return L.t("行咗", "走过了")
            case .cancelled: return L.t("取消咗", "取消了")
            case .expired: return L.t("過咗期", "过期了")
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
        .accessibilityHint(L.t("改時間、地點或者取消", "改时间、地点或取消"))
    }

    private func neighborCard(_ n: Resident) -> some View {
        // No outing update does not prove the person is home; sending may be disabled or the person hidden.
        let status: String = {
            if n.isOut, let place = store.placeName(n.atLandmarkID) { return L.t("出咗門 · \(place)附近", "出门了 · \(place)附近") }
            return L.t("冇出門消息", "没有出门消息")
        }()
        // F6: separate receive and send switches.
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
                    Text(L.t("約佢行", "约他散步")).frame(maxWidth: stacked ? .infinity : nil)
                }
                .buttonStyle(.dsSecondary)
            }
            Divider()
            RemindRow(text: L.t("佢出門話我知", "他出门告诉我"), symbol: "bell.fill", on: receive) {
                toggles += 1
                store.setRemind(n.id, receive: !receive)
            }
            RemindRow(text: L.t("我出門話佢知", "我出门告诉他"), symbol: "figure.walk", on: send) {
                toggles += 1
                store.setRemind(n.id, send: !send)
            }
            Button { unlinking = n } label: {
                Text(L.t("唔再做街坊", "不再做邻居"))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L.t("佢唔會收到解除通知", "对方不会收到解除通知"))
        }
        .dsCard()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.wave.2")
                .ds(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(L.t("仲未有街坊。見到面碰一碰，就會喺呢度出現。", "还没有邻居。见面碰一碰，就会出现在这里。"))
                .ds(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Local components

private extension AnyTransition {
    /// New cards slide from above, or fade only with Reduce Motion.
    static var tabsInsert: AnyTransition { DS.slide(.top) }
}

private extension View {
    /// Use a secondary action when primary=false, maintaining one primary per screen.
    @ViewBuilder func tabButtonStyle(primary: Bool) -> some View {
        if primary { buttonStyle(.dsPrimary) } else { buttonStyle(.dsSecondary) }
    }
}

/// Content/action rows place the button at right when possible, otherwise stack it full-width.
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

/// UX 26: section titles use bold black 24 pt text instead of unclear small gray headings.
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

/// UX 28: whole-row alert switches are at least 56 pt high with large explicit on/off controls.
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
                // Avoid solid orange secondary switches: on uses pale fill/outline, off uses gray.
                Label(on ? L.t("開", "开") : L.t("閂", "关"), systemImage: on ? "checkmark" : "xmark")
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
        .accessibilityValue(on ? L.t("開咗", "已开") : L.t("閂咗", "已关"))
        .accessibilityHint(L.t("撳一下\(on ? "閂" : "開")", "点一下\(on ? "关" : "开")"))
        .accessibilityAddTraits(.isToggle)
    }
}

/// Reveal daily greetings character by character on changes, or immediately under Reduce Motion.
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

/// Confirm before cancelling a meeting because it notifies the peer.
private struct CancelMeetupDialog: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var target: Appointment?

    func body(content: Content) -> some View {
        let name = target.flatMap { store.resident($0.partnerID)?.name } ?? L.t("街坊", "邻居")
        content.confirmationDialog(target.map { L.t("取消同\(name)\(store.dayTimeLabel($0.date))嘅約？", "取消和\(name)\(store.dayTimeLabel($0.date))的约？") } ?? "",
                                   isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }), titleVisibility: .visible) {
            if let a = target {
                Button(L.t("取消約會", "取消约会"), role: .destructive) { store.cancelMeetup(a.id); target = nil }
            }
            Button(L.t("唔取消", "不取消"), role: .cancel) { target = nil }
        } message: {
            Text(L.t("會話俾\(name)知。", "会告诉\(name)。"))
        }
    }
}

extension View {
    func cancelMeetupDialog(_ target: Binding<Appointment?>) -> some View { modifier(CancelMeetupDialog(target: target)) }
}
