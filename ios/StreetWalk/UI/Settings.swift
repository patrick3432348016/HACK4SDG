import SwiftUI

/// 设置（左上齿轮）：改我住的楼 / 楼层 / 小人；出门提醒总开关和接收时段；演示模式；清除记录。
/// 一页到底，不做多级菜单。
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmClear = false
    @State private var confirmMove = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    LabeledContent("住喺") {
                        Text(store.me.blockName ?? store.map?.placeName ?? "—").foregroundStyle(.secondary)
                    }
                    Button("改我住嘅樓") { confirmMove = true }
                    Stepper(value: Binding(get: { store.floorChoice }, set: { store.setFloor($0) }), in: 1...max(1, store.homeLevels)) {
                        LabeledContent("樓層", value: "\(store.floorChoice) 樓")
                    }
                    Picker("小人", selection: Binding(get: { store.mobilityChoice }, set: { store.setAvatar(mobility: $0) })) {
                        ForEach(Mobility.allCases, id: \.self) { m in
                            Label(m.label, systemImage: AvatarBadge(color: .clear, mobility: m).symbol).tag(m)
                        }
                    }
                    colorRow
                } header: {
                    Text("我").ds(.caption)
                }

                Section {
                    Toggle("出門提醒", isOn: $store.remindAll).tint(DS.accent)
                    if store.remindAll {
                        Picker("由", selection: $store.remindFrom) {
                            ForEach(5..<24, id: \.self) { Text(TemplateAI.hourLabel($0)).tag($0) }
                        }
                        Picker("到", selection: $store.remindTo) {
                            ForEach(6..<24, id: \.self) { Text(TemplateAI.hourLabel($0)).tag($0) }
                        }
                    }
                } header: {
                    Text("街坊出門話我知").ds(.caption)
                } footer: {
                    Text("只喺呢段時間通知你。每個街坊仲可以喺「街坊」頁分開開關。").ds(.caption)
                }

                Section {
                    Toggle("演示模式", isOn: Binding(get: { store.demoMode }, set: { store.setDemoMode($0) }))
                        .tint(DS.accent)
                        .disabled(LaunchArgs.has("-demo"))
                } footer: {
                    Text(LaunchArgs.has("-demo") ? "而家用演示參數開啟，唔可以喺度關。"
                         : "演示模式會加入示範街坊、示範紀錄同右上角嘅演示選單。關咗之後，圈入面暫時只有你（未接伺服器）。").ds(.caption)
                }

                Section {
                    Button("清除我嘅紀錄", role: .destructive) { confirmClear = true }
                } footer: {
                    Text("街坊關係、約會、反映、改過嘅地標名、散步紀錄都只存喺你部手機。地圖資料 © OpenStreetMap；天氣：香港天文台。").ds(.caption)
                }
            }
            .ds(.body)
            .tint(DS.accent)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { store.showSettings = false }.foregroundStyle(DS.accent)
                }
            }
            .confirmationDialog("清除全部紀錄？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清除", role: .destructive) { store.clearAllData(); store.populate() }
                Button("唔清", role: .cancel) {}
            } message: {
                Text("街坊、約會、反映同散步紀錄都會刪走，冇得還原。")
            }
            .confirmationDialog("改我住嘅樓？", isPresented: $confirmMove, titleVisibility: .visible) {
                Button("揀過座樓") { store.showSettings = false; store.beginChangeHome() }
                Button("唔改", role: .cancel) {}
            } message: {
                Text("會重新揀樓。之前嘅約會地點同反映位置會清走，街坊同散步紀錄保留。")
            }
        }
    }

    private var colorRow: some View {
        HStack(spacing: 0) {
            ForEach(0..<Palette.people.count, id: \.self) { i in
                let on = store.colorChoice == i
                Button { store.setAvatar(color: i) } label: {
                    Circle()
                        .fill(Palette.person(i))
                        .frame(width: 30, height: 30)
                        .overlay { if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("顏色 \(i + 1)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

extension AppStore {
    /// 我住的楼有几层（选楼层的上限）。
    var homeLevels: Int { scene.homeBuildingID.flatMap { (fullMap ?? map)?.building(id: $0)?.levels } ?? 30 }

    func setFloor(_ f: Int) {
        floorChoice = f
        UserDefaults.standard.set(f, forKey: "floor")
        if let i = residents.firstIndex(where: \.isMe) { residents[i].floor = f; refreshMe() }
    }

    func setAvatar(mobility: Mobility? = nil, color: Int? = nil) {
        if let mobility { mobilityChoice = mobility; UserDefaults.standard.set(mobility.rawValue, forKey: "mobility") }
        if let color { colorChoice = color; UserDefaults.standard.set(color, forKey: "color") }
        if let i = residents.firstIndex(where: \.isMe) {
            residents[i].mobility = mobilityChoice
            residents[i].colorIndex = colorChoice
        }
        syncScene()
        Haptics.select()
    }

    /// 开 / 关演示模式：示範街坊、示範纪录、演示菜单跟住变。
    func setDemoMode(_ on: Bool) {
        demoMode = on
        UserDefaults.standard.set(on, forKey: "demoMode")
        localCommunity?.demoEnabled = on
        if on && walkLog.values.allSatisfy({ !$0.demo }) && walkLog.isEmpty { seedDemoHistory() }
        // 演示模式同真机散步检测唔好同时开
        if on { if walkDetector.recording { finishLiveWalk() }; walkDetector.stop() } else { startWalkDetection() }
        populate()
    }

    /// 重新揀我住的楼：回到首次使用的选楼一步，完成后回主界面。
    func beginChangeHome() {
        walk = nil; find = nil; findFullScreen = false; proposal = nil; selection = nil
        pendingHome = nil
        phase = .onboarding(.locate)
        Task { await loadMap(home: nil, animated: true) }
    }
}
