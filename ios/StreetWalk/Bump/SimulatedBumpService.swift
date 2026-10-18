import Foundation

/// Member B's demo implementation pairs with the first non-neighbor after 2.2 seconds.
/// Emit simulated distances so the labeled demo follows the real-device approach-to-success UI.
/// Physical-device implementation: NearbyBumpService with UWB and Bonjour.
@MainActor
final class SimulatedBumpService: BumpService {
    private var work: [DispatchWorkItem] = []

    func startSearching(candidates: [Resident], onUpdate: @escaping (BumpUpdate) -> Void, onFound: @escaping (BumpMatch) -> Void) {
        cancel()
        // -videoBumpWith <id> selects the peer for recording, reducing distance from 1.1 m to 0.16 m for synchronized two-phone footage.
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
