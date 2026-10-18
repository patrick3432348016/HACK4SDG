import Foundation
import Testing
@testable import StreetWalk

// Mac 语音服务器：揀边把声（真人 / 缓存 / 系统）、流式 WAV 解析、搵服务器、组员 B 助手回覆 → 粤语复述卡、待查操作（B 嘅规则）。

struct TTSRouteTests {
    let server = URL(string: "http://192.168.1.20:8765")!
    let file = URL(fileURLWithPath: "/tmp/x.wav")

    @Test func 粤语有服务器就用真人声() {
        #expect(TTSRoute.decide(language: .cantonese, server: server, cached: nil, scripted: false) == .server(server))
    }

    @Test func 手机存咗就唔使网络() {
        #expect(TTSRoute.decide(language: .cantonese, server: nil, cached: file, scripted: false) == .cached(file))
        #expect(TTSRoute.decide(language: .cantonese, server: server, cached: file, scripted: true) == .cached(file))
    }

    @Test func 冇服务器普通话同演示脚本用系统声音() {
        #expect(TTSRoute.decide(language: .cantonese, server: nil, cached: nil, scripted: false) == .system)
        #expect(TTSRoute.decide(language: .mandarin, server: server, cached: nil, scripted: false) == .system)
        #expect(TTSRoute.decide(language: .english, server: server, cached: file, scripted: false) == .system)
        #expect(TTSRoute.decide(language: .cantonese, server: server, cached: nil, scripted: true) == .system, "脚本唔等服务器，画面同声音先对得准")
    }

    @Test func 语速同超时() {
        #expect(TTSRoute.speed(.slow) < TTSRoute.speed(.normal))
        #expect(TTSRoute.speed(.fast) > TTSRoute.speed(.normal))
        #expect(TTSRoute.firstAudioTimeout <= 6)
    }
}

struct StreamingWAVTests {
    func header(rate: Int = 32000, streaming: Bool = true, bits: UInt16 = 16) -> Data {
        var d = Data("RIFF".utf8)
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        u32(streaming ? 0xFFFF_FFFF : 36); d.append(Data("WAVEfmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(bits)
        d.append(Data("data".utf8)); u32(streaming ? 0xFFFF_FFFF : 0)
        return d
    }

    @Test func 头同样本分开几段到都解得返() {
        var p = StreamingWAVParser()
        let pcm: [Int16] = [1, -2, 300, -32768, 32767]
        var bytes = header()
        pcm.forEach { var v = $0.littleEndian; bytes.append(Data(bytes: &v, count: 2)) }
        var out: [Int16] = []
        // 每次喂 3 个字节（头会断开、样本会断开一半）
        var i = 0
        while i < bytes.count {
            out += p.feed(bytes.subdata(in: i..<min(i + 3, bytes.count)))
            i += 3
        }
        #expect(p.sampleRate == 32000)
        #expect(out == pcm)
        #expect(!p.failed)
    }

    @Test func 唔系PCM16就当失败() {
        var p = StreamingWAVParser()
        _ = p.feed(Data("{\"error\":1}".utf8))
        #expect(p.failed)
        var q = StreamingWAVParser()
        _ = q.feed(header(bits: 8))
        #expect(q.failed)
    }

    @Test func 手机缓存档案读得返() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = SpeechAudioCache.key(text: "你好", voiceID: "v1", speed: 1)
        #expect(key != SpeechAudioCache.key(text: "你好", voiceID: "v2", speed: 1), "换声音版本就唔用旧缓存")
        #expect(SpeechAudioCache.file(for: key, in: dir) == nil)
        SpeechAudioCache.store(Data([1, 0, 2, 0]), sampleRate: 32000, key: key, in: dir)
        let f = try #require(SpeechAudioCache.file(for: key, in: dir))
        var p = StreamingWAVParser()
        #expect(p.feed(try Data(contentsOf: f)) == [1, 2])
    }
}

@MainActor
struct VoiceServerTests {
    @Test func 地址补全() {
        #expect(VoiceServer.normalize("192.168.1.20")?.absoluteString == "http://192.168.1.20:8765")
        #expect(VoiceServer.normalize(" http://mac.local:9000/ ")?.absoluteString == "http://mac.local:9000")
        #expect(VoiceServer.normalize("https://abc.trycloudflare.com")?.absoluteString == "https://abc.trycloudflare.com")
        #expect(VoiceServer.normalize("") == nil)
        #expect(VoiceServer.normalize("ftp://x") == nil)
    }

    @Test func 候选次序亲手填先() {
        let found = URL(string: "http://10.0.0.5:8765")!
        let list = VoiceServer.candidates(manual: "10.0.0.9", discovered: [found], simulator: true)
        #expect(list.map(\.absoluteString) == ["http://10.0.0.9:8765", "http://10.0.0.5:8765", "http://127.0.0.1:8765"])
        #expect(VoiceServer.candidates(manual: "", discovered: [found, found], simulator: false) == [found])
    }

