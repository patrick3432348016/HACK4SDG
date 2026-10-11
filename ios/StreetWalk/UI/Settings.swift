import SwiftUI

/// 设置（左上齿轮）：改我住的楼 / 楼层 / 小人；出门提醒总开关和接收时段；演示模式；清除记录。
/// 一页到底，不做多级菜单。
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmClear = false
    @State private var confirmMove = false
    @State private var editingNickname = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
          ScrollViewReader { proxy in
            Form {
                // 界面同播报一齐转；默认粤语。演示 / 截图可以用启动参数 -lang cmn。
                Section {
                    BigSegments(options: AppLang.allCases, selection: Binding(get: { AppLanguage.shared.current }, set: { l in
                        AppLanguage.shared.choose(l)
                        store.previewVoice(VoiceSettings.shared.active)
                    }), label: \.label)
                    .padding(.vertical, 8)
                    .accessibilityLabel(L.t("語言", "语言"))
                } header: {
                    Text(L.t("語言", "语言")).ds(.caption)
                } footer: {
                    Text(L.t("文字同播報一齊轉。", "文字和播报一起切换。")).ds(.caption)
                }

                Section {
                    Button { editingNickname = true } label: {
                        LabeledContent(L.t("網名", "网名")) {
                            Text(store.nickname.isEmpty ? L.t("未有", "还没有") : store.nickname).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityHint(L.t("改排行榜上用嘅網名", "改排行榜上用的网名"))
                    LabeledContent(L.t("住喺", "住在")) {
                        Text(store.me.blockName ?? store.map?.placeName ?? "—").foregroundStyle(.secondary)
                    }
                    Button(L.t("改我住嘅樓", "改我住的楼")) { confirmMove = true }
                    Stepper(value: Binding(get: { store.floorChoice }, set: { store.setFloor($0) }), in: 1...max(1, store.homeLevels)) {
                        LabeledContent(L.t("樓層", "楼层"), value: L.t("\(store.floorChoice) 樓", "\(store.floorChoice) 楼"))
                    }
                    DSMenuPicker(title: L.t("小人", "形象"), selection: Binding(get: { store.mobilityChoice }, set: { store.setAvatar(mobility: $0) }),
                                 options: Mobility.allCases, label: \.label)
                    DSMenuPicker(title: L.t("年紀", "年龄"), selection: Binding(get: { store.ageChoice }, set: { store.setLook(age: $0) }),
                                 options: AgeGroup.allCases, label: \.label)
                    skinRow
                    colorRow
                } header: {
                    Text("我").ds(.caption)
                } footer: {
                    if !store.demoMode {
                        Text(L.t("同區嘅人見到你嘅網名、小人同連續日數；座數同樓層只有碰過一碰嘅街坊見到。", "同区的人能看到你的网名、形象和连续天数；楼栋和楼层只有碰过一碰的邻居能看到。")).ds(.caption)
                    }
                }

                Section {
                    Toggle(L.t("出門提醒", "出门提醒"), isOn: $store.remindAll).tint(DS.accent)
                    if store.remindAll {
                        DSMenuPicker(title: L.t("由", "从"), selection: $store.remindFrom, options: Array(5..<24), label: TemplateAI.hourLabel)
                        DSMenuPicker(title: "到", selection: $store.remindTo, options: Array(6..<24), label: TemplateAI.hourLabel)
                    }
                } header: {
                    Text(L.t("街坊出門話我知", "邻居出门告诉我")).ds(.caption)
                } footer: {
                    // 由、到一樣當全日（A66）
                    Text(store.remindFrom == store.remindTo ? L.t("「由」同「到」一樣，即係全日都會通知你。每個街坊仲可以喺「街坊」頁分開開關。", "「从」和「到」一样，就是全天都会通知你。每个邻居还可以在「邻居」页单独开关。")
                         : L.t("只喺呢段時間通知你\(store.remindFrom > store.remindTo ? "（跨夜）" : "")。每個街坊仲可以喺「街坊」頁分開開關。", "只在这段时间通知你\(store.remindFrom > store.remindTo ? "（跨夜）" : "")。每个邻居还可以在「邻居」页单独开关。")).ds(.caption)
                }

                VoiceSettingsSection()

                LocationSettingsSection()

                Section {
                    Toggle("演示模式", isOn: Binding(get: { store.demoMode }, set: { store.setDemoMode($0) }))
                        .tint(DS.accent)
                        .disabled(LaunchArgs.has("-demo"))
                } footer: {
                    Text(LaunchArgs.has("-demo") ? L.t("而家用演示參數開啟，唔可以喺度關。", "现在用演示参数开启，不能在这里关。")
                         : L.t("演示模式會加入示範街坊、示範紀錄同右上角嘅演示選單。關咗之後用真伺服器：排行榜係附近真人，要兩部手機碰一碰先做到街坊。", "演示模式会加入示范邻居、示范记录和右上角的演示菜单。关掉之后用真服务器：排行榜是附近真人，要两部手机碰一碰才能成为邻居。")).ds(.caption)
                }

                Section {
                    PrivacyRows().padding(.vertical, 8)
                    Button(L.t("讀出嚟", "读出来")) { store.sayAgain(PrivacyRows.spoken) }
                } header: {
                    Text(L.t("私隱：邊個見到乜", "隐私：谁能看到什么")).ds(.caption)
                }

                Section {
                    Button(L.t("清除我嘅紀錄", "清除我的记录"), role: .destructive) { confirmClear = true }
                } footer: {
                    Text(store.demoMode ? L.t("演示模式：街坊關係、約會、反映、改過嘅地標名、散步紀錄都只存喺你部手機。地圖資料 © OpenStreetMap；天氣：香港天文台。", "演示模式：邻居关系、约会、反馈、改过的地标名、散步记录都只存在你的手机里。地图数据 © OpenStreetMap；天气：香港天文台。")
                         : L.t("行過嘅路線、屋企位置只存喺你部手機。伺服器（新加坡）只有網名、小人、屋企附近嘅格子、連續日數、每日分鐘同落腳地標、街坊關係同約會；清除會一齊刪走。地圖資料 © OpenStreetMap；天氣：香港天文台。", "走过的路线、家的位置只存在你的手机里。服务器（新加坡）只有网名、形象、家附近的格子、连续天数、每日分钟和落脚地标、邻居关系和约会；清除会一起删掉。地图数据 © OpenStreetMap；天气：香港天文台。")).ds(.caption)
                }
            }
            .ds(.body)
            .tint(DS.accent)
            .onAppear {
                // 截图用：-voiceSettings voiceList 打开就捲去「聲音」嗰段（voiceGuideEnd = 指引卡底）
                guard LaunchArgs.has("-voiceSettings") else { return }
                let id = LaunchArgs.value("-voiceSettings").flatMap { $0.hasPrefix("voice") ? $0 : nil } ?? "voice"
                Task { @MainActor in
                    for _ in 0..<2 {   // 第一次未必捲到（列表仲未排好），隔阵再捲一次
                        try? await Task.sleep(for: .seconds(0.8))
                        if id.hasSuffix("End") { proxy.scrollTo(String(id.dropLast(3)), anchor: .bottom) } else { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
            // 由 iPhone 设定下载完声音返嚟：下载指引变咗「裝好咗」（矮咗），捲返去声音列表，见到新声音已经剔咗
            .onChange(of: VoiceSettings.shared.upgradedAt) { _, at in
                guard at != nil else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.3))
                    proxy.scrollTo("voiceList", anchor: .top)
                }
            }
          }
            .navigationTitle(L.t("設定", "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 标题和「完成」都用设计规范字号（系统默认 17pt 太小）。
                ToolbarItem(placement: .principal) { Text(L.t("設定", "设置")).ds(.bodyBold).accessibilityAddTraits(.isHeader) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { store.showSettings = false } label: { Text("完成").ds(.bodyBold) }.foregroundStyle(DS.accent)
                }
            }
            .sheet(isPresented: $editingNickname) {
                NicknameSheet().environment(store)
            }
            .confirmationDialog(L.t("清除全部紀錄？", "清除全部记录？"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清除", role: .destructive) { store.clearAllData(); store.populate() }
                Button(L.t("唔清", "不清除"), role: .cancel) {}
            } message: {
                Text(store.demoMode ? L.t("街坊、約會、反映、散步紀錄同過夜位置都會刪走，冇得還原。", "邻居、约会、反馈、散步记录和过夜位置都会删掉，无法还原。")
                     : L.t("街坊、約會、反映、散步紀錄同過夜位置都會刪走（連伺服器上嘅），冇得還原。", "邻居、约会、反馈、散步记录和过夜位置都会删掉（包括服务器上的），无法还原。"))
            }
            .confirmationDialog(L.t("改我住嘅樓？", "改我住的楼？"), isPresented: $confirmMove, titleVisibility: .visible) {
                Button(L.t("揀過座樓", "重新选楼")) { store.showSettings = false; store.beginChangeHome() }
                Button(L.t("唔改", "不改"), role: .cancel) {}
            } message: {
                Text(L.t("會重新揀樓。之前嘅約會地點同反映位置會清走，街坊同散步紀錄保留。", "会重新选楼。之前的约会地点和反馈位置会清掉，邻居和散步记录保留。"))
            }
        }
    }

    /// 肤色（A50）：同颜色一行一样，圆点 + 剔号，读屏读肤色名。
    private var skinRow: some View {
        HStack(spacing: 0) {
            ForEach(0..<Palette.skins.count, id: \.self) { i in
                let on = store.skinChoice == i
                Button { store.setLook(skin: i); Haptics.select() } label: {
                    Circle()
                        .fill(Palette.skin(i))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                        .frame(width: 30, height: 30)
                        .overlay { if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.primary) } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Palette.skinName(i))
                .accessibilityAddTraits(on ? .isSelected : [])
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
                .accessibilityLabel(Palette.name(i))
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
        installCommunity()      // 演示 → 示範街坊；真 → Supabase（AppStore+Backend）
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
        lookBeforeChange = (skinChoice, ageChoice)
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
        if let l = lookBeforeChange { skinChoice = l.skin; ageChoice = l.age }   // 肤色、年纪一改就存，要还原
        lookBeforeChange = nil
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
