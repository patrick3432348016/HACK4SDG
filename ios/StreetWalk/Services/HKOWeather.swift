import Foundation

/// 香港天文台开放数据整理后的结果：只留散步用得上的（警告、最近测站气温、最近分区雨量、九天预报）。
/// 纯解析，不联网（联网在 HKOWeatherService）；selftest 直接测这里。
struct HKOReport: Equatable {
    /// 数据来源：香港用天文台；香港以外（例如深圳）用 Open-Meteo 天气预报（OpenMeteo.swift），冇官方警告。
    enum Source: Equatable { case hko, forecast }

    struct Warning: Equatable {
        var code: String        // 例如 WHOT、WRAINA、WTS
        var name: String        // 例如 "黃色暴雨警告信號"
    }

    var station: String?
    var temperature: Int?
    var rainMM: Double?         // 最近分区过去一小时雨量
    var icon: Int?
    var warnings: [Warning] = []
    var todayMax: Int?          // 九天预报里有今日才有
    var todayPSR: String?
    var tomorrowPSR: String?    // 降雨概率：低 / 中低 / 中 / 中高 / 高
    var updated: Date?
    var source: Source = .hko

    /// 酷熱天氣警告，或气温 / 今日最高 33 度以上。
    var isHot: Bool {
        warnings.contains { $0.code.hasPrefix("WHOT") || $0.code == "VHOT" }
            || (temperature ?? 0) >= 33 || (todayMax ?? 0) >= 33 || icon == 90
    }

    /// 暴雨 / 雷暴警告，或附近过去一小时有雨、天气图标是雨（63–65；62 微雨全港统一，不算）、今日降雨概率中高以上。
    var isRain: Bool {
        isDanger || warnings.contains { $0.code.hasPrefix("WRAIN") || $0.code == "WTS" }
            || (rainMM ?? 0) >= 0.5 || rainIcon || ["中高", "高"].contains(todayPSR ?? "")
    }

    /// 八號以上風球、山泥傾瀉、新界北部水浸：唔好出門。
    var isDanger: Bool { warnings.contains { Self.isDangerCode($0.code) } }

    private var rainIcon: Bool { (63...65).contains(icon ?? 0) }

    /// 句首讲明来源和读数，例如"天文台話打鼓嶺而家 27 度，黃色暴雨警告信號生效。"；冇读数时为空。
    /// 香港以外讲"天氣預報話"，唔好冒认天文台。
    var line: String {
        var parts: [String] = []
        let en = L.isEn   // 英文：测站名系中文数据，唔讲；警告按 code 出英文名
        if let t = temperature { parts.append((station == "香港天文台" || en ? "" : station ?? "") + L.t("而家 \(t) 度", "现在 \(t) 度", "\(t)°C now")) }
        if !walkWarnings.isEmpty { parts.append((en ? walkWarningsEn : walkWarnings).joined(separator: en ? ", " : "、") + L.t("生效", "生效", " in force")) }
        else if (rainMM ?? 0) >= 0.5 { parts.append(L.t("附近落緊雨", "附近正在下雨", "raining nearby")) }
        else if rainIcon { parts.append(L.t("有雨", "有雨", "rain about")) }
        else if let psr = todayPSR, ["中高", "高"].contains(psr) { parts.append(L.t("今日降雨機會\(psr)", "今天降雨概率\(psr)", "\(psr == "高" ? "high" : "fair") chance of rain today")) }
        return parts.isEmpty ? "" : sourcePrefix + parts.joined(separator: en ? ", " : "，") + (en ? "" : "。")   // 英文唔加句号：AppStore+Places.oneSentence 会再拼
    }

    var sourcePrefix: String { source == .hko ? L.t("天文台話", "天文台说", "Observatory: ") : L.t("天氣預報話", "天气预报说", "Forecast: ") }

    /// 跟散步有关的警告（風球、山泥、水浸、酷熱、暴雨、雷暴），用来拼句；危险的排前面。
    var walkWarnings: [String] {
        let danger = warnings.filter { Self.isDangerCode($0.code) }
        let other = warnings.filter { $0.code.hasPrefix("WHOT") || $0.code == "VHOT" || $0.code.hasPrefix("WRAIN") || $0.code == "WTS" }
        return (danger + other).map(\.name)
    }

