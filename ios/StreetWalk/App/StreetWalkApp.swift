import SwiftUI

@main
struct StreetWalkApp: App {
    var body: some Scene {
        WindowGroup {
            SceneDebugView()
        }
    }
}

/// 临时：只看场景效果。
struct SceneDebugView: View {
    @State private var controller = DioramaController()
    @State private var hour: Double = LaunchArgs.hour ?? 10
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            DioramaView(controller: controller, showStats: LaunchArgs.has("-stats"))
                .frame(height: 520)
            Slider(value: $hour, in: 6...19) { Text("時間") }
                .padding()
            Text(String(format: "%02d:%02d", Int(hour), Int((hour - floor(hour)) * 60)))
            Text(controller.debugInfo.map { "\($0.key)=\($0.value)" }.joined(separator: " ")).font(.caption)
            Spacer()
        }
        .onAppear(perform: load)
        .onChange(of: hour) { _, h in setSun(h) }
    }

    private func load() {
        guard !loaded, let url = Bundle.main.url(forResource: "fallback_queenshill", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? OSMParser.parse(data, tile: TileKey(ix: 0, iy: 0), source: "fallback") else { return }
        loaded = true
        let picked = LandmarkDeriver.pick(LandmarkDeriver.candidates(in: map))
        let lms = picked.map { Landmark(id: $0.id, name: $0.osmName ?? $0.kind.rawValue, kind: $0.kind, pos: $0.pos, hasSeat: $0.hasSeat) }
        controller.load(map: map, landmarks: lms, animated: true)
        setSun(hour)
        if let l = lms.first {
            controller.setPeople([ScenePerson(id: "chan", color: UIColor(red: 0.11, green: 0.62, blue: 0.46, alpha: 1), mobility: .walk, motion: .wander(around: l.pos), label: "陳太")])
        }
    }

    private func setSun(_ h: Double) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SolarPosition.hongKong
        let day = cal.startOfDay(for: Date())
        let date = day.addingTimeInterval(h * 3600)
        controller.setSun(SolarPosition.at(date, lat: 22.5044, lon: 114.1563), animated: false)
    }
}

enum LaunchArgs {
    static func has(_ flag: String) -> Bool { ProcessInfo.processInfo.arguments.contains(flag) }
    static func value(_ flag: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    static var hour: Double? { value("-hour").flatMap(Double.init) }
}
