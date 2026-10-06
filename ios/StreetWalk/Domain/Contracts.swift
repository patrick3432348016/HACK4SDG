import Foundation

// 产品定稿 §8 的接口。成员 A（产品主体）和成员 B（AI、语音、碰一碰）只通过这里交接；改动要两人都同意。

/// 语音听懂后的意图。
enum VoiceIntent: Equatable {
    case invite(partnerID: String, day: Int, hour: Int?)    // 约人：day 0=今日 1=聽日 2=後日
    case goFind(partnerID: String)                           // 散步中过去找人
    case leave                                               // 请假
    case rename(landmarkID: String, newName: String)         // 改地标名
    case report(ReportKind)                                  // 反映问题
    case broadcast(String)                                   // 找人时播"我喺涼亭"
    case unknown
}

/// AI 用到的上下文（只给模板/模型看得到的最少信息）。
struct AIContext {
    var residents: [Resident]
    var landmarks: [Landmark]
    var now: Date
    var walking: Bool
    var finding: Bool
}

/// 成员 B 提供：所有 AI 能力。现在只有模板实现（TemplateAI），之后接真模型时实现同一协议即可。
protocol AIService {
    func parseVoice(_ transcript: String, context: AIContext) -> VoiceIntent
    func dailyLine(for resident: Resident, passed: [Landmark]) -> String
    func nameLandmark(_ c: LandmarkCandidate) -> String
    func alternativeNames(for l: Landmark) -> [String]
    func pickMeetupSpot(me: Resident, partner: Resident, date: Date, landmarks: [Landmark], shade: ShadeProviding) -> MeetProposal?
    func walkAdvice(weather: Weather, now: Date, shadeTip: (landmark: Landmark, shadedFrom: Int?)?) -> String?
    func monthlyReport(placeName: String, reports: [Report], landmarks: [Landmark]) -> MonthlyReport
}

/// 成员 A 提供：某地标某时段的遮荫比例（0–1）。
protocol ShadeProviding {
    func shade(landmarkID: String, at date: Date) -> Double
}

/// 成员 B 提供：碰一碰配对。现在是模拟实现，真机超宽带由组员实现同一协议。
protocol BumpService {
    func startSearching(candidates: [Resident], onFound: @escaping (Resident) -> Void)
    func cancel()
}

/// 成员 A 提供：碰一碰成功后建立街坊关系。
protocol NeighborRegistry: AnyObject {
    func createNeighbor(_ residentID: String, remind: Bool)
}

/// 成员 B 提供：语音播报。
protocol Speaking {
    func speak(_ text: String)
}
