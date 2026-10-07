import Foundation

/// 重启后要保留的数据。存在 Application Support/StreetWalk/state.json。
/// 上线后街坊关系、约会、反映、地标名以服务器为准，这里只当缓存；散步记录（含原始轨迹）只存在手机。
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
}

struct NeighborLink: Codable, Equatable {
    var since: Date
    var send: Bool
    var receive: Bool
}

/// 一日的散步记录（只记分钟、次数、经过的地标，不记轨迹）。demo = 演示模式预先放的示範纪录。
struct DayLog: Codable, Equatable {
    var minutes = 0
    var walks = 0
    var landmarks: [String] = []
    var demo = false
}

enum LocalStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StreetWalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    static func load() -> SavedState {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(SavedState.self, from: data) else { return SavedState() }
        return s
    }

    static func save(_ s: SavedState) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }

    /// 香港时区的日期键，例如 "2026-10-07"。
    static func dayKey(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SolarPosition.hongKong
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
