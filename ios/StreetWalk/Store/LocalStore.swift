import Foundation

/// Restart-persistent data at Application Support/StreetWalk/state.json.
/// Server-backed fields act as cache where supported; local walk history remains on the phone and raw tracks are not uploaded.
/// Decode absent fields with defaults and skip damaged meetings / reports individually; adding a field does not require a version increment.
/// Increment version for structural renames or type changes and migrate in LocalStore.load.
struct SavedState: Codable, Equatable {
    var version = 1
    /// Base tile and home building; moving invalidates map-dependent meeting places, reports and landmark names.
    var mapKey: String?
    var neighbors: [String: NeighborLink] = [:]
    var appointments: [Appointment] = []
    var reports: [Report] = []
    var landmarkNames: [String: String] = [:]
    var walkLog: [String: DayLog] = [:]
    var leaveDays: Set<String> = []
    /// Optional first-day task card field preserves compatibility with older saves.
    var firstDay: FirstDayProgress?
}

struct NeighborLink: Codable, Equatable {
    var since: Date
    var send: Bool
    var receive: Bool
}

/// Daily record stores minutes, count, passed landmarks and stopping places, not tracks; demo marks sample records.
struct DayLog: Codable, Equatable {
    var minutes = 0
    var walks = 0
    /// Pass-through landmarks remain local.
    var landmarks: [String] = []
    var demo = false
    /// Landmarks corresponding to stops of at least 2 minutes; use only these for shared greetings / uploads.
    var stops: [String] = []
    /// Measured pedometer steps; nil for unmeasured, simulator, demo, wheelchair or legacy records, estimated from minutes.
    var steps: Int?
    /// Minutes from walks without step measurements, allowing mixed measured / estimated totals within a day.
    var unmeasured = 0

    /// Total measured steps plus roughly 100 steps per unmeasured minute.
    var stepEstimate: Int { steps.map { $0 + unmeasured * 100 } ?? minutes * 100 }
    /// Whether an approximation label is required.
    var stepsEstimated: Bool { walks > 0 && (steps == nil || unmeasured > 0) }
}

enum LocalStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StreetWalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    /// Before saving after failed or partial recovery, preserve the original as state.bad-<timestamp>.json.
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

    /// F4: count walking days backward from today or yesterday; leave neither breaks nor increases the streak.
    /// includeDemo=false excludes sample records.
    static func streak(_ log: [String: DayLog], leaves: Set<String>, today: Date, includeDemo: Bool) -> Int {
        streakKeys(log, leaves: leaves, today: today, includeDemo: includeDemo).count
    }

    /// Date keys included in the streak.
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

    /// Simulated walks never overwrite real records; real walks replace that day's demo record.
    /// Return whether the walk was recorded.
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

    /// Seed nine demo days only where records are absent; preserve real records.
    static func seedDemo(_ log: inout [String: DayLog], today: Date) {
        let mins = [24, 32, 28, 41, 25, 36, 30, 22, 38]
        for (i, m) in mins.enumerated() {
            let k = dayKey(today.addingTimeInterval(-Double(i) * 86400))
            if log[k] == nil { log[k] = DayLog(minutes: m, walks: 1, landmarks: [], demo: true) }
        }
    }

    /// Hong Kong date key, for example 2026-10-07.
    static func dayKey(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SolarPosition.hongKong
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - A24 tolerant decoding of missing fields and individual damaged records

/// Track data loss during decoding to trigger an original-file backup.
final class DecodeReport {
    static let key = CodingUserInfoKey(rawValue: "streetwalk.decodeReport")!
    var lossy = false
}

private extension Decoder {
    func markLossy() { (userInfo[DecodeReport.key] as? DecodeReport)?.lossy = true }
}

private extension KeyedDecodingContainer {
    /// Default missing keys; also default invalid values while recording the loss.
    func value<T: Decodable>(_ key: Key, _ fallback: T, _ d: Decoder) -> T {
        guard contains(key) else { return fallback }
        if let v = try? decode(T.self, forKey: key) { return v }
        d.markLossy()
        return fallback
    }

    /// Decode arrays item by item and skip damaged entries.
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

/// Accept legacy meetings without fromPartner or reminded.
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