    @Test func 服务器状态() {
        let u = URL(string: "http://10.0.0.5:8765")!
        let ready = VoiceServer.Info(service: "jiefong-voice", tts: "sovits", voice_id: "v1", status: "ready", assistant: "supabase")
        #expect(VoiceServer.status(for: u, info: ready) == .connected(u, voiceID: "v1", assistant: true))
        var loading = ready
        loading.status = "loading"
        #expect(VoiceServer.status(for: u, info: loading) == .warming(u))
        #expect(VoiceServer.Status.warming(u).label != VoiceServer.Status.connected(u, voiceID: "v1", assistant: true).label)
        var demo = ready
        demo.assistant = "demo"
        #expect(VoiceServer.status(for: u, info: demo) == .connected(u, voiceID: "v1", assistant: false), "测试模式服务器唔做真约会")
    }
}

/// B 服务器嘅回覆（JSON 照抄服务器格式）。
func assistantReply(_ json: String) throws -> AssistantReply {
    try AssistantCoding.decoder().decode(AssistantReply.self, from: Data(json.utf8))
}

@MainActor
struct AssistantFlowTests {
    let lookup = AssistantFlow.Lookup(
        contactName: { $0 == "fang-id" ? "阿芳" : nil },
        placeName: { ["lm-1": "涼亭", "lm-2": "大樹底"][$0] },
        placeDetail: { id, _ in id == "lm-1" ? "你行 4 分鐘；嗰陣有樓遮住、有櫈" : nil },
        timeLabel: { _ in "聽日下晝 4 點" },
        dayLabel: { _ in "聽日" })
    let cid = String(repeating: "a", count: 32)
    let did = String(repeating: "b", count: 32)

