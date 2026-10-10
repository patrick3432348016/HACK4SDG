import ActivityKit
import SwiftUI
import WidgetKit

/// 小组件扩展：只有一个实时活动（真·灵动岛 + 锁屏），内容由 App 本地更新（IslandStatus，见 ios/Shared/）。
@main
struct StreetWalkWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StreetWalkLiveActivity()
    }
}

/// 散步「行緊 12 分」、找人「35 米」+ 箭咀、约会「15 分鐘後」。字大、句子短、粤语。
struct StreetWalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StreetWalkActivityAttributes.self) { context in
            LockScreenView(s: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            let stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IconBadge(s: s, size: 46)
                        .frame(maxHeight: .infinity)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BigValue(s: s, stale: stale, size: 26)
                        .frame(maxHeight: .infinity)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Headline(s: s, stale: stale, size: 22)
                        Text(secondLine(s, stale: stale))
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                StatusIcon(s: s, size: 18)
            } compactTrailing: {
                CompactValue(s: s, stale: stale)
            } minimal: {
                StatusIcon(s: s, size: 16)
            }
            .keylineTint(IslandStyle.accent)
        }
    }
}

// MARK: - 文字

/// 第二行：散步讲经过几多地方（太耐冇更新就叫佢打开 App）；找人讲喺边、几耐到；约会讲喺边见。
private func secondLine(_ s: IslandStatus, stale: Bool) -> String {
    switch s.kind {
    case .walk: return stale && !s.finished ? "打開 App 睇最新" : s.detail
    case .find: return s.findLine
    case .meet: return s.detail
    }
}

/// 第一行（大字）：「行緊 12 分鐘」「搵緊陳太」「15 分鐘後約咗陳太」（约会自己倒数）。
private struct Headline: View {
    let s: IslandStatus
    let stale: Bool
    let size: CGFloat

    var body: some View {
        Group {
            if s.kind == .meet, let t = s.target, !stale, s.minutes > 0 {
                Text("\(TimeDataSource<Date>.currentDate, format: Self.countdown(to: t))約咗\(s.name ?? "街坊")")
            } else if s.kind == .meet, stale || s.minutes <= 0 {
                Text("夠鐘見\(s.name ?? "街坊")喇")
            } else {
                Text(s.title)
            }
        }
        .font(.system(size: size, weight: .bold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    static func countdown(to t: Date) -> SystemFormatStyle.DateReference {
        .reference(to: t, allowedFields: [.hour, .minute], maxFieldCount: 1).locale(IslandStyle.locale)
    }
}

/// 右边大字：散步「12 分」、找人「35 米」、约会倒数。
private struct BigValue: View {
    let s: IslandStatus
    let stale: Bool
    let size: CGFloat

    var body: some View {
        Group {
            if s.kind == .meet, let t = s.target, !stale, s.minutes > 0 {
                Text(TimeDataSource<Date>.currentDate, format: Headline.countdown(to: t))
            } else if s.kind == .meet {
                Text(stale ? "夠鐘喇" : s.short)
            } else if s.finished {
                Image(systemName: "checkmark")
            } else {
                Text(s.short)
            }
        }
        .font(.system(size: size, weight: .bold))
        .monospacedDigit()
        .foregroundStyle(IslandStyle.accentOnBlack)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// 真·灵动岛右边（好窄）：「12 分」「35 米」「15 分」。约会自己倒数（App 喺背景都唔会停）。
private struct CompactValue: View {
    let s: IslandStatus
    let stale: Bool

    var body: some View {
        Group {
            if s.kind == .meet, let t = s.target, !stale, s.minutes > 0 {
                Text(TimeDataSource<Date>.currentDate,
                     format: .offset(to: t, allowedFields: [.hour, .minute], maxFieldCount: 1, sign: .never))
                    .environment(\.locale, IslandStyle.locale)
            } else if s.kind == .meet {
                Text(stale ? "夠鐘" : s.compact)
            } else {
                Text(s.compact)
            }
        }
        .font(.system(size: 16, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: 64)
    }
}

// MARK: - 图标

/// 散步小人、找人箭咀（按方向转）、约会时钟；橙色。
private struct StatusIcon: View {
    let s: IslandStatus
    let size: CGFloat

    var body: some View {
        Image(systemName: s.symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(IslandStyle.accent)
            .rotationEffect(.degrees(s.kind == .find ? s.bearing ?? 0 : 0))
    }
}

/// 橙色圆形底 + 白色图标（锁屏、展开嘅岛）。
private struct IconBadge: View {
    let s: IslandStatus
    let size: CGFloat

    var body: some View {
        Image(systemName: s.symbol)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(s.kind == .find ? s.bearing ?? 0 : 0))
            .frame(width: size, height: size)
            .background(Circle().fill(IslandStyle.accent))
    }
}

// MARK: - 锁屏

/// 锁屏 / 通知中心：一行「街坊行」，然后图标 + 两行大字；找人右边再出距离。
private struct LockScreenView: View {
    let s: IslandStatus
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk.circle.fill")
                    .foregroundStyle(IslandStyle.accentOnBlack)
                Text("街坊行")
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 8)
                if s.demo {
                    Text("示範")
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                }
            }
            .font(.system(size: 16, weight: .semibold))

            HStack(alignment: .center, spacing: 14) {
                IconBadge(s: s, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Headline(s: s, stale: stale, size: 26)
                    Text(secondLine(s, stale: stale))
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                if s.kind == .find {
                    BigValue(s: s, stale: stale, size: 30)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}
