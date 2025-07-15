import SwiftUI
import AVFoundation
import UIKit

struct LiveCameraView: View {
    @StateObject private var cameraManager = CameraFeedManager()
    @StateObject private var dataLogger = DataLogger()
    @StateObject private var detectionManager = DetectionManager()
    
    @State private var goalRegion = CGRect(x: 40, y: 100, width: 320, height: 240)
    @State private var detectedTargets: [[AnyHashable: Any]] = []
    @State private var detectedBall: [AnyHashable: Any]? = nil
    @State private var impactDetected = false
    @State private var impactMessage = ""
    @State private var showImpactFeedback = false
    @State private var frameSize = CGSize.zero
    @State private var frameCounter = 0
    @State private var showExportOptions = false
    @State private var exportSuccess = false
    @State private var exportMessage = ""
    @State private var showCameraPermissionAlert = false
    @State private var liveFrame: UIImage? = nil
    @State private var detectedTapeRegion: CGRect? = nil
    
    // Computed properties to avoid complex expressions
    private var statusText: Text {
        if detectionManager.goalLocked {
            return Text("Goal Locked")
        } else if detectionManager.validGoalRegionCounter > 0 {
            return Text("Goal Detected")
        } else {
            return Text("Finding Goal")
        }
    }
    
    private var statusBackgroundColor: Color {
        if detectionManager.goalLocked {
            return Color.green.opacity(0.8)
        } else if detectionManager.validGoalRegionCounter > 0 {
            return Color.orange.opacity(0.8)
        } else {
            return Color.red.opacity(0.8)
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            let viewSize = geo.size
            let scale = frameSize.width > 0 ? viewSize.width / frameSize.width : 1.0
            let yOffset: CGFloat = frameSize.height > 0 ? (viewSize.height - frameSize.height * scale) / 2 : 0
            
            ZStack {
                // Camera preview with goal detection overlay
                if let liveFrame = liveFrame {
                    GoalDetectionView(
                        liveFrame: liveFrame,
                        frameSize: frameSize,
                        detectedTapeRegion: detectedTapeRegion,
                        goalLocked: detectionManager.goalLocked
                    )
                } else {
                    Color.black.edgesIgnoringSafeArea(.all)
                }
                
                // Status overlay
                VStack {
                    HStack {
                        Spacer()
                        statusText
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(statusBackgroundColor)
                            .cornerRadius(10)
                        Spacer()
                    }
                    Spacer()
                }
                
                // Target detection overlay
                if detectionManager.goalLocked {
                    TargetDetectionView(
                        lockedTargets: detectionManager.lockedTargets,
                        frameSize: frameSize,
                        viewSize: viewSize,
                        yOffset: yOffset,
                        scale: scale
                    )
                    
                    // Current detected targets overlay with lock button
                    if detectionManager.showLockTargetsButton {
                        CurrentTargetsView(
                            currentTargets: detectionManager.currentDetectedTargets,
                            frameSize: frameSize,
                            viewSize: viewSize,
                            yOffset: yOffset,
                            scale: scale,
                            onLockTargets: {
                                detectionManager.lockCurrentTargets()
                            }
                        )
                    }
                    
                    // Reset button - always show when goal is locked
                    VStack {
                        Spacer()
                        HStack {
                            ResetButton(onReset: {
                                detectionManager.reset()
                            })
                            Spacer()
                        }
                    }
                }
                
                // HUD overlay
                HUDOverlay(
                    frameCounter: frameCounter,
                    lockedTargetsCount: detectionManager.lockedTargets.count,
                    currentTargetsCount: detectionManager.currentDetectedTargets.count,
                    goalLocked: detectionManager.goalLocked
                )
            }
            .edgesIgnoringSafeArea(.all)
        }
        .onAppear {
            setupCamera()
            setupFrameProcessing()
        }
        .onChange(of: goalRegion) { newRegion in
            cameraManager.updateGoalRegion(newRegion)
        }
        .onChange(of: detectedTapeRegion) { newRegion in
            detectionManager.processGoalDetection(newRegion, frameSize: frameSize)
        }
        .actionSheet(isPresented: $showExportOptions) {
            ActionSheet(
                title: Text("Export Data"),
                message: Text("Choose export format"),
                buttons: [
                    .default(Text("Export JSON")) { exportData(format: "json") },
                    .default(Text("Export CSV")) { exportData(format: "csv") },
                    .cancel()
                ]
            )
        }
        .alert(exportSuccess ? "Success" : "Error", isPresented: $exportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportMessage)
        }
        .alert("Camera Permission Required", isPresented: $showCameraPermissionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enable camera access in Settings to use the live camera feature.")
        }
    }
    
    private func setupCamera() {
        cameraManager.startSession()
    }
    
    private func setupFrameProcessing() {
        cameraManager.onFrameProcessed = { [weak cameraManager] frame, region in
            if frameSize != frame.size { frameSize = frame.size }
            liveFrame = frame
            guard true else { return } // Always process frames now
            DispatchQueue.global(qos: .userInitiated).async {
                // Enhanced backend processing with performance monitoring
                let performance = OpenCVWrapper.analyzeFramePerformance(frame) as? [AnyHashable: Any] ?? [:]
                
                // Auto-calibrate for lighting conditions every 30 frames
                if frameCounter % 30 == 0 {
                    OpenCVWrapper.calibrate(forLighting: frame)
                }
                
                // Main detection pipeline
                let result = OpenCVWrapper.detectTargets(inFrame: frame, goalRegion: region) as? [AnyHashable: Any] ?? [:]
                let targets = result["targets"] as? [[AnyHashable: Any]] ?? []
                if let tapeValue = result["tapeRegion"] as? NSValue {
                    detectedTapeRegion = tapeValue.cgRectValue
                } else {
                    detectedTapeRegion = nil
                }
                let ballDict = OpenCVWrapper.detectBall(inFrame: frame)
                let ball = ballDict as? [AnyHashable: Any] ?? [:]
                let impact = OpenCVWrapper.detectImpact(withBall: ball, targets: targets, goalRegion: region)
                
                // Motion detection for additional analysis
                let motionRegions = OpenCVWrapper.detectMotion(inFrame: frame) as? [[AnyHashable: Any]] ?? []
                
                // Get tracking statistics
                let stats = OpenCVWrapper.getTrackingStatistics() as? [AnyHashable: Any] ?? [:]
                DispatchQueue.main.async {
                    detectedTargets = targets
                    detectedBall = ballDict as? [AnyHashable: Any]
                    frameCounter += 1
                    
                    // Process targets through detection manager
                    detectionManager.processTargetDetection(targets)
                    
                    // Log frame and target count
                    print("Frame \(frameCounter): Detected \(detectedTargets.count) targets")
                    dataLogger.logFrame(
                        frameNumber: frameCounter,
                        ball: ballDict as? NSDictionary,
                        targets: targets.map { $0 as NSDictionary },
                        impactDetected: impact
                    )
                    
                    // Log enhanced backend processing data
                    if let processingTime = performance["processingTime"] as? NSNumber {
                        print("Frame processing time: \(processingTime.intValue) microseconds")
                    }
                    
                    if let brightness = performance["averageBrightness"] as? NSNumber {
                        print("Average brightness: \(brightness.floatValue)")
                    }
                    
                    if !motionRegions.isEmpty {
                        print("Motion regions detected: \(motionRegions.count)")
                    }
                    if impact && !impactDetected {
                        impactDetected = true
                        impactMessage = "HIT!"
                        showImpactFeedback = true
                        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                        impactFeedback.impactOccurred()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showImpactFeedback = false
                            impactDetected = false
                        }
                    }
                }
            }
        }
    }
    
    private func exportData(format: String) {
        var url: URL?
        if format == "json" {
            url = dataLogger.exportData()
        } else if format == "csv" {
            url = dataLogger.exportCSV()
        }
        if let url = url {
            exportSuccess = true
            exportMessage = "Data exported successfully to: \(url.lastPathComponent)"
        } else {
            exportSuccess = false
            exportMessage = "Failed to export data"
        }
    }
    
    func isGoalAligned() -> Bool {
        guard let tape = detectedTapeRegion, tape != .zero else { return false }
        let intersection = goalRegion.intersection(tape)
        let overlap = (intersection.width * intersection.height) / (goalRegion.width * goalRegion.height)
        return overlap > 0.7 // adjust threshold as needed
    }
}

