import AppKit
import SwiftUI
import WebKit

@MainActor
final class LocalServer: ObservableObject {
    @Published var url: URL?
    @Published var problem: String?
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()

    func start() {
        guard process == nil else { return }
        guard let path = Bundle.main.object(forInfoDictionaryKey: "AssistantProjectRoot") as? String else {
            problem = "工程路径缺失，请在 Xcode 重新构建。"; return
        }
        let root = URL(fileURLWithPath: path).standardizedFileURL
        let python = root.appendingPathComponent(".venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            problem = "请先运行解压目录内的 macOS/Setup.command 安装 Python 依赖，然后重新打开 App。"; return
        }
        let child = Process(), reader = Pipe(), parent = Pipe()
        child.executableURL = python
        child.arguments = [root.appendingPathComponent("macOS/server.py").path, "--watch-stdin"]
        child.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONIOENCODING"] = "utf-8"
        child.environment = environment
        child.standardOutput = reader
        child.standardError = FileHandle.nullDevice
        child.standardInput = parent
        output = reader; input = parent; process = child
        reader.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            Task { @MainActor [weak self] in self?.consume(data) }
        }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.process != nil else { return }
                self.url = nil
                self.problem = "本机服务已退出。请检查 Private/voice-config.json 或重新运行 Setup.command。"
                self.process = nil
            }
        }
        do { try child.run() }
        catch { stop(); problem = "无法启动 Python，请重新运行 macOS/Setup.command。" }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        guard buffer.count < 65536 else { stop(); problem = "本机服务启动输出异常。"; return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let info = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if info["error"] != nil {
                problem = "配置文件缺失或格式错误，请检查 Private/voice-config.json。"
            }
            if info["ready"] as? Bool == true, let value = info["url"] as? String,
               let target = URL(string: value), target.scheme == "http", target.host == "127.0.0.1", target.port != nil {
                url = target
            }
        }
    }

    func stop() {
        let child = process
        process = nil
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        if child?.isRunning == true { child?.terminate() }
        input = nil; output = nil; url = nil
    }
}

struct AssistantBrowser: NSViewRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(origin: url) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.uiDelegate = context.coordinator
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        let origin: URL
        init(origin: URL) { self.origin = origin }

        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            let local = origin.protocol == "http" && origin.host == "127.0.0.1" && origin.port == self.origin.port
            // WebKit and macOS request permission; never grant camera access.
            decisionHandler(local && frame.isMainFrame && type == .microphone ? .prompt : .deny)
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = action.request.url else { decisionHandler(.cancel); return }
            if target.scheme == origin.scheme && target.host == origin.host && target.port == origin.port {
                decisionHandler(.allow)
            } else {
                if target.scheme == "https", action.navigationType == .linkActivated { NSWorkspace.shared.open(target) }
                decisionHandler(.cancel)
            }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let target = action.request.url, target.scheme == "https" { NSWorkspace.shared.open(target) }
            return nil
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let server = LocalServer()
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { server.stop() }
}

@main
struct VoiceAssistantMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("街坊同行 · 粤语助手") { MainView(server: delegate.server) }
            .defaultSize(width: 1180, height: 860)
    }
}

struct MainView: View {
    @ObservedObject var server: LocalServer
    var body: some View {
        Group {
            if let url = server.url { AssistantBrowser(url: url) }
            else if let problem = server.problem {
                VStack(spacing: 16) { Text("服务尚未启动").font(.title2); Text(problem).multilineTextAlignment(.center) }.padding(40)
            } else { ProgressView("正在启动本机粤语助手…").padding(40) }
        }
        .frame(minWidth: 820, minHeight: 650)
        .task { server.start() }
    }
}
