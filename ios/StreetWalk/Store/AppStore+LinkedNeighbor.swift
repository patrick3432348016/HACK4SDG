import Foundation

// 【临时】碰一碰 / 二维码配上之后点样加街坊。
// 正式版本由另一位同事（后端整合）实现同一个签名：插入 Resident、标街坊、语音、问出门提醒、同后端同步。
// 整合时整个文件换走；碰一碰模块只调用 addLinkedNeighbor(_:)，喺 bumpStage == .searching（碰一碰画面开住）时调用，
// 正式版本要自己离开碰一碰画面（例如好似演示一样设 bumpStage = .found(id)）；冇嘅话 AppStore+Bump 会收埋画面。
extension AppStore {
    func addLinkedNeighbor(_ peer: LinkedPeer) {
        var r = resident(peer.id) ?? Resident(id: peer.id, name: peer.nickname, floor: peer.floor ?? 0,
                                              blockName: peer.block, colorIndex: peer.colorIndex,
                                              mobility: peer.mobility, streakDays: 0, todayLine: "")
        r.name = peer.nickname
        r.floor = peer.floor ?? r.floor
        r.blockName = peer.block ?? r.blockName
        r.colorIndex = peer.colorIndex
        r.mobility = peer.mobility
        r.skinTone = peer.skinTone
        r.ageGroup = peer.ageGroup
        if let i = residents.firstIndex(where: { $0.id == r.id }) { residents[i] = r } else { residents.append(r) }
        // 同演示一样：场景并排、语音「你同…而家係街坊」、问出门提醒（createNeighbor 先真正标街坊）。
        bumpMet(r)
    }
}
