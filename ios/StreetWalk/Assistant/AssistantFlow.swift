import Foundation

// 组员 B 服务器嘅回覆（状态 + 结构化指令）→ 我哋原有嘅「我聽到」复述卡（粤语、大字、每步都有掣）。纯逻辑，有单元测试。
// B 嘅 message 系普通话简体（俾佢自己嘅联调界面用）；呢度按 status / command / data 出粤语，冇对应先用 B 嘅字（转繁体）。

/// 一张助手卡要显示 / 讲嘅嘢。
struct AssistantCard: Equatable {
    enum Kind: Equatable { case thinking, ask, chooseContact, choosePlace, confirm, done, failed, info, uncertain, cancelled, notUnderstood }
    struct Option: Equatable, Identifiable {
        var id: String
        var label: String
        var detail: String?
    }
    var kind: Kind
    var title: String
    var detail: String?
    var spoken: String
    /// 揀联系人 / 地点（大掣）。
    var options: [Option] = []
    /// 补充资料嘅建议说法（撳 = 讲咗嗰句）。
    var chips: [String] = []
    var conversationID: String
    var draftID: String?
    /// 确认后嘅动作（约人：联系人、地点、时间），完成之后 App 用嚟加约会。
    var action: Action?

    struct Action: Equatable {
        var kind: String
        var contactID: String?
        var placeID: String?
        var startsAt: Date?
        var date: String?
        var newName: String?
    }

    /// 要用户揀 / 补嘢 / 撳「好」：唔好自动收起。
    var waitsForUser: Bool { [.thinking, .ask, .chooseContact, .choosePlace, .confirm, .uncertain].contains(kind) }
    /// 对话完咗（之后讲嘢开新对话）。
    var endsConversation: Bool { [.done, .failed, .cancelled, .info, .notUnderstood].contains(kind) }
}

enum AssistantFlow {
    /// 手机模板听到嘅意图 → 要唔要问 Mac 服务器（B 嘅助手）。
    /// 约人、听唔明嘅句子交俾服务器；改名（地标）、反映、找人、改约、取消约、请假仍然喺手机做（B 冇呢啲功能 / 请假喺手机即时做，可撤回）。
    static func shouldAsk(_ local: VoiceIntent) -> Bool {
        switch local {
        case .invite, .unknown: return true
        default: return false
        }
    }

    /// 服务器听唔明（help）而手机模板听得明：用返手机流程。
    /// B 嘅范围规则答咗（天气、拒答、紧急求助、交通…，data.policy）就一定用服务器嘅答案（B：夹杂 App 词语都成句拒绝）。
    static func shouldFallBack(_ reply: AssistantReply, local: VoiceIntent) -> Bool {
        guard reply.status == .info, (reply.command?.intent ?? "help") == "help" else { return false }
        if let p = policy(reply), p != "help" { return false }
        if case .unknown = local { return false }
        return true
    }

    struct Lookup {
        var contactName: (String) -> String?
        var placeName: (String) -> String?
        /// 地点说明（粤语）：步行分钟、嗰陣有冇遮。
        var placeDetail: (String, Date?) -> String?
        var timeLabel: (Date) -> String
        /// 只讲日子（请假）：「聽日」「10月20日（星期二）」。
        var dayLabel: (Date) -> String
    }

