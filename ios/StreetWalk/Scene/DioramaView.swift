import SceneKit
import SwiftUI

/// SwiftUI diorama with flow-controlled camera, single-finger selection, and two-finger zoom/pan.
/// Two-finger rotation and double-tap reset. One-finger pan requires controller.oneFingerPan or prior gesture zoom.
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

        // Single finger selects buildings/landmarks or pans where allowed; the small Today map reserves downward drag for SwiftUI enlargement.
        // Two-finger zoom/pan/rotation obey limits and stay within the base; double-tap resets (userZoom/userPan/userRotate).
        let c = context.coordinator
        let single = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        single.delegate = c
        v.addGestureRecognizer(single)
        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2
        double.delegate = c
        v.addGestureRecognizer(double)
        c.double = double
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        pinch.delegate = c
        v.addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = c
        v.addGestureRecognizer(pan)
        let rotate = UIRotationGestureRecognizer(target: c, action: #selector(Coordinator.rotate(_:)))
        rotate.delegate = c
        v.addGestureRecognizer(rotate)
        let pan1 = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan1(_:)))
        pan1.minimumNumberOfTouches = 1
        pan1.maximumNumberOfTouches = 1
        pan1.delegate = c
        v.addGestureRecognizer(pan1)
        c.pan1 = pan1
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

        weak var double: UITapGestureRecognizer?
        weak var pan1: UIPanGestureRecognizer?
        /// Suppress one-finger pan during a recent two-finger gesture to avoid applying movement twice.
        private var lastMulti: CFTimeInterval = 0

        @objc func tap(_ g: UITapGestureRecognizer) {
            parent.onTap?(parent.controller.hit(at: g.location(in: g.view)))
        }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            parent.controller.resetUserCamera()
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard g.state == .changed || g.state == .began, let v = g.view, g.numberOfTouches >= 2 else { return }
            lastMulti = CACurrentMediaTime()
            parent.controller.userZoom(by: g.scale, around: g.location(in: v))
            g.scale = 1
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard g.state == .changed || g.state == .began, let v = g.view else { return }
            lastMulti = CACurrentMediaTime()
            let t = g.translation(in: v), p = g.location(in: v)
            g.setTranslation(.zero, in: v)
            parent.controller.userPan(from: CGPoint(x: p.x - t.x, y: p.y - t.y), to: p)
        }

        @objc func rotate(_ g: UIRotationGestureRecognizer) {
            guard g.state == .changed || g.state == .began, let v = g.view, g.numberOfTouches >= 2 else { return }
            lastMulti = CACurrentMediaTime()
            parent.controller.userRotate(by: g.rotation, around: g.location(in: v))
            g.rotation = 0
        }

        /// Single-finger pan anchors the ground under the finger; stop when a second finger begins a multi-touch gesture.
        @objc func pan1(_ g: UIPanGestureRecognizer) {
            guard let v = g.view else { return }
            switch g.state {
            case .began: parent.controller.setOneFingerPanning(true)
            case .ended, .cancelled, .failed: parent.controller.setOneFingerPanning(false); return
            default: break
            }
            let t = g.translation(in: v), p = g.location(in: v)
            g.setTranslation(.zero, in: v)
            guard g.numberOfTouches == 1, CACurrentMediaTime() - lastMulti > 0.25 else { return }
            parent.controller.userPan(from: CGPoint(x: p.x - t.x, y: p.y - t.y), to: p)
        }

        /// Recognize pinch, pan, and rotation together, including a second finger joining an ongoing one-finger drag.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            func map(_ r: UIGestureRecognizer) -> Bool { r is UIPinchGestureRecognizer || r is UIPanGestureRecognizer || r is UIRotationGestureRecognizer }
            return map(g) && map(other) && g.view === other.view
        }

        /// Require single taps to await double-tap failure only after the camera has moved, avoiding ordinary landmark-tap latency.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            g is UITapGestureRecognizer && g !== double && other === double && parent.controller.userAdjusted
        }

        /// Disable double-tap recognition before camera changes to avoid conflicting with two single taps.
        /// One-finger pan requires oneFingerPan or previous zoom; the small Today map reserves downward drag for enlargement.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            if g === pan1 { return parent.controller.oneFingerPan || parent.controller.userAdjusted }
            return g !== double || parent.controller.userAdjusted
        }

    }
}
