import Foundation

#if DEBUG
/// -scriptBump exercises the real flow's fallback in a simulator without UWB / camera for screenshot inspection.
/// Usage: ./tools/run.sh -demoMode NO -skipOnboarding -resetData -scriptBump -bumpScanCode jiefong:<32 hexadecimal characters>
/// -demoMode NO selects device pairing; LocalTestLinker simulates a peer match after 3 seconds.
extension AppStore {
    func runScriptBump() {
        Task { @MainActor in
            while map == nil { try? await Task.sleep(for: .milliseconds(200)) }
            let t0 = Date()
            @MainActor func step(_ at: Double, _ name: String, _ action: () -> Void) async {
                let wait = at - Date().timeIntervalSince(t0)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                print("[scriptBump] t=\(at) \(name) progress=\(bumpProgress) qr=\(String(describing: bumpQR)) stage=\(bumpStage)")
                action()
            }
            await step(1, "Neighbors screen") { tab = .neighbors }
            await step(3, "Pairing: simulator has no UWB") { startBump() }
            await step(7, "Use QR code") { bumpUseQR() }
            await step(10, "Show QR code") { bumpShowQR() }
            await step(20, "Enable outing alerts") { if let id = remindPromptFor { createNeighbor(id, remind: true) } }
            await step(23, "Pair again") { startBump() }
            await step(25, "Scan QR code") { bumpUseQR(); bumpScanQR() }
            await step(37, "Decline reminders") { if let id = remindPromptFor { createNeighbor(id, remind: false) } }
            await step(40, "End") { print("[scriptBump] Neighbors: \(neighbors.map { "\($0.name) \($0.floorLabel)" })") }
        }
    }
}
#endif
