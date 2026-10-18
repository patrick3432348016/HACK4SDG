import Foundation

/// Supabase backend in Singapore; schema, access rules, and tests are under repository-root supabase/.
/// The publishable key belongs in the app; authorization relies on server RLS, not hiding that key.
enum BackendConfig {
    static let url = URL(string: "https://oajsqhpqsgqnvkgsdjtv.supabase.co")!
    static let publishableKey = "sb_publishable_BgcZ-r4jFWml1kILSiEgWg_HVoL4g3c"
}
