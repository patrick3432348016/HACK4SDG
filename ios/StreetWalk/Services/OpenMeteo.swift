import Foundation

/// 香港范围（大约）：天文台数据只覆盖香港。北面沿深圳河、深圳湾中线，所以蛇口、福田、梅林都喺外面。
/// 只用来拣天气来源，唔需要好准。
enum HongKongArea {
    /// (经度, 纬度)，顺时针。
    private static let outline: [(Double, Double)] = [
        (113.82, 22.15), (113.82, 22.40), (113.89, 22.42), (113.98, 22.475), (114.03, 22.495),
        (114.07, 22.515), (114.11, 22.535), (114.15, 22.555), (114.22, 22.555), (114.30, 22.57),
        (114.45, 22.50), (114.45, 22.15),
    ]

    static func contains(_ p: GeoPoint) -> Bool {
        var inside = false
        var j = outline.count - 1
        for i in outline.indices {
            let (xi, yi) = outline[i], (xj, yj) = outline[j]
            if (yi > p.lat) != (yj > p.lat), p.lon < (xj - xi) * (p.lat - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }
}

/// 香港以外嘅天气：Open-Meteo（免费、唔使 key、全球）。只送大约位置（经纬度取到 0.1 度，约 10 公里），唔送屋企位置。
enum OpenMeteo {
    static func url(near p: GeoPoint) -> URL? {
        let lat = (p.lat * 10).rounded() / 10, lon = (p.lon * 10).rounded() / 10
        return URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,precipitation,weather_code"
            + "&daily=temperature_2m_max,precipitation_probability_max"
            + "&timezone=auto&forecast_days=2")
    }

    /// 降雨概率 → 天文台用开嘅讲法（低 / 中低 / 中 / 中高 / 高），等提示句同香港一致。
    static func psr(_ percent: Double?) -> String? {
        guard let v = percent else { return nil }
        switch v {
        case ..<20: return "低"
        case ..<40: return "中低"
        case ..<60: return "中"
        case ..<80: return "中高"
        default: return "高"
        }
    }
}

extension HKOReport {
    /// Open-Meteo JSON → 报告（source = .forecast，冇警告）。WMO 天气代码：61–67、80–82 雨，95–99 雷暴 → 当作有雨（icon 63）。
    static func parseOpenMeteo(_ data: Data) -> HKOReport? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = j["current"] as? [String: Any],
              let temp = (cur["temperature_2m"] as? NSNumber)?.doubleValue else { return nil }
        var out = HKOReport()
        out.source = .forecast
        out.temperature = Int(temp.rounded())
        out.rainMM = (cur["precipitation"] as? NSNumber)?.doubleValue
        if let code = (cur["weather_code"] as? NSNumber)?.intValue,
           (61...67).contains(code) || (80...82).contains(code) || (95...99).contains(code) {
            out.icon = 63
        }
        if let daily = j["daily"] as? [String: Any] {
            let maxes = (daily["temperature_2m_max"] as? [Any])?.map { ($0 as? NSNumber)?.doubleValue }
            let probs = (daily["precipitation_probability_max"] as? [Any])?.map { ($0 as? NSNumber)?.doubleValue }
            out.todayMax = maxes?.first.flatMap { $0 }.map { Int($0.rounded()) }
            out.todayPSR = OpenMeteo.psr(probs?.first.flatMap { $0 })
            out.tomorrowPSR = OpenMeteo.psr(probs?.dropFirst().first.flatMap { $0 })
        }
        // current.time 系当地时间（timezone=auto），配 utc_offset_seconds。
        if let t = cur["time"] as? String, let off = (j["utc_offset_seconds"] as? NSNumber)?.intValue {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'T'HH:mm"
            f.timeZone = TimeZone(secondsFromGMT: off)
            out.updated = f.date(from: t)
        }
        return out
    }
}
