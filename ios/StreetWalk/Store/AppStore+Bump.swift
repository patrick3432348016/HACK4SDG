import SwiftUI

// F5 碰一碰：真机超宽带 + 二维码后备（2026-10-10）。
// 画面：UI/FullScreen.swift 嘅 BumpView（碰一碰）、UI/BumpQRViews.swift（二维码）。
// 入口 startBump() / cancelBump() 仍然喺 AppStore+Neighbors。
extension AppStore {
    /// 而家用边个碰一碰：演示模式 = 模拟（碰到示範街坊）；关咗演示模式 = 真机超宽带。
    var bump: BumpService { community.isSimulated ? simulatedBump : nearbyBump }

    /// 碰一碰 / 二维码配对用嘅后端（NeighborLinking.swift）。
    /// 【整合】社区服务实现咗 NeighborLinker（SupabaseCommunityService）就自动用佢，唔使改；
    /// 后端如果係另一个对象，改呢度一行就得。
    /// 未接后端：Debug 版用 LocalTestLinker（本机假扮对方），Release 版冇（画面讲「未連到伺服器」）。
    var linker: NeighborLinker? {
        if let l = community as? NeighborLinker { return l }
        #if DEBUG
        return LocalTestLinker.shared
        #else
        return nil
        #endif
    }

    // MARK: - 碰一碰

