import SwiftUI

// F5 device UWB pairing with QR fallback (2026-10-10).
// UI: BumpView in UI/FullScreen.swift and QR screens in UI/BumpQRViews.swift.
// startBump()/cancelBump() remain in AppStore+Neighbors.
extension AppStore {
    /// Demo uses simulated neighbors; normal mode uses device UWB.
    var bump: BumpService { community.isSimulated ? simulatedBump : nearbyBump }

    /// Backend for bump/QR pairing, defined in NeighborLinking.swift.
    /// Automatically use CommunityService when it implements NeighborLinker, as SupabaseCommunityService does.
    /// If pairing uses a separate backend object, replace this selection point.
    /// Without a backend, Debug uses LocalTestLinker; Release reports unavailable server instead of simulating success.
    var linker: NeighborLinker? {
        if let l = community as? NeighborLinker { return l }
        #if DEBUG
        return LocalTestLinker.shared
        #else
        return nil
        #endif
    }

    // MARK: - Proximity pairing

    /// Start/retry pairing after bumpStage is searching and the full-screen view is open.
    func beginBumpSearch() {
        stopBumpWork()
        bumpQR = nil
        bumpProgress = .searching
        nearbyBump.linker = linker
        bump.startSearching(candidates: residents, onUpdate: { [weak self] u in
            self?.bumpUpdated(u)
        }, onFound: { [weak self] m in
            self?.bumpMatched(m)
        })
        // Unsupported hardware fails immediately; do not first instruct the user to approach.
        if bumpProgress == .searching { say(L.t("將手機貼近對方手機。", "把手机贴近对方的手机。")) }
    }

    /// Stop all bump/QR work without changing the screen.
    func stopBumpWork() {
        simulatedBump.cancel()
        nearbyBump.cancel()
        bumpTask?.cancel()
        bumpTask = nil
    }

    func bumpUpdated(_ u: BumpUpdate) {
        guard bumpStage == .searching, bumpQR == nil else { return }
        let old = bumpProgress
        bumpProgress = u
        switch u {
        case .ranging:
            if case .ranging = old {} else { Haptics.light(); say(L.t("搵到對方部手機，慢慢貼近啲。", "找到对方的手机了，慢慢靠近些。")) }
        case .nearMe:
            if old != .nearMe { Haptics.select() }
        case .needsLocalNetwork:
            if old != u { say(L.t("要允許「本地網絡」，先搵到對方部手機。", "要允许「本地网络」，才能找到对方的手机。")) }
        case .failed(let f):
            Haptics.warning()
            say("\(f.title)。\(f.hint)")
        case .searching, .linking, .paired:
            break
        }
    }

    func bumpMatched(_ m: BumpMatch) {
        guard bumpStage == .searching else { return }
        switch m {
        case .demo(let r): bumpQR = nil; bumpMet(r)
        case .linked(let p): finishLinked(p)
        }
    }