struct TargetIndicator: View {
    let target: [AnyHashable: Any]
    var body: some View {
        let centerX = target["centerX"] as? NSNumber ?? 0
        let centerY = target["centerY"] as? NSNumber ?? 0
        let radius = target["radius"] as? NSNumber ?? 0
        let targetNumber = target["targetNumber"] as? NSNumber ?? 0
        ZStack {
            Circle()
                .stroke(Color.green, lineWidth: 3)
                .frame(width: CGFloat(radius.intValue * 2), height: CGFloat(radius.intValue * 2))
                .position(x: CGFloat(centerX.intValue), y: CGFloat(centerY.intValue))
            Text("\(targetNumber.intValue)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .background(Color.green)
                .clipShape(Circle())
                .frame(width: 20, height: 20)
                .position(x: CGFloat(centerX.intValue), y: CGFloat(centerY.intValue) - CGFloat(radius.intValue) - 15)
        }
    }
}

struct BallIndicator: View {
    let x: CGFloat
    let y: CGFloat
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 16, height: 16)
            .position(x: x, y: y)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 16, height: 16)
            )
    }
}

struct ImpactFeedbackView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.largeTitle)
            .fontWeight(.bold)
            .foregroundColor(.red)
            .background(Color.white.opacity(0.8))
            .padding()
            .cornerRadius(10)
            .scaleEffect(1.5)
            .animation(.easeInOut(duration: 0.3), value: message)
    }
}

struct LiveCameraView_Previews: PreviewProvider {
    static var previews: some View {
        LiveCameraView()
    }
} 
