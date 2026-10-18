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
    /// 截图自检：-voiceSettings x -uiPreview settingsProfile(End) / help / privacyPolicy / privacyScrolled / feedback / feedbackFailed 直接推入去嗰页。
    @State private var previewPage: String?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
          ScrollViewReader { proxy in
            Form {
                // 字體大小：即时生效、存低（TextSizeSetting），覆盖 iOS 文字大小
                Section {
                    TextSizePicker().padding(.vertical, 8)
                } header: {
                    Text(L.t("字體大小", "字体大小", "Text size")).ds(.caption)
                } footer: {
                    Text(L.t("撳一下即刻轉，成個 App 一齊變。", "点一下马上生效，整个 App 一起变。", "Tap once to change. The whole app changes together.")).ds(.caption)
                }
                .id("textSize")

                VoiceSettingsSection()

                // 界面同播报一齐转；默认粤语。演示 / 截图可以用启动参数 -lang cmn。
                Section {
                    // 三种语言：一行排唔落（「普通话（简体）」太长）就上下排
                    LanguageChooser { store.languageChanged() }
                    .padding(.vertical, 8)
                    .accessibilityLabel(L.t("語言", "语言", "Language"))
                } header: {
                    Text(L.t("語言", "语言", "Language")).ds(.caption)
                } footer: {
                    Text(L.t("文字同播報一齊轉。", "文字和播报一起切换。", "Words and voice change together.")).ds(.caption)
                }

                // 每项下面一行小字：讲清楚系乜、喺边度见到、边个见到（测试反馈 K-1）
                Section {
                    Button { editingNickname = true } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            LabeledContent(L.t("網名", "网名", "Nickname")) {
                                Text(store.nickname.isEmpty ? L.t("未有", "还没有", "Not set") : store.nickname).foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 44)
                            rowNote(L.t("排行榜同街坊見到你叫呢個名，唔使用真名。", "排行榜上和邻居看到的就是这个名字，不用写真名。", "Neighbours and the leaderboard see this name. No need for your real name."))
                        }
                        .padding(.vertical, 6)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityHint(L.t("改排行榜上用嘅網名", "改排行榜上用的网名", "Change your leaderboard nickname"))
                    VStack(alignment: .leading, spacing: 2) {
                        LabeledContent(L.t("住喺", "住在", "I live in")) {
                            Text(store.homeBlockShown ?? store.map?.shownPlaceName ?? "—").foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                        rowNote(L.t("「今日」頁幅地圖以呢座樓做中心。只有用碰一碰加咗嘅街坊先見到你住邊座。", "「今天」页的地图以这栋楼为中心。只有用碰一碰加过的邻居，才看得到你住哪栋。", "The map on the Today tab is centred on this block. Only neighbours added by tapping phones can see your block."))
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    Button { confirmMove = true } label: { Text(L.t("改我住嘅樓", "改我住的楼", "Change my block")).frame(minHeight: 56) }
                    VStack(alignment: .leading, spacing: 2) {
                        floorRow
                        rowNote(L.t("只有用碰一碰加咗嘅街坊先見到你住幾樓。", "只有用碰一碰加过的邻居，才看得到你住几楼。", "Only neighbours added by tapping phones can see your floor."))
                    }
                    .padding(.bottom, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        DSMenuPicker(title: L.t("出行方式", "出行方式", "How you get around"), selection: Binding(get: { store.mobilityChoice }, set: { store.setAvatar(mobility: $0) }),
                                     options: Mobility.allCases, label: \.label)
                        rowNote(L.t("地圖上代表你嘅小人係行路、拎拐杖、坐輪椅定推BB車。揀「輪椅」，坐輪椅出門都會自動記錄散步。", "地图上代表你的卡通小人是走路、拄拐杖、坐轮椅还是推婴儿车。选「轮椅」后，坐轮椅出门也能自动记录散步。", "Your figure on the map walks, uses a stick, a wheelchair or pushes a pram. Choose \"Wheelchair\" and wheelchair outings are recorded too."))
                    }
                    .padding(.bottom, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        DSMenuPicker(title: L.t("年齡層", "年龄层", "Age group"), selection: Binding(get: { store.ageChoice }, set: { store.setLook(age: $0) }),
                                     options: AgeGroup.allCases, label: \.label)
                        rowNote(L.t("只係改小人個樣：「長者」白頭髮，「後生」細粒啲。", "只改变卡通小人的样子：「长者」是白头发，「年轻人」个子小一点。", "Only changes how your figure looks: \"Senior\" has white hair, \"Young\" is smaller."))
                    }
                    .padding(.bottom, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        rowTitle(L.t("膚色", "肤色", "Skin colour"))
                        rowNote(L.t("小人嘅膚色。", "卡通小人的皮肤颜色。", "Your figure's skin colour."))
                        skinRow
                    }
                    .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 2) {
                        rowTitle(L.t("衫嘅顏色", "衣服颜色", "Shirt colour"))
                        rowNote(L.t("地圖上你個小人著呢個顏色嘅衫，街坊一睇就認得係你。", "地图上你的卡通小人穿这个颜色的衣服，邻居一看就认出是你。", "Your figure wears this colour on the map, so neighbours know it's you."))
                        colorRow
                    }
                    .padding(.top, 8)
                    .id("profileColor")
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(L.t("俾街坊睇到我住邊座", "让邻居看到我住哪栋", "Let neighbours see my block"), isOn: $store.shareHome).tint(DS.accent)
                        rowNote(L.t("熄咗，街坊只見到你嘅網名，唔知你住邊座、幾樓。", "关掉后，邻居只看到你的网名，不知道你住哪栋、几楼。", "When off, neighbours only see your nickname, not your block or floor."))
                    }
                    .frame(minHeight: 56)
                } header: {
                    Text(L.t("我嘅資料", "我的资料", "About me")).ds(.caption)
                } footer: {
                    if !store.demoMode {
                        Text(L.t("附近嘅人見到你嘅網名、小人同連續日數；住邊座、幾樓，只有用碰一碰加咗嘅街坊先見到。", "附近的人能看到你的网名、卡通小人和连续天数；住哪栋、几楼，只有用碰一碰加过的邻居才看得到。", "People nearby see your nickname, figure and streak. Your block and floor are only for neighbours added by tapping phones.")).ds(.caption)
                    }
                }
                .id("profile")

                Section {
                    Toggle(L.t("出門提醒", "出门提醒", "Out-and-about alerts"), isOn: $store.remindAll).tint(DS.accent).frame(minHeight: 56)
                    if store.remindAll {
                        DSMenuPicker(title: L.t("由", "从", "From"), selection: $store.remindFrom, options: Array(5..<24), label: TemplateAI.hourLabel)
                        DSMenuPicker(title: L.t("到", "到", "To"), selection: $store.remindTo, options: Array(6..<24), label: TemplateAI.hourLabel)
                    }
                } header: {
                    Text(L.t("街坊出門話我知", "邻居出门告诉我", "Tell me when neighbours go out")).ds(.caption)
                } footer: {
                    // 由、到一樣當全日（A66）
                    Text(store.remindFrom == store.remindTo ? L.t("「由」同「到」一樣，即係全日都會通知你。每個街坊仲可以喺「街坊」頁分開開關。", "「从」和「到」一样，就是全天都会通知你。每个邻居还可以在「邻居」页单独开关。", "\"From\" and \"To\" are the same, so alerts come all day. You can also turn each neighbour on or off in the Neighbours tab.")
                         : L.t("只喺呢段時間通知你\(store.remindFrom > store.remindTo ? "（跨夜）" : "")。每個街坊仲可以喺「街坊」頁分開開關。", "只在这段时间通知你\(store.remindFrom > store.remindTo ? "（跨夜）" : "")。每个邻居还可以在「邻居」页单独开关。", "Alerts only during these hours\(store.remindFrom > store.remindTo ? " (overnight)" : ""). You can also turn each neighbour on or off in the Neighbours tab.")).ds(.caption)
                }

                // 测试反馈：设定要有隐私政策同帮助反馈（放喺「進階」上面，唔使展开就见到）
                Section {
                    NavigationLink { HelpView() } label: {
                        Label(L.t("幫助同意見", "帮助与反馈", "Help & feedback"), systemImage: "questionmark.circle").frame(minHeight: 56)
                    }
                    NavigationLink { PrivacyPolicyView() } label: {
                        Label(L.t("私隱政策", "隐私政策", "Privacy policy"), systemImage: "hand.raised").frame(minHeight: 56)
                    }
                    // 10-18 组员：F10 月报以前只喺演示菜单，真用户模式睇唔到、测唔到
                    NavigationLink { ReportView() } label: {
                        Label(L.t("社區月報（俾社工睇）", "社区月报（给社工看）", "Community monthly report"), systemImage: "doc.text").frame(minHeight: 56)
                    }
                }

                // 進階：开发同排查用嘅嘢，平时收埋（长者见到 IP 地址会惊）
                Section {
                    Button {
                        withAnimation(DS.motion(DS.snappy)) { showAdvanced.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L.t("進階", "高级", "Advanced")).ds(.bodyBold)
                                Text(L.t("畀幫手設定嘅人用", "给帮忙设置的人用", "For the person helping you set up")).ds(.caption).foregroundStyle(.secondary)
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
                    .accessibilityLabel(L.t("進階，畀幫手設定嘅人用", "高级，给帮忙设置的人用", "Advanced, for the person helping you set up"))
                    .accessibilityValue(showAdvanced ? L.t("打開咗", "已展开", "Open") : L.t("收埋咗", "已收起", "Closed"))
                } footer: {
                    if !showAdvanced {
                        Text(L.t("語音伺服器、揀把聲、下載聲音、定位、演示模式、清除紀錄", "语音服务器、选声音、下载声音、定位、演示模式、清除记录", "Voice server, voices, downloads, location, demo mode, clear records")).ds(.caption)
                    }
                }
                .id("advanced")

                if showAdvanced {
                    advancedSections
                }
            }
            .ds(.body)
            .tint(DS.accent)
            .navigationDestination(item: $previewPage) { p in
                switch p {
                case "help": HelpView()
                case "feedback", "feedbackFailed": FeedbackView()
                default: PrivacyPolicyView()
                }
            }
            .onAppear {
                // 截图用：-uiPreview settingsProfile 捲去「我嘅資料」；其余推入「幫助」「私隱政策」「提意見」
                if let p = LaunchArgs.value("-uiPreview"), ["settingsProfile", "settingsProfileEnd", "help", "privacyPolicy", "privacyScrolled", "feedback", "feedbackFailed"].contains(p) {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.8))
                        if p.hasPrefix("settingsProfile") { proxy.scrollTo(p.hasSuffix("End") ? "profileColor" : "profile", anchor: p.hasSuffix("End") ? .bottom : .top) } else { previewPage = p }
                    }
                    return
                }
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
            .navigationTitle(L.t("設定", "设置", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            // 实色导航栏：往下拉时内容唔会同「設定」标题叠埋（UX 评审 29）
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                // 标题和「完成」都用设计规范字号（系统默认 17pt 太小）；导航栏高度固定，特大字都封顶喺 xxLarge。
                ToolbarItem(placement: .principal) {
                    Text(L.t("設定", "设置", "Settings")).ds(.bodyBold).accessibilityAddTraits(.isHeader)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { store.showSettings = false } label: { Text(L.t("完成", "完成", "Done")).ds(.bodyBold).dynamicTypeSize(...DynamicTypeSize.xxLarge) }.foregroundStyle(DS.accent)
                }
            }
            .sheet(isPresented: $editingNickname) {
                NicknameSheet().environment(store)
            }
            .confirmationDialog(L.t("清除全部紀錄？", "清除全部记录？", "Clear all records?"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(L.t("清除", "清除", "Clear"), role: .destructive) { store.clearAllData(); store.populate() }
                Button(L.t("唔清", "不清除", "Keep"), role: .cancel) {}
            } message: {
                Text(store.demoMode ? L.t("街坊、約會、反映、散步紀錄同過夜位置都會刪走，冇得還原。", "邻居、约会、反馈、散步记录和过夜位置都会删掉，无法还原。", "Neighbours, walk plans, reports, walk records and overnight places will be deleted. This cannot be undone.")
                     : L.t("街坊、約會、反映、散步紀錄同過夜位置都會刪走（連伺服器上嘅），冇得還原。", "邻居、约会、反馈、散步记录和过夜位置都会删掉（包括服务器上的），无法还原。", "Neighbours, walk plans, reports, walk records and overnight places will be deleted (on the server too). This cannot be undone."))
            }
            .confirmationDialog(L.t("改我住嘅樓？", "改我住的楼？", "Change my block?"), isPresented: $confirmMove, titleVisibility: .visible) {
                Button(L.t("揀過座樓", "重新选楼", "Choose again")) { store.showSettings = false; store.beginChangeHome() }
                Button(L.t("唔改", "不改", "Don't change"), role: .cancel) {}
            } message: {
                Text(L.t("會重新揀樓。之前嘅約會地點同反映位置會清走，街坊同散步紀錄保留。", "会重新选楼。之前的约会地点和反馈位置会清掉，邻居和散步记录保留。", "You will choose your block again. Old walk plan places and report spots will be cleared. Neighbours and walk records stay."))
            }
        }
    }

    /// 「進階」打开后：语音服务器 / 揀把声 / 下载指引、出门自动记录（定位纪录）、演示模式、私隱、清除纪录。
    @ViewBuilder private var advancedSections: some View {
        VoiceAdvancedSections()

        LocationSettingsSection()

        Section {
            Toggle(L.t("演示模式", "演示模式", "Demo mode"), isOn: Binding(get: { store.demoMode }, set: { store.setDemoMode($0) }))
                .tint(DS.accent)
                .frame(minHeight: 56)
                .disabled(LaunchArgs.has("-demo"))
        } footer: {
            Text(LaunchArgs.has("-demo") ? L.t("而家用演示參數開啟，唔可以喺度關。", "现在用演示参数开启，不能在这里关。", "Turned on by a demo setting. Cannot turn off here.")
                 : L.t("演示模式會加入示範街坊、示範紀錄同右上角嘅演示選單。關咗之後用真伺服器：排行榜係附近真人，要兩部手機碰一碰先做到街坊。", "演示模式会加入示范邻居、示范记录和右上角的演示菜单。关掉之后用真服务器：排行榜是附近真人，要两部手机碰一碰才能成为邻居。", "Demo mode adds sample neighbours, sample records and a demo menu at the top right. Turn it off to use the real server: the leaderboard shows real people nearby, and you tap phones to add neighbours.")).ds(.caption)
        }

        Section {
            Button(L.t("清除我嘅紀錄", "清除我的记录", "Clear my records"), role: .destructive) { confirmClear = true }.frame(minHeight: 56)
        } footer: {
            Text(store.demoMode ? L.t("演示模式：街坊關係、約會、反映、改過嘅地標名、散步紀錄都只存喺你部手機。地圖資料 © OpenStreetMap；天氣：香港天文台。", "演示模式：邻居关系、约会、反馈、改过的地标名、散步记录都只存在你的手机里。地图数据 © OpenStreetMap；天气：香港天文台。", "Demo mode: neighbours, walk plans, reports, renamed landmarks and walk records are only kept on your phone. Map data © OpenStreetMap; weather: Hong Kong Observatory.")
                 : L.t("行過嘅路線、屋企位置只存喺你部手機。伺服器（新加坡）只有網名、小人、屋企附近嘅格子、連續日數、每日分鐘同落腳地標、街坊關係同約會；清除會一齊刪走。地圖資料 © OpenStreetMap；天氣：香港天文台。", "走过的路线、家的位置只存在你的手机里。服务器（新加坡）只有网名、形象、家附近的格子、连续天数、每日分钟和落脚地标、邻居关系和约会；清除会一起删掉。地图数据 © OpenStreetMap；天气：香港天文台。", "Your routes and home location stay on your phone. The server (Singapore) only has your nickname, figure, the area near home, streak, daily minutes and stop landmarks, neighbours and walk plans. Clearing deletes them too. Map data © OpenStreetMap; weather: Hong Kong Observatory.")).ds(.caption)
        }
    }

    /// 每项下面嘅说明小字。
    private func rowNote(_ text: String) -> some View {
        Text(text).ds(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 冇掣嘅一行（肤色、颜色）嘅标题。
    private func rowTitle(_ text: String) -> some View {
        Text(text).ds(.body).accessibilityAddTraits(.isHeader)
    }

    /// 楼层：两粒 56pt 大掣（系统 Stepper 嘅 −/+ 得 32pt 高，长者撳唔中）。字大排唔落一行就将掣放落第二行。
    private var floorRow: some View {
        let f = store.floorChoice
        let top = max(1, store.homeLevels)
        let value = L.t("\(f) 樓", "\(f) 楼", "\(f)/F")
        let buttons = HStack(spacing: 12) {
            stepButton("minus", L.t("低一層", "低一层", "One floor down"), enabled: f > 1) { store.setFloor(f - 1) }
            stepButton("plus", L.t("高一層", "高一层", "One floor up"), enabled: f < top) { store.setFloor(f + 1) }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(L.t("樓層", "楼层", "Floor")).lineLimit(1)
                Spacer(minLength: 8)
                Text(value).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                buttons
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.t("樓層", "楼层", "Floor"))
                    Spacer(minLength: 8)
                    Text(value).monospacedDigit().foregroundStyle(.secondary)
                }
                buttons
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("樓層", "楼层", "Floor"))
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

/// 揀界面语言（设定页、首次使用欢迎页共用）：粵語 / 普通话 / English，撳一下即时转，播报跟住转（AppLanguage.choose）。
/// 一行排得落就一行，排唔落就上下排。short = 欢迎页用短名（唔写繁简）。
struct LanguageChooser: View {
    var short = false
    var onChange: () -> Void = {}

    private func name(_ l: AppLang) -> String {
        guard short else { return l.label }
        switch l {
        case .yue: return "粵語"
        case .cmn: return "普通话"
        case .en: return "English"
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(spacing: 8) { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        ForEach(AppLang.allCases, id: \.self) { l in
            let on = AppLanguage.shared.current == l
            Button {
                guard !on else { return }
                AppLanguage.shared.choose(l)
                Haptics.select()
                onChange()
            } label: {
                Text(name(l))
                    .ds(on ? .bodyBold : .body)
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(on ? DS.accent : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}

extension AppStore {
    /// 转咗界面语言：地标名、街坊今日一句等跟住转，再用新语言试读一句（播报语言 AppLanguage.choose 已经转咗）。
    func languageChanged() {
        populate()
        syncScene()
        previewVoice(VoiceSettings.shared.active, current: true)
    }

    /// 设定页「住喺」显示嘅楼名：英文界面有英文名用英文（me.blockName 系中文原名，上传用）。
    var homeBlockShown: String? {
        guard let id = scene.homeBuildingID, let m = map else { return me.blockName }
        if MapModel.placeholderPos(id) != nil { return L.t("示意樓", "示意楼", "Sample block") }
        return m.building(id: id)?.shownName ?? me.blockName
    }

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
