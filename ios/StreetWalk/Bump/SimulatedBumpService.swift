import Foundation

/// 成员 B：碰一碰的模拟实现。2 秒后"碰到"第一个还不是街坊的人。
/// 真机版本用 Nearby Interaction（超宽带）+ MultipeerConnectivity 实现同一协议。
final class SimulatedBumpService: BumpService {
    private var work: DispatchWorkItem?

    func startSearching(candidates: [Resident], onFound: @escaping (Resident) -> Void) {
        cancel()
        guard let target = candidates.first(where: { !$0.isMe && !$0.isNeighbor }) else { return }
        let w = DispatchWorkItem { onFound(target) }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: w)
    }

    func cancel() {
        work?.cancel()
        work = nil
    }
}
