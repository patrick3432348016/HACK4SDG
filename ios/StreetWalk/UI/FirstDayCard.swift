import SwiftUI

/// 「今日」页最上面嘅「第一日」任务卡（UX 报告第五节）：今日三件事，做完一件打一个勾；三件做齐讲一声，留住等用户撳「收起」。
/// 自己判断要唔要出（AppStore.showsFirstDay）：放喺「今日」页 VStack 最上面一行 `FirstDayCard()` 就得。
/// 未做嘅撳得：出去行 → 即刻开始记录（A-3，散步中写「记录紧」）；碰一碰 → 开碰一碰画面；约佢 → 出约人卡（聽日）。
/// 个勾自己撳得（J-2）：打咗勾嘅撳一下取消，再撳又打返勾；未做嘅撳左边个圈都打得勾。
struct FirstDayCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.showsFirstDay, let f = store.firstDay {
            content(f)
                .transition(DS.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private func content(_ f: FirstDayProgress) -> some View {
        let done = f.finishedAt != nil
        let count = store.firstDayDoneCount
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(done ? L.t("三件事做齊晒！", "三件事都做完了！", "All 3 done!") : L.t("今日三件事", "今天三件事", "3 things for today"))
                    .ds(.bodyBold)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(count) / 3")
                    .ds(.captionBold)
                    .monospacedDigit()
                    .foregroundStyle(done ? DS.accentInk : .secondary)
                    .contentTransition(.numericText(value: Double(count)))
                    .accessibilityLabel(L.t("做咗 \(count) 件", "做了 \(count) 件", "\(count) done"))
            }
            VStack(spacing: 0) {
                row(.walk, done: store.firstDayDone(.walk),
                    title: L.t("出去行 \(FirstDayProgress.walkGoal) 分鐘", "出去走 \(FirstDayProgress.walkGoal) 分钟", "Go out for \(FirstDayProgress.walkGoal) minutes"),
                    note: walkNote(f), action: store.walk == nil ? { store.startManualWalk() } : {})   // 散步中撳字唔使做嘢
                Divider().padding(.leading, 64)
                row(.bump, done: store.firstDayDone(.bump),
                    title: L.t("見到街坊碰一碰", "见到邻居碰一碰", "Meet a neighbour, tap phones"),
                    note: nil, action: { store.startBump() })
                Divider().padding(.leading, 64)
                row(.invite, done: store.firstDayDone(.invite),
                    title: L.t("約佢聽日一齊行", "约他明天一起走", "Invite them for a walk tomorrow"),
                    note: inviteNote, action: { store.firstDayInvite() })
            }
            // 测试反馈：做齐即刻自己收埋，好似「全部消失」→ 做齐后留住，由用户自己撳「收起」
            if done {
                Button {
                    withAnimation(DS.motion(DS.spring)) { store.closeFirstDay() }
                } label: {
                    Text(L.t("知道喇，收起", "知道了，收起", "Got it, hide")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsSecondary)
            }
        }
        .dsCard()
        .animation(DS.motion(DS.spring), value: f)
        .sensoryFeedback(.success, trigger: count)
        .onAppear { store.firstDayCheck() }
        .onChange(of: store.appointments.count) { _, _ in store.firstDayCheck() }
        .onChange(of: store.neighbors.count) { _, _ in store.firstDayCheck() }
    }

    /// J-3b：约咗之后（今日、聽日、之后几日都算）喺任务下面写返约咗乜：
    /// 「约好了：明天早上 8 点 · 陈太 · 凉亭」「约了：…（等陈太确认）」「陈太约你：…（去回复）」。
    private var inviteNote: String? {
        guard let a = store.appointments.filter({ $0.isOpen && $0.date > store.now }).sorted(by: { $0.date < $1.date }).first else { return nil }
        let name = store.resident(a.partnerID)?.name ?? L.t("街坊", "邻居", "Neighbour")
        let place = store.placeName(a.landmarkID).map { " · \($0)" } ?? ""
        let what = "\(store.dayTimeLabel(a.date)) · \(name)\(place)"
        switch (a.status, a.fromPartner) {
        case (.waiting, true): return L.t("\(name)約你：\(store.dayTimeLabel(a.date))\(place)（去回覆）", "\(name)约你：\(store.dayTimeLabel(a.date))\(place)（去回复）", "\(name) invited you: \(store.dayTimeLabel(a.date))\(place) (reply)")
        case (.waiting, false): return L.t("約咗：\(what)（等\(name)確認）", "约了：\(what)（等\(name)确认）", "Invited: \(what) (waiting for \(name))")
        default: return L.t("約好咗：\(what)", "约好了：\(what)", "All set: \(what)")
        }
    }

    /// 散步中：「記錄緊，行咗 3 分鐘」；未够：「行咗 4 / 10 分鐘 · 撳呢度開始記錄」；未行過：「撳呢度開始記錄」。
    private func walkNote(_ f: FirstDayProgress) -> String? {
        if let w = store.walk { return L.t("記錄緊，行咗 \(w.minutes) 分鐘", "正在记录，已走 \(w.minutes) 分钟", "Recording, \(w.minutes) min so far") }
        guard !store.firstDayDone(.walk) else { return nil }
        let m = f.walkMinutes ?? 0
        let start = L.t("撳呢度開始記錄", "点这里开始记录", "Tap here to start recording")
        return m > 0 ? L.t("行咗 \(m) / \(FirstDayProgress.walkGoal) 分鐘 · \(start)", "走了 \(m) / \(FirstDayProgress.walkGoal) 分钟 · \(start)", "\(m) / \(FirstDayProgress.walkGoal) min · \(start)") : start
    }

    /// 一行：左边个勾自己撳得（打勾 / 取消）；打咗勾嘅成行撳都係取消；未做嘅撳字就做嗰件事（冇事做就打勾）。
    @ViewBuilder private func row(_ item: FirstDayProgress.Item, done: Bool, title: String, note: String?, action: (() -> Void)?) -> some View {
        let toggle = { store.firstDayToggle(item) }
        let text = HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .ds(.body)
                    .foregroundStyle(done ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note).ds(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if action != nil && !done && !(item == .walk && store.walk != nil) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())

        HStack(spacing: 8) {
            Button(action: toggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(done ? DS.accent : Color.secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(done ? L.t("做咗", "做了", "Done") : L.t("未做", "还没做", "Not done"))
            .accessibilityHint(done ? L.t("撳一下取消個勾", "点一下取消勾", "Tap to untick") : L.t("撳一下打勾", "点一下打勾", "Tap to tick"))
            Button(action: done ? toggle : (action ?? toggle)) { text }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(done ? L.t("撳一下取消個勾", "点一下取消勾", "Tap to untick") : action == nil ? L.t("撳一下打勾", "点一下打勾", "Tap to tick") : "")
        }
    }
}
