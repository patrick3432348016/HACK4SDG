import SwiftUI
import UIKit

/// 设定页「幫助同意見」「私隱政策」（测试反馈：设定要有隐私协议同帮助反馈）。
/// 两页都系纯文字，一页到底；内容跟返 App 实际做法写（同 PrivacyRows / 清除纪录嘅说明一致）。
/// 「提意見」：喺 App 入面写，撳「發送」送去后端 feedback 表（supabase/migrations/002_feedback.sql）。

struct HelpView: View {
    @Environment(AppStore.self) private var store

    private var faqs: [(q: String, a: String)] { [
        (L.t("「今日」頁上面幅地圖係乜？", "「今天」页上面的地图是什么？"),
         L.t("係你屋企附近 200 米。街坊出咗門，會喺佢附近嘅地標出現，等你哋搵到對方。撳地標可以睇有冇櫈、有冇陰，同約街坊喺度等。向下拉地圖可以睇大啲。", "是你家附近 200 米的范围。邻居出门后，会出现在他附近的地标旁边，方便你们找到对方。点一下地标，可以看那里有没有凳子、有没有树荫，也可以约邻居在那里见面。把地图往下拉，能看得更大。")),
        (L.t("橙色個咪做咩用？", "橙色的麦克风有什么用？"),
         L.t("撳一下就可以講嘢，唔使打字。例如：「約阿明聽日行」「今日天氣點」「搵阿明」；散步時講「呢度冇櫈」。講完佢會讀返俾你聽，影響到別人嘅事要你撳「好」先做。", "点一下就能说话，不用打字。比如：「约阿明明天一起散步」「今天天气怎么样」「找阿明」；散步时可以说「这里没凳子」。说完它会把听到的话读给你听；会影响到别人的事，要你点「好的」才会去做。")),
        (L.t("點樣加街坊？", "怎样加邻居？"),
         L.t("見到面，兩個人都打開街坊行，喺「街坊」頁撳「碰一碰加街坊」，兩部手機靠埋。加咗之後先見到對方住邊座、幾樓。", "见面时，两个人都打开街坊行，在「邻居」页点「碰一碰加邻居」，把两部手机靠在一起就加好了。加了以后，才能看到对方住哪栋、几楼。")),
        (L.t("散步點樣記錄？", "散步怎么记录？"),
         L.t("唔使撳任何嘢。定位揀「始終允許」，出門行就會自動記，返到屋企就計好。", "什么都不用点。定位选「始终允许」，出门走路就会自动记录，回到家就记好了。")),
        (L.t("約咗人之後喺邊度睇？", "约好以后在哪里看？"),
         L.t("「今日」頁會列出約好嘅時間同地點；「街坊」頁都有。想改時間、地點，撳嗰張卡就得。", "「今天」页会列出约好的时间和地点，「邻居」页也有。想改时间或地点，点一下那张卡片就行。")),
        (L.t("字太細 / 聲太細？", "字太小、声音太小怎么办？"),
         L.t("設定最上面「字體大小」揀大啲。讀出嚟嘅聲大細跟手機音量，撳手機側邊嘅音量掣調大；「聲音」嗰度可以揀語速，撳「試聽」試吓。手機靜音都會讀。", "在设置最上面的「字体大小」选大一点。读出来的声音大小跟着手机音量，按手机侧面的音量键调大；在「声音」那里可以调说话快慢，点「试听」听一下。手机开了静音也会读。")),
    ] }

    var body: some View {
        Form {
            // 测试反馈 K-3b：以前要「話畀幫你裝 App 嘅人知」，而家喺 App 入面直接写、直接发；放最上面一眼见到
            Section {
                NavigationLink { FeedbackView() } label: {
                    Label(L.t("寫意見畀我哋", "给我们提意见"), systemImage: "square.and.pencil").ds(.bodyBold).frame(minHeight: 56)
                }
                .id("feedback")
            } header: {
                Text(L.t("意見反饋", "意见反馈")).ds(.caption)
            } footer: {
                Text(L.t("邊度唔方便、睇唔明，都可以寫低，撳「發送」就會傳畀我哋。", "哪里不方便、哪里看不懂，都可以写下来，点「发送」就会发给我们。")).ds(.caption)
            }

            ForEach(Array(faqs.enumerated()), id: \.offset) { i, f in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(f.q).ds(.bodyBold).accessibilityAddTraits(.isHeader)
                        Text(f.a).ds(.body).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                } header: {
                    if i == 0 { Text(L.t("常見問題", "常见问题")).ds(.caption) }
                }
            }
        }
        .settingsSubpage(L.t("幫助同意見", "帮助与反馈"))
    }
}

