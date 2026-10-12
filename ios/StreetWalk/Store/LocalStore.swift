import Foundation

/// 重启后要保留的数据。存在 Application Support/StreetWalk/state.json。
/// 上线后街坊关系、约会、反映、地标名以服务器为准，这里只当缓存；散步记录（含原始轨迹）只存在手机。
/// 读取时缺字段用默认值、坏咗嘅约会 / 反映逐条跳过（见下面 init(from:)）；加字段唔使升 version，
/// 结构真系改咗（改名、改类型）先升 version，喺 LocalStore.load 做迁移。
struct SavedState: Codable, Equatable {
    var version = 1
    /// 底座是哪一格、哪座楼。换了地方，跟地图有关的数据（约会地点、反映位置、改过的地标名）就作废。
    var mapKey: String?
    var neighbors: [String: NeighborLink] = [:]
    var appointments: [Appointment] = []
    var reports: [Report] = []
    var landmarkNames: [String: String] = [:]
    var walkLog: [String: DayLog] = [:]
    var leaveDays: Set<String> = []
    /// 「今日三件事」任务卡（首次使用之后）。可选：旧存档冇呢个字段都读得返。
    var firstDay: FirstDayProgress?
}

struct NeighborLink: Codable, Equatable {
    var since: Date
    var send: Bool
    var receive: Bool
}

/// 一日的散步记录（只记分钟、次数、经过的地标、落脚点，不记轨迹）。demo = 演示模式预先放的示範纪录。
struct DayLog: Codable, Equatable {
    var minutes = 0
    var walks = 0
    /// 经过的地标（只留喺手机）。
    var landmarks: [String] = []
    var demo = false
    /// 落脚点（停 ≥2 分钟）对应的地标：对外（每日一句、上线后上传）只用呢个。
    var stops: [String] = []
    /// 计步器量到嘅步数；nil = 冇量（模拟器、演示、轮椅、旧纪录），按分钟估算。
    var steps: Int?
    /// 冇量步数嗰几次散步嘅分钟（同日有量、有冇量时，冇量嗰部分照估算）。
    var unmeasured = 0

    /// 步数：量到嘅，加冇量嘅分钟按每分钟约 100 步估算。
    var stepEstimate: Int { steps.map { $0 + unmeasured * 100 } ?? minutes * 100 }
    /// 有冇用到估算（界面写「約」）。
    var stepsEstimated: Bool { walks > 0 && (steps == nil || unmeasured > 0) }
}

