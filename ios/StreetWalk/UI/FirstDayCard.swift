import SwiftUI

/// UX section 5: first-day tasks sit atop Today; announce completion and retain the card until manually dismissed.
/// FirstDayCard checks AppStore.showsFirstDay itself; place it first in Today's VStack.
/// Incomplete actions start recording, open pairing, or propose tomorrow's invitation; show recording state during a walk.
/// J-2: users can toggle completed checks and manually check incomplete tasks via the circle.
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
                    note: walkNote(f), cta: L.t("開始", "开始", "Start"),
                    action: store.walk == nil ? { store.startManualWalk() } : {})   // Tapping the task text while already walking does nothing.
                Divider().padding(.leading, 64)
                row(.bump, done: store.firstDayDone(.bump),
                    title: L.t("見到街坊碰一碰", "见到邻居碰一碰", "Meet a neighbour, tap phones"),
                    note: nil, cta: L.t("碰一碰", "碰一碰", "Tap"), action: { store.startBump() })
                Divider().padding(.leading, 64)
                row(.invite, done: store.firstDayDone(.invite),
                    title: store.firstDayInviteTitle,
                    note: inviteNote, cta: L.t("去約", "去约", "Invite"), action: { store.firstDayInvite() })
            }
            // Feedback: keep the completed card until explicit dismissal instead of making everything disappear.
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

    /// J-3b: display meeting details below the task for any scheduled date.
    /// Distinguish confirmed meetings, my pending invitations and incoming invitations awaiting response.
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

    /// Show active recording minutes or progress toward 10 minutes; before any walk, rely on the Start button.
    private func walkNote(_ f: FirstDayProgress) -> String? {
        if let w = store.walk { return L.t("記錄緊，行咗 \(w.minutes) 分鐘", "正在记录，已走 \(w.minutes) 分钟", "Recording, \(w.minutes) min so far") }
        guard !store.firstDayDone(.walk) else { return nil }
        let m = f.walkMinutes ?? 0
        // 10-18: the right-side Start button makes another start instruction redundant.
        return m > 0 ? L.t("行咗 \(m) / \(FirstDayProgress.walkGoal) 分鐘", "走了 \(m) / \(FirstDayProgress.walkGoal) 分钟", "\(m) / \(FirstDayProgress.walkGoal) min") : nil
    }

    /// The check toggles completion; completed rows uncheck on tap, while incomplete text performs its action or checks it when no action exists.
    /// 10-18: cta is an orange button with white text to make incomplete actions visibly tappable.
    @ViewBuilder private func row(_ item: FirstDayProgress.Item, done: Bool, title: String, note: String?, cta: String, action: (() -> Void)?) -> some View {
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
                Text(cta)
                    .ds(.captionBold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .background(DS.accent, in: Capsule())
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
