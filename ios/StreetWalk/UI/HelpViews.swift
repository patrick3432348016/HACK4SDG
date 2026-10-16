import SwiftUI

/// 设定页「幫助同意見」「私隱政策」（测试反馈：设定要有隐私协议同帮助反馈）。
/// 两页都系纯文字，一页到底；内容跟返 App 实际做法写（同 PrivacyRows / 清除纪录嘅说明一致）。

/// 意见反馈收件地址；未定就唔出「寫電郵」掣，只叫佢话俾帮手装 App 嘅人知。
enum SupportConfig {
    static let feedbackEmail: String? = nil
}

struct HelpView: View {
    @Environment(AppStore.self) private var store

    private var faqs: [(q: String, a: String)] { [
        (L.t("上面幅地圖係乜？", "上面的地图是什么？"),
         L.t("係你屋企附近 200 米。街坊出咗門，會喺佢附近嘅地標出現，等你哋搵到對方。撳地標可以睇有冇櫈、有冇陰，同約街坊喺度等。向下拉地圖可以睇大啲。", "是你家附近 200 米。邻居出门了，会在他附近的地标出现，帮你们找到对方。点地标可以看有没有凳子、有没有阴凉，和约邻居在那里见。往下拉地图可以看大一点。")),
        (L.t("右上角個咪做咩用？", "右上角的麦克风做什么用？"),
         L.t("撳一下就可以講嘢，唔使打字。例如：「約阿明聽日行」「今日天氣點」「搵阿明」「呢度冇櫈」。講完佢會讀返俾你聽，影響到別人嘅事要你撳「好」先做。", "点一下就可以说话，不用打字。例如：「约阿明明天一起走」「今天天气怎么样」「找阿明」「这里没凳子」。说完它会读给你听，影响到别人的事要你点「好」才会做。")),
        (L.t("點樣做街坊？", "怎样成为邻居？"),
         L.t("見到面，兩個人都打開街坊行，撳「碰一碰」，兩部手機靠埋。碰過先見到對方住邊座、幾樓。", "见面时，两个人都打开街坊行，点「碰一碰」，两部手机靠在一起。碰过才看到对方住哪栋、几楼。")),
        (L.t("散步點樣記錄？", "散步怎样记录？"),
         L.t("唔使撳任何嘢。定位揀「始終允許」，出門行就會自動記，返到屋企就計好。", "不用点任何东西。定位选「始终允许」，出门走路就会自动记，回到家就算好。")),
        (L.t("約咗人之後喺邊度睇？", "约了人之后在哪里看？"),
         L.t("「今日」頁最上面會出約好嘅時間同地點；「街坊」頁都有。想改時間、地點，撳嗰張卡就得。", "「今天」页最上面会显示约好的时间和地点；「邻居」页也有。想改时间、地点，点那张卡就可以。")),
        (L.t("字太細 / 聲太細？", "字太小 / 声音太小？"),
         L.t("設定最上面「字體大小」揀大啲；聲音喺「聲音」揀語速，撳「試聽」試吓。手機靜音都會讀。", "设置最上面「字体大小」选大一点；声音在「声音」选语速，点「试听」试一下。手机静音也会读。")),
    ] }

    var body: some View {
        Form {
            ForEach(Array(faqs.enumerated()), id: \.offset) { _, f in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(f.q).ds(.bodyBold).accessibilityAddTraits(.isHeader)
                        Text(f.a).ds(.body).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                if let mail = SupportConfig.feedbackEmail, let url = URL(string: "mailto:\(mail)?subject=\(L.t("街坊行意見", "街坊行意见").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                    Link(destination: url) {
                        Label(L.t("寫電郵畀我哋", "给我们写邮件"), systemImage: "envelope").frame(minHeight: 56)
                    }
                }
            } header: {
                Text(L.t("意見反饋", "意见反馈")).ds(.caption)
            } footer: {
                Text(SupportConfig.feedbackEmail == nil
                     ? L.t("有問題或者建議，話畀幫你裝 App 嘅人知；佢哋會轉交我哋。", "有问题或建议，告诉帮你装 App 的人；他们会转交给我们。")
                     : L.t("有問題或者建議，寫電郵畀我哋。", "有问题或建议，给我们写邮件。")).ds(.caption)
            }
        }
        .navigationTitle(L.t("幫助同意見", "帮助与反馈"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyPolicyView: View {
    @Environment(AppStore.self) private var store

    private var sections: [(title: String, body: String)] { [
        (L.t("我哋收乜", "我们收集什么"),
         L.t("網名、小人樣、屋企附近嘅格子（約 400 米一格，冇門牌冇座標）、連續日數、每日行咗幾多分鐘、落腳嘅地標名、街坊關係同約會。", "网名、形象、家附近的格子（约 400 米一格，没有门牌和坐标）、连续天数、每天走了多少分钟、落脚的地标名、邻居关系和约会。")),
        (L.t("只喺你部手機", "只在你的手机上"),
         L.t("行過嘅路線、屋企準確位置、住邊座幾樓（只會畀碰過一碰嘅街坊睇）。", "走过的路线、家的准确位置、住哪栋几楼（只给碰过一碰的邻居看）。")),
        (L.t("放喺邊", "存在哪里"),
         L.t("伺服器喺新加坡（Supabase）。匿名登入，唔使電話號碼或者電郵。", "服务器在新加坡（Supabase）。匿名登录，不需要电话号码或邮箱。")),
        (L.t("講嘢", "说话"),
         L.t("撳咪講嘢時，聲音會交俾語音服務（豆包）轉做文字同理解，用完唔會存低；冇撳咪就唔會聽。", "点麦克风说话时，声音会交给语音服务（豆包）转成文字和理解，用完不保存；不点麦克风就不会听。")),
        (L.t("反映", "反馈问题"),
         L.t("「冇櫈」「太曬」呢類反映係匿名嘅，同一個地方夠十個人先交俾社工同屋邨管理。", "「没凳子」「太晒」这类反馈是匿名的，同一个地方满十个人才交给社工和屋邨管理。")),
        (L.t("刪除", "删除"),
         L.t("設定 →「進階」→「清除我嘅紀錄」，手機同伺服器上你嘅資料會一齊刪走。", "设置 →「高级」→「清除我的记录」，手机和服务器上你的资料会一起删掉。")),
        (L.t("資料來源", "数据来源"),
         L.t("地圖資料 © OpenStreetMap；天氣：香港天文台。", "地图数据 © OpenStreetMap；天气：香港天文台。")),
    ] }

    var body: some View {
        Form {
            Section {
                PrivacyRows().padding(.vertical, 8)
                Button(L.t("讀出嚟", "读出来")) { store.sayAgain(PrivacyRows.spoken) }.frame(minHeight: 56)
            } header: {
                Text(L.t("邊個見到乜", "谁能看到什么")).ds(.caption)
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, s in
                Section {
                    Text(s.body).ds(.body).fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
                } header: {
                    Text(s.title).ds(.caption)
                }
            }
        }
        .navigationTitle(L.t("私隱政策", "隐私政策"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
