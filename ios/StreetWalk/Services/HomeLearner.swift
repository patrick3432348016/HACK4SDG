import Foundation

// Local home inference: pure logic without sensor access, suitable for unit tests.
// Use only Hong Kong nighttime locations (22:00–06:00) from visits, home-region events, significant changes, and nighttime app launches.
// Round coordinates to four decimal places (~11 m), retain 14 days, and keep them on this phone without upload.

/// A nighttime sample is either a visit/home-region interval or a single significant-change/location point.
struct NightSample: Codable, Equatable {
    enum Source: String, Codable {
        case visit          // System CLVisit event.
        case region         // Within the 100-m monitored home region.
        case significant    // Significant location change.
        case fix            // One location when opening the app at night.
        case simulated      // Simulator testing via -simNights.
    }

    var lat: Double
    var lon: Double
    var start: Date
    /// A nil end means ongoing; cap its contribution at start+openCap or now.
    var end: Date?
    var source: Source

    var point: GeoPoint { GeoPoint(lat: lat, lon: lon) }
}

/// Inference result.
enum HomeVerdict: Equatable {
    /// Fewer than two recorded nights; nights contains the count.
    case learning(nights: Int)
    /// The most frequent overnight location is within 150 m of the selected home.
    case confirmed(nights: Int, distance: Double)
    /// Different overnight location without enough evidence to ask: 150–300 m away, or beyond 300 m without two consecutive nights.
    case unsure(nights: Int, distance: Double)
    /// At least two recent consecutive nights beyond 300 m from home: ask whether the user moved.
    case moved(to: GeoPoint, nights: Int, distance: Double)
    /// No selected home, or example-estate home: suggest the overnight location. distance is from the current model home when available.
    case suggest(at: GeoPoint, nights: Int, distance: Double?)
}

struct HomeLearner: Codable, Equatable {
    static let keepDays = 14.0
    static let clusterRadius = 80.0
    static let confirmRadius = 150.0
    static let movedDistance = 300.0
    static let minNights = 2
    /// Treat a standalone location sample as a fifteen-minute stay.
    static let pointDwell: TimeInterval = 15 * 60
    /// Cap unfinished visits at 12 hours and home-region intervals at 16 hours to limit missing-exit effects after termination.
    static let openCap: TimeInterval = 12 * 3600
    static let openRegionCap: TimeInterval = 16 * 3600
    static let nightStart = 22
    static let nightEnd = 6

    var samples: [NightSample] = []

    // MARK: - Adding samples

    static func round(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }

    /// Round coordinates; merge same-source intervals starting within one minute and 50 m by updating the end; remove samples older than 14 days.
    /// Discard completed samples with no nighttime overlap; do not retain daytime visit history here.
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

    /// Close an ongoing interval of the selected source at at, such as on home-region exit; return whether anything changed.
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

    // MARK: - Nights

    /// Night key: 22:00–23:59 belongs to that date, 00:00–05:59 to the previous date; 10-11 03:00 maps to 2026-10-10.
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

    /// Previous night's key.
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

    /// Distribute a sample's duration across nights in seconds; a nighttime point contributes fifteen minutes.
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

    // MARK: - Clustering

    struct Cluster: Equatable {
        var center: GeoPoint
        var seconds: Double
        /// Seconds spent at a location each night.
        var perNight: [String: Double]
        var nights: Set<String> { Set(perNight.keys) }
    }

    /// Cluster samples within 80 m, seeding with longer stays and weighting the centre by duration; sort by total stay descending.
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

    /// Main location per night is the longest stay; newest nights first.
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

    // MARK: - Inference

    /// home is the current selected-building centre; picked distinguishes a user choice from example/developer defaults.
    func verdict(home: GeoPoint?, picked: Bool, now: Date, calendar: Calendar) -> HomeVerdict {
        let cs = clusters(now: now, calendar: calendar)
        let all = Set(cs.flatMap(\.nights))
        // Most recent night's main location and the consecutive-night count there.
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
