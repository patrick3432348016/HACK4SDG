import Foundation

// 服务器上嘅行（supabase/migrations/001_init.sql）。栏名照抄 snake_case。只用 Foundation。

/// profiles.avatar：{"mobility","color","skin","age"}。
struct AvatarJSON: Codable, Equatable, Sendable {
    var mobility: String?
    var color: Int?
    var skin: Int?
    var age: String?
}

/// 上传自己的资料（profiles，upsert on id）。座数楼层只有互为街坊先睇到（服务器函数保证）。
struct ProfileUpsert: Codable, Equatable, Sendable {
    var id: String
    var nickname: String
    var avatar: AvatarJSON
    var tile_x: Int
    var tile_y: Int
    var community_name: String?
    var block: String?
    var floor: Int?
    var streak: Int
    var streak_day: String?
    var lang: String = "zh-HK"
}

/// community_board()：附近 3×3 格嘅真人。冇座数楼层。
struct BoardRow: Codable, Equatable, Sendable {
    var id: String
    var nickname: String
    var avatar: AvatarJSON?
    var streak: Int
    var month_steps: Int?
    var is_me: Bool
    var is_neighbor: Bool
    var daily_line: String?
}

/// my_neighbors()：互为街坊。out_at = 佢出门时嘅地标名（佢开咗发送、我开咗接收先有）。
struct NeighborRow: Codable, Equatable, Sendable {
    var id: String
    var nickname: String
    var avatar: AvatarJSON?
    var block: String?
    var floor: Int?
    var streak: Int?
    var since: Date?
    var send_remind: Bool?
    var receive_remind: Bool?
    var out_at: String?
    var out_since: Date?
    var daily_line: String?
}

/// link_neighbor() 配上之后返回嘅对方资料。
struct LinkRow: Codable, Equatable, Sendable {
    var id: String
    var nickname: String
    var avatar: AvatarJSON?
    var block: String?
    var floor: Int?
}

struct MeetupRow: Codable, Equatable, Sendable {
    var id: String
    var inviter: String
    var invitee: String
    var at: Date
    var landmark_name: String?
    var reason: String?
    var status: String          // waiting / accepted / declined / done / cancelled / expired
    var updated_by: String?
    var updated_at: Date?
}

struct SignalRow: Codable, Equatable, Sendable {
    var id: Int64
    var from_user: String
    var to_user: String
    var kind: String            // find_ask / find_answer / find_cancel / say / trip / poke
    var payload: JSONValue
    var created_at: Date?
}

/// 发信号（signals 冇 update；id 由服务器生成）。
struct SignalInsert: Codable, Equatable, Sendable {
    var from_user: String
    var to_user: String
    var kind: String
    var payload: JSONValue
}

struct OutingUpsert: Codable, Equatable, Sendable {
    var user_id: String
    var landmark_name: String?
    var started_at: Date?
    var updated_at: Date
}

struct WalkUpsert: Codable, Equatable, Sendable {
    var user_id: String
    var day: String
    var minutes: Int
    var steps: Int
    var stop_landmarks: [String]
    var daily_line: String?
}

struct ReportInsert: Codable, Equatable, Sendable {
    var id: String
    var user_id: String
    var tile_x: Int
    var tile_y: Int
    var landmark_name: String
    var kind: String            // sunny / no_seat / rough / other
    var raw_text: String?
}

struct ReportFollowUpRow: Codable, Equatable, Sendable {
    var id: String
    var follow_up: String?
}

/// monthly_report()：人数 ≥ 10 嘅「地标 × 反映类型」，另附附近散步人次。
struct MonthlyRow: Codable, Equatable, Sendable {
    var landmark_name: String
    var kind: String
    var people: Int
    var walk_count: Int
    var walkers: Int
}

// 可选栏要明确写 null（upsert 只更新 body 入面有嘅栏：唔写 = 唔改）。
extension ProfileUpsert {
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(nickname, forKey: .nickname)
        try c.encode(avatar, forKey: .avatar)
        try c.encode(tile_x, forKey: .tile_x)
        try c.encode(tile_y, forKey: .tile_y)
        try c.encode(community_name, forKey: .community_name)
        try c.encode(block, forKey: .block)
        try c.encode(floor, forKey: .floor)
        try c.encode(streak, forKey: .streak)
        try c.encode(streak_day, forKey: .streak_day)
        try c.encode(lang, forKey: .lang)
    }
}

extension OutingUpsert {
    /// landmark_name 一定写（回家 = null）；started_at 只喺新一次出门时写（途中换地标保留开始时间）。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(user_id, forKey: .user_id)
        try c.encode(landmark_name, forKey: .landmark_name)
        try c.encodeIfPresent(started_at, forKey: .started_at)
        try c.encode(updated_at, forKey: .updated_at)
    }
}
