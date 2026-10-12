import SwiftUI

/// 「今日」页最上面嘅「第一日」任务卡（UX 报告第五节）：今日三件事，做完一件打一个勾；三件做齐讲一声、停一阵就收埋。
/// 自己判断要唔要出（AppStore.showsFirstDay）：放喺「今日」页 VStack 最上面一行 `FirstDayCard()` 就得。
/// 未做嘅两件撳得：碰一碰 → 开碰一碰画面；约佢 → 出约人卡（聽日）。行路唔使撳，出去行就自动记。
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
                    note: nil, action: { store.firstDayInvite() })
            }
        }
        .dsCard()
        .animation(DS.motion(DS.spring), value: f)
        .sensoryFeedback(.success, trigger: f.doneCount)
        .onAppear { store.firstDayCheck() }
        .onChange(of: store.appointments.count) { _, _ in store.firstDayCheck() }
        .onChange(of: store.neighbors.count) { _, _ in store.firstDayCheck() }
        .task(id: done) {
            // 做齐：俾佢睇清楚三个勾，停一阵先收埋
            guard done else { return }
            try? await Task.sleep(for: .seconds(4))
            withAnimation(DS.motion(DS.spring)) { store.closeFirstDay() }
        }
    }

    /// 行咗一啲但未够：「行咗 4 / 10 分鐘」。
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
