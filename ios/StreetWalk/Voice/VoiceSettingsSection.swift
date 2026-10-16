import SwiftUI
import UIKit

// 设定页「聲音」：播报开关、语速三档、试听（常用，放上面）；
// 语音服务器、揀把声、教用户去 iPhone 设定下载声音（VoiceAdvancedSections）收喺设定页最底「進階」。

struct VoiceSettingsSection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var v = VoiceSettings.shared
        Section {
            Toggle(isOn: $v.enabled) { Text(L.t("語音播報", "语音播报")) }
                .tint(DS.accent)
                .frame(minHeight: 52)
            // 播报语言跟设定页顶「語言」（AppLanguage.choose），呢度唔再分开揀。
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("語速", "语速"))
                BigSegments(options: SpeechPace.allCases, selection: Binding(get: { v.pace }, set: { p in
                    v.pace = p
                    store.previewVoice(v.active, current: true)
                }), label: \.label)
            }
            .padding(.vertical, 8)
            PreviewButton(speaker: store.speaker) { store.previewVoice(v.active, current: true) }
                .padding(.vertical, 4)
        } header: {
            Text(L.t("聲音", "声音")).ds(.caption)
        } footer: {
            Text(v.enabled ? L.t("有人約你、街坊出門、改約等新消息，開住 App 時會讀出嚟（靜音模式都會讀，大細聲跟手機音量）。", "有人约你、邻居出门、改约等新消息，开着 App 时会读出来（静音模式也会读，音量跟手机音量）。") : L.t("閂咗：唔會自動讀出嚟，字照樣喺畫面顯示；撳「再聽一次」仍然會讀。", "关闭后：不会自动读出来，文字照样在画面显示；点「再听一次」仍然会读。"))
                .ds(.caption)
        }
        .id("voice")
    }
}

/// 「試聽」掣：讲紧就变「正在播放…」（撳咗一定见到反应），讲完变返。
struct PreviewButton: View {
    @ObservedObject var speaker: Speaker
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(speaker.previewing ? L.t("播緊⋯", "正在播放…") : L.t("試聽", "试听"),
                  systemImage: speaker.previewing ? "speaker.wave.2.fill" : "play.fill")
                .symbolEffect(.variableColor.iterative, isActive: speaker.previewing && !DS.reduceMotion)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
        .disabled(speaker.previewing)
        .animation(DS.motion(DS.snappy), value: speaker.previewing)
    }
}

/// 设定页「進階」入面嘅声音部分：语音服务器、揀把声、下载声音指引。
struct VoiceAdvancedSections: View {
    var body: some View {
        let v = VoiceSettings.shared
        VoiceServerSection()

        Section {
            if v.voices.isEmpty {
                Text(v.scanned ? L.t("部手機未有\(v.language.label)聲音。", "手机里还没有\(v.language.label)声音。") : L.t("搵緊手機入面嘅聲音⋯", "正在找手机里的声音⋯")).foregroundStyle(.secondary)
            }
            ForEach(v.voices) { voice in
                VoiceRow(voice: voice, on: v.active?.id == voice.id)
            }
        } header: {
            Text(L.t("揀把聲（\(v.language.label)）", "选声音（\(v.language.label)）")).ds(.caption)
        } footer: {
            Text(voiceFooter(v)).ds(.caption)
        }
        .id("voiceList")

        if let up = v.recentUpgrade {
            // 下载完返嚟：喺指引原位讲「裝好咗」，唔会成段突然唔见
            Section { UpgradeDone(voice: up) }.id("voiceGuide")
        } else if v.scanned && !v.hasNaturalVoice {
            Section {
                VoiceDownloadGuide(language: v.language)
            }
            .id("voiceGuide")
        }
    }

    private func voiceFooter(_ v: VoiceSettings) -> String {
        let s = v.isAuto ? L.t("自動用咗最自然嗰把。撳個名就轉用嗰把。", "已自动用最自然的那个。点名字就换成那个。") : L.t("撳個名就轉用嗰把。", "点名字就换成那个。")
        return s
    }
}

