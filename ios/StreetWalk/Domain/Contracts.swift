import Foundation

// Product specification §8 contracts between member A (app) and B (AI, speech, pairing). Both must agree to changes.

/// Intent understood from speech.
enum VoiceIntent: Equatable {
    case invite(partnerID: String, day: Int, hour: Int?)    // Invite: day 0 = today, 1 = tomorrow, 2 = day after tomorrow.
    case goFind(partnerID: String)                           // Find a neighbor during a walk.
    case leave                                               // Request leave.
    case rename(landmarkID: String, newName: String)         // Rename a landmark.
    case report(ReportKind)                                  // Report a local issue.
    case broadcast(String)                                   // Relay a location phrase during finding, such as being at the pavilion.
    // Added 2026-10-07 by A, pending B's agreement: reschedule/cancel. Empty partnerID selects the nearest meetup.
    case changeMeetup(partnerID: String?, day: Int?, hour: Int?, landmarkID: String?)   // Examples: change to 4 pm or move the meeting to the pavilion.
    case cancelMeetup(partnerID: String?)                                                 // Example: cancel the meetup with Mrs Chan.
    case unknown
}

/// Minimal context available to the template/model.
struct AIContext {
    var residents: [Resident]
    var landmarks: [Landmark]
    var now: Date
    var walking: Bool
    var finding: Bool
}

/// AIService contract supplied by B. TemplateAI provides the local template implementation; model integration can implement the same protocol.
protocol AIService {
    func parseVoice(_ transcript: String, context: AIContext) -> VoiceIntent
    func dailyLine(for resident: Resident, passed: [Landmark]) -> String
    func nameLandmark(_ c: LandmarkCandidate) -> String
    func alternativeNames(for l: Landmark) -> [String]
    func pickMeetupSpot(me: Resident, partner: Resident, date: Date, landmarks: [Landmark], shade: ShadeProviding) -> MeetProposal?
    func walkAdvice(weather: Weather, now: Date, shadeTip: (landmark: Landmark, shadedFrom: Int?)?) -> String?
    /// reports includes anonymous reports from other estate residents; stats contains A/backend-computed aggregates. stats added 2026-10-07, pending B's confirmation.
    func monthlyReport(placeName: String, reports: [Report], landmarks: [Landmark], stats: MonthlyStats) -> MonthlyReport
}

/// A supplies a landmark's shade fraction (0–1) for a requested time.
protocol ShadeProviding {
    func shade(landmarkID: String, at date: Date) -> Double
}

/// B supplies pairing: SimulatedBumpService in demo mode and NearbyBumpService/UWB on devices, adapted from B's UWBMeetDemo.
/// 2026-10-10 device integration adds onUpdate for distance/failures and changes onFound from Resident to BumpMatch.
/// Demo returns a simulated resident; device mode returns backend LinkedPeer. Types are in Domain/BumpEvents.swift.
@MainActor
protocol BumpService: AnyObject {
    func startSearching(candidates: [Resident], onUpdate: @escaping (BumpUpdate) -> Void, onFound: @escaping (BumpMatch) -> Void)
    func cancel()
}

/// A establishes the neighbor relationship after pairing; call on the main thread.
@MainActor
protocol NeighborRegistry: AnyObject {
    func createNeighbor(_ residentID: String, remind: Bool)
}

/// B supplies speech synthesis.
protocol Speaking {
    func speak(_ text: String)
}