    static func card(_ r: AssistantReply, lookup: Lookup) -> AssistantCard {
        let cmd = r.command ?? AssistantCommand()
        let name = cmd.contactQuery.map(hant) ?? L.t("對方", "对方")
        let at = cmd.startsAt.flatMap(parseDate)
        var c = AssistantCard(kind: .info, title: hant(r.message), detail: nil, spoken: hant(r.speechText),
                              conversationID: r.conversationId, draftID: r.draftId)
        switch r.status {
        case .needsInput:
            c.kind = .ask
            switch cmd.intent {
            case "invite":
                if at == nil {
                    c.title = L.t("約\(name)幾時行？", "约\(name)什么时候走？")
                    c.chips = [L.t("聽日朝早八點", "明天早上八点"), L.t("聽日下晝四點", "明天下午四点"), L.t("今日下晝五點", "今天下午五点")]
                } else if cmd.maxWalkMinutes == nil {
                    c.title = L.t("你同\(name)最多行幾耐？", "你和\(name)最多走多久？")
                    c.detail = at.map { L.t("時間：\(lookup.timeLabel($0))", "时间：\(lookup.timeLabel($0))") }
                    c.chips = [L.t("最多行十分鐘", "最多走十分钟"), L.t("最多行十五分鐘", "最多走十五分钟"), L.t("最多行二十分鐘", "最多走二十分钟")]
                } else {
                    c.title = L.t("附近冇地方啱晒：唔夠近，或者嗰陣冇遮蔭資料。", "附近没有完全合适的地方：不够近，或者那时没有遮荫资料。")
                    c.detail = L.t("可以行遠啲，或者轉個時間。", "可以走远一点，或者换个时间。")
                    c.chips = [L.t("最多行二十分鐘", "最多走二十分钟"), L.t("聽日朝早八點", "明天早上八点")]
                }
            case "leave":
                c.title = L.t("邊日請假？", "哪天请假？")
                c.chips = [L.t("今日請假", "今天请假"), L.t("聽日請假", "明天请假")]
            case "rename":
                c.title = L.t("網名想改做咩？", "网名想改成什么？")
            default:
                c.title = hant(r.message)
            }
            c.spoken = c.title
        case .chooseContact:
            c.kind = .chooseContact
            c.title = L.t("約邊個？", "约谁？")
            c.options = r.choices.map { .init(id: $0.id, label: hant($0.label), detail: nil) }
            c.spoken = L.t("約邊個？揀一個街坊。", "约谁？选一位邻居。")
        case .choosePlace:
            c.kind = .choosePlace
            c.title = L.t("約\(name)\(at.map(lookup.timeLabel) ?? "")，喺邊度等？", "约\(name)\(at.map(lookup.timeLabel) ?? "")，在哪里等？")
            c.options = r.choices.map { .init(id: $0.id, label: lookup.placeName($0.id) ?? hant($0.label),
                                              detail: lookup.placeDetail($0.id, at) ?? hant($0.detail)) }
            c.spoken = L.t("喺邊度等？揀一個地方：", "在哪里等？选一个地方：") + c.options.prefix(3).map(\.label).joined(separator: "、") + "。"
        case .needsConfirmation:
            c.kind = .confirm
            let a = action(r.data)
            c.action = a
            switch a?.kind {
            case "invite":
                let who = a?.contactID.flatMap(lookup.contactName) ?? name
                let when = (a?.startsAt ?? at).map(lookup.timeLabel) ?? ""
                let place = a?.placeID.flatMap(lookup.placeName) ?? ""
                c.title = L.t("約\(who)\(when)一齊行", "约\(who)\(when)一起走")
                c.detail = L.t("地點：\(place)\n確認後會問\(who)，佢應承先算約好。", "地点：\(place)\n确认后会问\(who)，对方答应才算约好。")
                c.spoken = L.t("約\(who)\(when)，喺\(place)", "约\(who)\(when)，在\(place)")
            case "leave":
                let day = a?.date.flatMap(parseDay).map(lookup.dayLabel) ?? a?.date ?? ""
                c.title = L.t("\(day)請假？", "\(day)请假？")
                c.detail = L.t("連續日數會保留", "连续天数会保留")
                c.spoken = c.title
            case "rename":
                c.title = L.t("網名改做「\(a?.newName ?? cmd.newName ?? "")」？", "网名改成「\(a?.newName ?? cmd.newName ?? "")」？")
                c.detail = L.t("排行榜同街坊會見到新網名", "排行榜和邻居会看到新网名")
                c.spoken = L.t("網名改做\(a?.newName ?? cmd.newName ?? "")", "网名改成\(a?.newName ?? cmd.newName ?? "")")
            default:
                c.title = hant(r.message)
            }
        case .completed:
            c.kind = .done
            c.title = L.t("做好咗", "完成了")
            c.spoken = c.title
        case .cancelled:
            c.kind = .cancelled
            c.title = L.t("取消咗，冇做任何嘢。", "已取消，什么都没做。")
            c.spoken = c.title
        case .uncertain:
            c.kind = .uncertain
            c.title = L.t("未知做咗未", "不确定是否完成")
            c.detail = L.t("網絡唔穩。撳「查結果」，唔好再約多次。", "网络不稳。点「查结果」，不要再约一次。")
            c.spoken = L.t("未知做咗未。撳查結果，唔好再約多次。", "不确定是否完成。点查结果，不要再约一次。")
        case .info:
            let op = r.data["operation_status"]?.string ?? r.data["operationStatus"]?.string
            if let p = policy(r), p != "app" {
                // B 嘅范围规则（2026-10-12）：天文台天气、固定拒答 / 求助提示、交通、排行榜、纪录、打招呼。
                // 讲 B 嘅原句（官方天气资料或固定句，唔系模型自由作答），标题用短句。
                c.kind = .info
                c.detail = hant(r.message)
                c.spoken = hant(r.speechText)
                c.title = policyTitle(p)
            } else if op == "failed" || op == "expired" {
                c.kind = .failed
                c.title = op == "expired" ? L.t("等得太耐，張卡過咗期，冇做到。", "等太久，卡片过期了，没有完成。") : L.t("做唔到：資料有變，冇寫入。", "做不到：资料有变，没有写入。")
                c.detail = L.t("可以再講一次。", "可以再说一次。")
                c.spoken = c.title
            } else if cmd.intent == "help" {
                c.kind = .notUnderstood
                c.title = L.t("唔好意思，我未聽明白。", "不好意思，我没听明白。")
                c.spoken = L.t("唔好意思，我未聽明白。可以再講一次，或者揀一句。", "不好意思，我没听明白。可以再说一次，或者选一句。")
            } else {
                c.kind = .info
            }
        }
        return c
    }

