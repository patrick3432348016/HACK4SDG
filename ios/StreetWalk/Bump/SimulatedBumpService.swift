import Foundation

/// 成员 B：碰一碰的模拟实现（演示模式）。2.2 秒后"碰到"第一个还不是街坊的人；
/// 中间报几次模拟距离，等演示画面同真机一样由「靠近啲」行到「成功」（画面标明「示範」）。
/// 真机版本：NearbyBumpService（超宽带 + Bonjour）。
@MainActor
final class SimulatedBumpService: BumpService {
    private var work: [DispatchWorkItem] = []

    func startSearching(candidates: [Resident], onUpdate: @escaping (BumpUpdate) -> Void, onFound: @escaping (BumpMatch) -> Void) {
        cancel()
        // 录宣传片（-videoBumpWith <id>）：指定碰边个，距离由 1.1 米慢慢收到 0.16 米（两部手机同步录，剪成两部一齐靠近）
        let want = LaunchArgs.value("-videoBumpWith")
        guard let target = candidates.first(where: { !$0.isMe && !$0.isNeighbor && (want == nil || $0.id == want) }) else { return }
        onUpdate(.searching)
        let steps: [(Double, () -> Void)]
        if want != nil {
            var list: [(Double, () -> Void)] = []
            for i in 0...18 {
                let d = Float(1.1 - 0.94 * Double(i) / 18)
                list.append((0.8 + Double(i) * 0.2, { onUpdate(.ranging(d)) }))
            }
            list.append((4.8, { onUpdate(.linking) }))
            list.append((5.6, { onFound(.demo(target)) }))
            steps = list
        } else {
            steps = [
                (0.7, { onUpdate(.ranging(0.62)) }),
                (1.1, { onUpdate(.ranging(0.38)) }),
                (1.5, { onUpdate(.ranging(0.16)) }),
                (1.9, { onUpdate(.linking) }),
                (2.2, { onFound(.demo(target)) }),
            ]
        }
        for (t, f) in steps {
            let w = DispatchWorkItem(block: f)
            work.append(w)
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: w)
        }
    }

    func cancel() {
        work.forEach { $0.cancel() }
        work = []
    }
}