    /// Briefly show pairing success, then call addLinkedNeighbor for insertion, speech, and reminder consent.
    func finishLinked(_ p: LinkedPeer) {
        guard bumpStage == .searching else { return }
        bumpProgress = .paired
        bumpQR?.linking = false
        bumpQR?.paired = true
        Haptics.success()
        bumpTask?.cancel()
        bumpTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.9))
            guard let self, !Task.isCancelled, self.bumpStage == .searching else { return }
            self.bumpQR = nil
            self.addLinkedNeighbor(p)
            // addLinkedNeighbor should exit pairing, for example via bumpStage=.found; close it here if necessary.
            if self.bumpStage == .searching { self.bumpStage = .idle; self.syncScene() }
        }
    }

    // MARK: - QR fallback when either phone lacks usable UWB

    /// Stop proximity pairing and choose display/scan.
    func bumpUseQR() {
        stopBumpWork()
        bumpQR = BumpQRState(mode: .choose)
        say(L.t("一部手機出示二維碼，另一部掃。", "一台手机出示二维码，另一台扫。"))
    }

    /// Display a QR while polling the backend; rotate the code before its two-minute expiry.
    func bumpShowQR() {
        stopBumpWork()
        let code = PairCode.random()
        bumpQR = BumpQRState(mode: .show(code))
        say(L.t("請對方用佢部手機掃呢個二維碼。", "请对方用他的手机扫这个二维码。"))
        bumpTask = Task { [weak self] in await self?.waitForScan(code) }
    }

    /// Open the scanner. Debug simulators can use -bumpScanCode jiefong:<32-character code> without a camera.
    func bumpScanQR() {
        stopBumpWork()
        bumpQR = BumpQRState(mode: .scan)
        say(L.t("將鏡頭對住對方嘅二維碼。", "把镜头对准对方的二维码。"))
        #if DEBUG
        if let fake = LaunchArgs.value("-bumpScanCode") {
            bumpTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.qrScanned(fake)
            }
        }
        #endif
    }

    /// Handle scanned content, which may not be a StreetWalk QR.
    func qrScanned(_ payload: String) {
        guard let q = bumpQR, q.mode == .scan, !q.linking, !q.paired else { return }
        guard let code = PairCode.parseQR(payload) else {
            let s = L.t("呢個唔係街坊行嘅二維碼。請對方撳「出示二維碼」。", "这不是街坊行的二维码。请对方按「出示二维码」。")
            if q.note != s { Haptics.warning(); say(s) }
            bumpQR?.note = s
            return
        }
        guard code != q.rejected else { return }   // Do not repeatedly retry the code that just failed.
        bumpQR?.linking = true
        bumpQR?.note = nil
        Haptics.select()
        bumpTask?.cancel()
        bumpTask = Task { [weak self] in await self?.linkScanned(code) }
    }

    private func waitForScan(_ first: String) async {
        if community.isSimulated { await demoQRMatch(after: 3); return }
        guard let linker else { qrFailed(L.t("未連到伺服器，呢個版本加唔到街坊。", "未连接服务器，这个版本加不了邻居。")); return }
        var code = first
        while !Task.isCancelled {
            do {
                if let p = try await LinkPolling.poll(linker, code: code, timeout: BumpTuning.qrRotate) {
                    finishLinked(p)
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                bumpQR?.note = L.t("網絡有問題，再試緊…", "网络有问题，正在重试…")
            }
            guard !Task.isCancelled, bumpQR?.mode == .show(code) else { return }
            code = PairCode.random()   // Expired: generate a new code and wait again.
            bumpQR?.mode = .show(code)
        }
    }

    private func linkScanned(_ code: String) async {
        if community.isSimulated { await demoQRMatch(after: 1); return }
        guard let linker else { qrFailed(L.t("未連到伺服器，呢個版本加唔到街坊。", "未连接服务器，这个版本加不了邻居。")); return }
        do {
            if let p = try await LinkPolling.poll(linker, code: code) {
                finishLinked(p)
            } else {
                bumpQR?.rejected = code
                qrFailed(L.t("配對唔到。請對方撳「出示二維碼」換個新嘅，再掃一次。", "配对不上。请对方按「出示二维码」换个新的，再扫一次。"))
            }
        } catch is CancellationError {
        } catch {
            qrFailed(L.t("網絡有問題，睇下有冇上網，再掃一次。", "网络有问题，看看有没有联网，再扫一次。"))
        }
    }

    /// Demo QR pairing is also simulated and eventually selects the first non-neighbor demo resident.
    private func demoQRMatch(after seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled, bumpStage == .searching else { return }
        guard let r = residents.first(where: { !$0.isMe && !$0.isNeighbor }) else {
            qrFailed(L.t("圈入面嘅人都已經係你街坊。", "圈里的人都已经是你的邻居了。"))
            return
        }
        bumpQR = nil
        bumpMet(r)
    }

    private func qrFailed(_ s: String) {
        bumpQR?.linking = false
        bumpQR?.note = s
        Haptics.warning()
        say(s)
    }
}
