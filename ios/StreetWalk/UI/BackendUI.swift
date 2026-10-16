import SwiftUI

// 真后端用到嘅界面：网名（首次使用「樓層同網名」一页、设置、旧用户补填）、「想過嚟搵你，方唔方便？」卡、「未連線」。

// MARK: - 网名

/// 大字输入框 + 一撳就用嘅建议 + 字数。1–20 字。
struct NicknameEditor: View {
    @Environment(AppStore.self) private var store
    @Binding var text: String
    @FocusState private var focused: Bool

    private var count: Int { text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count }
    private var tooLong: Bool { count > CommunityProfile.nicknameLimit }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField(L.t("例如：陳太、李伯", "例如：陈太、李伯"), text: $text)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .padding(.horizontal, 16)
                .frame(minHeight: 72)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .strokeBorder(tooLong ? Color.red : (focused ? DS.accent : Color.primary.opacity(0.12)), lineWidth: focused || tooLong ? 2 : 1))
                .accessibilityLabel(L.t("網名", "网名"))
                .accessibilityHint(L.t("1 至 20 個字", "1 到 20 个字"))

            HStack {
                Text(tooLong ? L.t("太長喇，最多 20 個字", "太长了，最多 20 个字") : L.t("唔使用真名，1 至 20 個字", "不用真名，1 到 20 个字"))
                    .ds(.caption)
                    .foregroundStyle(tooLong ? Color.red : .secondary)
                Spacer(minLength: 8)
                Text("\(count) / \(CommunityProfile.nicknameLimit)")
                    .ds(.caption)
                    .monospacedDigit()
                    .foregroundStyle(tooLong ? Color.red : .secondary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("或者撳一個：", "或者点一个：")).ds(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(store.nicknameSuggestions, id: \.self) { s in
                        let on = text.trimmingCharacters(in: .whitespaces) == s
                        Button {
                            text = s
                            focused = false
                            Haptics.select()
                            store.say(s)
                        } label: {
                            Text(s)
                                .ds(.bodyBold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(on ? DS.accentSoft : Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(on ? DS.accent : Color.primary.opacity(0.08), lineWidth: on ? 3 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L.t("用「\(s)」做網名", "用「\(s)」做网名"))
                    }
                }
            }
        }
    }
}

/// 设置页改网名；旧用户关咗演示模式但未有网名时都用呢张（主界面弹出）。
struct NicknameSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L.t("排行榜上同區嘅人會見到呢個網名。", "排行榜上同区的人会看到这个网名。"))
                        .ds(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    NicknameEditor(text: $text)
                    Button {
                        if store.setNickname(text) {
                            store.say(L.t("好，網名改咗做\(store.nickname)。", "好，网名改成了\(store.nickname)。"))
                            dismiss()
                        }
                    } label: {
                        Text(L.t("好", "好")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsPrimary)
                    .disabled(CommunityProfile.cleanNickname(text) == nil)
                    .opacity(CommunityProfile.cleanNickname(text) == nil ? 0.45 : 1)
                }
                .padding(.horizontal, DS.side)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .principal) { Text(L.t("網名", "网名")).ds(.bodyBold).accessibilityAddTraits(.isHeader) }
                if !store.needsNickname {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Text(L.t("唔改", "不改")).ds(.bodyBold) }.foregroundStyle(DS.accent)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(store.needsNickname)
        .onAppear { text = store.nickname }
    }
}

// MARK: - F8 收到「想過嚟搵你，方唔方便？」

/// 底部卡（要答，唔可以扫走）：大「好」同「唔方便」。
struct IncomingFindCard: View {
    @Environment(AppStore.self) private var store
    @State private var taps = 0

    var body: some View {
        if let ask = store.incomingFind, let p = store.resident(ask.fromID) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    AvatarBadge(p, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("\(p.name)想過嚟搵你，方唔方便？", "\(p.name)想过来找你，方便吗？"))
                            .ds(.bodyBold)
                            .fixedSize(horizontal: false, vertical: true)
                        if let place = store.placeName(ask.landmarkID) {
                            Text(L.t("佢會過去\(place)附近搵你。", "他会去\(place)附近找你。"))
                                .ds(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                Button {
                    taps += 1
                    store.answerIncomingFind(true)
                } label: {
                    Text(L.t("好", "好")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)

                Button {
                    taps += 1
                    store.answerIncomingFind(false)
                } label: {
                    Text(L.t("唔方便", "不方便")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsSecondary)
            }
            .sensoryFeedback(.selection, trigger: taps)
        }
    }
}

// MARK: - 未連線

/// 真后端连唔到（冇网络 / 服务器暂时唔得）：主画面左上细细一粒。写入已经排队，连返就自动送出。
/// 系统唔俾街坊行用流动数据（测试员 D-1 / D-5：开流量都显示「未联网」）：改讲「未允許用流量」，撳一下去设定开。
struct OfflineChip: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.supabase?.cellularDenied == true {
            Button { openSettings() } label: {
                chip(L.t("未允許用流動數據", "没允许用流量"), symbol: "antenna.radiowaves.left.and.right.slash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("街坊行未允許用流動數據", "街坊行没有被允许使用流量"))
            .accessibilityHint(L.t("撳一下去設定，打開「流動數據」或者「無線數據」。", "点一下去设置，打开「无线数据」或「蜂窝数据」。"))
        } else {
            chip(L.t("未連線", "未联网"), symbol: "wifi.slash")
                .accessibilityLabel(L.t("未連線。你做嘅改動會留住，連返網就會送出。", "未联网。你的改动会保留，联网后就会发送。"))
        }
    }

    private func chip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .ds(.captionBold)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.orange.opacity(0.6), lineWidth: 1.5))
    }
}