    /// 英文界面用：天文台警告名系中文数据，按 code 出英文名。
    var walkWarningsEn: [String] {
        let danger = warnings.filter { Self.isDangerCode($0.code) }
        let other = warnings.filter { $0.code.hasPrefix("WHOT") || $0.code == "VHOT" || $0.code.hasPrefix("WRAIN") || $0.code == "WTS" }
        return (danger + other).map { Self.englishName($0.code) }
    }

    static func englishName(_ c: String) -> String {
        if c.hasPrefix("TC8") { return "Gale or Storm Signal No. 8" }
        if c.hasPrefix("WHOT") || c == "VHOT" { return "Very Hot Weather Warning" }
        switch c {
        case "TC9": return "Increasing Gale or Storm Signal No. 9"
        case "TC10": return "Hurricane Signal No. 10"
        case "WL": return "Landslip Warning"
        case "WFNTSA": return "Flooding notice for the northern New Territories"
        case "WRAINA": return "Amber Rainstorm Warning"
        case "WRAINR": return "Red Rainstorm Warning"
        case "WRAINB": return "Black Rainstorm Warning"
        case "WTS": return "Thunderstorm Warning"
        default: return "Weather warning"
        }
    }

    static func isDangerCode(_ c: String) -> Bool {
        c.hasPrefix("TC8") || c == "TC9" || c == "TC10" || c == "WL" || c == "WFNTSA"
    }

    /// 风球 warnsum 的 name 只写"熱帶氣旋警告信號"，按 code 讲清楚几号。
    static func displayName(code: String, type: String?, name: String?) -> String {
        if code.hasPrefix("TC8") { return L.t("八號烈風或暴風信號", "八号烈风或暴风信号", "Gale or Storm Signal No. 8") }
        switch code {
        case "TC9": return L.t("九號烈風或暴風風力增強信號", "九号烈风或暴风风力增强信号", "Increasing Gale or Storm Signal No. 9")
        case "TC10": return L.t("十號颶風信號", "十号飓风信号", "Hurricane Signal No. 10")
        case "WL": return L.t("山泥傾瀉警告", "山泥倾泻警告", "Landslip Warning")
        case "WFNTSA": return L.t("新界北部水浸特別報告", "新界北部水浸特别报告", "Flooding notice for the northern New Territories")
        default: return (type ?? "") + (name ?? code)
        }
    }
}

extension HKOReport {
    /// 三份 JSON（rhrread 必须有，其余可缺）→ 报告。near 用来挑最近的测站和分区。
    static func parse(rhrread: Data, warnsum: Data?, fnd: Data?, near p: GeoPoint, today: Date) -> HKOReport? {
        guard let r = try? JSONSerialization.jsonObject(with: rhrread) as? [String: Any],
              let temps = (r["temperature"] as? [String: Any])?["data"] as? [[String: Any]] else { return nil }
        var out = HKOReport()
        let byTemp = temps.compactMap { d -> (String, Int)? in
            guard let place = d["place"] as? String, let v = d["value"] as? NSNumber, stations[place] != nil else { return nil }
            return (place, v.intValue)
        }
        if let best = byTemp.min(by: { distance(stations[$0.0]!, p) < distance(stations[$1.0]!, p) }) {
            out.station = best.0; out.temperature = best.1
        } else if let hq = temps.first(where: { $0["place"] as? String == "香港天文台" }) {
            out.station = "香港天文台"; out.temperature = (hq["value"] as? NSNumber)?.intValue
        }
        let rains = ((r["rainfall"] as? [String: Any])?["data"] as? [[String: Any]] ?? []).compactMap { d -> (String, Double)? in
            guard let place = d["place"] as? String, districts[place] != nil, (d["main"] as? String) != "TRUE" else { return nil }
            return (place, (d["max"] as? NSNumber)?.doubleValue ?? 0)
        }
        out.rainMM = rains.min { distance(districts[$0.0]!, p) < distance(districts[$1.0]!, p) }?.1
        out.icon = (r["icon"] as? [NSNumber])?.first?.intValue
        out.updated = (r["updateTime"] as? String).flatMap(isoDate)

        if let warnsum, let w = try? JSONSerialization.jsonObject(with: warnsum) as? [String: Any] {
            out.warnings = w.values.compactMap { v in
                guard let v = v as? [String: Any], let code = v["code"] as? String, (v["actionCode"] as? String) != "CANCEL" else { return nil }
                return Warning(code: code, name: displayName(code: code, type: v["type"] as? String, name: v["name"] as? String))
            }.sorted { $0.code < $1.code }
        }

        if let fnd, let f = try? JSONSerialization.jsonObject(with: fnd) as? [String: Any],
           let days = f["weatherForecast"] as? [[String: Any]] {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd"
            fmt.timeZone = TimeZone(identifier: "Asia/Hong_Kong")
            let todayKey = fmt.string(from: today), tomorrowKey = fmt.string(from: today.addingTimeInterval(86400))
            for d in days {
                switch d["forecastDate"] as? String {
                case todayKey:
                    out.todayPSR = d["PSR"] as? String
                    out.todayMax = ((d["forecastMaxtemp"] as? [String: Any])?["value"] as? NSNumber)?.intValue
                case tomorrowKey:
                    out.tomorrowPSR = d["PSR"] as? String
                default: break
                }
            }
        }
        return out
    }

