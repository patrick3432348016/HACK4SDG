import Foundation

/// Contract between proximity/QR pairing and the backend.
/// Both phones obtain the same one-time code through proximity exchange or QR, then call NeighborLinker.link(code:).
/// After both submit, link_neighbor in 001_init.sql establishes mutual neighbor rows and returns the peer profile.
/// Pending pairing returns nil; poll every 1–2 seconds. Both participants can retrieve each other, but a third phone cannot join.

/// Paired peer profile; avatar contains mobility, color, skin, and age.
struct LinkedPeer: Equatable {
    let id: String
    let nickname: String
    let mobility: Mobility
    let colorIndex: Int
    let skinTone: Int
    let ageGroup: AgeGroup
    let block: String?
    let floor: Int?
}

@MainActor
protocol NeighborLinker: AnyObject {
    /// Submit a one-time code, preferably 128 random bits in hex. Return the peer when both have submitted, otherwise nil.
    func link(code: String) async throws -> LinkedPeer?
}
