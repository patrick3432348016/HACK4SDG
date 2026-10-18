import SwiftUI
import UIKit

// Frequent Sound controls: enable, three speeds and preview.
// VoiceAdvancedSections places server, voice selection and download instructions under Advanced.

struct VoiceSettingsSection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var v = VoiceSettings.shared
        Section {
            Toggle(isOn: $v.enabled) { Text(L.t("語音播報", "语音播报", "Read aloud")) }
                .tint(DS.accent)
                .frame(minHeight: 52)
            // Speech follows the top-level App language; do not provide an independent language selector here.
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("語速", "语速", "Speed"))
                BigSegments(options: SpeechPace.allCases, selection: Binding(get: { v.pace }, set: { p in
                    v.pace = p
                    store.previewVoice(v.active, current: true)
                }), label: \.label)
            }
            .padding(.vertical, 8)
            PreviewButton(speaker: store.speaker) { store.previewVoice(v.active, current: true) }
                .padding(.vertical, 4)
        } header: {
            Text(L.t("聲音", "声音", "Voice")).ds(.caption)
        } footer: {
            Text(v.enabled ? L.t("有人約你、街坊出門、改約等新消息，開住 App 時會讀出嚟（靜音模式都會讀，大細聲跟手機音量）。", "有人约你、邻居出门、改约等新消息，开着 App 时会读出来（静音模式也会读，音量跟手机音量）。", "When the app is open, news is read aloud: invites, neighbours going out, changed plans. Works in silent mode too. Volume follows your phone.") : L.t("閂咗：唔會自動讀出嚟，字照樣喺畫面顯示；撳「再聽一次」仍然會讀。", "关闭后：不会自动读出来，文字照样在画面显示；点「再听一次」仍然会读。", "Off: nothing is read out by itself. Text still shows on screen. Tap \"Hear again\" to listen."))
                .ds(.caption)
        }
        .id("voice")
    }
}

/// Preview button turns orange and shows playing during output, resets on completion/interruption, and stops on a second tap.
/// key identifies current, assistant or a system voice ID; only that button changes state.
struct PreviewButton: View {
    @ObservedObject var speaker: Speaker
    var key = "current"
    var title = L.t("試聽", "试听", "Preview")
    var wide = true
    var action: () -> Void

    var body: some View {
        let on = speaker.previewing && speaker.previewKey == key
        Button { on ? speaker.stop() : action() } label: {
            Label(on ? L.t("播緊⋯", "正在播放…", "Playing…") : title, systemImage: on ? "speaker.wave.2.fill" : "play.fill")
                .labelStyle(.titleAndIcon)
                .symbolEffect(.variableColor.iterative, isActive: on && !DS.reduceMotion)
                .frame(maxWidth: wide ? .infinity : nil)
                .fixedSize(horizontal: !wide, vertical: false)
        }
        .buttonStyle(.dsSecondary)
        .background(on ? DS.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(DS.motion(DS.snappy), value: on)
        .accessibilityHint(on ? L.t("撳一下停", "点一下停止", "Tap to stop") : "")
    }
}

/// Advanced voice controls: server, voice choice and download instructions.
struct VoiceAdvancedSections: View {
    var body: some View {
        let v = VoiceSettings.shared
        VoiceServerSection()

        Section {
            if v.voices.isEmpty {
                Text(v.scanned ? L.t("部手機未有\(v.language.label)聲音。", "手机里还没有\(v.language.label)声音。", "No \(v.language.label) voice on this phone yet.") : L.t("搵緊手機入面嘅聲音⋯", "正在找手机里的声音⋯", "Looking for voices on this phone…")).foregroundStyle(.secondary)
            }
            ForEach(v.voices) { voice in
                VoiceRow(voice: voice, on: v.active?.id == voice.id)
            }
        } header: {
            Text(L.t("揀把聲（\(v.language.label)）", "选声音（\(v.language.label)）", "Choose a voice (\(v.language.label))")).ds(.caption)
        } footer: {
            Text(voiceFooter(v)).ds(.caption)
        }
        .id("voiceList")

        if let up = v.recentUpgrade {
            // After download, show installed state where the guide was instead of removing the section.
            Section { UpgradeDone(voice: up) }.id("voiceGuide")
        } else if v.scanned && !v.hasNaturalVoice {
            Section {
                VoiceDownloadGuide(language: v.language)
            }
            .id("voiceGuide")
        }
    }

