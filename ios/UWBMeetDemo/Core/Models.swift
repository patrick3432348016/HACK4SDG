import Foundation

struct PublicProfile: Codable, Equatable {
    let id: UUID
    let name: String
    let symbol: String
    let interests: [String]

    static func demo(id: UUID, isPatrick: Bool) -> Self {
        Self(id: id, name: isPatrick ? "Patrick · 演示" : "小陈 · 演示",
             symbol: isPatrick ? "figure.run" : "figure.badminton",
             interests: isPatrick ? ["跑步", "羽毛球"] : ["散步", "羽毛球"])
    }

    var valid: Bool { !name.isEmpty && name.count <= 40 && symbol.count <= 60 &&
        interests.count <= 8 && interests.allSatisfy { $0.count <= 20 } }
}

struct SharedContact: Codable, Equatable {
    let profile: PublicProfile
    let wechat: String?
    let whatsapp: String?
    var valid: Bool { profile.valid && (wechat?.count ?? 0) <= 80 && (whatsapp?.count ?? 0) <= 40 }
}

struct FriendRecord: Codable, Identifiable {
    var id: UUID { contact.profile.id }
    var contact: SharedContact
    var date: Date
    var exchangeID: String
    var acknowledged: Bool
}

enum MessageKind: String, Codable { case hello, near, consent, contact, receipt, cancel }

struct WireMessage: Codable {
    let version: Int
    let session: UUID
    let sequence: Int
    let kind: MessageKind
    let profile: PublicProfile?
    let token: Data?
    let contact: SharedContact?
}

struct SequenceGuard {
    private var session: UUID?
    private var next = 0
    mutating func accept(_ message: WireMessage) -> Bool {
        guard message.version == 1, message.sequence == next else { return false }
        if let session {
            guard message.session == session, message.kind != .hello else { return false }
        } else {
            guard message.kind == .hello else { return false }
            session = message.session
        }
        next += 1
        return true
    }
}

