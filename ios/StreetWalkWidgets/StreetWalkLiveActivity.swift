import ActivityKit
import SwiftUI
import WidgetKit

/// Widget extension provides one Live Activity for Dynamic Island / Lock Screen, locally updated from shared IslandStatus.
@main
struct StreetWalkWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StreetWalkLiveActivity()
    }
}

/// Short, large localized walking, finding and meeting status.
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

// MARK: - Text

/// Second line: passed places or stale-update guidance for walking, location/ETA for finding, meeting place for appointments.
private func secondLine(_ s: IslandStatus, stale: Bool) -> String {
    switch s.kind {
    case .walk: return stale && !s.finished ? s.t("打開 App 睇最新", "打开 App 看最新") : s.detail
    case .find: return s.findLine
    case .meet: return s.detail
    }
}

/// Large first line describes walking, finding a peer or an automatically counted-down meeting.
private struct Headline: View {
    let s: IslandStatus
    let stale: Bool
    let size: CGFloat

    var body: some View {
        Group {
            if s.kind == .meet, let t = s.target, !stale, s.minutes > 0 {
                if s.lang == .cmn {
                    Text("\(TimeDataSource<Date>.currentDate, format: Self.countdown(to: t, s))约了\(s.name ?? "邻居")")
                } else {
                    Text("\(TimeDataSource<Date>.currentDate, format: Self.countdown(to: t, s))約咗\(s.name ?? "街坊")")
                }
            } else if s.kind == .meet, stale || s.minutes <= 0 {
                Text(s.t("夠鐘見\(s.name ?? "街坊")喇", "该去见\(s.name ?? "邻居")了"))
            } else {
                Text(s.title)
            }
        }
        .font(.system(size: size, weight: .bold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    static func countdown(to t: Date, _ s: IslandStatus) -> SystemFormatStyle.DateReference {
        .reference(to: t, allowedFields: [.hour, .minute], maxFieldCount: 1).locale(IslandStyle.locale(s))
    }
}

/// Large right-side value: walking minutes, finding meters or meeting countdown.
private struct BigValue: View {
    let s: IslandStatus
    let stale: Bool
    let size: CGFloat

    var body: some View {
        Group {
            if s.kind == .meet, let t = s.target, !stale, s.minutes > 0 {
                Text(TimeDataSource<Date>.currentDate, format: Headline.countdown(to: t, s))
            } else if s.kind == .meet {
                Text(stale ? s.t("夠鐘喇", "到点了") : s.short)
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

/// Compact island value fits the narrow space; meeting countdown continues while the App is backgrounded.
private struct CompactValue: View {
    let s: IslandStatus
    let stale: Bool

    var body: some View {
        Group {
            if s.kind == .meet, let t = s.target, !stale, s.minutes > 0 {
                Text(TimeDataSource<Date>.currentDate,
                     format: .offset(to: t, allowedFields: [.hour, .minute], maxFieldCount: 1, sign: .never))
                    .environment(\.locale, IslandStyle.locale(s))
            } else if s.kind == .meet {
                Text(stale ? s.t("夠鐘", "到点") : s.compact)
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

// MARK: - Icons

/// Orange walker, direction-rotated finding arrow or meeting clock.
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

/// Orange circular background and white icon for Lock Screen / expanded island.
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

// MARK: - Lock Screen

/// Lock Screen / Notification Center shows the App name, icon and two large lines, plus finding distance at right.
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
                    Text(s.t("示範", "示范"))
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
