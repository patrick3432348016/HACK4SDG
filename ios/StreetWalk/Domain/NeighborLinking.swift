import Foundation

/// 碰一碰 / 二维码配对的约定（碰一碰模块 ↔ 后端模块）。
/// 两部手机经近距离连接（或者扫二维码）拿到同一个一次性码，各自交给 `NeighborLinker.link(code:)`；
/// 服务器（supabase/migrations/001_init.sql 的 link_neighbor）两边都提交咗就写入互为街坊，并返回对方资料。
/// 未配上返回 nil，可以每 1–2 秒再问一次；同一个码两边都查到对方，第三部手机永远配唔上。

/// 配上之后服务器返回嘅对方资料（profiles 表；avatar 是 {"mobility","color","skin","age"}）。
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
    /// 提交一次性配对码（建议 128 bit 随机，十六进制）。对方都提交咗就返回对方；未配上返回 nil。
    func link(code: String) async throws -> LinkedPeer?
}