    func reply(_ status: String, command: String = #"{"intent":"invite","contact_query":"阿芳","starts_at":"2026-10-11T16:00:00+08:00","max_walk_minutes":null}"#,
               choices: String = "[]", data: String = "{}", draft: String? = nil, message: String = "请选择") throws -> AssistantReply {
        try assistantReply(#"{"conversation_id":"\#(cid)","status":"\#(status)","message":"\#(message)","speech_text":"\#(message)","command":\#(command),"choices":\#(choices),"draft_id":\#(draft.map { "\"\($0)\"" } ?? "null"),"data":\#(data),"demo":false}"#)
    }

    @Test func 问最多行几耐出建议说法() throws {
        let c = AssistantFlow.card(try reply("needs_input"), lookup: lookup)
        #expect(c.kind == .ask)
        #expect(c.title.contains("阿芳") && c.title.contains("最多行幾耐"))
        #expect(c.chips.contains("最多行十五分鐘"))
        #expect(c.waitsForUser)
    }

    @Test func 冇时间先问时间() throws {
        let c = AssistantFlow.card(try reply("needs_input", command: #"{"intent":"invite","contact_query":"阿芳"}"#), lookup: lookup)
        #expect(c.title == "約阿芳幾時行？")
        #expect(!c.chips.isEmpty)
    }

    @Test func 揀地点用手机嘅粤语说明() throws {
        let choices = #"[{"id":"lm-1","label":"涼亭","detail":"你步行 4 分钟"},{"id":"lm-9","label":"测试·广场","detail":"你步行 9 分钟"}]"#
        let c = AssistantFlow.card(try reply("choose_place", choices: choices), lookup: lookup)
        #expect(c.kind == .choosePlace)
        #expect(c.options.map(\.label) == ["涼亭", "測試·廣場"], "手机冇嘅地点：用 B 嘅字转繁体")
        #expect(c.options[0].detail == "你行 4 分鐘；嗰陣有樓遮住、有櫈")
        #expect(c.options[1].detail == "你步行 9 分鐘")
    }

    @Test func 复述卡要撳好() throws {
        let data = #"{"action":{"kind":"invite","contact_id":"fang-id","place_id":"lm-1","starts_at":"2026-10-11T16:00:00+08:00","max_walk_minutes":15,"prefer_shade":false}}"#
        let c = AssistantFlow.card(try reply("needs_confirmation", data: data, draft: did), lookup: lookup)
        #expect(c.kind == .confirm)
        #expect(c.title == "約阿芳聽日下晝 4 點一齊行")
        #expect(c.detail?.contains("涼亭") == true)
        #expect(c.detail?.contains("佢應承先算約好") == true)
        #expect(c.detail?.contains("揀呢度係因為：你行 4 分鐘；嗰陣有樓遮住、有櫈。") == true, "F7：一句话讲点解揀呢度")
        #expect(c.spoken.contains("揀呢度係因為"))
        #expect(c.draftID == did)
        #expect(c.action?.placeID == "lm-1")
        #expect(c.action?.contactID == "fang-id")
        #expect(c.action?.startsAt == AssistantFlow.parseDate("2026-10-11T08:00:00Z"))
    }

    @Test func 理由包成一句() {
        #expect(TemplateAI.whyHere("嗰陣有樓遮住、有櫈、") == "揀呢度係因為：嗰陣有樓遮住、有櫈。")
        #expect(TemplateAI.whyHere("  ") == "")
    }

    @Test func 结果未知唔准再做() throws {
        let c = AssistantFlow.card(try reply("uncertain", draft: did), lookup: lookup)
        #expect(c.kind == .uncertain)
        #expect(c.waitsForUser)
        let failed = AssistantFlow.card(try reply("info", data: #"{"operation_status":"failed","receipt_id":null}"#), lookup: lookup)
        #expect(failed.kind == .failed)
        #expect(!failed.title.contains("好咗"))
    }

    @Test func 听唔明交返手机模板() throws {
        let help = try reply("info", command: #"{"intent":"help"}"#, message: "可以说")
        #expect(AssistantFlow.card(help, lookup: lookup).kind == .notUnderstood)
        #expect(AssistantFlow.shouldFallBack(help, local: .invite(partnerID: "fang-id", day: 1, hour: 16)))
        #expect(!AssistantFlow.shouldFallBack(help, local: .unknown))
        #expect(AssistantFlow.shouldAsk(.invite(partnerID: "x", day: 0, hour: nil)))
        #expect(AssistantFlow.shouldAsk(.unknown))
        #expect(!AssistantFlow.shouldAsk(.leave), "请假喺手机即时做（可撤回）")
        #expect(!AssistantFlow.shouldAsk(.rename(landmarkID: "lm-1", newName: "大樹底")), "地标改名系手机功能")
        #expect(!AssistantFlow.shouldAsk(.report(.sunny)))
    }

    @Test func 完成讲清楚只系邀请() {
        let a = AssistantCard.Action(kind: "invite", contactID: "fang-id", placeID: "lm-1", startsAt: nil)
        let t = AssistantFlow.doneTitle(a, contactName: "阿芳", timeLabel: "聽日下晝 4 點", place: "涼亭")
        #expect(t == "約咗阿芳聽日下晝 4 點喺涼亭，等緊佢確認。")
    }
}

/// 假服务器（URLProtocol）：测 B 嘅「撳好之前先记低、未知就只准查」。
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String)?)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let (code, body) = Self.handler?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct AssistantSessionTests {
    let draft = String(repeating: "c", count: 32)
    let conv = String(repeating: "d", count: 32)

    func session() -> (AssistantSession, UserDefaults) {
        let d = UserDefaults(suiteName: "assistant-test-\(UUID().uuidString)")!
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        let s = AssistantSession(defaults: d)
        s.configure(baseURL: URL(string: "http://127.0.0.1:8765")!, userID: "me", session: URLSession(configuration: cfg)) { "token" }
        return (s, d)
    }

    func body(_ status: String) -> String {
        #"{"conversation_id":"\#(conv)","status":"\#(status)","message":"m","speech_text":"m","command":{"intent":"invite"},"choices":[],"draft_id":"\#(draft)","data":{"operation_status":"committed","receipt_id":"r1"},"demo":false}"#
    }

    @Test func 撳好断线之后只准查结果() async throws {
        let (s, d) = session()
        StubProtocol.handler = { _ in nil }   // 断线
        await #expect(throws: (any Error).self) { try await s.confirm(draftID: draft) }
        #expect(s.unresolvedDraftID == draft, "送出前已经记低")
        #expect(d.string(forKey: "MobilityAssistant.pending.supabase:me:http://127.0.0.1:8765") == draft)
        await #expect(throws: AssistantAPIError.self) { try await s.turn("約阿芳") }
        // 查结果：服务器话做好咗 → 清走待查
        var paths: [String] = []
        StubProtocol.handler = { req in paths.append(req.url!.path); return (200, body("completed")) }
        let r = try await s.reconcile()
        #expect(r?.status == .completed)
        #expect(paths == ["/v1/drafts/\(draft)/reconcile"], "只查，唔会再 confirm")
        #expect(s.unresolvedDraftID == nil)
        StubProtocol.handler = nil
    }

    @Test func 换用户唔读人哋嘅待查操作() {
        let (s, d) = session()
        d.set(draft, forKey: "MobilityAssistant.pending.supabase:other:http://127.0.0.1:8765")
        #expect(s.unresolvedDraftID == nil)
        s.configure(baseURL: URL(string: "http://127.0.0.1:8765")!, userID: "other") { "t" }
        #expect(s.unresolvedDraftID == draft)
    }
}
