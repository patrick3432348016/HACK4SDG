import Foundation

/// Interface and speech languages are linked: Mandarin selects the zh-CN system voice (skipping the Mac Cantonese server; see TTSRoute), zh-CN recognition, and the zh-CN assistant locale.
extension AppLang {
    var spoken: SpokenLanguage { self == .cmn ? .mandarin : .cantonese }
}

extension AppLanguage {
    /// Settings changes update the UI immediately, persist the selection, and switch speech.
    @MainActor func choose(_ l: AppLang) {
        set(l)
        VoiceSettings.shared.followAppLanguage()
    }
}

extension VoiceSettings {
    /// Synchronize speech language at startup and whenever UI language changes.
    func followAppLanguage() {
        let want = L.lang.spoken
        if language != want { language = want }
    }
}
