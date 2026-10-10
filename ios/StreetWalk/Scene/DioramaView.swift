import SceneKit
import SwiftUI

/// SwiftUI 里的 3D 微缩模型。只看不操作：镜头由流程自动移动；单击只用于首次使用时选楼。
struct DioramaView: UIViewRepresentable {
    let controller: DioramaController
    var onTap: ((DioramaController.Hit?) -> Void)?
    /// 跟随系统深浅色，切换时场景重建材质。
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> SCNView {
        controller.setDark(colorScheme == .dark)
        let v = SCNView(frame: .zero)
        v.scene = controller.scene
        v.delegate = controller
        v.backgroundColor = SceneStyle.background
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        // 只在有变化时才渲染：人在走、镜头在飞、楼在升起时 60 fps；静止时一帧都不画（省电、不发热）。
        // isPlaying = true 会令 SCNView 每帧重画（实测静止时 60 fps、约 6% CPU），SCNAction 和过渡动画不需要它。
        // 静止时标签内容变了由 DioramaController.labelsChanged 补推。
        v.isPlaying = false
        v.rendersContinuously = false
        v.allowsCameraControl = false
        v.showsStatistics = LaunchArgs.has("-stats")
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
        controller.setDark(colorScheme == .dark)
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
