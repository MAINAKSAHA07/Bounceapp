import SwiftUI
import AVFoundation

struct CameraFeedForFFTDetection: UIViewControllerRepresentable {
    var onFrame: (UIImage) -> Void

    func makeUIViewController(context: Context) -> CameraFeedController {
        let controller = CameraFeedController()
        controller.onFrame = onFrame
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraFeedController, context: Context) {}
}

class CameraFeedController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((UIImage) -> Void)?
    private let session = AVCaptureSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    private func setupCamera() {
        session.sessionPreset = .medium
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera"))
        session.addOutput(output)

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                self.onFrame?(uiImage)
            }
        }
    }
} 