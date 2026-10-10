import Foundation

/// 后端（Supabase，新加坡机房）。表结构、权限规则和测试在仓库根目录 supabase/。
/// publishable key 本来就要放喺 App 入面：权限全靠服务器上嘅 RLS，唔靠藏 key。
enum BackendConfig {
    static let url = URL(string: "https://oajsqhpqsgqnvkgsdjtv.supabase.co")!
    static let publishableKey = "sb_publishable_BgcZ-r4jFWml1kILSiEgWg_HVoL4g3c"
}
