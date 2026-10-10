import SwiftUI

struct ContentView: View {
    @ObservedObject var model: MeetCoordinator
    @State private var showReset = false
    private let green = Color(red: 0.10, green: 0.39, blue: 0.32)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("北都 · 运动伙伴").font(.caption.weight(.semibold)).foregroundStyle(green)
                    Text("靠近一点，\n认识新朋友。").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("独立 UWB 路演原型 · 测试身份与虚构联系方式")
                        .font(.caption).foregroundStyle(.secondary)
                    if !model.supportsUWB {
                        Label("当前设备不支持精确 UWB 测距，无法进行真实演示。", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    if model.phase == .idle || model.phase == .failed { setup }
                    if model.active || model.phase == .success { sessionView }
                    Text(model.status).font(.callout).accessibilityIdentifier("status")
                    if model.phase == .failed {
                        Button("重新设置", action: model.resetSession).buttonStyle(.borderedProminent)
                    }
                    NavigationLink("查看本机演示好友") { FriendsView(store: model.store) }
                    DisclosureGroup("诊断记录（仅状态，不含联系方式）") {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("触发起点：≤ 0.30 m，连续 0.50 s；不是已验证参数。")
                            ForEach(Array(model.logs.enumerated()), id: \.offset) { _, item in
                                Text(item).font(.system(.caption, design: .monospaced))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.caption)
                    Button("重置演示（清除本机测试好友）", role: .destructive) { showReset = true }
                        .font(.footnote)
                }.padding(24)
            }
            .background(Color(red: 0.96, green: 0.97, blue: 0.94))
            .tint(green)
            .alert("清除本机演示好友？", isPresented: $showReset) {
                Button("取消", role: .cancel) {}
                Button("重置", role: .destructive, action: model.resetDemo)
            } message: { Text("仅清除这个独立程序的测试记录。另一台手机需单独重置。") }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("演示名片", selection: $model.isPatrick) {
                Text("Patrick").tag(true)
                Text("小陈").tag(false)
            }.pickerStyle(.segmented)
            Button("我是发起方", systemImage: "antenna.radiowaves.left.and.right") { model.start(host: true) }
                .buttonStyle(.borderedProminent).disabled(!model.supportsUWB)
            Text("另一台手机：输入本轮配对码（可在演示前准备）").font(.caption)
            TextField("XXXXX-XXXXX-XXXXX-XXXXX", text: $model.joinCode)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.characters)
                .autocorrectionDisabled().font(.system(.body, design: .monospaced))
            Button("加入这次演示") { model.start(host: false) }
                .buttonStyle(.bordered).disabled(!model.supportsUWB || !PeerTransport.validCode(model.joinCode))
        }
    }

    private var sessionView: some View {
        VStack(spacing: 18) {
            if !model.hostCode.isEmpty && model.phase == .searching {
                Text("一次性配对码 · 请当面交给另一位演示者").font(.caption)
                Text(model.hostCode).font(.system(.title3, design: .monospaced)).textSelection(.enabled)
            }
            if model.phase == .searching || model.phase == .ranging {
                ZStack {
                    Circle().stroke(green.opacity(0.15), lineWidth: 12)
                    Circle().trim(from: 0, to: progress).stroke(green, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 8) {
                        Image(systemName: "iphone.radiowaves.left.and.right").font(.largeTitle)
                        if let distance = model.distance, distance.isFinite, distance >= 0 {
                            Text(String(format: "%.2f m", distance)).font(.system(.title, design: .rounded))
                        } else { Text("等待测距").font(.headline) }
                        Text("真实 UWB 读数").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(width: 220, height: 220).animation(.easeOut(duration: 0.2), value: progress)
            }
            if let peer = model.peer, [.confirming, .exchanging, .success].contains(model.phase) {
                Image(systemName: peer.symbol).font(.system(size: 48)).foregroundStyle(green)
                Text(peer.name).font(.title2.bold())
                Text(peer.interests.joined(separator: " · ")).foregroundStyle(.secondary)
                if !model.commonInterests.isEmpty { Text("共同兴趣：\(model.commonInterests)").font(.callout) }
                if model.phase == .confirming {
                    Toggle("分享演示微信号", isOn: $model.shareWechat).disabled(model.localConsent)
                    Toggle("分享演示 WhatsApp 字段", isOn: $model.shareWhatsApp).disabled(model.localConsent)
                    Text("分享的都是虚构测试值，不会读取手机联系人。").font(.caption).foregroundStyle(.secondary)
                    Button(model.localConsent ? "等待对方确认" : "确认成为运动伙伴", action: model.confirm)
                        .buttonStyle(.borderedProminent).disabled(model.localConsent)
                    Text(model.peerConsent ? "对方已确认" : "对方尚未确认").font(.caption)
                }
            }
            if model.phase == .exchanging { ProgressView("交换并保存中…") }
            if model.phase == .success {
                Label("已成为运动伙伴", systemImage: "checkmark.circle.fill")
                    .font(.title2.bold()).foregroundStyle(green)
                Text("请同时查看另一台手机；本机结果不能替代双机验收。").font(.caption)
                Button("结束本轮", action: model.resetSession).buttonStyle(.bordered)
            } else {
                Button("取消本轮", role: .destructive, action: model.cancel)
            }
        }.frame(maxWidth: .infinity).padding(20).background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private var progress: CGFloat {
        guard let d = model.distance, d.isFinite, d >= 0 else { return 0.03 }
        return CGFloat(max(0.03, min(1, 1 - d / 2)))
    }
}

struct FriendsView: View {
    @ObservedObject var store: FriendStore
    var body: some View {
        List {
            if let error = store.error { Text(error).foregroundStyle(.red) }
            if store.friends.isEmpty { Text("还没有演示好友。完成双机确认后会保存在这里。") }
            ForEach(store.friends) { friend in
                VStack(alignment: .leading, spacing: 8) {
                    Label(friend.contact.profile.name, systemImage: friend.contact.profile.symbol).font(.headline)
                    Text(friend.acknowledged ? "本机已保存 · 已收到对方保存回执" : "本机已接收 · 尚未完成双向确认")
                        .font(.caption).foregroundStyle(friend.acknowledged ? .green : .orange)
                    if let wechat = friend.contact.wechat { Text("微信（虚构）：\(wechat)").textSelection(.enabled) }
                    if let whatsapp = friend.contact.whatsapp { Text("WhatsApp（虚构）：\(whatsapp)") }
                    if friend.contact.wechat == nil && friend.contact.whatsapp == nil { Text("对方未分享联系方式") }
                }.padding(.vertical, 6)
            }
        }.navigationTitle("本机演示好友")
    }
}
