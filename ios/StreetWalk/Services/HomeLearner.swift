import Foundation

// 喺手机上估计屋企喺边（纯逻辑，唔掂传感器，可单测）。
// 只用夜晚（香港时间 22:00–06:00）嘅位置：系统「到访」、返到 / 离开屋企范围、大范围移动、夜晚开 App 时嘅一个定位。
// 坐标四舍五入到小数点后 4 位（约 11 m），只留 14 日，只喺呢部手机，唔上传。

/// 一个夜晚位置样本：一段时间（到访、喺屋企范围内）或者一个点（大范围移动、一个定位）。
struct NightSample: Codable, Equatable {
    enum Source: String, Codable {
        case visit          // 系统「到访」（CLVisit）
        case region         // 喺屋企 100 m 范围内（区域监察）
        case significant    // 大范围移动
        case fix            // 夜晚打开 App 时嘅一个定位
        case simulated      // 模拟器测试（-simNights）
    }

    var lat: Double
    var lon: Double
    var start: Date
    /// nil：仲喺度（到访未离开、仲喺屋企范围内）。计算时最多计到 start 之后 openCap、或者而家。
    var end: Date?
    var source: Source

    var point: GeoPoint { GeoPoint(lat: lat, lon: lon) }
}

/// 估计结果。
enum HomeVerdict: Equatable {
    /// 未够两晚（nights：已经记录咗几多晚）。
    case learning(nights: Int)
    /// 最常过夜嘅地方喺揀咗嘅屋企 150 m 内。
    case confirmed(nights: Int, distance: Double)
    /// 过夜嘅地方同揀咗嘅屋企有啲距离，但未够理由问（150–300 m，或者 300 m 外但唔係连续两晚）。
    case unsure(nights: Int, distance: Double)
    /// 最近连续两晚或以上都喺揀咗嘅屋企 300 m 外过夜：问「係咪搬咗屋」。
    case moved(to: GeoPoint, nights: Int, distance: Double)
    /// 未揀屋企（或者用示例屋邨揀）：建议用过夜嘅地方。distance：同而家模型屋企嘅距离（冇就 nil）。
    case suggest(at: GeoPoint, nights: Int, distance: Double?)
}

struct HomeLearner: Codable, Equatable {
    static let keepDays = 14.0
    static let clusterRadius = 80.0
    static let confirmRadius = 150.0
    static let movedDistance = 300.0
    static let minNights = 2
    /// 单独一个定位当喺度停咗 15 分钟。
    static let pointDwell: TimeInterval = 15 * 60
    /// 未完嘅到访最多计 12 小时；屋企范围最多 16 小时（App 被系统收咗、收唔到离开时唔会一直计落去）。
    static let openCap: TimeInterval = 12 * 3600
    static let openRegionCap: TimeInterval = 16 * 3600
    static let nightStart = 22
    static let nightEnd = 6

    var samples: [NightSample] = []

    // MARK: - 加样本

    static func round(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }

    /// 加一个样本：坐标四舍五入；同一段（同来源、开始时间差唔过 1 分钟、50 m 内）就更新结束时间；清走 14 日前嘅。
    /// 已经完咗又完全唔掂夜晚嘅样本唔留（日头去过边唔记）。
    mutating func add(_ s: NightSample, now: Date, calendar: Calendar) {
        var s = s
        s.lat = Self.round(s.lat)
        s.lon = Self.round(s.lon)
        prune(now: now)
        if let i = samples.firstIndex(where: { $0.source == s.source && abs($0.start.timeIntervalSince(s.start)) < 60
            && Self.distance($0.point, s.point) < 50 }) {
            samples[i] = s
        } else {
            guard s.end == nil || !Self.pieces(s, now: now, calendar: calendar).isEmpty else { return }
            samples.append(s)
        }
        samples.sort { $0.start < $1.start }
    }

    /// 某来源未完嘅一段喺 at 完咗（例如离开屋企范围）。返回有冇改到。
    @discardableResult
    mutating func close(_ source: NightSample.Source, at: Date) -> Bool {
        var changed = false
        for i in samples.indices where samples[i].source == source && samples[i].end == nil {
            let cap = samples[i].start.addingTimeInterval(source == .region ? Self.openRegionCap : Self.openCap)
            samples[i].end = max(samples[i].start, min(at, cap))
            changed = true
        }
        return changed
    }

    func hasOpen(_ source: NightSample.Source) -> Bool { samples.contains { $0.source == source && $0.end == nil } }

    mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.keepDays * 86400)
        samples.removeAll { ($0.end ?? $0.start.addingTimeInterval(Self.openRegionCap)) < cutoff }
    }

    // MARK: - 夜晚

    /// 某个时间属于边一晚：22:00–23:59 係当日，00:00–05:59 係前一日（例如 10-11 03:00 → "2026-10-10"）。
    static func nightKey(_ t: Date, calendar: Calendar) -> String {
        dayKey(t.addingTimeInterval(-Double(nightEnd) * 3600), calendar: calendar)
    }

    static func isNight(_ t: Date, calendar: Calendar) -> Bool {
        let h = calendar.component(.hour, from: t)
        return h >= nightStart || h < nightEnd
    }

    static func dayKey(_ t: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: t)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 前一晚嘅 key。
    static func previousKey(_ key: String, calendar: Calendar) -> String? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let d = calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)),
              let prev = calendar.date(byAdding: .day, value: -1, to: d) else { return nil }
        return dayKey(prev, calendar: calendar)
    }

    struct Piece: Equatable {
        var night: String
        var seconds: Double
    }

    /// 一个样本喺边几晚、每晚喺度几耐（秒）。单点：喺夜晚就当 15 分钟。
    static func pieces(_ s: NightSample, now: Date, calendar: Calendar) -> [Piece] {
        let cap = s.source == .region ? openRegionCap : openCap
        let end = s.end ?? max(s.start, min(now, s.start.addingTimeInterval(cap)))
        guard end > s.start else {
            return isNight(s.start, calendar: calendar) ? [Piece(night: nightKey(s.start, calendar: calendar), seconds: pointDwell)] : []
        }
        var out: [Piece] = []
        var day = calendar.startOfDay(for: s.start.addingTimeInterval(-Double(nightEnd) * 3600))
        for _ in 0..<20 {
            guard let ws = calendar.date(bySettingHour: nightStart, minute: 0, second: 0, of: day),
                  let we = calendar.date(byAdding: .hour, value: 24 - nightStart + nightEnd, to: ws), ws < end else { break }
            let overlap = min(end, we).timeIntervalSince(max(s.start, ws))
            if overlap > 0 { out.append(Piece(night: dayKey(day, calendar: calendar), seconds: overlap)) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    // MARK: - 归类

    struct Cluster: Equatable {
        var center: GeoPoint
        var seconds: Double
        /// 每晚喺度几耐（秒）。
        var perNight: [String: Double]
        var nights: Set<String> { Set(perNight.keys) }
    }

    /// 80 m 内嘅样本归做同一个地方（停得耐嘅先定中心，中心按停留时间加权）。按总停留时间由多到少。
    func clusters(now: Date, calendar: Calendar) -> [Cluster] {
        var items: [(p: GeoPoint, piece: Piece, start: Date)] = []
        for s in samples {
            for piece in Self.pieces(s, now: now, calendar: calendar) { items.append((s.point, piece, s.start)) }
        }
        items.sort { $0.piece.seconds != $1.piece.seconds ? $0.piece.seconds > $1.piece.seconds : $0.start < $1.start }
        var out: [Cluster] = []
        for it in items {
            if let i = out.firstIndex(where: { Self.distance($0.center, it.p) <= Self.clusterRadius }) {
                let w0 = out[i].seconds, w1 = it.piece.seconds, w = w0 + w1
                out[i].center = GeoPoint(lat: (out[i].center.lat * w0 + it.p.lat * w1) / w, lon: (out[i].center.lon * w0 + it.p.lon * w1) / w)
                out[i].seconds = w
                out[i].perNight[it.piece.night, default: 0] += w1
            } else {
                out.append(Cluster(center: it.p, seconds: it.piece.seconds, perNight: [it.piece.night: it.piece.seconds]))
            }
        }
        return out.sorted { $0.seconds > $1.seconds }
    }

    /// 每晚主要喺边（嗰晚停得最耐嘅地方）。最近嘅排先。
    struct NightSummary: Equatable {
        var night: String
        var center: GeoPoint
        var hours: Double
    }

    func nights(now: Date, calendar: Calendar) -> [NightSummary] {
        let cs = clusters(now: now, calendar: calendar)
        let keys = Set(cs.flatMap(\.nights))
        return keys.sorted(by: >).compactMap { k in
            guard let c = cs.max(by: { ($0.perNight[k] ?? 0) < ($1.perNight[k] ?? 0) }), let s = c.perNight[k] else { return nil }
            return NightSummary(night: k, center: c.center, hours: s / 3600)
        }
    }

    // MARK: - 结论

    /// home：而家模型用紧嘅屋企（揀咗嘅楼嘅中心）；picked：係用户自己揀嘅（唔係示例屋邨、唔係开发用嘅默认楼）。
    func verdict(home: GeoPoint?, picked: Bool, now: Date, calendar: Calendar) -> HomeVerdict {
        let cs = clusters(now: now, calendar: calendar)
        let all = Set(cs.flatMap(\.nights))
        // 最近一晚主要喺边，连续几多晚都係嗰度
        var recent: (cluster: Cluster, run: Int)?
        if let latest = all.max(), let top = cs.max(by: { ($0.perNight[latest] ?? 0) < ($1.perNight[latest] ?? 0) }) {
            var run = 1
            var k = latest
            while let prev = Self.previousKey(k, calendar: calendar), top.perNight[prev] != nil,
                  cs.max(by: { ($0.perNight[prev] ?? 0) < ($1.perNight[prev] ?? 0) }) == top {
                run += 1
                k = prev
            }
            recent = (top, run)
        }
        let recentHome = recent.flatMap { $0.run >= Self.minNights ? $0.cluster : nil }
        guard let candidate = recentHome ?? cs.first(where: { $0.nights.count >= Self.minNights }) else {
            return .learning(nights: all.count)
        }
        let nights = candidate.nights.count
        guard let home else { return .suggest(at: candidate.center, nights: nights, distance: nil) }
        let d = Self.distance(home, candidate.center)
        if d <= Self.confirmRadius { return .confirmed(nights: nights, distance: d) }
        if !picked { return .suggest(at: candidate.center, nights: nights, distance: d) }
        if d > Self.movedDistance, let r = recent, r.cluster == candidate, r.run >= Self.minNights {
            return .moved(to: candidate.center, nights: r.run, distance: d)
        }
        return .unsure(nights: nights, distance: d)
    }

    static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double { LocalProjection(origin: a).toLocal(b).length }
}