    private static func isoDate(_ s: String) -> Date? { ISO8601DateFormatter().date(from: s) }

    private static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let dx = (a.lon - b.lon) * cos(b.lat * .pi / 180), dy = a.lat - b.lat
        return dx * dx + dy * dy
    }

    /// 测站大概位置（只用来挑最近的一个）。
    static let stations: [String: GeoPoint] = [
        "京士柏": .init(lat: 22.312, lon: 114.173), "香港天文台": .init(lat: 22.302, lon: 114.174), "黃竹坑": .init(lat: 22.248, lon: 114.174),
        "打鼓嶺": .init(lat: 22.529, lon: 114.157), "流浮山": .init(lat: 22.469, lon: 113.984), "大埔": .init(lat: 22.446, lon: 114.179),
        "沙田": .init(lat: 22.402, lon: 114.210), "屯門": .init(lat: 22.386, lon: 113.964), "將軍澳": .init(lat: 22.316, lon: 114.256),
        "西貢": .init(lat: 22.376, lon: 114.275), "長洲": .init(lat: 22.201, lon: 114.027), "赤鱲角": .init(lat: 22.310, lon: 113.922),
        "青衣": .init(lat: 22.344, lon: 114.110), "石崗": .init(lat: 22.436, lon: 114.085), "荃灣可觀": .init(lat: 22.383, lon: 114.108),
        "荃灣城門谷": .init(lat: 22.376, lon: 114.127), "香港公園": .init(lat: 22.278, lon: 114.162), "筲箕灣": .init(lat: 22.282, lon: 114.236),
        "九龍城": .init(lat: 22.335, lon: 114.185), "跑馬地": .init(lat: 22.270, lon: 114.184), "黃大仙": .init(lat: 22.339, lon: 114.206),
        "赤柱": .init(lat: 22.214, lon: 114.219), "觀塘": .init(lat: 22.318, lon: 114.225), "深水埗": .init(lat: 22.336, lon: 114.137),
        "啟德跑道公園": .init(lat: 22.305, lon: 114.216), "元朗公園": .init(lat: 22.441, lon: 114.019), "大美督": .init(lat: 22.475, lon: 114.237),
    ]

    /// 十八区大概中心（雨量按区给）。
    static let districts: [String: GeoPoint] = [
        "中西區": .init(lat: 22.283, lon: 114.150), "東區": .init(lat: 22.279, lon: 114.226), "葵青": .init(lat: 22.355, lon: 114.110),
        "離島區": .init(lat: 22.260, lon: 113.950), "北區": .init(lat: 22.495, lon: 114.140), "西貢": .init(lat: 22.380, lon: 114.270),
        "沙田": .init(lat: 22.385, lon: 114.195), "南區": .init(lat: 22.240, lon: 114.170), "大埔": .init(lat: 22.450, lon: 114.170),
        "荃灣": .init(lat: 22.370, lon: 114.110), "屯門": .init(lat: 22.390, lon: 113.975), "灣仔": .init(lat: 22.275, lon: 114.180),
        "元朗": .init(lat: 22.445, lon: 114.030), "油尖旺": .init(lat: 22.310, lon: 114.170), "深水埗": .init(lat: 22.330, lon: 114.160),
        "九龍城": .init(lat: 22.320, lon: 114.190), "黃大仙": .init(lat: 22.340, lon: 114.195), "觀塘": .init(lat: 22.315, lon: 114.225),
    ]
}
