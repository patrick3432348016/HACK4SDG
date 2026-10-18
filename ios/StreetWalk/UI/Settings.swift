import SwiftUI

/// Settings orders frequent controls first: text size, sound, language, profile and outing alerts.
/// UX 17: collapse server, voice selection/download, location, demo and data controls under Advanced.
/// Use one scrolling page rather than nested menus.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmClear = false
    @State private var confirmMove = false
    @State private var editingNickname = false
    @State private var showAdvanced = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
          ScrollViewReader { proxy in
            Form {
                // TextSizeSetting applies and persists immediately, overriding system text size.
                Section {
                    TextSizePicker().padding(.vertical, 8)
                } header: {
                    Text(L.t("字體大小", "字体大小")).ds(.caption)
                } footer: {
                    Text(L.t("撳一下即刻轉，成個 App 一齊變。", "点一下马上生效，整个 App 一起变。")).ds(.caption)
                }
                .id("textSize")

                VoiceSettingsSection()

                // Switch UI and speech together; default Cantonese, with -lang cmn for demo/screenshots.
                Section {
                    BigSegments(options: AppLang.allCases, selection: Binding(get: { AppLanguage.shared.current }, set: { l in
                        AppLanguage.shared.choose(l)
                        store.previewVoice(VoiceSettings.shared.active, current: true)
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
                        .frame(minHeight: 56)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityHint(L.t("改排行榜上用嘅網名", "改排行榜上用的网名"))
                    LabeledContent(L.t("住喺", "住在")) {
                        Text(store.me.blockName ?? store.map?.placeName ?? "—").foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 56)
                    Button { confirmMove = true } label: { Text(L.t("改我住嘅樓", "改我住的楼")).frame(minHeight: 56) }
                    floorRow
                    DSMenuPicker(title: L.t("出行方式", "出行方式"), selection: Binding(get: { store.mobilityChoice }, set: { store.setAvatar(mobility: $0) }),
                                 options: Mobility.allCases, label: \.label)
                    DSMenuPicker(title: L.t("年齡層", "年龄层"), selection: Binding(get: { store.ageChoice }, set: { store.setLook(age: $0) }),
                                 options: AgeGroup.allCases, label: \.label)
                    skinRow
                    colorRow
                } header: {
                    Text(L.t("我嘅資料", "我的资料")).ds(.caption)
                } footer: {
                    if !store.demoMode {
                        Text(L.t("同區嘅人見到你嘅網名、小人同連續日數；座數同樓層只有碰過一碰嘅街坊見到。", "同区的人能看到你的网名、形象和连续天数；楼栋和楼层只有碰过一碰的邻居能看到。")).ds(.caption)
                    }
                }

                Section {
                    Toggle(L.t("出門提醒", "出门提醒"), isOn: $store.remindAll).tint(DS.accent).frame(minHeight: 56)
                    if store.remindAll {
                        DSMenuPicker(title: L.t("由", "从"), selection: $store.remindFrom, options: Array(5..<24), label: TemplateAI.hourLabel)
                        DSMenuPicker(title: "到", selection: $store.remindTo, options: Array(6..<24), label: TemplateAI.hourLabel)
                    }
                } header: {
                    Text(L.t("街坊出門話我知", "邻居出门告诉我")).ds(.caption)
                } footer: {
                    // Equal start and end mean all day (A66).
                    Text(store.remindFrom == store.remindTo ? L.t("「由」同「到」一樣，即係全日都會通知你。每個街坊仲可以喺「街坊」頁分開開關。", "「从」和「到」一样，就是全天都会通知你。每个邻居还可以在「邻居」页单独开关。")
                         : L.t("只喺呢段時間通知你\(store.remindFrom > store.remindTo ? "（跨夜）" : "")。每個街坊仲可以喺「街坊」頁分開開關。", "只在这段时间通知你\(store.remindFrom > store.remindTo ? "（跨夜）" : "")。每个邻居还可以在「邻居」页单独开关。")).ds(.caption)
                }

                // Place privacy and help/feedback above Advanced so they remain visible without expansion.
                Section {
                    NavigationLink { HelpView() } label: {
                        Label(L.t("幫助同意見", "帮助与反馈"), systemImage: "questionmark.circle").frame(minHeight: 56)
                    }
                    NavigationLink { PrivacyPolicyView() } label: {
                        Label(L.t("私隱政策", "隐私政策"), systemImage: "hand.raised").frame(minHeight: 56)
                    }
                }

                // Hide developer and troubleshooting controls under Advanced to avoid confusing ordinary users with server addresses.
                Section {
                    Button {
                        withAnimation(DS.motion(DS.snappy)) { showAdvanced.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L.t("進階", "高级")).ds(.bodyBold)
                                Text(L.t("畀幫手設定嘅人用", "给帮忙设置的人用")).ds(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel(L.t("進階，畀幫手設定嘅人用", "高级，给帮忙设置的人用"))
                    .accessibilityValue(showAdvanced ? L.t("打開咗", "已展开") : L.t("收埋咗", "已收起"))
                } footer: {
                    if !showAdvanced {
                        Text(L.t("語音伺服器、揀把聲、下載聲音、定位、演示模式、清除紀錄", "语音服务器、选声音、下载声音、定位、演示模式、清除记录")).ds(.caption)
                    }
                }
                .id("advanced")

                if showAdvanced {
                    advancedSections
                }
            }
            .ds(.body)
            .tint(DS.accent)
            .onAppear {
                // -voiceSettings voiceList scrolls to Sound; voiceGuideEnd targets the guide bottom. Expand Advanced first.
                guard LaunchArgs.has("-voiceSettings") else { return }
                let id = LaunchArgs.value("-voiceSettings").flatMap { $0.hasPrefix("voice") ? $0 : nil } ?? "voice"
                if id != "voice" { showAdvanced = true }
                Task { @MainActor in
                    for _ in 0..<2 {   // Retry scrolling after layout because the first attempt may run before rows exist.
                        try? await Task.sleep(for: .seconds(0.8))
                        if id.hasSuffix("End") { proxy.scrollTo(String(id.dropLast(3)), anchor: .bottom) } else { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
            // After downloading a system voice, the guide shrinks to installed state; scroll back to show the selected new voice.
            .onChange(of: VoiceSettings.shared.upgradedAt) { _, at in
                guard at != nil else { return }
                showAdvanced = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.3))
                    proxy.scrollTo("voiceList", anchor: .top)
                }
            }
          }
            .navigationTitle(L.t("設定", "设置"))
            .navigationBarTitleDisplayMode(.inline)
            // UX 29: opaque navigation prevents scrolling content from overlapping the Settings title.
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                // Use design-system title and Done sizes instead of 17 pt defaults; cap navigation text at xxLarge for fixed bar height.
                ToolbarItem(placement: .principal) {
                    Text(L.t("設定", "设置")).ds(.bodyBold).accessibilityAddTraits(.isHeader)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { store.showSettings = false } label: { Text("完成").ds(.bodyBold).dynamicTypeSize(...DynamicTypeSize.xxLarge) }.foregroundStyle(DS.accent)
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

    /// Advanced contains server/voice/download, automatic recording/location records, demo, privacy and deletion controls.
    @ViewBuilder private var advancedSections: some View {
        VoiceAdvancedSections()

        LocationSettingsSection()

        Section {
            Toggle("演示模式", isOn: Binding(get: { store.demoMode }, set: { store.setDemoMode($0) }))
                .tint(DS.accent)
                .frame(minHeight: 56)
                .disabled(LaunchArgs.has("-demo"))
        } footer: {
            Text(LaunchArgs.has("-demo") ? L.t("而家用演示參數開啟，唔可以喺度關。", "现在用演示参数开启，不能在这里关。")
                 : L.t("演示模式會加入示範街坊、示範紀錄同右上角嘅演示選單。關咗之後用真伺服器：排行榜係附近真人，要兩部手機碰一碰先做到街坊。", "演示模式会加入示范邻居、示范记录和右上角的演示菜单。关掉之后用真服务器：排行榜是附近真人，要两部手机碰一碰才能成为邻居。")).ds(.caption)
        }

        Section {
            Button(L.t("清除我嘅紀錄", "清除我的记录"), role: .destructive) { confirmClear = true }.frame(minHeight: 56)
        } footer: {
            Text(store.demoMode ? L.t("演示模式：街坊關係、約會、反映、改過嘅地標名、散步紀錄都只存喺你部手機。地圖資料 © OpenStreetMap；天氣：香港天文台。", "演示模式：邻居关系、约会、反馈、改过的地标名、散步记录都只存在你的手机里。地图数据 © OpenStreetMap；天气：香港天文台。")
                 : L.t("行過嘅路線、屋企位置只存喺你部手機。伺服器（新加坡）只有網名、小人、屋企附近嘅格子、連續日數、每日分鐘同落腳地標、街坊關係同約會；清除會一齊刪走。地圖資料 © OpenStreetMap；天氣：香港天文台。", "走过的路线、家的位置只存在你的手机里。服务器（新加坡）只有网名、形象、家附近的格子、连续天数、每日分钟和落脚地标、邻居关系和约会；清除会一起删掉。地图数据 © OpenStreetMap；天气：香港天文台。")).ds(.caption)
        }
    }

    /// Use 56 pt floor buttons instead of the 32 pt system Stepper; wrap controls below the label at large text sizes.
    private var floorRow: some View {
        let f = store.floorChoice
        let top = max(1, store.homeLevels)
        let value = L.t("\(f) 樓", "\(f) 楼")
        let buttons = HStack(spacing: 12) {
            stepButton("minus", L.t("低一層", "低一层"), enabled: f > 1) { store.setFloor(f - 1) }
            stepButton("plus", L.t("高一層", "高一层"), enabled: f < top) { store.setFloor(f + 1) }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(L.t("樓層", "楼层")).lineLimit(1)
                Spacer(minLength: 8)
                Text(value).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                buttons
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.t("樓層", "楼层"))
                    Spacer(minLength: 8)
                    Text(value).monospacedDigit().foregroundStyle(.secondary)
                }
                buttons
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("樓層", "楼层"))
        .accessibilityValue(value)
        .accessibilityAdjustableAction { d in
            switch d {
            case .increment: if f < top { store.setFloor(f + 1) }
            case .decrement: if f > 1 { store.setFloor(f - 1) }
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { action(); Haptics.select() } label: {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 64, height: 56)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)   // Use borderless buttons in a Form row so tapping one does not trigger both.
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// A50: skin-tone dots include a checkmark and accessible tone names.
    private var skinRow: some View {
        HStack(spacing: 0) {
            ForEach(0..<Palette.skins.count, id: \.self) { i in
                let on = store.skinChoice == i
                Button { store.setLook(skin: i); Haptics.select() } label: {
                    Circle()
                        .fill(Palette.skin(i))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                        .frame(width: 34, height: 34)
                        .overlay { if on { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.primary) } }
                        .frame(maxWidth: .infinity, minHeight: 56)
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
                        .frame(width: 34, height: 34)
                        .overlay { if on { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white) } }
                        .frame(maxWidth: .infinity, minHeight: 56)
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
    /// Number of floors in my building, bounding the floor picker.
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
        // A54: wheelchair walk detection does not depend on a walking classification.
        walkDetector.seated = mobilityChoice == .wheelchair
        uploadProfile()
        syncScene()
        Haptics.select()
    }

    /// Toggling demo updates sample neighbors, records and menu.
    func setDemoMode(_ on: Bool) {
        demoMode = on
        UserDefaults.standard.set(on, forKey: "demoMode")
        installCommunity()      // Demo uses sample neighbors; normal mode uses Supabase via AppStore+Backend.
        if on && walkLog.isEmpty { seedDemoHistory() }
        // Do not run demo mode and real-device walk detection together.
        if on {
            if walkDetector.recording { finishLiveWalk() }
            walkDetector.stop()
        } else {
            // A33: leaving demo ends simulated walking/finding, clears time/weather overrides and restores actual time and HKO data.
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

    /// Changing home re-enters building selection, returns to main on completion and supports cancellation midway.
    func beginChangeHome() {
        walk = nil; if find != nil { endFind() }; findFullScreen = false; proposal = nil; selection = nil
        pendingHome = nil
        lookBeforeChange = (skinChoice, ageChoice)
        changingHome = true
        phase = .onboarding(.locate)
        Task { await loadMap(home: nil, animated: true) }
    }

    /// A80: cancelling restores saved building, floor and avatar before returning to main.
    func cancelChangeHome() {
        let d = UserDefaults.standard
        changingHome = false
        pendingHome = nil
        floorChoice = d.object(forKey: "floor") as? Int ?? floorChoice
        mobilityChoice = Mobility(rawValue: d.string(forKey: "mobility") ?? "") ?? mobilityChoice
        colorChoice = d.object(forKey: "color") as? Int ?? colorChoice
        if let l = lookBeforeChange { skinChoice = l.skin; ageChoice = l.age }   // Restore skin tone and age because edits save immediately.
        lookBeforeChange = nil
        highlightResidential(false)
        scene.highlightBuildings([], color: nil)
        phase = .main
        Task {
            // A location-step loadMap may still be fetching an outside tile; wait before restoring the home tile,
            // otherwise a late result could replace the base and reset home to a default building.
            while loadingMap { try? await Task.sleep(for: .milliseconds(200)) }
            await loadMap(home: (d.object(forKey: "homeBuilding") as? NSNumber)?.int64Value, animated: true)
            scene.resetCamera()
        }
    }

    /// A80: stepping back from floor selection restores the larger selection base and residential highlights.
    func backToPickHome() {
        phase = .onboarding(.pickHome)
        guard let full = fullMap else { return }
        let id = pendingHome
        let v = full.pickView(near: id.flatMap { full.building(id: $0)?.centroid })
        install(v, home: nil, animated: false)
        // Use loadMap's full-screen selection camera, scaled from a 300 m base.
        let k = v.size / 300
        scene.setCamera(target: Vec2(x: -65 * k, y: 65 * k), distance: Float(2.85 * k), animated: false)
        highlightResidential(true)
        if let id, v.building(id: id) != nil { pickHome(id) } else { pendingHome = nil }
    }
}
