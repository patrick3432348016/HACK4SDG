import Foundation

#if DEBUG
/// -scriptBump exercises the real flow's fallback in a simulator without UWB / camera for screenshot inspection.
/// Usage: ./tools/run.sh -demoMode NO -skipOnboarding -resetData -scriptBump -bumpScanCode jiefong:<32 hexadecimal characters>
/// -demoMode NO selects device pairing; LocalTestLinker simulates a peer match after 3 seconds.
extension AppStore {
    func runScriptBump() {
        // -scriptBump with -uiPreview bumpSearching / bumpRanging / bumpTimeout renders states without UWB or server access.
        // After 12 seconds, bumpSearching shows a slow-search explanation and a prominent QR button.
        if let p = LaunchArgs.value("-uiPreview"), p.hasPrefix("bump") {
            Task { @MainActor in
                while map == nil { try? await Task.sleep(for: .milliseconds(200)) }
                tab = .neighbors
                bumpStage = .searching
                switch p {
                case "bumpTimeout": bumpProgress = .failed(.timeout)
                case "bumpRanging": bumpProgress = .ranging(0.42)
                default: bumpProgress = .searching
                }
            }
            return
        }
        Task { @MainActor in
            while map == nil { try? await Task.sleep(for: .milliseconds(200)) }
            let t0 = Date()
            @MainActor func step(_ at: Double, _ name: String, _ action: () -> Void) async {
                let wait = at - Date().timeIntervalSince(t0)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                print("[scriptBump] t=\(at) \(name) progress=\(bumpProgress) qr=\(String(describing: bumpQR)) stage=\(bumpStage)")
                action()
            }
            await step(1, "街坊頁") { tab = .neighbors }
            await step(3, "碰一碰（模擬器冇超寬頻）") { startBump() }
            await step(7, "用二維碼") { bumpUseQR() }
            await step(10, "出示二維碼") { bumpShowQR() }
            await step(20, "開出門提醒") { if let id = remindPromptFor { createNeighbor(id, remind: true) } }
            await step(23, "再碰一碰") { startBump() }
            await step(25, "掃二維碼") { bumpUseQR(); bumpScanQR() }
            await step(37, "唔開提醒") { if let id = remindPromptFor { createNeighbor(id, remind: false) } }
            await step(40, "完") { print("[scriptBump] 街坊：\(neighbors.map { "\($0.name) \($0.floorLabel)" })") }
        }
    }
}
#endif