    private func voiceFooter(_ v: VoiceSettings) -> String {
        let s = v.isAuto ? L.t("自動用咗最自然嗰把。撳個名就轉用嗰把。", "已自动用最自然的那个。点名字就换成那个。", "The most natural voice is used. Tap a name to switch.") : L.t("撳個名就轉用嗰把。", "点名字就换成那个。", "Tap a name to switch.")
        return s
    }
}

/// Tap a voice name to select and preview; a large separate Preview action sits at right.
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
            .accessibilityLabel(L.t("\(voice.displayName)，\(voice.subtitle)", "\(voice.displayName)，\(voice.subtitle)", "\(voice.displayName), \(voice.subtitle)"))
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityHint(L.t("撳兩下轉用呢把聲", "点两下换成这个声音", "Double-tap to use this voice"))

            PreviewButton(speaker: store.speaker, key: voice.id, wide: false) { store.previewVoice(voice) }
                .accessibilityLabel(L.t("試聽\(voice.displayName)", "试听\(voice.displayName)", "Preview \(voice.displayName)"))
        }
        .padding(.vertical, 4)
    }

    private var subtitle: Text {
        let g: String? = switch voice.gender {
        case .female: L.t("女聲 · ", "女声 · ", "Female · ")
        case .male: L.t("男聲 · ", "男声 · ", "Male · ")
        case .unknown: nil
        }
        return Text(g ?? "").foregroundStyle(.secondary)
            + Text(voice.tier.label).foregroundStyle(voice.tier == .premium ? DS.accentInk : Color.secondary)
    }
}

/// Without enhanced voices, guide users through Settings; the App cannot download them or deep-link directly to the Voices screen.
struct VoiceDownloadGuide: View {
    @Environment(AppStore.self) private var store
    let language: SpokenLanguage

    /// Guide terminology follows iOS 26 Read & Speak versus iOS 18 Spoken Content, checked against Apple Hong Kong support and iOS 26.5 strings.
    static var menuName: String {
        if #available(iOS 26, *) { return L.t("閲讀與朗讀", "阅读与朗读", "Read & Speak") }
        return L.t("語音內容", "朗读内容", "Spoken Content")
    }

    var steps: [String] {
        let (region, names) = switch language {
        case .cantonese: (L.t("中文（香港）", "中文（香港）", "Chinese (Hong Kong)"), L.t("「Wing」或者「善怡」", "「Wing」或「善怡」", "\"Sinji\" or \"Wing\""))
        case .mandarin: (L.t("中文（中國大陸）", "中文（中国大陆）", "Chinese (China mainland)"), L.t("「月」或者「黎瀲」", "「月」或「黎潋」", "\"Yue\" or \"Lilian\""))
        case .english: (L.t("英文（美國）", "英文（美国）", "English (US)"), L.t("「Ava」", "「Ava」", "\"Ava\""))
        }
        let group = language == .english ? L.t("英文", "英文", "English") : L.t("中文", "中文", "Chinese")
        return [
            L.t("撳下面「打開 iPhone 設定」。如果見到「街坊行」嗰頁，撳左上角「‹」返去，直到見到「設定」兩個大字。", "点下面「打开 iPhone 设置」。如果看到「街坊行」那页，点左上角「‹」返回，直到看到「设置」两个大字。", "Tap \"Open iPhone Settings\" below. If you see the StreetWalk page, tap \"‹\" at the top left until you see the big word \"Settings\"."),
            L.t("撳「輔助使用」。", "点「辅助功能」。", "Tap \"Accessibility\"."),
            L.t("撳「\(Self.menuName)」。", "点「\(Self.menuName)」。", "Tap \"\(Self.menuName)\"."),
            L.t("撳「聲音」。", "点「声音」。", "Tap \"Voices\"."),
            L.t("撳「\(group)」，再撳「\(region)」。", "点「\(group)」，再点「\(region)」。", "Tap \"\(group)\", then \"\(region)\"."),
            L.t("揀\(names)：要名後面寫住「優質」嗰個（冇就揀「已強化」）。撳旁邊個雲朵掣下載，等佢下載完。", "选\(names)：要名字后面写着「高音质」的那个（没有就选「增强音质」）。点旁边的云朵按钮下载，等它下载完。", "Pick \(names) marked \"Premium\" (or \"Enhanced\"). Tap the cloud button and wait for the download."),
            L.t("返嚟街坊行，會自動轉用新聲音。", "回到街坊行，会自动换成新声音。", "Come back to StreetWalk. The new voice is used by itself."),
        ]
    }

