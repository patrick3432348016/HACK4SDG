import SwiftUI
import UIKit

// 设定页「聲音」：播报开关、讲粤语定普通话、揀把声（试听）、语速三档；未有自然啲嘅声就教用户去 iPhone 设定下载。

struct VoiceSettingsSection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var v = VoiceSettings.shared
        Section {
            Toggle(isOn: $v.enabled) { Text("語音播報") }
                .tint(DS.accent)
                .frame(minHeight: 52)
            VStack(alignment: .leading, spacing: 12) {
                Text("播報語言")
                BigSegments(options: SpokenLanguage.pickable, selection: Binding(get: { v.language }, set: { l in
                    v.language = l
                    store.previewVoice(v.active)
                }), label: \.label)
            }
            .padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 12) {
                Text("語速")
                BigSegments(options: SpeechPace.allCases, selection: Binding(get: { v.pace }, set: { p in
                    v.pace = p
                    store.previewVoice(v.active)
                }), label: \.label)
            }
            .padding(.vertical, 8)
        } header: {
            Text("聲音").ds(.caption)
        } footer: {
            Text(v.enabled ? "有新消息會讀出嚟。" : "閂咗：唔會自動讀出嚟，字照樣喺畫面顯示；撳「再聽一次」仍然會讀。")
                .ds(.caption)
        }
        .id("voice")

        Section {
            if v.voices.isEmpty {
                Text(v.scanned ? "部手機未有\(v.language.label)聲音。" : "搵緊手機入面嘅聲音⋯").foregroundStyle(.secondary)
            }
            ForEach(v.voices) { voice in
                VoiceRow(voice: voice, on: v.active?.id == voice.id)
            }
        } header: {
            Text("揀把聲（\(v.language.label)）").ds(.caption)
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
        var s = v.isAuto ? "自動用咗最自然嗰把。撳個名就轉用嗰把。" : "撳個名就轉用嗰把。"
        if v.language == .mandarin { s += "提示文字暫時仲係廣東話，普通話版整緊；試聽句子係普通話。" }
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
            .accessibilityHint("撳兩下轉用呢把聲")

            Button { store.previewVoice(voice) } label: {
                Label("試聽", systemImage: "play.fill").labelStyle(.titleAndIcon).fixedSize()
            }
            .buttonStyle(.dsSecondary)
            .accessibilityLabel("試聽\(voice.displayName)")
        }
        .padding(.vertical, 4)
    }

    private var subtitle: Text {
        let g: String? = switch voice.gender {
        case .female: "女聲 · "
        case .male: "男聲 · "
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
        if #available(iOS 26, *) { return "閲讀與朗讀" }
        return "語音內容"
    }

    var steps: [String] {
        let (region, names) = switch language {
        case .cantonese: ("中文（香港）", "「Wing」或者「善怡」")
        case .mandarin: ("中文（中國大陸）", "「月」或者「黎瀲」")
        case .english: ("英文（美國）", "「Ava」")
        }
        let group = language == .english ? "英文" : "中文"
        return [
            "撳下面「打開 iPhone 設定」。如果見到「街坊行」嗰頁，撳左上角「‹」返去，直到見到「設定」兩個大字。",
            "撳「輔助使用」。",
            "撳「\(Self.menuName)」。",
            "撳「聲音」。",
            "撳「\(group)」，再撳「\(region)」。",
            "揀\(names)：要名後面寫住「優質」嗰個（冇就揀「已強化」）。撳旁邊個雲朵掣下載，等佢下載完。",
            "返嚟街坊行，會自動轉用新聲音。",
        ]
    }

    var spoken: String {
        "想把聲自然啲，可以喺 iPhone 設定免費下載。" + steps.enumerated().map { "第\($0.offset + 1)步，\($0.element)" }.joined()
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
                Text("想把聲自然啲？").ds(.title).accessibilityAddTraits(.isHeader)
            }
            Text("iPhone 有免費、更自然嘅聲音，要你自己下載一次（大約 50 MB，最好用 Wi-Fi）。")
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
                Text("打開 iPhone 設定").frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
            Button { store.sayAgain(spoken) } label: {
                Label("讀出步驟", systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity)
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
                Text("裝好咗！").ds(.title).accessibilityAddTraits(.isHeader)
            }
            Text("而家用緊「\(voice.displayName)」（\(voice.subtitle)）同你講嘢。")
                .ds(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button { store.previewVoice(voice) } label: {
                Label("試聽", systemImage: "play.fill").frame(maxWidth: .infinity)
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
        // 截图用：-voiceSettings [voice|voiceList|voiceGuide] 直接打开设定页嘅「聲音」
        if LaunchArgs.has("-voiceSettings") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                showSettings = true
            }
        }
    }

    /// 由 iPhone 设定下载完返嚟：已经自动转用，讲一声（用新把声讲）。
    func voiceUpgraded(_ v: VoiceInfo) {
        toast("裝好咗新聲音。而家用「\(v.displayName)」同你講嘢。")
    }

    /// 试听：清走排紧嘅播报，即刻用呢把声讲试听句子。聆听中唔讲。读屏开着就等佢读完个掣先讲。
    func previewVoice(_ v: VoiceInfo?) {
        guard !listening else { return }
        announcer.hold(speaker)
        _ = announcer.release()
        let language = VoiceSettings.shared.language
        if UIAccessibility.isVoiceOverRunning {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                speaker.preview(v, language: language)
            }
        } else {
            speaker.preview(v, language: language)
        }
    }
}