/// 一把声：撳名 = 揀用（顺便试听），右边大「試聽」掣。
private struct VoiceRow: View {
    @Environment(AppStore.self) private var store
    let voice: VoiceInfo
    let on: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button {
                VoiceSettings.shared.choose(voice)
                Haptics.select()
                store.previewVoice(voice)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(on ? DS.accent : Color.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.displayName).ds(.bodyBold)
                        subtitle.ds(.caption)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(voice.displayName)，\(voice.subtitle)")
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityHint(L.t("撳兩下轉用呢把聲", "点两下换成这个声音"))

            Button { store.previewVoice(voice) } label: {
                Label(L.t("試聽", "试听"), systemImage: "play.fill").labelStyle(.titleAndIcon).fixedSize()
            }
            .buttonStyle(.dsSecondary)
            .accessibilityLabel(L.t("試聽\(voice.displayName)", "试听\(voice.displayName)"))
        }
        .padding(.vertical, 4)
    }

    private var subtitle: Text {
        let g: String? = switch voice.gender {
        case .female: L.t("女聲 · ", "女声 · ")
        case .male: L.t("男聲 · ", "男声 · ")
        case .unknown: nil
        }
        return Text(g ?? "").foregroundStyle(.secondary)
            + Text(voice.tier.label).foregroundStyle(voice.tier == .premium ? DS.accentInk : Color.secondary)
    }
}

/// 冇「增強」或以上嘅声：教用户去 iPhone 设定下载（App 冇得代下载，亦冇公开链接直接跳去「聲音」页）。
struct VoiceDownloadGuide: View {
    @Environment(AppStore.self) private var store
    let language: SpokenLanguage

    /// iOS 26 叫「閲讀與朗讀」，iOS 18 叫「語音內容」（Apple 香港支援页面同 iOS 26.5 系统字串核对过）。
    static var menuName: String {
        if #available(iOS 26, *) { return L.t("閲讀與朗讀", "阅读与朗读") }
        return L.t("語音內容", "朗读内容")
    }

    var steps: [String] {
        let (region, names) = switch language {
        case .cantonese: ("中文（香港）", L.t("「Wing」或者「善怡」", "「Wing」或「善怡」"))
        case .mandarin: (L.t("中文（中國大陸）", "中文（中国大陆）"), L.t("「月」或者「黎瀲」", "「月」或「黎潋」"))
        case .english: (L.t("英文（美國）", "英文（美国）"), "「Ava」")
        }
        let group = language == .english ? "英文" : "中文"
        return [
            L.t("撳下面「打開 iPhone 設定」。如果見到「街坊行」嗰頁，撳左上角「‹」返去，直到見到「設定」兩個大字。", "点下面「打开 iPhone 设置」。如果看到「街坊行」那页，点左上角「‹」返回，直到看到「设置」两个大字。"),
            L.t("撳「輔助使用」。", "点「辅助功能」。"),
            L.t("撳「\(Self.menuName)」。", "点「\(Self.menuName)」。"),
            L.t("撳「聲音」。", "点「声音」。"),
            L.t("撳「\(group)」，再撳「\(region)」。", "点「\(group)」，再点「\(region)」。"),
            L.t("揀\(names)：要名後面寫住「優質」嗰個（冇就揀「已強化」）。撳旁邊個雲朵掣下載，等佢下載完。", "选\(names)：要名字后面写着「高音质」的那个（没有就选「增强音质」）。点旁边的云朵按钮下载，等它下载完。"),
            L.t("返嚟街坊行，會自動轉用新聲音。", "回到街坊行，会自动换成新声音。"),
        ]
    }