    var spoken: String {
        L.t("想把聲自然啲，可以喺 iPhone 設定免費下載。", "想让声音更自然，可以在 iPhone 设置里免费下载。", "For a more natural voice, download one free in iPhone Settings.") + steps.enumerated().map { L.t("第\($0.offset + 1)步，\($0.element)", "第\($0.offset + 1)步，\($0.element)", " Step \($0.offset + 1): \($0.element)") }.joined()
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
                Text(L.t("想把聲自然啲？", "想让声音更自然？", "Want a more natural voice?")).ds(.title).accessibilityAddTraits(.isHeader)
            }
            Text(L.t("iPhone 有免費、更自然嘅聲音，要你自己下載一次（大約 50 MB，最好用 Wi-Fi）。", "iPhone 有免费、更自然的声音，需要你自己下载一次（大约 50 MB，最好用 Wi-Fi）。", "iPhone has free, more natural voices. Download one once (about 50 MB, best on Wi-Fi)."))
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
                Text(L.t("打開 iPhone 設定", "打开 iPhone 设置", "Open iPhone Settings")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
            Button { store.sayAgain(spoken) } label: {
                Label(L.t("讀出步驟", "读出步骤", "Read steps aloud"), systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsSecondary)
        }
        .padding(.vertical, 12)
    }
}

/// On return from Settings, the newly installed voice has already been selected.
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
                Text(L.t("裝好咗！", "装好了！", "Installed!")).ds(.title).accessibilityAddTraits(.isHeader)
            }
            Text(L.t("而家用緊「\(voice.displayName)」（\(voice.subtitle)）同你講嘢。", "现在用「\(voice.displayName)」（\(voice.subtitle)）和你说话。", "Now using \"\(voice.displayName)\" (\(voice.subtitle))."))
                .ds(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button { store.previewVoice(voice) } label: {
                Label(L.t("試聽", "试听", "Preview"), systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsSecondary)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}

/// Large segmented controls replace small system Picker labels; selection is orange with white text.
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
    /// The main store wires voice-upgrade announcements during launch.
    func attachVoice() {
        VoiceSettings.shared.onUpgrade = { [weak self] v in self?.voiceUpgraded(v) }
        // Discover the voice server automatically; use system speech when unavailable. See VoiceServer.swift.
        let server = VoiceServer.shared
        speaker.server = server
        speaker.token = { [weak self] in try? await self?.supabase?.api.accessToken() }
        server.onConnected = { [weak self] _ in self?.voiceServerConnected() }
        server.start()
        // Screenshot entry: -voiceSettings voice, voiceList or voiceGuide opens Sound settings.
        if LaunchArgs.has("-voiceSettings") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                showSettings = true
            }
        }
    }

    /// On server connection, warm common phrases and reconcile the previous unresolved assistant operation once.
    func voiceServerConnected() {
        if let url = VoiceServer.shared.speechURL, let v = VoiceServer.shared.voiceID {
            VoicePrewarm.run(server: url, speed: TTSRoute.speed(VoiceSettings.shared.pace), voiceID: v, language: VoiceSettings.shared.language)
        }
        assistantConnected()
    }

    /// Announce automatic selection of the downloaded voice using that voice.
    func voiceUpgraded(_ v: VoiceInfo) {
        toast(L.t("裝好咗新聲音。而家用「\(v.displayName)」同你講嘢。", "装好了新声音。现在用「\(v.displayName)」和你说话。", "New voice installed. Now using \"\(v.displayName)\"."))
    }

    /// Clear queued speech for immediate preview, avoid listening capture, and wait for VoiceOver's button announcement first.
    /// current previews the actual route, including connected Doubao Xiaohe; individual system-voice previews remain separate.
    func previewVoice(_ v: VoiceInfo?, current: Bool = false, text: String? = nil, key: String = "current") {
        // Avoid output during listening and explain why the preview is silent.
        guard !listening else {
            showToastSilently(L.t("聽緊你講嘢，講完先試聽。", "正在听你说话，说完再试听。", "Listening to you. Preview after you finish."))
            return
        }
        announcer.hold(speaker)
        _ = announcer.release()
        let language = VoiceSettings.shared.language
        if UIAccessibility.isVoiceOverRunning {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                if !(current ? speaker.previewCurrent(language: language, text: text, key: key) : speaker.preview(v, language: language)) { volumeHint() }
            }
        } else if !(current ? speaker.previewCurrent(language: language, text: text, key: key) : speaker.preview(v, language: language)) {
            volumeHint()
        }
    }

    /// At zero media volume show text only so guidance does not interrupt the preview.
    private func volumeHint() {
        showToastSilently(L.t("手機音量太細，按側邊「大聲」掣。", "手机音量太小，请按侧边的音量加键。", "Volume is too low. Press the volume up button."))
    }

    /// Do not use the speaking toast helper, which would interrupt newly started preview audio.
    private func showToastSilently(_ s: String) {
        toast = s
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            if self.toast == s { self.toast = nil }
        }
    }
}


