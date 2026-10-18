import SwiftUI
import UIKit
import AVFoundation
import VisionKit
import CoreImage.CIFilterBuiltins

/// Generate a QR image with CoreImage CIQRCodeGenerator; content is jiefong:<one-time code> from PairCode.qrPayload.
enum QRImage {
    private static let context = CIContext()

    static func make(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = context.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Prefer VisionKit DataScannerViewController; fall back to AVFoundation.
/// Request camera permission first; report unavailable camera/simulator or denied permission through onUnavailable.
struct QRScannerView: View {
    enum Status: Equatable { case checking, dataScanner, avCapture, denied, noCamera }
    var onCode: (String) -> Void
    @State private var status: Status = .checking

    var body: some View {
        Group {
            switch status {
            case .checking:
                ProgressView().controlSize(.large)
            case .dataScanner:
                DataScannerRepresentable(onCode: onCode)
            case .avCapture:
                AVScannerRepresentable(onCode: onCode)
            case .denied:
                unavailable(L.t("未允許用鏡頭", "未允许使用相机", "Camera not allowed"), L.t("去「設定」打開鏡頭，或者請對方掃你。", "去「设置」打开相机，或者请对方扫你。", "Turn on the camera in Settings, or let them scan you."), settings: true)
            case .noCamera:
                unavailable(L.t("呢部手機用唔到鏡頭", "这部手机用不了相机", "This phone has no camera"), L.t("請對方掃你嘅二維碼。", "请对方扫你的二维码。", "Ask them to scan your QR code."), settings: false)
            }
        }
        .task { status = await Self.resolve() }
    }

    private func unavailable(_ title: String, _ hint: String, settings: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title).ds(.bodyBold).multilineTextAlignment(.center)
            Text(hint).ds(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if settings {
                Button { openSettings() } label: { Text(L.t("去設定", "去设置", "Open Settings")) }
                    .buttonStyle(.dsSecondary)
            }
        }
        .padding(20)
        .accessibilityElement(children: .combine)
    }

    static func resolve() async -> Status {
        #if targetEnvironment(simulator)
        return .noCamera
        #else
        var auth = AVCaptureDevice.authorizationStatus(for: .video)
        if auth == .notDetermined {
            auth = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        }
        guard auth == .authorized else { return .denied }
        guard AVCaptureDevice.default(for: .video) != nil else { return .noCamera }
        let vk = await MainActor.run { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }
        return vk ? .dataScanner : .avCapture
        #endif
    }
}

@MainActor
func openSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}

/// VisionKit scanner for supported iOS 16+/A12-or-newer hardware.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           qualityLevel: .balanced, recognizesMultipleItems: false,
                                           isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true,
                                           isGuidanceEnabled: true, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let b) = item, let s = b.payloadStringValue { onCode(s); return }
            }
        }
    }
}

/// AVFoundation fallback for devices without VisionKit scanning.
private struct AVScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> AVScannerController {
        let vc = AVScannerController()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ vc: AVScannerController, context: Context) { vc.onCode = onCode }
}

final class AVScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "jiefong.qr.capture")
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let s = session
        queue.async { if !s.isRunning { s.startRunning() } }   // startRunning blocks; do not call it on the main thread.
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let s = session
        queue.async { if s.isRunning { s.stopRunning() } }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let codes = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        MainActor.assumeIsolated {
            if let s = codes.first { onCode?(s) }
        }
    }
}
