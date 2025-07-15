import SwiftUI
import AVKit
import UniformTypeIdentifiers
import PhotosUI
import AVFoundation

struct ContentView: View {
    @State private var inputURL: URL?
    @State private var outputURL: URL?
    @State private var showVideoPlayer = false
    @State private var showPicker = false
    @State private var showSaveDialog = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showVideoSheet = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var showCamera = false
    @State private var cameraPermissionGranted = false
    @State private var showLiveCamera = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Bounce Back Trainer")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top)

                VStack(spacing: 15) {
                    // Live Camera Button
                    Button(action: {
                        checkCameraPermission()
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Live Camera Mode")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .sheet(isPresented: $showLiveCamera) {
                        LiveCameraView()
                    }

                    Button(action: {
                        checkCameraPermission()
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Record Video")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .sheet(isPresented: $showCamera) {
                        CameraView { url in
                            if let url = url {
                                inputURL = url
                            }
                        }
                    }

                    PhotosPicker(selection: $selectedItem,
                               matching: .videos) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("Choose from Library")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .onChange(of: selectedItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                let tempURL = FileManager.default.temporaryDirectory
                                    .appendingPathComponent("input_video.mp4")
                                try? data.write(to: tempURL)
                                inputURL = tempURL
                            }
                        }
                    }
                }
                .padding(.horizontal)

                if let inputURL = inputURL {
                    VideoPlayer(player: AVPlayer(url: inputURL))
                        .frame(height: 200)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }

                Button(action: {
                    guard let input = inputURL else { return }
                    isProcessing = true

                    let output = FileManager.default.temporaryDirectory
                        .appendingPathComponent("analyzed_output.avi")

                    // Debug: Check if file exists
                    print("Input URL: \(input.path)")
                    print("File exists: \(FileManager.default.fileExists(atPath: input.path))")

                    // No need for securityScopedResource for temp file
                    if FileManager.default.fileExists(atPath: input.path) {
                        print("Analyzing: \(input.path)")
                        OpenCVWrapper.analyzeVideo(input.path, outputPath: output.path)
                        print("Output saved to: \(output.path)")
                        outputURL = output
                        isProcessing = false
                    } else {
                        errorMessage = "Failed to access input video"
                        showError = true
                        isProcessing = false
                    }
                }) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.trailing, 5)
                        }
                        Image(systemName: "wand.and.stars")
                        Text(isProcessing ? "Processing..." : "Analyze Video")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(inputURL == nil || isProcessing ? Color.gray : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(inputURL == nil || isProcessing)
                .padding(.horizontal)

                if let outputURL = outputURL {
                    VStack(spacing: 15) {
                        Button(action: {
                            showVideoSheet = true
                        }) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("View Output Video")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        Button(action: {
                            saveVideoToPhotos(url: outputURL)
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text("Save to Photos")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .navigationTitle("Bounce Back Trainer")
        }
        .sheet(isPresented: $showVideoSheet) {
            if let url = outputURL {
                OutputVideoView(url: url)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = true
            showLiveCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermissionGranted = granted
                    if granted {
                        showLiveCamera = true
                    } else {
                        errorMessage = "Camera access is required to record videos"
                        showError = true
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Please enable camera access in Settings"
            showError = true
        @unknown default:
            errorMessage = "Unknown camera permission status"
            showError = true
        }
    }
    
    private func saveVideoToPhotos(url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    errorMessage = "Please allow access to Photos in Settings"
                    showError = true
                }
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("Video saved to Photos successfully")
                    } else {
                        errorMessage = "Error saving video: \(error?.localizedDescription ?? "Unknown error")"
                        showError = true
                    }
                }
            }
        }
    }
}

struct VideoDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.movie] }
    
    var url: URL?
    
    init(url: URL?) {
        self.url = url
    }
    
    init(configuration: ReadConfiguration) throws {
        url = nil
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url = url else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try FileWrapper(url: url, options: .immediate)
    }
}

