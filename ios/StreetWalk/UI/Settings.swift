import SwiftUI

/// 设置（左上齿轮）。常用嘅放上面：字體大小、聲音、語言、我嘅資料、出門提醒；
/// 其余（语音服务器、揀把声、下载声音指引、定位、演示模式、私隱、清除纪录）收喺最底「進階」，平时收埋（UX 评审 17）。
/// 一页到底，不做多级菜单。
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
                // 字體大小：即时生效、存低（TextSizeSetting），覆盖 iOS 文字大小
                Section {
                    TextSizePicker().padding(.vertical, 8)
                } header: {
                    Text(L.t("字體大小", "字体大小")).ds(.caption)
                } footer: {
                    Text(L.t("撳一下即刻轉，成個 App 一齊變。", "点一下马上生效，整个 App 一起变。")).ds(.caption)
                }
                .id("textSize")

                VoiceSettingsSection()

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
                    DSMenuPicker(title: L.t("小人", "形象"), selection: Binding(get: { store.mobilityChoice }, set: { store.setAvatar(mobility: $0) }),
                                 options: Mobility.allCases, label: \.label)
                    DSMenuPicker(title: L.t("年紀", "年龄"), selection: Binding(get: { store.ageChoice }, set: { store.setLook(age: $0) }),
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
                    // 由、到一樣當全日（A66）
                    Text(store.remindFrom == store.remindTo ? L.t("「由」同「到」一樣，即係全日都會通知你。每個街坊仲可以喺「街坊」頁分開開關。", "「从」和「到」一样，就是全天都会通知你。每个邻居还可以在「邻居」页单独开关。")
                         : L.t("只喺呢段時間通知你\(store.remindFrom > store.remindTo ? "（跨夜）" : "")。每個街坊仲可以喺「街坊」頁分開開關。", "只在这段时间通知你\(store.remindFrom > store.remindTo ? "（跨夜）" : "")。每个邻居还可以在「邻居」页单独开关。")).ds(.caption)
                }

                // 進階：开发同排查用嘅嘢，平时收埋（长者见到 IP 地址会惊）
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
                        Text(L.t("語音伺服器、揀把聲、下載聲音、定位、演示模式、私隱、清除紀錄", "语音服务器、选声音、下载声音、定位、演示模式、隐私、清除记录")).ds(.caption)
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
                // 截图用：-voiceSettings voiceList 打开就捲去「聲音」嗰段（voiceGuideEnd = 指引卡底）；揀把声 / 指引喺「進階」入面，先打开
                guard LaunchArgs.has("-voiceSettings") else { return }
                let id = LaunchArgs.value("-voiceSettings").flatMap { $0.hasPrefix("voice") ? $0 : nil } ?? "voice"
                if id != "voice" { showAdvanced = true }
                Task { @MainActor in
                    for _ in 0..<2 {   // 第一次未必捲到（列表仲未排好），隔阵再捲一次
                        try? await Task.sleep(for: .seconds(0.8))
                        if id.hasSuffix("End") { proxy.scrollTo(String(id.dropLast(3)), anchor: .bottom) } else { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
            // 由 iPhone 设定下载完返嚟：下载指引变咗「裝好咗」（矮咗），捲返去声音列表，见到新声音已经剔咗
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
            // 实色导航栏：往下拉时内容唔会同「設定」标题叠埋（UX 评审 29）
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                // 标题和「完成」都用设计规范字号（系统默认 17pt 太小）；导航栏高度固定，特大字都封顶喺 xxLarge。
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

    /// 「進階」打开后：语音服务器 / 揀把声 / 下载指引、出门自动记录（定位纪录）、演示模式、私隱、清除纪录。
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
            PrivacyRows().padding(.vertical, 8)
            Button(L.t("讀出嚟", "读出来")) { store.sayAgain(PrivacyRows.spoken) }.frame(minHeight: 56)
        } header: {
            Text(L.t("私隱：邊個見到乜", "隐私：谁能看到什么")).ds(.caption)
        }

        Section {
            Button(L.t("清除我嘅紀錄", "清除我的记录"), role: .destructive) { confirmClear = true }.frame(minHeight: 56)
        } footer: {
            Text(store.demoMode ? L.t("演示模式：街坊關係、約會、反映、改過嘅地標名、散步紀錄都只存喺你部手機。地圖資料 © OpenStreetMap；天氣：香港天文台。", "演示模式：邻居关系、约会、反馈、改过的地标名、散步记录都只存在你的手机里。地图数据 © OpenStreetMap；天气：香港天文台。")
                 : L.t("行過嘅路線、屋企位置只存喺你部手機。伺服器（新加坡）只有網名、小人、屋企附近嘅格子、連續日數、每日分鐘同落腳地標、街坊關係同約會；清除會一齊刪走。地圖資料 © OpenStreetMap；天氣：香港天文台。", "走过的路线、家的位置只存在你的手机里。服务器（新加坡）只有网名、形象、家附近的格子、连续天数、每日分钟和落脚地标、邻居关系和约会；清除会一起删掉。地图数据 © OpenStreetMap；天气：香港天文台。")).ds(.caption)
        }
    }

    /// 楼层：两粒 56pt 大掣（系统 Stepper 嘅 −/+ 得 32pt 高，长者撳唔中）。字大排唔落一行就将掣放落第二行。
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
        .buttonStyle(.borderless)   // 表单一行有两粒掣：唔用 borderless 会撳一下两粒一齐郁
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .disabled(!enabled)
        .accessibilityLabel(label)
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
