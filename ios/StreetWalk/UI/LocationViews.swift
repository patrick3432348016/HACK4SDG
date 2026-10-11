import CoreLocation
import SwiftUI

// 后台出门检测嘅界面：「始终允许」解释页、今日页嘅提示卡（权限未齐、係咪搬咗屋）、设定一栏、「定位紀錄」页。

// MARK: - 「始终允许」解释页

/// 完成首次使用之后弹一次：大字讲清楚点解要「始终允许」，按「好」先弹系统框。
struct AlwaysAskSheet: View {
    @Environment(AppStore.self) private var store

    static var spoken: String { L.t("想你鎖咗機、手機放喺袋，出門散步都自動記錄，要將定位改做始終允許。喺屋企唔會一直開定位，唔會好食電。屋企喺邊、行過嘅路，只留喺你部手機。", "想在锁屏、手机放口袋时，出门散步也自动记录，要把定位改成始终允许。在家不会一直开定位，不会很耗电。家在哪里、走过的路，只留在你的手机上。") }

    var body: some View {
        let lm = LocationMonitor.shared
        let viaSettings = lm.askedAlways || lm.auth == .denied || lm.auth == .restricted || (lm.auth == .authorizedAlways && !lm.precise)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero.frame(maxWidth: .infinity)
                Text(L.t("出門自動記錄", "出门自动记录")).ds(.title).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 16) {
                    row("lock.iphone", L.t("手機鎖咗、放喺袋，出門散步都會自動記錄，唔使打開 App。", "手机锁屏、放口袋，出门散步也会自动记录，不用打开 App。"))
                    row("location.fill", viaSettings
                        ? L.t("撳下面個掣打開設定：撳「位置」，揀「永遠」（有啲手機寫「始終」），再開「精確位置」。", "点下面的按钮打开设置：点「位置」，选「永远」（有些手机写「始终」），再开「精确位置」。")
                        : L.t("要將定位改做「始終允許」。等陣彈出嚟嘅框，請揀「改為始終允許」（有啲手機寫「永遠允許」）。", "要把定位改成「始终允许」。待会儿弹出的框，请选「改为始终允许」（有些手机写「永远允许」）。"))
                    row("battery.75percent", L.t("喺屋企唔會一直開定位，只係出門行路先用準確定位，唔會好食電。", "在家不会一直开定位，只有出门走路才用精确定位，不会很耗电。"))
                    row("lock.shield.fill", L.t("屋企喺邊、行過嘅路，只留喺你部手機，唔會上傳。", "家在哪里、走过的路，只留在你的手机上，不会上传。"))
                }
                Button { store.sayAgain(Self.spoken) } label: {
                    Label(L.t("再聽一次", "再听一次"), systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity)
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
                    Text(viaSettings ? L.t("打開 iPhone 設定", "打开 iPhone 设置") : L.t("好，下一步", "好，下一步")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
                Button { lm.showAlwaysAsk = false } label: {
                    Text(L.t("遲啲先", "以后再说")).frame(maxWidth: .infinity)
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
            if lm.needsAttention, (lm.cardHiddenUntil ?? .distantPast) < Date() {
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
        case .moved: return L.t("你係咪搬咗屋？要唔要將屋企同社區搬過嚟？", "你是不是搬家了？要不要把家和社区搬过来？")
        case .suggest: return L.t("你屋企係咪喺第二度？要唔要將屋企同社區搬過嚟？", "你家是不是在别处？要不要把家和社区搬过来？")
        }
    }

    private var detail: String {
        switch prompt {
        case .moved(_, let d, let n):
            return L.t("最近 \(n) 晚你都喺\(relHome(d, "離而家屋企", "离现在的家"))嘅地方過夜。", "最近 \(n) 晚你都在\(relHome(d, "離而家屋企", "离现在的家"))的地方过夜。")
        case .suggest(_, let d, let n):
            let far = d.map { "（\(relHome($0, "離而家個模型", "离现在的模型"))）" } ?? ""
            return L.t("最近 \(n) 晚你都喺同一個地方過夜\(far)。", "最近 \(n) 晚你都在同一个地方过夜\(far)。")
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
            Text(L.t("唔係", "不是")).frame(maxWidth: stacked ? .infinity : nil)
        }
        .buttonStyle(.dsSecondary)
        Button { store.acceptHomePrompt() } label: {
            Text(L.t("係，搬過嚟", "是，搬过来")).frame(maxWidth: .infinity)
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
                    Text(L.t("出門自動記錄未開齊", "出门自动记录未开全")).ds(.bodyBold)
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
            Text(L.t("遲啲先", "以后再说")).frame(maxWidth: stacked ? .infinity : nil)
        }
        .buttonStyle(.dsSecondary)
        Button { if lm.needsAlways { lm.showAlwaysAsk = true } else { lm.openSettings() } } label: {
            Text(L.t("點樣開", "怎么开")).frame(maxWidth: .infinity)
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
            LabeledContent(L.t("定位", "定位")) { Text(LocationMonitor.authLabel(lm.auth)).foregroundStyle(lm.auth == .authorizedAlways ? Color.secondary : DS.accent) }
            if !lm.precise {
                LabeledContent(L.t("精確位置", "精确位置")) { Text(L.t("關咗", "已关闭")).foregroundStyle(DS.accent) }
            }
            LabeledContent(L.t("動作與健身", "运动与健身")) {
                Text(LocationMonitor.motionLabel(lm.motionAuth)).foregroundStyle(lm.motionAuth == .denied ? DS.accent : Color.secondary)
            }
            if !lm.backgroundRefreshOK {
                LabeledContent(L.t("背景 App 重新整理", "后台 App 刷新")) { Text(L.t("關咗", "已关闭")).foregroundStyle(DS.accent) }
            }
            if lm.needsAttention || lm.motionAuth == .denied || lm.motionAuth == .restricted {
                if lm.auth == .authorizedWhenInUse || lm.auth == .notDetermined, !lm.askedAlways {
                    Button(L.t("改做始終允許", "改成始终允许")) { lm.showAlwaysAsk = true }
                } else {
                    Button(L.t("打開 iPhone 設定", "打开 iPhone 设置")) { lm.openSettings() }
                }
            }
            NavigationLink { LocationLogView() } label: { Text(L.t("定位紀錄", "定位记录")) }
        } header: {
            Text(L.t("出門自動記錄", "出门自动记录")).ds(.caption)
        } footer: {
            Text(LocationStatusText.footer(lm)).ds(.caption)
        }
    }
}

/// LocationMonitor.describe 嘅「離屋企」（普通话「离家」）换成另一个参照。
@MainActor fileprivate func relHome(_ d: Double?, _ yue: String, _ cmn: String) -> String {
    LocationMonitor.describe(d).replacingOccurrences(of: "離屋企", with: yue).replacingOccurrences(of: "离家", with: cmn)
}

/// 状态文字（设定、今日卡、定位纪录共用）。
enum LocationStatusText {
    /// 有咩未齐（齐晒就 nil）。
    @MainActor static func problem(_ lm: LocationMonitor) -> String? {
        switch lm.auth {
        case .denied, .restricted: return L.t("定位已經拒絕咗：唔會記錄路線同地標，亦唔知你幾時返到屋企。", "定位已被拒绝：不会记录路线和地标，也不知道你什么时候到家。")
        case .notDetermined: return L.t("未允許定位：散步唔會自動記錄。", "未允许定位：散步不会自动记录。")
        case .authorizedWhenInUse: return L.t("定位只係「用緊 App 時」先開：鎖咗機出門唔會即時記錄，要等你打開 App 先補返分鐘同步數（冇地標）。", "定位只在「使用 App 期间」开启：锁屏出门不会实时记录，要等你打开 App 才补记分钟和步数（没有地标）。")
        default: break
        }
        if !lm.precise { return L.t("「精確位置」關咗：認唔到你行過邊個地標，亦唔知你幾時出門。", "「精确位置」已关闭：认不出你走过哪个地标，也不知道你什么时候出门。") }
        if lm.motionAuth == .denied || lm.motionAuth == .restricted { return L.t("「動作與健身」關咗：認唔到你開始行路。", "「运动与健身」已关闭：识别不到你开始走路。") }
        if !lm.backgroundRefreshOK { return L.t("「背景 App 重新整理」關咗（或者開咗低耗電模式）：App 俾系統收咗之後，出門唔會被叫醒。去 設定 → 一般 → 背景 App 重新整理 開返。", "「后台 App 刷新」已关闭（或开了低电量模式）：App 被系统关掉后，出门不会被唤醒。去 设置 → 通用 → 后台 App 刷新 重新打开。") }
        return nil
    }

    @MainActor static func footer(_ lm: LocationMonitor) -> String {
        problem(lm) ?? L.t("出門會自動記錄，鎖咗機都得。唔好喺多工畫面將街坊行掃走，否則出門唔會自動記錄。", "出门会自动记录，锁屏也可以。别在多任务界面把街坊行划掉，否则出门不会自动记录。")
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
                InfoRow(title: L.t("自動記錄", "自动记录"), value: statusText(lm))
                InfoRow(title: L.t("屋企", "家"), value: verdictText(lm.verdict))
                InfoRow(title: L.t("而家", "现在"), value: lm.insideHome.map { $0 ? L.t("喺屋企範圍內（100 米）", "在家范围内（100 米）") : L.t("唔喺屋企範圍", "不在家范围内") } ?? L.t("未知喺唔喺屋企", "不知道是否在家"))
            } header: { Text(L.t("狀態", "状态")).ds(.caption) }

            Section {
                InfoRow(title: L.t("今日", "今天"), value: today.walks > 0 ? L.t("記咗 \(today.walks) 次，共 \(today.minutes) 分鐘", "记了 \(today.walks) 次，共 \(today.minutes) 分钟") : L.t("今日未有散步紀錄", "今天还没有散步记录"))
                ForEach(todayEvents.reversed()) { e in EventRow(event: e) }
            } header: { Text(L.t("今日散步（包括補記）", "今天散步（包括补记）")).ds(.caption) }

            Section {
                if nights.isEmpty {
                    Text(L.t("未有。夜晚 10 點到朝早 6 點喺邊過夜，會喺呢度記低（最多 14 晚）。", "暂无。晚上 10 点到早上 6 点在哪里过夜，会记在这里（最多 14 晚）。")).ds(.caption).foregroundStyle(.secondary)
                }
                ForEach(nights, id: \.night) { n in
                    InfoRow(title: Self.nightLabel(n.night), value: "\(placeText(n.center, lm)) · \(String(format: "%.1f", n.hours))" + L.t(" 小時", " 小时"))
                }
            } header: { Text(L.t("過夜位置", "过夜位置")).ds(.caption) } footer: {
                Text(L.t("只存喺你部手機，唔會上傳；連續兩晚喺同一度就當係屋企。", "只存在你的手机上，不会上传；连续两晚在同一处就当作家。")).ds(.caption)
            }

            Section {
                if wakes.isEmpty { Text(L.t("未有。出門、返屋企時 iOS 會喺背景叫醒街坊行，會喺呢度記低。", "暂无。出门、回家时 iOS 会在后台唤醒街坊行，会记在这里。")).ds(.caption).foregroundStyle(.secondary) }
                ForEach(Array(wakes)) { e in EventRow(event: e) }
            } header: { Text(L.t("最近喚醒", "最近唤醒")).ds(.caption) }

            Section {
                ForEach(Array(others)) { e in EventRow(event: e) }
            } header: { Text(L.t("其他紀錄", "其他记录")).ds(.caption) }

            Section {
                Label(L.t("唔好喺多工畫面將街坊行掃走，否則出門唔會自動記錄。", "别在多任务界面把街坊行划掉，否则出门不会自动记录。"), systemImage: "exclamationmark.triangle.fill")
                    .ds(.body)
                Label(L.t("手機重新開機之後，打開一次街坊行。", "手机重启之后，打开一次街坊行。"), systemImage: "arrow.clockwise")
                    .ds(.body)
            } header: { Text(L.t("提提你", "提醒你")).ds(.caption) }

            Section {
                Button(L.t("清除定位紀錄", "清除定位记录"), role: .destructive) { confirmClear = true }
            }
        }
        .navigationTitle(L.t("定位紀錄", "定位记录"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text(L.t("定位紀錄", "定位记录")).ds(.bodyBold).accessibilityAddTraits(.isHeader) }
        }
        .confirmationDialog(L.t("清除定位紀錄？", "清除定位记录？"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L.t("清除", "清除"), role: .destructive) { lm.clearRecords() }
            Button(L.t("唔清", "不清除"), role: .cancel) {}
        } message: {
            Text(L.t("最近喚醒同過夜位置會刪走；散步紀錄唔受影響。", "最近唤醒和过夜位置会被删除；散步记录不受影响。"))
        }
        .onAppear { lm.reevaluate() }
    }