    var spoken: String {
        L.t("想把聲自然啲，可以喺 iPhone 設定免費下載。", "想让声音更自然，可以在 iPhone 设置里免费下载。") + steps.enumerated().map { "第\($0.offset + 1)步，\($0.element)" }.joined()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 48, height: 48)
                    .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                Text(L.t("想把聲自然啲？", "想让声音更自然？")).ds(.title).accessibilityAddTraits(.isHeader)
            }
            Text(L.t("iPhone 有免費、更自然嘅聲音，要你自己下載一次（大約 50 MB，最好用 Wi-Fi）。", "iPhone 有免费、更自然的声音，需要你自己下载一次（大约 50 MB，最好用 Wi-Fi）。"))
                .ds(.body)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(i + 1)")
                            .ds(.bodyBold)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(DS.accent, in: Circle())
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 8 }
                        Text(s).ds(.body).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Text(L.t("打開 iPhone 設定", "打开 iPhone 设置")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
            Button { store.sayAgain(spoken) } label: {
                Label(L.t("讀出步驟", "读出步骤"), systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsSecondary)
        }
        .padding(.vertical, 12)
    }
}

/// 由 iPhone 设定下载完返嚟：已经自动转用新声音。
private struct UpgradeDone: View {
    @Environment(AppStore.self) private var store
    let voice: VoiceInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.green, in: Circle())
                    .accessibilityHidden(true)
                Text(L.t("裝好咗！", "装好了！")).ds(.title).accessibilityAddTraits(.isHeader)
            }
            Text(L.t("而家用緊「\(voice.displayName)」（\(voice.subtitle)）同你講嘢。", "现在用「\(voice.displayName)」（\(voice.subtitle)）和你说话。"))
                .ds(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button { store.previewVoice(voice) } label: {
                Label(L.t("試聽", "试听"), systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsSecondary)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}

/// 大粒分段掣（系统 Picker 嘅分段字太细）：揀中 = 橙底白字。
struct BigSegments<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { o in
                let on = o == selection
                Button {
                    guard !on else { return }
                    selection = o
                    Haptics.select()
                } label: {
                    Text(label(o))
                        .ds(on ? .bodyBold : .body)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(on ? DS.accent : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

extension AppStore {
    /// 启动时接好：装咗更好嘅声音就讲俾用户知（launch() 调用，只係主 store）。
    func attachVoice() {
        VoiceSettings.shared.onUpgrade = { [weak self] v in self?.voiceUpgraded(v) }
        // Mac 语音服务器（粤语真人声 + 组员 B 嘅助手）：自动搵；搵唔到照用系统声音（Voice/VoiceServer.swift）
        let server = VoiceServer.shared
        speaker.server = server
        speaker.token = { [weak self] in try? await self?.supabase?.api.accessToken() }
        server.onConnected = { [weak self] _ in self?.voiceServerConnected() }
        server.start()
        // 截图用：-voiceSettings [voice|voiceList|voiceGuide] 直接打开设定页嘅「聲音」
        if LaunchArgs.has("-voiceSettings") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                showSettings = true
            }
        }
    }

    /// 连上语音服务器：常用句子叫服务器先合成好（之后即刻出声），上次未知嘅助手操作查一次。
    func voiceServerConnected() {
        if let url = VoiceServer.shared.speechURL, let v = VoiceServer.shared.voiceID {
            VoicePrewarm.run(server: url, speed: TTSRoute.speed(VoiceSettings.shared.pace), voiceID: v)
        }
        assistantConnected()
    }

    /// 由 iPhone 设定下载完返嚟：已经自动转用，讲一声（用新把声讲）。
    func voiceUpgraded(_ v: VoiceInfo) {
        toast(L.t("裝好咗新聲音。而家用「\(v.displayName)」同你講嘢。", "装好了新声音。现在用「\(v.displayName)」和你说话。"))
    }

    /// 试听：清走排紧嘅播报，即刻用呢把声讲试听句子。聆听中唔讲。读屏开着就等佢读完个掣先讲。
    /// current：「聲音」主掣——试听真播报会用嘅声（连到 Mac 就係豆包小何）；「進階」逐把系统声音试听就唔使。
    func previewVoice(_ v: VoiceInfo?, current: Bool = false) {
        // 聆听中唔讲（会录埋入去），但要话俾人知点解冇声
        guard !listening else {
            showToastSilently(L.t("聽緊你講嘢，講完先試聽。", "正在听你说话，说完再试听。"))
            return
        }
        announcer.hold(speaker)
        _ = announcer.release()
        let language = VoiceSettings.shared.language
        if UIAccessibility.isVoiceOverRunning {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                if !(current ? speaker.previewCurrent(language: language) : speaker.preview(v, language: language)) { volumeHint() }
            }
        } else if !(current ? speaker.previewCurrent(language: language) : speaker.preview(v, language: language)) {
            volumeHint()
        }
    }

    /// 媒体音量调到最细：试听有播但听唔到。只出字（唔读，免得盖住试听）。
    private func volumeHint() {
        showToastSilently(L.t("手機音量太細，按側邊「大聲」掣。", "手机音量太小，请按侧边的音量加键。"))
    }

    /// 只出字唔读（toast() 会读出嚟，会截断啱啱开始嘅试听）。
    private func showToastSilently(_ s: String) {
        toast = s
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            if self.toast == s { self.toast = nil }
        }
    }
}