    /// 开始（或者「再試」）碰一碰。bumpStage 要已经係 .searching（全屏画面开住）。
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
        // 唔支援嘅手机会即刻报失败：唔好先讲「貼近」再讲「唔支援」。
        // D-4：顶部对顶部会弹「隔空投送」，叫人并排、隔一拳就得（10-18 背对背会叫出 Siri，删咗）。
        if bumpProgress == .searching {
            say(L.t("兩部手機並排擺、隔一個拳頭就得，唔好頂部對頂部。", "两台手机并排放、隔一个拳头就行，不要顶部对顶部。", "Hold the phones side by side, a fist apart. Not top to top."))
        }
    }

    /// 搵咗 BumpTuning.slowSearch 秒都未搵到对方部手机（BumpView 计时叫）：讲一次点样检查，提示可以用二维码（D-5 / D-6）。
    func bumpSearchSlow() {
        guard bumpStage == .searching, bumpQR == nil, bumpProgress == .searching || bumpProgress == .needsLocalNetwork else { return }
        Haptics.light()
        say(L.t("仲未搵到對方。兩部手機都要開住 Wi-Fi 同藍牙，唔使連網絡。或者撳「用二維碼」。",
                "还没找到对方。两台手机都要打开 Wi-Fi 和蓝牙，不用连网络。也可以点「用二维码」。", "Can’t find them yet. Turn on Wi-Fi and Bluetooth on both phones (no internet needed). Or use a QR code."))
    }

    /// 系统唔俾街坊行用流量（设定入面「無線數據 / 流動數據」）：用流量时配对一定失败（D-5）。
    var cellularDenied: Bool { supabase?.cellularDenied == true }

    /// 用流量但系统唔俾：讲清楚去设定开。
    var cellularDeniedHint: String {
        L.t("設定入面未允許「街坊行」用流動數據。撳「去設定」打開「流動數據」（或者將「無線數據」改做「無線局域網與流動網絡」），或者連 Wi-Fi。",
            "设置里没有允许「街坊行」用流量。点「去设置」，把「无线数据」改成「WLAN与蜂窝网络」（或者打开「蜂窝数据」），也可以连上 Wi-Fi。", "StreetWalk isn’t allowed to use mobile data. Tap Open Settings and turn on Mobile Data, or connect to Wi-Fi.")
    }

    /// 停晒碰一碰、二维码嘅工作（唔改画面）。
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
            if case .ranging = old {} else { Haptics.light(); say(L.t("搵到對方部手機，慢慢貼近啲。", "找到对方的手机了，慢慢靠近些。", "Found their phone. Move closer slowly.")) }
        case .nearMe:
            if old != .nearMe { Haptics.select() }
        case .needsLocalNetwork:
            if old != u { say(L.t("要允許「本地網絡」，先搵到對方部手機。", "要允许「本地网络」，才能找到对方的手机。", "Allow Local Network to find their phone.")) }
        case .failed(let f):
            Haptics.warning()
            say("\(f.title)\(L.t("。", "。", ". "))\(f == .network && cellularDenied ? cellularDeniedHint : f.hint)")
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

    /// 配上咗（碰一碰或者二维码）：画面先显示「成功」一阵，再交俾 addLinkedNeighbor（插入街坊、语音、问出门提醒）。
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
            // addLinkedNeighbor 应该自己离开碰一碰画面（例如 bumpStage = .found）；冇嘅话喺度收埋。
            if self.bumpStage == .searching { self.bumpStage = .idle; self.syncScene() }
        }
    }

    // MARK: - 二维码（唔支援超宽带、碰唔到、或者只有一部支援时用）

    /// 「用二維碼」：停碰一碰，揀出示定掃。
    func bumpUseQR() {
        stopBumpWork()
        bumpQR = BumpQRState(mode: .choose)
        say(L.t("一部手機出示二維碼，另一部掃。", "一台手机出示二维码，另一台扫。", "One phone shows a QR code. The other scans it."))
    }

    /// 出示二维码：一路问伺服器，对方扫咗就配上。码快过期（后端 2 分钟）就自动换新码。
    func bumpShowQR() {
        stopBumpWork()
        let code = PairCode.random()
        bumpQR = BumpQRState(mode: .show(code))
        say(L.t("請對方用佢部手機掃呢個二維碼。", "请对方用他的手机扫这个二维码。", "Ask them to scan this QR code with their phone."))
        bumpTask = Task { [weak self] in await self?.waitForScan(code) }
    }

    /// 掃二维码：开镜头。模拟器冇镜头，Debug 版可以用启动参数 `-bumpScanCode jiefong:<32 位码>` 扮扫到。
    func bumpScanQR() {
        stopBumpWork()
        bumpQR = BumpQRState(mode: .scan)
        say(L.t("將鏡頭對住對方嘅二維碼。", "把镜头对准对方的二维码。", "Point the camera at their QR code."))
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

    /// 镜头扫到嘢（可能唔係我哋嘅二维码）。
    func qrScanned(_ payload: String) {
        guard let q = bumpQR, q.mode == .scan, !q.linking, !q.paired else { return }
        guard let code = PairCode.parseQR(payload) else {
            let s = L.t("呢個唔係街坊行嘅二維碼。請對方撳「出示二維碼」。", "这不是街坊行的二维码。请对方按「出示二维码」。", "This isn’t a StreetWalk QR code. Ask them to show their QR code.")
            if q.note != s { Haptics.warning(); say(s) }
            bumpQR?.note = s
            return
        }
        guard code != q.rejected else { return }   // 啱啱配唔到嘅码：唔好不停重试
        bumpQR?.linking = true
        bumpQR?.note = nil
        Haptics.select()
        bumpTask?.cancel()
        bumpTask = Task { [weak self] in await self?.linkScanned(code) }
    }

    private func waitForScan(_ first: String) async {
        if community.isSimulated { await demoQRMatch(after: 3); return }
        guard let linker else { qrFailed(L.t("未連到伺服器，呢個版本加唔到街坊。", "未连接服务器，这个版本加不了邻居。", "No server. This version can’t add neighbours.")); return }
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
                bumpQR?.note = cellularDenied ? cellularDeniedHint : L.t("網絡有問題，再試緊…", "网络有问题，正在重试…", "Network problem, retrying…")
            }
            guard !Task.isCancelled, bumpQR?.mode == .show(code) else { return }
            code = PairCode.random()   // 过咗期：换个新码再等
            bumpQR?.mode = .show(code)
        }
    }

    private func linkScanned(_ code: String) async {
        if community.isSimulated { await demoQRMatch(after: 1); return }
        guard let linker else { qrFailed(L.t("未連到伺服器，呢個版本加唔到街坊。", "未连接服务器，这个版本加不了邻居。", "No server. This version can’t add neighbours.")); return }
        do {
            if let p = try await LinkPolling.poll(linker, code: code) {
                finishLinked(p)
            } else {
                bumpQR?.rejected = code
                qrFailed(L.t("配對唔到。請對方撳「出示二維碼」換個新嘅，再掃一次。", "配对不上。请对方按「出示二维码」换个新的，再扫一次。", "Couldn’t pair. Ask them to show a new QR code, then scan again."))
            }
        } catch is CancellationError {
        } catch {
            qrFailed(cellularDenied ? cellularDeniedHint : L.t("網絡有問題，睇下有冇上網，再掃一次。", "网络有问题，看看有没有联网，再扫一次。", "Network problem. Check you’re online and scan again."))
        }
    }

    /// 演示模式：二维码都係模拟，过一阵「碰到」第一个未係街坊嘅示範街坊。
    private func demoQRMatch(after seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled, bumpStage == .searching else { return }
        guard let r = residents.first(where: { !$0.isMe && !$0.isNeighbor }) else {
            qrFailed(L.t("圈入面嘅人都已經係你街坊。", "圈里的人都已经是你的邻居了。", "Everyone here is already your neighbour."))
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
