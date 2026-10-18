import SwiftUI

// MARK: - Single-level demo menu in the top-right capsule

struct DemoMenu: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Menu {
            Section {
                if store.walk == nil {
                    Button { store.startWalk() } label: { Label(L.t("出門", "出门"), systemImage: "figure.walk") }
                } else {
                    Button { store.finishWalk() } label: { Label(L.t("返屋企", "回家"), systemImage: "house.fill") }
                }
            }
            Section("陳太") {
                Button { store.neighborGoesOut() } label: { Label(L.t("陳太出門", "陳太出门"), systemImage: "door.left.hand.open") }
                Button { store.partnerInvites() } label: { Label(L.t("陳太約你", "陳太约你"), systemImage: "envelope.fill") }
                Button { store.neighborGoesHome() } label: { Label(L.t("陳太返屋企", "陳太回家"), systemImage: "house.fill") }
                Button { store.declineNextAsk() } label: { Label(L.t("陳太唔方便（下一次）", "陳太不方便（下一次）"), systemImage: "hand.raised.fill") }
                if store.find != nil {
                    Button { store.lateDemo() } label: { Label(L.t("遲到", "迟到"), systemImage: "clock.badge.exclamationmark") }
                }
            }
            Section(L.t("天氣同時間", "天气和时间")) {
                Button { store.setWeather(.hot) } label: {
                    Label(L.t("酷熱", "酷热"), systemImage: store.weather == .hot ? "checkmark" : "sun.max.fill")
                }
                Button { store.setWeather(.rain) } label: {
                    Label(L.t("落雨", "下雨"), systemImage: store.weather == .rain ? "checkmark" : "cloud.rain.fill")
                }
                Button { store.setWeather(.normal) } label: {
                    Label(L.t("天氣正常", "天气正常"), systemImage: store.weather == .normal ? "checkmark" : "cloud.sun.fill")
                }
                Button { store.showTimeSlider = true } label: { Label(L.t("時間…", "时间…"), systemImage: "clock") }
            }
            Section {
                Button { store.showReport = true } label: { Label(L.t("月尾報告", "月底报告"), systemImage: "doc.text.fill") }
                Button { store.simulateFollowUp() } label: { Label(L.t("屋邨管理回覆反映", "屋邨管理回复反馈"), systemImage: "checkmark.seal.fill") }
                Button { store.regenerateHere() } label: { Label(L.t("重新載入地圖", "重新加载地图"), systemImage: "arrow.clockwise") }
                Button(role: .destructive) { store.resetDemo() } label: {
                    Label("重置演示", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                // At large text sizes, keep only the icon to leave room for elapsed walking time.
                if !typeSize.isAccessibilitySize { Text("演示") }
            }
            .ds(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
            .contentShape(Capsule())
        }
        .menuOrder(.fixed)
        // Menu labels ignore foregroundStyle; use neutral color matching the Settings gear instead of system blue.
        .tint(.primary)
        .accessibilityLabel(L.t("演示選單", "演示菜单"))
    }
}

// MARK: - Medium-height time slider updates scene sun and shadows

struct TimeSliderSheet: View {
    @Environment(AppStore.self) private var store
    @State private var hour: Double = 15
    /// Do not send programmatic hour changes back to the store.
    @State private var syncing = false

    var body: some View {
        let h = shownHour
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.t("時間", "时间"))
                    .ds(.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("完成") { store.showTimeSlider = false }
                    .ds(.bodyBold)
                    .foregroundStyle(DS.accent)
            }