/// Voice server Settings supports automatic discovery and manual URL for Doubao recognition, understanding and Xiaohe speech.
private struct VoiceServerSection: View {
    @Environment(AppStore.self) private var store
    @State private var draft = VoiceServer.shared.manualURL
    @FocusState private var editing: Bool

    var body: some View {
        let server = VoiceServer.shared
        Section {
            HStack(spacing: 12) {
                Text(L.t("語音伺服器", "语音服务器", "Voice server"))
                Spacer(minLength: 0)
                Label(server.status.label, systemImage: server.status.isConnected ? "checkmark.circle.fill" : "wifi.slash")
                    .foregroundStyle(server.status.isConnected ? DS.accentInk : Color.secondary)
            }
            .frame(minHeight: 52)
            .accessibilityElement(children: .combine)
            if let u = server.status.url {
                Text(u.host() ?? u.absoluteString).ds(.caption).foregroundStyle(.secondary)
            }
            TextField(L.t("自動搵（或者填地址）", "自动找（或者填地址）", "Auto-find (or type address)"), text: $draft)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($editing)
                .submitLabel(.done)
                .onSubmit { server.manualURL = draft }
                .frame(minHeight: 52)
            if editing || draft != server.manualURL {
                Button(L.t("用呢個地址", "用这个地址", "Use this address")) { server.manualURL = draft; editing = false }
                    .buttonStyle(.dsSecondary)
            }
            if server.speechURL != nil {
                PreviewButton(speaker: store.speaker, key: "assistant", title: L.t("試聽助手把聲", "试听助手的声音", "Preview assistant"), wide: false) {
                    store.previewVoice(nil, current: true, text: L.t("你好，我係街坊行嘅語音助手，有咩想問就撳咪同我講。", "你好，我是街坊行的语音助手，有什么想问就按麦克风跟我说。", "Hello, I'm the StreetWalk voice assistant. Tap the mic and talk to me."), key: "assistant")
                }
            }
        } header: {
            Text(L.t("語音助手（Mac）", "语音助手（Mac）", "Voice assistant (Mac)")).ds(.caption)
        } footer: {
            Text(server.status.isConnected
                 ? (server.earURL != nil
                    ? L.t("撳一下咪就可以一路傾：講完唔使撳，佢講緊嘢你開口就會停。Mac 閂咗會自動轉返手機聽同手機聲音。", "按一下麦克风就可以一直聊：说完不用按，它说话时你开口就会停。Mac 关了会自动换回手机识别和手机声音。", "Tap the mic once to keep chatting. No need to tap after you speak. It stops talking when you start. If the Mac is off, the phone listens and speaks instead.")
                    : L.t("提示用 Mac 上嘅聲音讀；Mac 閂咗會自動轉返手機聲音。", "提示用 Mac 上的声音读；Mac 关了会自动换回手机声音。", "Messages are read in the Mac voice. If the Mac is off, the phone voice is used."))
                 : L.t("Mac 開咗語音伺服器、同一個 Wi-Fi 就會自動搵到；搵唔到可以填 Mac 顯示嘅地址。冇都照用手機聲音。", "Mac 开了语音服务器、连同一个 Wi-Fi 就会自动找到；找不到可以填 Mac 显示的地址。没有也照用手机声音。", "Found by itself when the Mac voice server is on the same Wi-Fi. If not, type the address the Mac shows. Without it, the phone voice is used."))
                .ds(.caption)
        }
        .id("voiceServer")
    }
}
