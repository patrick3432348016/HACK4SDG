import Foundation

#if DEBUG
/// 开发用（-scriptBump）：喺模拟器（冇超宽带、冇镜头）行一次真机碰一碰嘅后备流程，逐步截图检查。
/// 用法：./tools/run.sh -demoMode NO -skipOnboarding -resetData -scriptBump -bumpScanCode jiefong:<32 位十六进制>
/// （-demoMode NO = 关演示模式，用真机碰一碰；后端用 LocalTestLinker，3 秒后扮对方配上。）
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