            HStack(spacing: 12) {
                Image(systemName: sunSymbol(h))
                    .font(.system(size: 36, weight: .semibold))
                    .symbolRenderingMode(.multicolor)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.label(h))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: h))
                    Text(sunCaption(h))
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .animation(DS.motion(DS.snappy), value: h)
            .accessibilityElement(children: .combine)

            Slider(value: $hour, in: 6...19, step: 0.25) {
                Text(L.t("時間", "时间"))
            } minimumValueLabel: {
                Image(systemName: "sunrise.fill").foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "moon.fill").foregroundStyle(.secondary)
            }
            .tint(DS.accent)
            .accessibilityValue(Self.label(hour))

            if store.demoHour != nil {
                Button {
                    store.setDemoHour(nil)
                    setLocal(Self.clamp(Self.realHour()))
                } label: {
                    Label(L.t("跟返而家時間", "恢复现在时间"), systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.dsSecondary)
                .transition(DS.slide(.top))
            }

            Text(L.t("地標遮蔭 · 按畫面入面啲樓大約計（唔計樹）", "地标遮荫 · 按画面里的楼大约估算（不算树）"))
                .ds(.captionBold)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.landmarks) { lm in shadeRow(lm, h) }
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, DS.side)
        .padding(.top, 24)
        .animation(DS.motion(DS.spring), value: store.demoHour == nil)
        .sensoryFeedback(.selection, trigger: hour)
        // MainView.sheet owns consistent height and background settings.
        .onAppear { setLocal(Self.clamp(store.demoHour ?? Self.realHour())) }
        .onChange(of: hour) { _, new in
            if syncing { syncing = false } else { store.setDemoHour(new) }
        }
    }

    private var shownHour: Double { store.demoHour ?? Self.realHour() }

    private func setLocal(_ h: Double) {
        guard h != hour else { return }
        syncing = true
        hour = h
    }

    private func shadeRow(_ lm: Landmark, _ h: Double) -> some View {
        let v = store.shadeValue(lm.id, at: AppStore.today(at: h))
        let pct = Int(((v ?? 0) * 100).rounded())
        return HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(DS.accent)
            Text(lm.name)
                .ds(.body)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 64, height: 10)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray))
                        .frame(width: 64 * CGFloat(v ?? 0), height: 10)
                }
                .accessibilityHidden(true)
            Text(v == nil ? L.t("遮蔭 —", "遮荫 —") : L.t("遮蔭 \(pct)%", "遮荫 \(pct)%"))
                .ds(.captionBold)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(pct)))
                .frame(minWidth: 104, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(DS.motion(DS.snappy), value: pct)
        .accessibilityElement(children: .combine)
    }

    private func sunSymbol(_ h: Double) -> String {
        let el = sunElevation(h)
        if let el, el <= 0 { return "moon.stars.fill" }
        if h < 8 { return "sunrise.fill" }
        if h >= 17 { return "sunset.fill" }
        return "sun.max.fill"
    }

    private func sunCaption(_ h: Double) -> String {
        guard let el = sunElevation(h) else { return L.t("拖動睇吓影點樣郁", "拖动看看影子怎么动") }
        if el <= 0 { return L.t("太陽已經落山", "太阳已经落山") }
        return L.t("太陽高度 \(Int(el.rounded()))° · 拖動睇吓影點樣郁", "太阳高度 \(Int(el.rounded()))° · 拖动看看影子怎么动")
    }

    private func sunElevation(_ h: Double) -> Double? {
        guard let m = store.map else { return nil }
        return SolarPosition.at(AppStore.today(at: h), lat: m.center.lat, lon: m.center.lon).elevation
    }

    static func realHour() -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SolarPosition.hongKong
        let c = cal.dateComponents([.hour, .minute], from: Date())
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
    }

    static func clamp(_ h: Double) -> Double { min(19, max(6, (h * 4).rounded() / 4)) }

    /// Localized time label, including minutes.
    static func label(_ h: Double) -> String {
        let total = Int((h * 60).rounded())
        let hh = (total / 60) % 24, mm = total % 60
        let period = hh < 5 ? "凌晨" : hh < 12 ? L.t("朝早", "早上") : hh < 13 ? "中午" : hh < 18 ? L.t("下晝", "下午") : L.t("夜晚", "晚上")
        let h12 = hh % 12 == 0 ? 12 : hh % 12
        return "\(period) \(h12):\(mm < 10 ? "0" : "")\(mm)"
    }
}

// MARK: - Monthly report for community workers and planners

struct ReportView: View {
    @Environment(AppStore.self) private var store
    @State private var shown = false

    var body: some View {
        let r = store.monthly
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(L.t("社工 / 規劃方視角", "社工 / 规划方视角"), systemImage: "person.badge.shield.checkmark.fill")
                        .ds(.captionBold)
                        .foregroundStyle(DS.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DS.accentSoft, in: Capsule())
                    Spacer()
                    Button("完成") { store.showReport = false }
                        .ds(.bodyBold)
                        .foregroundStyle(DS.accent)
                }

                Text(r.title)
                    .ds(.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(r.summary)
                    .ds(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if store.monthlyStats.isDemo {
                    DemoNote(text: L.t("單機演示：全邨人次、你嘅散步紀錄同其他居民嘅反映係示範數據；你自己嘅反映係真嘅。", "单机演示：全邨人次、你的散步记录和其他居民的反馈是示范数据；你自己的反馈是真的。"))
                }

                HStack(spacing: 8) {
                    metric("散步人次", shown ? r.walkers : 0, symbol: "figure.walk")
                    metric(L.t("一齊行", "一起走"), shown ? r.meetups : 0, symbol: "person.2.fill")
                }

                Text(L.t("居民反映", "居民反馈"))
                    .ds(.bodyBold)
                    .padding(.top, 8)

                if r.items.isEmpty {
                    Text(L.t("今個月未有 \(TemplateAI.minReporters) 人以上嘅反映", "本月还没有 \(TemplateAI.minReporters) 人以上的反馈"))
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .dsCard()
                } else {
                    ForEach(Array(r.items.enumerated()), id: \.element.id) { i, item in
                        itemRow(item)
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown || DS.reduceMotion ? 0 : 12)
                            .animation(DS.motion(DS.spring).delay(0.1 + Double(i) * 0.06), value: shown)
                    }
                }

                Label {
                    Text(L.t("只計 \(TemplateAI.minReporters) 人以上嘅反映 · 冇任何個人路線 · 交俾：社工、屋邨管理、新發展區團隊", "只计 \(TemplateAI.minReporters) 人以上的反馈 · 没有任何个人路线 · 交给：社工、屋邨管理、新发展区团队"))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield.fill")
                }
                .ds(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            .padding(.horizontal, DS.side)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(DS.motion(.smooth(duration: 0.9))) { shown = true }
        }
    }

    private func metric(_ title: String, _ value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .ds(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
        }
        .dsCard()
        .accessibilityElement(children: .combine)
    }

    private func itemRow(_ item: MonthlyReport.Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 48, height: 48)
                .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.place) · \(item.kind.label)").ds(.bodyBold)
                Text(L.t("\(item.count) 人反映", "\(item.count) 人反馈"))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                Text(L.t("建議：\(item.suggestion)", "建议：\(item.suggestion)"))
                    .ds(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .dsCard()
        .accessibilityElement(children: .combine)
    }
}

/// -uiPreview <name> renders a target state directly for simulator screenshot checks.
/// declined shows refused consent; buildingList shows the picker list; todayBottom scrolls Today to the bottom.
enum UIPreview {
    static func `is`(_ name: String) -> Bool { LaunchArgs.value("-uiPreview") == name }
}
