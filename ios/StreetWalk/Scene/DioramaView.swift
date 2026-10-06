import SceneKit
import SwiftUI

/// SwiftUI 里的 3D 微缩模型。手势：单指平移（带惯性）、双指缩放、双击复位、单击选中。
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
        if !LaunchArgs.has("-notilt") { v.technique = TiltShift.technique() }
        controller.view = v

        let c = context.coordinator
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2
        let single = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        single.require(toFail: double)
        [pan, pinch, double, single].forEach { $0.delegate = c; v.addGestureRecognizer($0) }
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

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let p = g.location(in: g.view)
            switch g.state {
            case .began: parent.controller.panBegan(at: p)
            case .changed: parent.controller.panChanged(at: p)
            case .ended, .cancelled: parent.controller.panEnded(at: p, velocity: g.velocity(in: g.view))
            default: break
            }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began: parent.controller.pinchBegan()
            case .changed: parent.controller.pinchChanged(scale: g.scale)
            default: break
            }
        }

        @objc func doubleTap(_ g: UITapGestureRecognizer) { parent.controller.resetCamera() }

        @objc func tap(_ g: UITapGestureRecognizer) {
            parent.onTap?(parent.controller.hit(at: g.location(in: g.view)))
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (g is UIPinchGestureRecognizer && other is UIPanGestureRecognizer) || (g is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
        }
    }
}
