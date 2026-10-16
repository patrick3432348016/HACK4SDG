import SceneKit
import SwiftUI

/// SwiftUI 里的 3D 微缩模型。镜头由流程自动移动；单指撳（选楼、撳地标），双指捏合放大缩细、双指拖动睇其他位置，双击复位。
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

        // 单指：撳（选楼、地标）；单指拖动留俾 SwiftUI「向下拉放大」同页面，所以平移要双指。
        // 双指：捏合缩放、拖动平移（有上下限、唔拖得出底座，见 DioramaController.userZoom / userPan）；双击复位。
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

        @objc func tap(_ g: UITapGestureRecognizer) {
            parent.onTap?(parent.controller.hit(at: g.location(in: g.view)))
        }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            parent.controller.resetUserCamera()
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard g.state == .changed || g.state == .began, let v = g.view, g.numberOfTouches >= 2 else { return }
            parent.controller.userZoom(by: g.scale, around: g.location(in: v))
            g.scale = 1
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard g.state == .changed || g.state == .began, let v = g.view else { return }
            let t = g.translation(in: v), p = g.location(in: v)
            g.setTranslation(.zero, in: v)
            parent.controller.userPan(from: CGPoint(x: p.x - t.x, y: p.y - t.y), to: p)
        }

        /// 捏合同双指拖动一齐认（一边放大一边移）。
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (g is UIPinchGestureRecognizer && other is UIPanGestureRecognizer) || (g is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
        }

        /// 双击复位：只喺双指郁过镜头之后先要单击等双击落空（平时撳地标唔会慢咗）。
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            g is UITapGestureRecognizer && g !== double && other === double && parent.controller.userAdjusted
        }

        /// 未郁过镜头时双击唔使认（免得同两下单击撞）。
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            g !== double || parent.controller.userAdjusted
        }

    }
}