enum LocalStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StreetWalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    /// 读唔到（或者只救返部分）时，原文件先复制一份 state.bad-时间.json，之后写盘都唔会冚咗佢。
    static func load(from url: URL = url) -> SavedState {
        guard let data = try? Data(contentsOf: url) else { return SavedState() }
        let report = DecodeReport()
        let decoder = JSONDecoder()
        decoder.userInfo[DecodeReport.key] = report
        guard let s = try? decoder.decode(SavedState.self, from: data) else {
            backup(url)
            return SavedState()
        }
        if report.lossy { backup(url) }
        return s
    }

    static func save(_ s: SavedState, to url: URL = url) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear(_ url: URL = url) { try? FileManager.default.removeItem(at: url) }

    static func backup(_ url: URL) {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let to = url.deletingLastPathComponent().appendingPathComponent("state.bad-\(f.string(from: Date())).json")
        try? FileManager.default.copyItem(at: url, to: to)
    }

    /// 连续天数：从今日（今日未行就从昨日）往回数行过的日子。请假日唔断、但唔加（F4：请假期间连续天数保留）。
    /// includeDemo = false 时不计示範纪录。
    static func streak(_ log: [String: DayLog], leaves: Set<String>, today: Date, includeDemo: Bool) -> Int {
        streakKeys(log, leaves: leaves, today: today, includeDemo: includeDemo).count
    }

    /// 计入连续天数嘅日子（日期键）。
    static func streakKeys(_ log: [String: DayLog], leaves: Set<String>, today: Date, includeDemo: Bool) -> [String] {
        func walked(_ k: String) -> Bool {
            guard let l = log[k], includeDemo || !l.demo else { return false }
            return l.walks > 0
        }
        var day = today
        if !walked(dayKey(day)) && !leaves.contains(dayKey(day)) { day = day.addingTimeInterval(-86400) }
        var keys: [String] = []
        for _ in 0..<3650 {
            let k = dayKey(day)
            if walked(k) { keys.append(k) } else if !leaves.contains(k) { break }
            day = day.addingTimeInterval(-86400)
        }
        return keys
    }

    /// 记一次散步。演示散步（simulated）算示範纪录，唔会改真实纪录；真实散步盖过当日嘅示範纪录。
    /// 返回有冇记到。
    @discardableResult
    static func record(_ log: inout [String: DayLog], key: String, minutes: Int, landmarks: [String], stops: [String] = [],
                       steps: Int? = nil, simulated: Bool) -> Bool {
        var l = log[key] ?? DayLog(demo: simulated)
        if simulated && !l.demo { return false }
        if !simulated && l.demo { l = DayLog() }
        l.minutes += minutes
        l.walks += 1
        l.landmarks += landmarks.filter { !l.landmarks.contains($0) }
        l.stops += stops.filter { !l.stops.contains($0) }
        if let steps { l.steps = (l.steps ?? 0) + steps } else { l.unmeasured += minutes }
        log[key] = l
        return true
    }

    /// 示範纪录：过去 8 日 + 今日早上，连续 9 日。只填冇纪录嘅日子，真实纪录唔郁。
    static func seedDemo(_ log: inout [String: DayLog], today: Date) {
        let mins = [24, 32, 28, 41, 25, 36, 30, 22, 38]
        for (i, m) in mins.enumerated() {
            let k = dayKey(today.addingTimeInterval(-Double(i) * 86400))
            if log[k] == nil { log[k] = DayLog(minutes: m, walks: 1, landmarks: [], demo: true) }
        }
    }

    /// 香港时区的日期键，例如 "2026-10-07"。
    static func dayKey(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SolarPosition.hongKong
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - 宽松读取（A24：旧存档缺字段、某条坏咗，都唔好成份读唔返）

/// 读取时有冇丢过嘢（丢过就备份原文件）。
final class DecodeReport {
    static let key = CodingUserInfoKey(rawValue: "streetwalk.decodeReport")!
    var lossy = false
}

private extension Decoder {
    func markLossy() { (userInfo[DecodeReport.key] as? DecodeReport)?.lossy = true }
}

private extension KeyedDecodingContainer {
    /// 缺键用默认值；有键但读唔到都用默认值，并记低有损失。
    func value<T: Decodable>(_ key: Key, _ fallback: T, _ d: Decoder) -> T {
        guard contains(key) else { return fallback }
        if let v = try? decode(T.self, forKey: key) { return v }
        d.markLossy()
        return fallback
    }

    /// 数组逐条读，坏咗嘅跳过。
    func lossyArray<T: Decodable>(_ key: Key, _ d: Decoder) -> [T] {
        guard contains(key) else { return [] }
        guard let items = try? decode([Lossy<T>].self, forKey: key) else { d.markLossy(); return [] }
        if items.contains(where: { $0.value == nil }) { d.markLossy() }
        return items.compactMap(\.value)
    }
}

private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension SavedState {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.init()
        version = c.value(.version, 1, d)
        mapKey = c.value(.mapKey, nil, d)
        neighbors = c.value(.neighbors, [:], d)
        appointments = c.lossyArray(.appointments, d)
        reports = c.lossyArray(.reports, d)
        landmarkNames = c.value(.landmarkNames, [:], d)
        walkLog = c.value(.walkLog, [:], d)
        leaveDays = c.value(.leaveDays, [], d)
        firstDay = c.value(.firstDay, nil, d)
    }
}

extension DayLog {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.init()
        minutes = c.value(.minutes, 0, d)
        walks = c.value(.walks, 0, d)
        landmarks = c.value(.landmarks, [], d)
        demo = c.value(.demo, false, d)
        stops = c.value(.stops, [], d)
        steps = c.value(.steps, nil, d)
        unmeasured = c.value(.unmeasured, 0, d)
    }
}

/// 约会：旧存档冇 fromPartner、reminded 都读得返。
extension Appointment {
    private enum Keys: String, CodingKey { case id, partnerID, date, landmarkID, reason, status, fromPartner, reminded }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        self.init(id: c.value(.id, UUID(), d),
                  partnerID: try c.decode(String.self, forKey: .partnerID),
                  date: try c.decode(Date.self, forKey: .date),
                  landmarkID: try c.decode(String.self, forKey: .landmarkID),
                  reason: c.value(.reason, "", d),
                  status: try c.decode(Status.self, forKey: .status),
                  fromPartner: c.value(.fromPartner, false, d),
                  reminded: c.value(.reminded, false, d))
    }
}
