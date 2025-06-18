import SwiftUI
import AVFoundation

struct CameraView: UIViewControllerRepresentable {
    let onVideoRecorded: (URL?) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let videoURL = info[.mediaURL] as? URL {
                // Create a temporary file URL
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("recorded_video.mp4")
                
                // Copy the video to the temporary location
                do {
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    try FileManager.default.copyItem(at: videoURL, to: tempURL)
                    parent.onVideoRecorded(tempURL)
                } catch {
                    print("Error saving video: \(error)")
                    parent.onVideoRecorded(nil)
                }
            } else {
                parent.onVideoRecorded(nil)
            }
            
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onVideoRecorded(nil)
            picker.dismiss(animated: true)
        }
    }
} 