    /// 完成卡：按确认卡嘅动作讲清楚做咗乜。
    static func doneTitle(_ a: AssistantCard.Action?, contactName: String?, timeLabel: String?, place: String?) -> String {
        switch a?.kind {
        case "invite": return L.t("約咗\(contactName ?? "對方")\(timeLabel ?? "")\(place.map { "喺\($0)" } ?? "")，等緊佢確認。", "约了\(contactName ?? "对方")\(timeLabel ?? "")\(place.map { "在\($0)" } ?? "")，等对方确认。")
        case "leave": return L.t("請咗假，連續日數會保留。", "已请假，连续天数会保留。")
        case "rename": return L.t("網名改咗做「\(a?.newName ?? "")」。", "网名已改成「\(a?.newName ?? "")」。")
        default: return L.t("做好咗。", "完成了。")
        }
    }

    // MARK: - 小工具

    /// 服务器用 B 嘅范围规则答（data.policy）：weather / deny / emergency / traffic / board / history / help / app。
    static func policy(_ r: AssistantReply) -> String? { r.data["policy"]?.string }

    static func policyTitle(_ p: String) -> String {
        switch p {
        case "weather": return L.t("天文台天氣", "天文台天气")
        case "deny": return L.t("呢個我幫唔到", "这个我帮不了")
        case "emergency": return L.t("有危險請即刻求助", "有危险请马上求助")
        case "traffic": return L.t("交通資料未接通", "交通资料未接通")
        case "board": return L.t("排行榜", "排行榜")
        case "history": return L.t("散步紀錄", "散步记录")
        default: return L.t("我可以幫你", "我可以帮你")
        }
    }

    static func action(_ data: [String: AssistantJSON]) -> AssistantCard.Action? {
        guard let a = data["action"] else { return nil }
        func f(_ snake: String) -> String? {
            a[snake]?.string ?? a[camel(snake)]?.string
        }
        guard let kind = f("kind") else { return nil }
        return .init(kind: kind, contactID: f("contact_id"), placeID: f("place_id"), startsAt: f("starts_at").flatMap(parseDate),
                     date: f("date"), newName: f("new_name"))
    }

    static func camel(_ snake: String) -> String {
        let parts = snake.split(separator: "_")
        return parts.enumerated().map { $0.offset == 0 ? String($0.element) : $0.element.capitalized }.joined()
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    static func parseDay(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Asia/Hong_Kong")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s).map { $0.addingTimeInterval(12 * 3600) }
    }

    /// B 嘅简体字 → 繁体（意思唔变；冇对应粤语讲法时先用）。
    static func hant(_ s: String) -> String {
        L.isCmn ? s : (s.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? s)
    }
}
