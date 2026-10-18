import SceneKit
import SwiftUI

/// SwiftUI 3D diorama. This historical scene moves its camera automatically; tapping only selects a building during onboarding.
struct DioramaView: UIViewRepresentable {
    let controller: DioramaController
    var onTap: ((DioramaController.Hit?) -> Void)?
    /// Follow system light/dark appearance and rebuild scene materials when it changes.
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> SCNView {
        controller.setDark(colorScheme == .dark)
        let v = SCNView(frame: .zero)
        v.scene = controller.scene
        v.delegate = controller
        v.backgroundColor = SceneStyle.background
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        // Render at 60 fps only while people/camera/buildings animate; draw no frames when idle to reduce power and heat.
        // isPlaying=true forces continuous redraw (observed idle 60 fps/~6% CPU); SCNAction and transitions do not require it.
        // DioramaController.labelsChanged publishes changed labels while the scene is idle.
        v.isPlaying = false
        v.rendersContinuously = false
        v.allowsCameraControl = false
        v.showsStatistics = LaunchArgs.has("-stats")
        v.pointOfView = controller.scene.rootNode.childNodes.first { $0.camera != nil }
        if LaunchArgs.has("-tilt") { v.technique = TiltShift.technique() }
        controller.view = v

        // No drag, zoom, or double-tap interaction in this historical scene; retain a single tap for onboarding home selection.
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