/// 「語音伺服器」：Mac 上嘅語音伺服器（tools/voice_server.sh，組員 B 嘅豆包：識別 + 理解 + 小何聲）。自動搵；搵唔到可以親手填地址。
private struct VoiceServerSection: View {
    @Environment(AppStore.self) private var store
    @State private var draft = VoiceServer.shared.manualURL
    @FocusState private var editing: Bool

    var body: some View {
        let server = VoiceServer.shared
        Section {
            HStack(spacing: 12) {
                Text(L.t("語音伺服器", "语音服务器"))
                Spacer(minLength: 0)
                Label(server.status.label, systemImage: server.status.isConnected ? "checkmark.circle.fill" : "wifi.slash")
                    .foregroundStyle(server.status.isConnected ? DS.accentInk : Color.secondary)
            }
            .frame(minHeight: 52)
            .accessibilityElement(children: .combine)
            if let u = server.status.url {
                Text(u.host() ?? u.absoluteString).ds(.caption).foregroundStyle(.secondary)
            }
            TextField(L.t("自動搵（或者填地址）", "自动找（或者填地址）"), text: $draft)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($editing)
                .submitLabel(.done)
                .onSubmit { server.manualURL = draft }
                .frame(minHeight: 52)
            if editing || draft != server.manualURL {
                Button(L.t("用呢個地址", "用这个地址")) { server.manualURL = draft; editing = false }
                    .buttonStyle(.dsSecondary)
            }
            if server.speechURL != nil {
                Button { store.sayAgain(L.t("你好，我係街坊行嘅語音助手，有咩想問就撳咪同我講。", "你好，我是街坊行的语音助手，有什么想问就按麦克风跟我说。")) } label: {
                    Label(L.t("試聽助手把聲", "试听助手的声音"), systemImage: "play.fill")
                }
                .buttonStyle(.dsSecondary)
            }
        } header: {
            Text(L.t("語音助手（Mac）", "语音助手（Mac）")).ds(.caption)
        } footer: {
            Text(server.status.isConnected
                 ? (server.earURL != nil
                    ? L.t("撳一下咪就可以一路傾：講完唔使撳，佢講緊嘢你開口就會停。Mac 閂咗會自動轉返手機聽同手機聲音。", "按一下麦克风就可以一直聊：说完不用按，它说话时你开口就会停。Mac 关了会自动换回手机识别和手机声音。")
                    : L.t("提示用 Mac 上嘅聲音讀；Mac 閂咗會自動轉返手機聲音。", "提示用 Mac 上的声音读；Mac 关了会自动换回手机声音。"))
                 : L.t("Mac 開咗語音伺服器、同一個 Wi-Fi 就會自動搵到；搵唔到可以填 Mac 顯示嘅地址。冇都照用手機聲音。", "Mac 开了语音服务器、连同一个 Wi-Fi 就会自动找到；找不到可以填 Mac 显示的地址。没有也照用手机声音。"))
                .ds(.caption)
        }
        .id("voiceServer")
    }
}
