import SwiftUI

/// UX section 5: first-day tasks sit atop Today; announce completion and retain the card until manually dismissed.
/// FirstDayCard checks AppStore.showsFirstDay itself; place it first in Today's VStack.
/// Remaining pairing/invitation tasks are tappable; invitations default to tomorrow. Walking is recorded automatically without a task-card tap.
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
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(done ? L.t("三件事做齊晒！", "三件事都做完了！") : L.t("今日三件事", "今天三件事"))
                    .ds(.bodyBold)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(f.doneCount) / 3")
                    .ds(.captionBold)
                    .monospacedDigit()
                    .foregroundStyle(done ? DS.accentInk : .secondary)
                    .contentTransition(.numericText(value: Double(f.doneCount)))
                    .accessibilityLabel(L.t("做咗 \(f.doneCount) 件", "做了 \(f.doneCount) 件"))
            }
            VStack(spacing: 0) {
                row(done: f.walked,
                    title: L.t("出去行 \(FirstDayProgress.walkGoal) 分鐘", "出去走 \(FirstDayProgress.walkGoal) 分钟"),
                    note: walkNote(f), action: nil)
                Divider().padding(.leading, 52)
                row(done: f.bumped == true,
                    title: L.t("見到街坊碰一碰", "见到邻居碰一碰"),
                    note: nil, action: { store.startBump() })
                Divider().padding(.leading, 52)
                row(done: f.invited == true,
                    title: L.t("約佢聽日一齊行", "约他明天一起走"),
                    note: inviteNote, action: f.invited == true ? nil : { store.firstDayInvite() })
            }
            // Feedback: keep the completed card until explicit dismissal instead of making everything disappear.
            if done {
                Button {
                    withAnimation(DS.motion(DS.spring)) { store.closeFirstDay() }
                } label: {
                    Text(L.t("知道喇，收起", "知道了，收起")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsSecondary)
            }
        }
        .dsCard()
        .animation(DS.motion(DS.spring), value: f)
        .sensoryFeedback(.success, trigger: f.doneCount)
        .onAppear { store.firstDayCheck() }
        .onChange(of: store.appointments.count) { _, _ in store.firstDayCheck() }
        .onChange(of: store.neighbors.count) { _, _ in store.firstDayCheck() }
    }

    /// After inviting, show the proposed time/place and whether the neighbor's confirmation is pending.
    private var inviteNote: String? {
        guard let a = store.appointments.filter({ $0.isOpen && $0.date > store.now }).sorted(by: { $0.date < $1.date }).first else { return nil }
        let name = store.resident(a.partnerID)?.name ?? L.t("街坊", "邻居")
        let place = store.placeName(a.landmarkID) ?? ""
        let status = a.status == .waiting
            ? (a.fromPartner ? L.t("\(name)約你", "\(name)约你") : L.t("等\(name)確認", "等\(name)确认"))
            : L.t("\(name)答應咗", "\(name)答应了")
        return "\(store.dayTimeLabel(a.date)) · \(place)（\(status)）"
    }

    /// Show partial progress toward the ten-minute walking task.
    private func walkNote(_ f: FirstDayProgress) -> String? {
        let m = f.walkMinutes ?? 0
        guard m > 0, !f.walked else { return nil }
        return L.t("行咗 \(m) / \(FirstDayProgress.walkGoal) 分鐘", "走了 \(m) / \(FirstDayProgress.walkGoal) 分钟")
    }

    @ViewBuilder private func row(done: Bool, title: String, note: String?, action: (() -> Void)?) -> some View {
        let label = HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(done ? DS.accent : Color.secondary.opacity(0.6))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .ds(.body)
                    .foregroundStyle(done ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note).ds(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if action != nil && !done {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())

        if let action, !done {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
        } else {
            label
                .accessibilityElement(children: .combine)
                .accessibilityValue(done ? L.t("做咗", "做了") : L.t("未做", "还没做"))
        }
    }
}