// MARK: - 提意见（写字 → 发去后端）

/// 写意见：草稿存喺手机（@AppStorage，退出返嚟都喺度），发送成功先清；发唔到讲原因、草稿保留。
struct FeedbackView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("feedback.draft") private var draft = UIPreview.is("feedback") || UIPreview.is("feedbackFailed") ? "地图上的字有点小，希望可以再大一点。" : ""
    @State private var state: SendState = .idle
    @FocusState private var editing: Bool

    enum SendState: Equatable { case idle, sending, sent, failed(String) }

    static let limit = 1000
    private var text: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text(L.t("喺度寫⋯（可以撳鍵盤上個咪講）", "在这里写……（也可以点键盘上的麦克风说）"))
                            .ds(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    TextEditor(text: $draft)
                        .ds(.body)
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .focused($editing)
                        .accessibilityLabel(L.t("意見內容", "意见内容"))
                        .onChange(of: draft) { _, d in
                            if d.count > Self.limit { draft = String(d.prefix(Self.limit)) }
                            // 发送成功后再写新嘢：收起「收到」（发送成功清草稿嗰下唔算）
                            if state == .sent, !d.isEmpty { state = .idle }
                        }
                }
                .padding(.vertical, 4)
            } header: {
                Text(L.t("你嘅意見", "你的意见")).ds(.caption)
            } footer: {
                Text(L.t("會匿名傳畀街坊行開發團隊（伺服器喺新加坡），連埋 App 版本同手機型號方便搵問題；唔會傳你嘅位置。", "会匿名发给街坊行开发团队（服务器在新加坡），同时附上 App 版本和手机型号，方便查问题；不会发送你的位置。")).ds(.caption)
            }

            Section {
                Button(action: send) {
                    HStack(spacing: 10) {
                        if state == .sending { ProgressView().tint(.white) }
                        Text(state == .sending ? L.t("發送緊⋯", "正在发送…") : L.t("發送", "发送"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
                .disabled(text.isEmpty || state == .sending)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .id("send")

                if let note = statusNote {
                    Label { Text(note.text).fixedSize(horizontal: false, vertical: true) } icon: {
                        Image(systemName: note.symbol).foregroundStyle(note.color)
                    }
                    .ds(.body)
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .settingsSubpage(L.t("提意見", "提意见"))
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if UIPreview.is("feedbackFailed") { state = .failed(L.t("冇網絡。", "没连上网络。")) } }
    }

    private var statusNote: (text: String, symbol: String, color: Color)? {
        switch state {
        case .sent: return (L.t("收到，多謝你！我哋會睇。", "收到了，谢谢你！我们会认真看。"), "checkmark.circle.fill", .green)
        case .failed(let why): return (L.t("\(why)未發送到，你寫嘅嘢已經保存，遲啲再撳「發送」。", "\(why)还没发出去，你写的内容已经保存，等一下再点「发送」。"), "exclamationmark.triangle.fill", .orange)
        default: return nil
        }
    }

    private func send() {
        let body = text
        guard !body.isEmpty, state != .sending else { return }
        editing = false
        state = .sending
        Task { @MainActor in
            do {
                try await FeedbackSender.send(body, demo: store.demoMode)
                // 发送途中再改咗就留住新草稿
                if draft.trimmingCharacters(in: .whitespacesAndNewlines) == body { draft = "" }
                state = .sent
                Haptics.success()
                store.say(L.t("收到，多謝你嘅意見。", "收到了，谢谢你的意见。"))
            } catch {
                state = .failed(FeedbackSender.reason(error))
                Haptics.warning()
            }
        }
    }
}

/// 意见送去 Supabase 嘅 feedback 表（只准插入自己嘅，唔准读）。未登录就先匿名登录（演示模式都得）。
@MainActor
enum FeedbackSender {
    struct Row: Encodable {
        let body: String
        let lang: String
        let app_version: String
        let device: String
        let os: String
        let demo: Bool
    }

    static func send(_ text: String, demo: Bool) async throws {
        let api = SupabaseCommunityService.shared.api
        if await api.userID == nil { try await api.signInAnonymously() }
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let row = Row(body: String(text.prefix(FeedbackView.limit)), lang: L.lang.rawValue, app_version: version,
                      device: deviceModel, os: "iOS \(UIDevice.current.systemVersion)", demo: demo)
        _ = try await api.request("POST", "/rest/v1/feedback", body: try BackendCoding.encoder.encode(row), prefer: "return=minimal")
    }

    /// 失败原因（一句，放喺「未發送到」前面）。
    static func reason(_ error: Error) -> String {
        if let e = error as? BackendError, e.isRetryable { return L.t("連唔到網絡。", "没连上网络。") }
        return L.t("伺服器暫時收唔到。", "服务器暂时收不到。")
    }

    /// 手机型号代码（例如 iPhone15,4）；模拟器用佢模拟紧嘅型号。
    private static var deviceModel: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return "\(sim) (sim)" }
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

// MARK: - 私隐政策

struct PrivacyPolicyView: View {
    @Environment(AppStore.self) private var store

    private var sections: [(title: String, body: String)] { [
        (L.t("我哋收乜", "我们收集什么"),
         L.t("網名、小人樣、屋企附近嘅格子（約 400 米一格，冇門牌冇座標）、連續日數、每日行咗幾多分鐘、落腳嘅地標名、街坊關係同約會。", "网名、卡通小人的样子、家附近的格子（大约 400 米一格，没有门牌，也没有坐标）、连续天数、每天走了多少分钟、歇脚的地标名称、邻居关系和约会。")),
        (L.t("只喺你部手機", "只存在你的手机里"),
         L.t("行過嘅路線、屋企準確位置。住邊座幾樓會上傳，但只會畀用碰一碰加咗嘅街坊睇。", "走过的路线、家的准确位置。住哪栋、几楼会上传，但只给用碰一碰加过的邻居看。")),
        (L.t("放喺邊", "存在哪里"),
         L.t("伺服器喺新加坡（Supabase）。匿名登入，唔使電話號碼或者電郵。", "服务器在新加坡（Supabase）。匿名登录，不需要电话号码，也不需要邮箱。")),
        (L.t("講嘢", "说话"),
         L.t("只有撳咗咪先會聽。連到我哋嘅語音伺服器時，聲音經伺服器交俾豆包（火山引擎）轉做文字同理解，測試期間對話會記低用嚟搵錯；連唔到就用 iPhone 自帶嘅語音識別（蘋果）。", "只有点了麦克风才会听。连上我们的语音服务器时，声音会经服务器交给豆包（火山引擎）转成文字、理解意思；测试期间对话会被记下来，用来查找问题。连不上时，就用 iPhone 自带的语音识别（苹果）。")),
        (L.t("反映", "地点反馈"),
         L.t("「冇櫈」「太曬」呢類反映係匿名嘅，同一個地方夠十個人先交俾社工同屋邨管理。", "「没凳子」「太晒」这类反馈是匿名的，同一个地方有十个人反馈了，才会交给社工和屋邨管理处。")),
        (L.t("意見", "意见"),
         L.t("「幫助同意見」入面寫嘅意見會匿名傳畀開發團隊，連埋 App 版本同手機型號，用嚟改善 App；唔包你嘅位置。", "在「帮助与反馈」里写的意见，会匿名发给开发团队，同时附上 App 版本和手机型号，用来改进 App；不包含你的位置。")),
        (L.t("刪除", "删除"),
         L.t("設定 →「進階」→「清除我嘅紀錄」，手機同伺服器上你嘅資料會一齊刪走。", "设置 →「高级」→「清除我的记录」，手机和服务器上你的资料会一起删掉。")),
        (L.t("資料來源", "数据来源"),
         L.t("地圖資料 © OpenStreetMap；天氣：香港天文台。", "地图数据 © OpenStreetMap；天气：香港天文台。")),
    ] }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section {
                    PrivacyRows().padding(.vertical, 8)
                    Button(L.t("讀出嚟", "读出来")) { store.sayAgain(PrivacyRows.spoken) }.frame(minHeight: 56)
                } header: {
                    Text(L.t("邊個見到乜", "谁能看到什么")).ds(.caption)
                }
                ForEach(Array(sections.enumerated()), id: \.offset) { i, s in
                    Section {
                        Text(s.body).ds(.body).fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
                    } header: {
                        Text(s.title).ds(.caption)
                    }
                    .id(i)
                }
            }
            .onAppear {
                // 截图自检：捲到中间，睇小标题捲上去时会唔会同导航栏标题叠埋
                guard UIPreview.is("privacyScrolled") else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.8))
                    proxy.scrollTo(1, anchor: .top)
                }
            }
        }
        .settingsSubpage(L.t("私隱政策", "隐私政策"))
    }
}

extension View {
    /// 设定入面推入去嘅页：标题用设计规范字号，导航栏实色。
    /// iOS 26 导航栏默认透明，向上捲时「邊個見到乜」呢类小标题会喺「私隱政策」后面隐约叠埋（测试反馈 K-3）；同设定首页一样用实色底。
    func settingsSubpage(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).ds(.bodyBold).lineLimit(1).accessibilityAddTraits(.isHeader)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                }
            }
    }
}