    private func statusText(_ lm: LocationMonitor) -> String {
        if store.demoMode { return L.t("演示模式開住：唔記錄真散步（喺設定關咗演示模式）", "演示模式开着：不记录真实散步（在设置里关掉演示模式）") }
        if !WalkDetector.isAvailable { return L.t("呢部機冇動作感應，唔會自動記錄", "这台手机没有运动感应，不会自动记录") }
        if let p = LocationStatusText.problem(lm) { return L.t("未開齊。\(p)", "未开全。\(p)") }
        if lm.home == nil { return L.t("未有屋企位置（打開一次主畫面）", "还没有家的位置（打开一次主界面）") }
        guard lm.monitoring else { return L.t("未開始監察（打開一次主畫面）", "未开始监测（打开一次主界面）") }
        return lm.lowPower ? L.t("開咗，但低耗電模式開緊：iOS 可能遲啲先叫醒街坊行", "已开启，但低电量模式开着：iOS 可能晚点才唤醒街坊行") : L.t("開咗：離開屋企會自動開始記錄", "已开启：离开家会自动开始记录")
    }

    private func verdictText(_ v: HomeVerdict) -> String {
        switch v {
        case .learning(let n): return n == 0 ? L.t("學緊：未有過夜紀錄（要 2 晚）", "学习中：还没有过夜记录（要 2 晚）") : L.t("學緊：記咗 \(n) 晚，要 2 晚", "学习中：记了 \(n) 晚，要 2 晚")
        case .confirmed(let n, let d): return L.t("已確認：\(n) 晚喺你揀嘅樓附近過夜（相差 \(Int(d.rounded())) 米）", "已确认：\(n) 晚在你选的楼附近过夜（相差 \(Int(d.rounded())) 米）")
        case .unsure(let n, let d): return L.t("未確認：\(n) 晚過夜嘅地方\(relHome(d, "離你揀嘅樓", "离你选的楼"))", "未确认：\(n) 晚过夜的地方\(relHome(d, "離你揀嘅樓", "离你选的楼"))")
        case .moved(_, let n, let d): return L.t("最近 \(n) 晚都喺\(LocationMonitor.describe(d))嘅地方過夜（會問你係咪搬咗屋）", "最近 \(n) 晚都在\(LocationMonitor.describe(d))的地方过夜（会问你是否搬家了）")
        case .suggest(_, let n, let d):
            return L.t("你未揀屋企：\(n) 晚喺同一個地方過夜\(d.map { "（\(relHome($0, "離而家個模型", "离现在的模型")))" } ?? "")", "你还没选家：\(n) 晚在同一个地方过夜\(d.map { "（\(relHome($0, "離而家個模型", "离现在的模型")))" } ?? "")")
        }
    }

    private func placeText(_ p: GeoPoint, _ lm: LocationMonitor) -> String {
        guard let h = lm.home else { return L.t("未有屋企位置對比", "没有家的位置可对比") }
        let d = HomeLearner.distance(h, p)
        return d <= HomeLearner.confirmRadius ? L.t("喺屋企附近（\(Int(d.rounded())) 米）", "在家附近（\(Int(d.rounded())) 米）") : LocationMonitor.describe(d)
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
                    Text(L.t("背景", "后台")).ds(.caption).foregroundStyle(DS.accent)
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
