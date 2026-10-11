import Foundation

/// 界面语言同播报语言绑埋：揀普通话 → 系统 zh-CN 声音（Mac 粤语服务器自动跳过，见 TTSRoute）、语音识别 zh-CN、助手 locale zh-CN。
extension AppLang {
    var spoken: SpokenLanguage { self == .cmn ? .mandarin : .cantonese }
}

extension AppLanguage {
    /// 设定页揀语言：界面即时转、存低，播报跟住转。
    @MainActor func choose(_ l: AppLang) {
        set(l)
        VoiceSettings.shared.followAppLanguage()
    }
}

extension VoiceSettings {
    /// 播报语言跟界面语言（启动时同切换时叫）。
    func followAppLanguage() {
        let want = L.lang.spoken
        if language != want { language = want }
    }
}
