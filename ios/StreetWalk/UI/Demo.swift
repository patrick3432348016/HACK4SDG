import SwiftUI

// MARK: - 演示菜单（右上胶囊，一层）

struct DemoMenu: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Menu {
            Section {
                if store.walk == nil {
                    Button { store.startWalk() } label: { Label(L.t("出門", "出门", "Go out"), systemImage: "figure.walk") }
                } else {
                    Button { store.finishWalk() } label: { Label(L.t("返屋企", "回家", "Go home"), systemImage: "house.fill") }
                }
            }
            Section(L.t("陳太", "陳太", "Mrs Chan")) {
                Button { store.neighborGoesOut() } label: { Label(L.t("陳太出門", "陳太出门", "Mrs Chan goes out"), systemImage: "door.left.hand.open") }
                Button { store.partnerInvites() } label: { Label(L.t("陳太約你", "陳太约你", "Mrs Chan invites you"), systemImage: "envelope.fill") }
                Button { store.neighborGoesHome() } label: { Label(L.t("陳太返屋企", "陳太回家", "Mrs Chan goes home"), systemImage: "house.fill") }
                Button { store.declineNextAsk() } label: { Label(L.t("陳太唔方便（下一次）", "陳太不方便（下一次）", "Mrs Chan says no (next time)"), systemImage: "hand.raised.fill") }
                if store.find != nil {
                    Button { store.lateDemo() } label: { Label(L.t("遲到", "迟到", "Running late"), systemImage: "clock.badge.exclamationmark") }
                }
            }
            Section(L.t("天氣同時間", "天气和时间", "Weather and time")) {
                Button { store.setWeather(.hot) } label: {
                    Label(L.t("酷熱", "酷热", "Very hot"), systemImage: store.weather == .hot ? "checkmark" : "sun.max.fill")
                }
                Button { store.setWeather(.rain) } label: {
                    Label(L.t("落雨", "下雨", "Rain"), systemImage: store.weather == .rain ? "checkmark" : "cloud.rain.fill")
                }
                Button { store.setWeather(.normal) } label: {
                    Label(L.t("天氣正常", "天气正常", "Normal weather"), systemImage: store.weather == .normal ? "checkmark" : "cloud.sun.fill")
                }
                Button { store.showTimeSlider = true } label: { Label(L.t("時間…", "时间…", "Time…"), systemImage: "clock") }
            }
            Section {
                Button { store.showReport = true } label: { Label(L.t("月尾報告", "月底报告", "Monthly report"), systemImage: "doc.text.fill") }
                Button { store.simulateFollowUp() } label: { Label(L.t("屋邨管理回覆反映", "屋邨管理回复反馈", "Estate office replies"), systemImage: "checkmark.seal.fill") }
                Button { store.regenerateHere() } label: { Label(L.t("重新載入地圖", "重新加载地图", "Reload map"), systemImage: "arrow.clockwise") }
                Button(role: .destructive) { store.resetDemo() } label: {
                    Label(L.t("重置演示", "重置演示", "Reset demo"), systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                // 大字号时只留图标，让位给左边「行緊 N 分鐘」。
                if !typeSize.isAccessibilitySize { Text(L.t("演示", "演示", "Demo")) }
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
        // Menu 的 label 不跟 foregroundStyle，会变系统蓝；用中性色，和左边齿轮一致。
        .tint(.primary)
        .accessibilityLabel(L.t("演示選單", "演示菜单", "Demo menu"))
    }
}

// MARK: - 时间滑杆（.medium 半屏，拖动时场景里的太阳和影子跟住郁）

struct TimeSliderSheet: View {
    @Environment(AppStore.self) private var store
    @State private var hour: Double = 15
    /// 程序改 hour 时不回推给 store。
    @State private var syncing = false

    var body: some View {
        let h = shownHour
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.t("時間", "时间", "Time"))
                    .ds(.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(L.t("完成", "完成", "Done")) { store.showTimeSlider = false }
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
                Text(L.t("時間", "时间", "Time"))
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
                    Label(L.t("跟返而家時間", "恢复现在时间", "Back to current time"), systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.dsSecondary)
                .transition(DS.slide(.top))
            }

            Text(L.t("地標遮蔭 · 按畫面入面啲樓大約計（唔計樹）", "地标遮荫 · 按画面里的楼大约估算（不算树）", "Landmark shade · rough guess from the buildings shown (trees not counted)"))
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
        // 半屏高度、底色由 MainView 的 .sheet 统一设定（以前两处设定不一致）。
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
            Text(v == nil ? L.t("遮蔭 —", "遮荫 —", "Shade —") : L.t("遮蔭 \(pct)%", "遮荫 \(pct)%", "Shade \(pct)%"))
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
        guard let el = sunElevation(h) else { return L.t("拖動睇吓影點樣郁", "拖动看看影子怎么动", "Drag to see the shadows move") }
        if el <= 0 { return L.t("太陽已經落山", "太阳已经落山", "Sun has set") }
        return L.t("太陽高度 \(Int(el.rounded()))° · 拖動睇吓影點樣郁", "太阳高度 \(Int(el.rounded()))° · 拖动看看影子怎么动", "Sun height \(Int(el.rounded()))° · drag to see the shadows move")
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

    /// 例如"下晝 3:15"。
    static func label(_ h: Double) -> String {
        let total = Int((h * 60).rounded())
        let hh = (total / 60) % 24, mm = total % 60
        let period = hh < 5 ? L.t("凌晨", "凌晨", "am") : hh < 12 ? L.t("朝早", "早上", "am") : hh < 13 ? L.t("中午", "中午", "pm") : hh < 18 ? L.t("下晝", "下午", "pm") : L.t("夜晚", "晚上", "pm")
        let h12 = hh % 12 == 0 ? 12 : hh % 12
        if L.isEn { return "\(h12):\(mm < 10 ? "0" : "")\(mm) \(hh < 12 ? "am" : "pm")" }   // 英文：3:15 pm
        return "\(period) \(h12):\(mm < 10 ? "0" : "")\(mm)"
    }
}

// MARK: - 月尾报告（社工 / 规划方视角）

struct ReportView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var shown = false

    var body: some View {
        let r = store.monthly
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(L.t("社工 / 規劃方視角", "社工 / 规划方视角", "Social worker / planner view"), systemImage: "person.badge.shield.checkmark.fill")
                        .ds(.captionBold)
                        .foregroundStyle(DS.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DS.accentSoft, in: Capsule())
                    Spacer()
                    Button(L.t("完成", "完成", "Done")) { store.showReport = false; dismiss() }
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
                    DemoNote(text: L.t("單機演示：全邨人次、你嘅散步紀錄同其他居民嘅反映係示範數據；你自己嘅反映係真嘅。", "单机演示：全邨人次、你的散步记录和其他居民的反馈是示范数据；你自己的反馈是真的。", "Offline demo: estate totals, your walk history and other residents' reports are sample data. Your own reports are real."))
                }

                HStack(spacing: 8) {
                    metric(L.t("散步人次", "散步人次", "Walks"), shown ? r.walkers : 0, symbol: "figure.walk")
                    metric(L.t("一齊行", "一起走", "Walks together"), shown ? r.meetups : 0, symbol: "person.2.fill")
                }

                Text(L.t("居民反映", "居民反馈", "Residents' reports"))
                    .ds(.bodyBold)
                    .padding(.top, 8)

                if r.items.isEmpty {
                    Text(L.t("今個月未有 \(TemplateAI.minReporters) 人以上嘅反映", "本月还没有 \(TemplateAI.minReporters) 人以上的反馈", "No issue reported by \(TemplateAI.minReporters)+ people this month"))
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
                    Text(L.t("只計 \(TemplateAI.minReporters) 人以上嘅反映 · 冇任何個人路線 · 交俾：社工、屋邨管理、新發展區團隊", "只计 \(TemplateAI.minReporters) 人以上的反馈 · 没有任何个人路线 · 交给：社工、屋邨管理、新发展区团队", "Only issues reported by \(TemplateAI.minReporters)+ people · no personal routes · sent to: social workers, estate office, new development area team"))
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
                Text(L.t("\(item.count) 人反映", "\(item.count) 人反馈", "\(item.count) people reported"))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                Text(L.t("建議：\(item.suggestion)", "建议：\(item.suggestion)", "Suggestion: \(item.suggestion)"))
                    .ds(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .dsCard()
        .accessibilityElement(children: .combine)
    }
}

/// 截图自检：启动参数 `-uiPreview <名>` 直接摆出要检查的界面（模拟器点不到时用）。
/// declined = 同意页按了「唔同意」；buildingList = 选楼清单；todayBottom = 今日页滚到底。
enum UIPreview {
    static func `is`(_ name: String) -> Bool { LaunchArgs.value("-uiPreview") == name }
}
