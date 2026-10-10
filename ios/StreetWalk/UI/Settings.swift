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
                    // 由、到一樣當全日（A66）
                    Text(store.remindFrom == store.remindTo ? "「由」同「到」一樣，即係全日都會通知你。每個街坊仲可以喺「街坊」頁分開開關。"
                         : "只喺呢段時間通知你\(store.remindFrom > store.remindTo ? "（跨夜）" : "")。每個街坊仲可以喺「街坊」頁分開開關。").ds(.caption)
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
        uploadProfile()
    }

    func setAvatar(mobility: Mobility? = nil, color: Int? = nil) {
        if let mobility { mobilityChoice = mobility; UserDefaults.standard.set(mobility.rawValue, forKey: "mobility") }
        if let color { colorChoice = color; UserDefaults.standard.set(color, forKey: "color") }
        if let i = residents.firstIndex(where: \.isMe) {
            residents[i].mobility = mobilityChoice
            residents[i].colorIndex = colorChoice
        }
        // 坐轮椅：散步检测唔靠「行路」判断（A54）
        walkDetector.seated = mobilityChoice == .wheelchair
        uploadProfile()
        syncScene()
        Haptics.select()
    }

    /// 开 / 关演示模式：示範街坊、示範纪录、演示菜单跟住变。
    func setDemoMode(_ on: Bool) {
        demoMode = on
        UserDefaults.standard.set(on, forKey: "demoMode")
        localCommunity?.demoEnabled = on
        if on && walkLog.isEmpty { seedDemoHistory() }
        // 演示模式同真机散步检测唔好同时开
        if on {
            if walkDetector.recording { finishLiveWalk() }
            walkDetector.stop()
        } else {
            // 关演示：演示散步 / 找人、时间滑杆、手选天气全部收返，用返真实时间同天文台（A33）
            if walk != nil, !walkDetector.recording {
                ticker?.cancel(); ticker = nil
                walk = nil; paceTip = nil; track = WalkTrack()
                scene.followID = nil; scene.setTrail([])
                community.publishOuting(landmarkID: nil)
            }
            if find != nil { endFind() } else { scene.resetCamera() }
            showTimeSlider = false
            hko.demoOverride = false
            setDemoHour(nil)
            applyLiveWeather()
            startWalkDetection()
        }
        populate()
        syncNotifications()
    }

    /// 重新揀我住的楼：回到首次使用的选楼一步，完成后回主界面。中途可以「唔改」退返出去。
    func beginChangeHome() {
        walk = nil; if find != nil { endFind() }; findFullScreen = false; proposal = nil; selection = nil
        pendingHome = nil
        changingHome = true
        phase = .onboarding(.locate)
        Task { await loadMap(home: nil, animated: true) }
    }

    /// 改楼途中「唔改」：用返已存嘅楼、楼层、小人，返主界面（A80）。
    func cancelChangeHome() {
        let d = UserDefaults.standard
        changingHome = false
        pendingHome = nil
        floorChoice = d.object(forKey: "floor") as? Int ?? floorChoice
        mobilityChoice = Mobility(rawValue: d.string(forKey: "mobility") ?? "") ?? mobilityChoice
        colorChoice = d.object(forKey: "color") as? Int ?? colorChoice
        highlightResidential(false)
        scene.highlightBuildings([], color: nil)
        phase = .main
        Task {
            // 定位一步嘅 loadMap 可能仲未返（人喺外面、嗰格要上网拉）：等佢完咗先装返屋企格，
            // 唔係旧结果后返嚟会将底座换成外面嗰格、屋企变默认楼
            while loadingMap { try? await Task.sleep(for: .milliseconds(200)) }
            await loadMap(home: (d.object(forKey: "homeBuilding") as? NSNumber)?.int64Value, animated: true)
            scene.resetCamera()
        }
    }

    /// 由楼层页返上一步：底座已经收窄咗，要换返选楼用嘅大底座、亮返住宅楼（A80）。
    func backToPickHome() {
        phase = .onboarding(.pickHome)
        guard let full = fullMap else { return }
        let id = pendingHome
        let v = full.pickView(near: id.flatMap { full.building(id: $0)?.centroid })
        install(v, home: nil, animated: false)
        // 同 loadMap 选楼一步一样嘅全屏镜头（按 300 m 调，再按边长缩放）
        let k = v.size / 300
        scene.setCamera(target: Vec2(x: -65 * k, y: 65 * k), distance: Float(2.85 * k), animated: false)
        highlightResidential(true)
        if let id, v.building(id: id) != nil { pickHome(id) } else { pendingHome = nil }
    }
}
