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
    static func shouldFallBack(_ reply: AssistantReply, local: VoiceIntent) -> Bool {
        guard reply.status == .info, (reply.command?.intent ?? "help") == "help" else { return false }
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
        let name = cmd.contactQuery.map(hant) ?? "對方"
        let at = cmd.startsAt.flatMap(parseDate)
        var c = AssistantCard(kind: .info, title: hant(r.message), detail: nil, spoken: hant(r.speechText),
                              conversationID: r.conversationId, draftID: r.draftId)
        switch r.status {
        case .needsInput:
            c.kind = .ask
            switch cmd.intent {
            case "invite":
                if at == nil {
                    c.title = "約\(name)幾時行？"
                    c.chips = ["聽日朝早八點", "聽日下晝四點", "今日下晝五點"]
                } else if cmd.maxWalkMinutes == nil {
                    c.title = "你同\(name)最多行幾耐？"
                    c.detail = at.map { "時間：\(lookup.timeLabel($0))" }
                    c.chips = ["最多行十分鐘", "最多行十五分鐘", "最多行二十分鐘"]
                } else {
                    c.title = "附近冇地方啱晒：唔夠近，或者嗰陣冇遮蔭資料。"
                    c.detail = "可以行遠啲，或者轉個時間。"
                    c.chips = ["最多行二十分鐘", "聽日朝早八點"]
                }
            case "leave":
                c.title = "邊日請假？"
                c.chips = ["今日請假", "聽日請假"]
            case "rename":
                c.title = "網名想改做咩？"
            default:
                c.title = hant(r.message)
            }
            c.spoken = c.title
        case .chooseContact:
            c.kind = .chooseContact
            c.title = "約邊個？"
            c.options = r.choices.map { .init(id: $0.id, label: hant($0.label), detail: nil) }
            c.spoken = "約邊個？揀一個街坊。"
        case .choosePlace:
            c.kind = .choosePlace
            c.title = "約\(name)\(at.map(lookup.timeLabel) ?? "")，喺邊度等？"
            c.options = r.choices.map { .init(id: $0.id, label: lookup.placeName($0.id) ?? hant($0.label),
                                              detail: lookup.placeDetail($0.id, at) ?? hant($0.detail)) }
            c.spoken = "喺邊度等？揀一個地方：" + c.options.prefix(3).map(\.label).joined(separator: "、") + "。"
        case .needsConfirmation:
            c.kind = .confirm
            let a = action(r.data)
            c.action = a
            switch a?.kind {
            case "invite":
                let who = a?.contactID.flatMap(lookup.contactName) ?? name
                let when = (a?.startsAt ?? at).map(lookup.timeLabel) ?? ""
                let place = a?.placeID.flatMap(lookup.placeName) ?? ""
                c.title = "約\(who)\(when)一齊行"
                c.detail = "地點：\(place)\n確認後會問\(who)，佢應承先算約好。"
                c.spoken = "約\(who)\(when)，喺\(place)"
            case "leave":
                let day = a?.date.flatMap(parseDay).map(lookup.dayLabel) ?? a?.date ?? ""
                c.title = "\(day)請假？"
                c.detail = "連續日數會保留"
                c.spoken = c.title
            case "rename":
                c.title = "網名改做「\(a?.newName ?? cmd.newName ?? "")」？"
                c.detail = "排行榜同街坊會見到新網名"
                c.spoken = "網名改做\(a?.newName ?? cmd.newName ?? "")"
            default:
                c.title = hant(r.message)
            }
        case .completed:
            c.kind = .done
            c.title = "做好咗"
            c.spoken = c.title
        case .cancelled:
            c.kind = .cancelled
            c.title = "取消咗，冇做任何嘢。"
            c.spoken = c.title
        case .uncertain:
            c.kind = .uncertain
            c.title = "未知做咗未"
            c.detail = "網絡唔穩。撳「查結果」，唔好再約多次。"
            c.spoken = "未知做咗未。撳查結果，唔好再約多次。"
        case .info:
            let op = r.data["operation_status"]?.string ?? r.data["operationStatus"]?.string
            if op == "failed" || op == "expired" {
                c.kind = .failed
                c.title = op == "expired" ? "等得太耐，張卡過咗期，冇做到。" : "做唔到：資料有變，冇寫入。"
                c.detail = "可以再講一次。"
                c.spoken = c.title
            } else if cmd.intent == "help" {
                c.kind = .notUnderstood
                c.title = "唔好意思，我未聽明白。"
                c.spoken = "唔好意思，我未聽明白。可以再講一次，或者揀一句。"
            } else {
                c.kind = .info
            }
        }
        return c
    }

    /// 完成卡：按确认卡嘅动作讲清楚做咗乜。
    static func doneTitle(_ a: AssistantCard.Action?, contactName: String?, timeLabel: String?, place: String?) -> String {
        switch a?.kind {
        case "invite": return "約咗\(contactName ?? "對方")\(timeLabel ?? "")\(place.map { "喺\($0)" } ?? "")，等緊佢確認。"
        case "leave": return "請咗假，連續日數會保留。"
        case "rename": return "網名改咗做「\(a?.newName ?? "")」。"
        default: return "做好咗。"
        }
    }

    // MARK: - 小工具

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
        s.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? s
    }
}
