import Foundation
import Combine

final class FriendStore: ObservableObject {
    @Published private(set) var friends: [FriendRecord] = []
    @Published private(set) var error: String?
    private let url: URL

    init() {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("demo-friends.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { friends = try JSONDecoder().decode([FriendRecord].self, from: Data(contentsOf: url)) }
        catch { self.error = "无法读取演示好友记录；请重置记录后重试。" }
    }

    func store(_ contact: SharedContact, exchangeID: String) throws {
        var next = friends.filter { $0.id != contact.profile.id }
        next.insert(FriendRecord(contact: contact, date: Date(), exchangeID: exchangeID, acknowledged: false), at: 0)
        try save(next)
    }

    func acknowledge(_ exchangeID: String) throws {
        var next = friends
        guard let index = next.firstIndex(where: { $0.exchangeID == exchangeID }) else { return }
        next[index].acknowledged = true
        try save(next)
    }

    func reset() throws { try save([]) }

    private func save(_ next: [FriendRecord]) throws {
        do {
            try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtection])
            friends = next
            error = nil
        } catch {
            self.error = "保存失败，不能确认交友完成。"
            throw error
        }
    }
}
