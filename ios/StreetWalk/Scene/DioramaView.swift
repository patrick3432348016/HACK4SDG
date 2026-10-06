import SceneKit
import SwiftUI

/// SwiftUI 里的 3D 微缩模型。只看不操作：镜头由流程自动移动；单击只用于首次使用时选楼。
struct DioramaView: UIViewRepresentable {
    let controller: DioramaController
    var onTap: ((DioramaController.Hit?) -> Void)?
    var showStats = false

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        v.scene = controller.scene
        v.delegate = controller
        v.backgroundColor = SceneStyle.background
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.isPlaying = true
        v.rendersContinuously = true
        v.allowsCameraControl = false
        v.showsStatistics = showStats
        v.pointOfView = controller.scene.rootNode.childNodes.first { $0.camera != nil }
        if LaunchArgs.has("-tilt") { v.technique = TiltShift.technique() }
        controller.view = v

        // 场景只看不操作：没有拖动、缩放、双击；只保留单击（首次使用时点选自己住的楼）。
        let c = context.coordinator
        let single = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        single.delegate = c
        v.addGestureRecognizer(single)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        context.coordinator.parent = self
        v.showsStatistics = showStats
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: DioramaView
        init(parent: DioramaView) { self.parent = parent }

        @objc func tap(_ g: UITapGestureRecognizer) {
            parent.onTap?(parent.controller.hit(at: g.location(in: g.view)))
        }

    }
}
