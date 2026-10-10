import CoreLocation
import SwiftUI

// 后台出门检测嘅界面：「始终允许」解释页、今日页嘅提示卡（权限未齐、係咪搬咗屋）、设定一栏、「定位紀錄」页。

// MARK: - 「始终允许」解释页

/// 完成首次使用之后弹一次：大字讲清楚点解要「始终允许」，按「好」先弹系统框。
struct AlwaysAskSheet: View {
    @Environment(AppStore.self) private var store

    static let spoken = "想你鎖咗機、手機放喺袋，出門散步都自動記錄，要將定位改做始終允許。喺屋企唔會一直開定位，唔會好食電。屋企喺邊、行過嘅路，只留喺你部手機。"

    var body: some View {
        let lm = LocationMonitor.shared
        let viaSettings = lm.askedAlways || lm.auth == .denied || lm.auth == .restricted || (lm.auth == .authorizedAlways && !lm.precise)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero.frame(maxWidth: .infinity)
                Text("出門自動記錄").ds(.title).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 16) {
                    row("lock.iphone", "手機鎖咗、放喺袋，出門散步都會自動記錄，唔使打開 App。")
                    row("location.fill", viaSettings
                        ? "撳下面個掣打開設定：撳「位置」，揀「永遠」（有啲手機寫「始終」），再開「精確位置」。"
                        : "要將定位改做「始終允許」。等陣彈出嚟嘅框，請揀「改為始終允許」（有啲手機寫「永遠允許」）。")
                    row("battery.75percent", "喺屋企唔會一直開定位，只係出門行路先用準確定位，唔會好食電。")
                    row("lock.shield.fill", "屋企喺邊、行過嘅路，只留喺你部手機，唔會上傳。")
                }
                Button { store.sayAgain(Self.spoken) } label: {
                    Label("再聽一次", systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsSecondary)
            }
            .padding(.horizontal, DS.side)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                Button {
                    lm.showAlwaysAsk = false
                    if viaSettings { lm.openSettings() } else { lm.requestAlways() }
                } label: {
                    Text(viaSettings ? "打開 iPhone 設定" : "好，下一步").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
                Button { lm.showAlwaysAsk = false } label: {
                    Text("遲啲先").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsSecondary)
            }
            .padding(.horizontal, DS.side)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .top) { Divider() }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear { store.say(Self.spoken) }
    }

    private var hero: some View {
        ZStack {
            Circle().fill(DS.accentSoft).frame(width: 136, height: 136)
            Image(systemName: "figure.walk")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(DS.accent)
            Image(systemName: "lock.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(DS.accent, in: Circle())
                .overlay(Circle().strokeBorder(Color(.systemGroupedBackground), lineWidth: 4))
                .offset(x: 48, y: -44)
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 48, height: 48)
                .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            Text(text)
                .ds(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 今日页嘅提示卡

/// 今日页最顶：係咪搬咗屋（连续两晚喺第二度过夜）、自动记录未开齐（唔係「始终允许」）。演示模式唔出。
struct LocationCards: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let lm = LocationMonitor.shared
        if store.phase == .main, !store.demoMode {
            if let p = lm.homePrompt {
                HomePromptCard(prompt: p).transition(.opacity)
            }
            if lm.needsAlways, (lm.cardHiddenUntil ?? .distantPast) < Date() {
                PermissionCard().transition(.opacity)
            }
        }
    }
}

private struct HomePromptCard: View {
    @Environment(AppStore.self) private var store
    let prompt: LocationMonitor.HomePrompt

    private var title: String {
        switch prompt {
        case .moved: return "你係咪搬咗屋？要唔要將屋企同社區搬過嚟？"
        case .suggest: return "你屋企係咪喺第二度？要唔要將屋企同社區搬過嚟？"
        }
    }

    private var detail: String {
        switch prompt {
        case .moved(_, let d, let n):
            return "最近 \(n) 晚你都喺\(LocationMonitor.describe(d).replacingOccurrences(of: "離屋企", with: "離而家屋企"))嘅地方過夜。"
        case .suggest(_, let d, let n):
            let far = d.map { "（\(LocationMonitor.describe($0).replacingOccurrences(of: "離屋企", with: "離而家個模型"))）" } ?? ""
            return "最近 \(n) 晚你都喺同一個地方過夜\(far)。"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "house.and.flag.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 48, height: 48)
                    .background(DS.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).ds(.bodyBold).fixedSize(horizontal: false, vertical: true)
                    Text(detail).ds(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons(stacked: false) }
                VStack(spacing: 8) { buttons(stacked: true) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .onAppear {
            let lm = LocationMonitor.shared
            guard lm.spokenPrompt != title else { return }
            lm.spokenPrompt = title
            store.say(title)
        }
    }

    @ViewBuilder private func buttons(stacked: Bool) -> some View {
        Button { store.declineHomePrompt() } label: {
            Text("唔係").frame(maxWidth: stacked ? .infinity : nil)
        }
        .buttonStyle(.dsSecondary)
        Button { store.acceptHomePrompt() } label: {
            Text("係，搬過嚟").frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsPrimary)
    }
}

private struct PermissionCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let lm = LocationMonitor.shared
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("出門自動記錄未開齊").ds(.bodyBold)
                    Text(LocationStatusText.problem(lm) ?? "").ds(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons(lm, stacked: false) }
                VStack(spacing: 8) { buttons(lm, stacked: true) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    @ViewBuilder private func buttons(_ lm: LocationMonitor, stacked: Bool) -> some View {
        Button { lm.hideCard(days: 3) } label: {
            Text("遲啲先").frame(maxWidth: stacked ? .infinity : nil)
        }
        .buttonStyle(.dsSecondary)
        Button { lm.showAlwaysAsk = true } label: {
            Text("點樣開").frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsPrimary)
    }
}

// MARK: - 设定一栏

/// 设定页「出門自動記錄」：定位、精确位置、动作与健身嘅状态，未齐就有掣去开；入「定位紀錄」。
struct LocationSettingsSection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let lm = LocationMonitor.shared
        Section {
            LabeledContent("定位") { Text(LocationMonitor.authLabel(lm.auth)).foregroundStyle(lm.auth == .authorizedAlways ? Color.secondary : DS.accent) }
            if !lm.precise {
                LabeledContent("精確位置") { Text("關咗").foregroundStyle(DS.accent) }
            }
            LabeledContent("動作與健身") {
                Text(LocationMonitor.motionLabel(lm.motionAuth)).foregroundStyle(lm.motionAuth == .denied ? DS.accent : Color.secondary)
            }
            if lm.needsAlways || lm.motionAuth == .denied || lm.motionAuth == .restricted {
                if lm.auth == .authorizedWhenInUse || lm.auth == .notDetermined, !lm.askedAlways {
                    Button("改做始終允許") { lm.showAlwaysAsk = true }
                } else {
                    Button("打開 iPhone 設定") { lm.openSettings() }
                }
            }
            NavigationLink { LocationLogView() } label: { Text("定位紀錄") }
        } header: {
            Text("出門自動記錄").ds(.caption)
        } footer: {
            Text(LocationStatusText.footer(lm)).ds(.caption)
        }
    }
}

/// 状态文字（设定、今日卡、定位纪录共用）。
enum LocationStatusText {
    /// 有咩未齐（齐晒就 nil）。
    @MainActor static func problem(_ lm: LocationMonitor) -> String? {
        switch lm.auth {
        case .denied, .restricted: return "定位已經拒絕咗：唔會記錄路線同地標，亦唔知你幾時返到屋企。"
        case .notDetermined: return "未允許定位：散步唔會自動記錄。"
        case .authorizedWhenInUse: return "定位只係「用緊 App 時」先開：鎖咗機出門唔會即時記錄，要等你打開 App 先補返分鐘同步數（冇地標）。"
        default: break
        }
        if !lm.precise { return "「精確位置」關咗：認唔到你行過邊個地標，亦唔知你幾時出門。" }
        if lm.motionAuth == .denied || lm.motionAuth == .restricted { return "「動作與健身」關咗：認唔到你開始行路。" }
        return nil
    }

    @MainActor static func footer(_ lm: LocationMonitor) -> String {
        problem(lm) ?? "出門會自動記錄，鎖咗機都得。唔好喺多工畫面將街坊行掃走，否則出門唔會自動記錄。"
    }
}

// MARK: - 定位紀錄（俾自己喺真機核對三日测试）

struct LocationLogView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmClear = false

    var body: some View {
        let lm = LocationMonitor.shared
        let cal = AppStore.hk
        let today = store.log(for: store.now)
        let todayEvents = lm.log.events(on: Date(), calendar: cal).filter { $0.kind == .walkEnd || $0.kind == .backfill || $0.kind == .walkStart }
        let wakes = lm.log.events.filter(\.isWake).suffix(15).reversed()
        let others = lm.log.events.filter { !$0.isWake }.suffix(30).reversed()
        let nights = lm.learner.nights(now: Date(), calendar: cal)
        List {
            Section {
                InfoRow(title: "自動記錄", value: statusText(lm))
                InfoRow(title: "屋企", value: verdictText(lm.verdict))
                InfoRow(title: "而家", value: lm.insideHome.map { $0 ? "喺屋企範圍內（100 米）" : "唔喺屋企範圍" } ?? "未知喺唔喺屋企")
            } header: { Text("狀態").ds(.caption) }

            Section {
                InfoRow(title: "今日", value: today.walks > 0 ? "記咗 \(today.walks) 次，共 \(today.minutes) 分鐘" : "今日未有散步紀錄")
                ForEach(todayEvents.reversed()) { e in EventRow(event: e) }
            } header: { Text("今日散步（包括補記）").ds(.caption) }

            Section {
                if nights.isEmpty {
                    Text("未有。夜晚 10 點到朝早 6 點喺邊過夜，會喺呢度記低（最多 14 晚）。").ds(.caption).foregroundStyle(.secondary)
                }
                ForEach(nights, id: \.night) { n in
                    InfoRow(title: Self.nightLabel(n.night), value: "\(placeText(n.center, lm)) · \(String(format: "%.1f", n.hours)) 小時")
                }
            } header: { Text("過夜位置").ds(.caption) } footer: {
                Text("只存喺你部手機，唔會上傳；連續兩晚喺同一度就當係屋企。").ds(.caption)
            }

            Section {
                if wakes.isEmpty { Text("未有。出門、返屋企時 iOS 會喺背景叫醒街坊行，會喺呢度記低。").ds(.caption).foregroundStyle(.secondary) }
                ForEach(Array(wakes)) { e in EventRow(event: e) }
            } header: { Text("最近喚醒").ds(.caption) }

            Section {
                ForEach(Array(others)) { e in EventRow(event: e) }
            } header: { Text("其他紀錄").ds(.caption) }

            Section {
                Label("唔好喺多工畫面將街坊行掃走，否則出門唔會自動記錄。", systemImage: "exclamationmark.triangle.fill")
                    .ds(.body)
                Label("手機重新開機之後，打開一次街坊行。", systemImage: "arrow.clockwise")
                    .ds(.body)
            } header: { Text("提提你").ds(.caption) }

            Section {
                Button("清除定位紀錄", role: .destructive) { confirmClear = true }
            }
        }
        .navigationTitle("定位紀錄")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text("定位紀錄").ds(.bodyBold).accessibilityAddTraits(.isHeader) }
        }
        .confirmationDialog("清除定位紀錄？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除", role: .destructive) { lm.clearRecords() }
            Button("唔清", role: .cancel) {}
        } message: {
            Text("最近喚醒同過夜位置會刪走；散步紀錄唔受影響。")
        }
        .onAppear { lm.reevaluate() }
    }

    private func statusText(_ lm: LocationMonitor) -> String {
        if store.demoMode { return "演示模式開住：唔記錄真散步（喺設定關咗演示模式）" }
        if !WalkDetector.isAvailable { return "呢部機冇動作感應，唔會自動記錄" }
        if let p = LocationStatusText.problem(lm) { return "未開齊。\(p)" }
        if lm.home == nil { return "未有屋企位置（打開一次主畫面）" }
        return lm.monitoring ? "開咗：離開屋企會自動開始記錄" : "未開始監察（打開一次主畫面）"
    }

    private func verdictText(_ v: HomeVerdict) -> String {
        switch v {
        case .learning(let n): return n == 0 ? "學緊：未有過夜紀錄（要 2 晚）" : "學緊：記咗 \(n) 晚，要 2 晚"
        case .confirmed(let n, let d): return "已確認：\(n) 晚喺你揀嘅樓附近過夜（相差 \(Int(d.rounded())) 米）"
        case .unsure(let n, let d): return "未確認：\(n) 晚過夜嘅地方\(LocationMonitor.describe(d).replacingOccurrences(of: "離屋企", with: "離你揀嘅樓"))"
        case .moved(_, let n, let d): return "最近 \(n) 晚都喺\(LocationMonitor.describe(d))嘅地方過夜（會問你係咪搬咗屋）"
        case .suggest(_, let n, let d):
            return "你未揀屋企：\(n) 晚喺同一個地方過夜\(d.map { "（\(LocationMonitor.describe($0).replacingOccurrences(of: "離屋企", with: "離而家個模型")))" } ?? "")"
        }
    }

    private func placeText(_ p: GeoPoint, _ lm: LocationMonitor) -> String {
        guard let h = lm.home else { return "未有屋企位置對比" }
        let d = HomeLearner.distance(h, p)
        return d <= HomeLearner.confirmRadius ? "喺屋企附近（\(Int(d.rounded())) 米）" : LocationMonitor.describe(d)
    }

    /// "2026-10-09" → 「10 月 9 日晚」。
    static func nightLabel(_ key: String) -> String {
        let p = key.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? "\(p[1]) 月 \(p[2]) 日晚" : key
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).ds(.caption).foregroundStyle(.secondary)
            Text(value).ds(.body).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct EventRow: View {
    let event: LocationEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(Self.time(event.at)).ds(.caption).monospacedDigit().foregroundStyle(.secondary)
                Text(event.title).ds(.bodyBold)
                if event.background {
                    Text("背景").ds(.caption).foregroundStyle(DS.accent)
                        .padding(.horizontal, 8)
                        .background(DS.accentSoft, in: Capsule())
                }
            }
            Text(event.detail).ds(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// 「10/10 08:05」（香港时间）。
    static func time(_ d: Date) -> String {
        let c = AppStore.hk.dateComponents([.month, .day, .hour, .minute], from: d)
        return String(format: "%d/%d %02d:%02d", c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }
}
