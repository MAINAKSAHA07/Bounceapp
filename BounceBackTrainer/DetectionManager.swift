import Foundation
import UIKit

class DetectionManager: ObservableObject {
    @Published var goalLocked = false
    @Published var targetsLocked = false
    @Published var lockedGoalRegion: CGRect? = nil
    @Published var lockedTargets: [[AnyHashable: Any]] = []
    @Published var validGoalRegionCounter = 0
    @Published var currentDetectedTargets: [[AnyHashable: Any]] = []
    @Published var showLockTargetsButton = false
    
    // Validation parameters
    private let minGoalAreaRatio: CGFloat = 0.01  // 1% of frame
    private let maxGoalAreaRatio: CGFloat = 0.80  // 80% of frame
    private let minAspectRatio: CGFloat = 0.5
    private let maxAspectRatio: CGFloat = 2.5
    private let requiredValidFrames = 5
    
    func validateGoalRegion(_ region: CGRect, frameSize: CGSize) -> Bool {
        guard frameSize != .zero else { return false }
        
        let minArea = frameSize.width * frameSize.height * minGoalAreaRatio
        let maxArea = frameSize.width * frameSize.height * maxGoalAreaRatio
        let area = region.width * region.height
        let aspect = region.width / max(region.height, 1)
        
        let areaMinOk = area > minArea
        let areaMaxOk = area < maxArea
        let aspectOk = aspect > minAspectRatio && aspect < maxAspectRatio
        
        return areaMinOk && areaMaxOk && aspectOk
    }
    
    func processGoalDetection(_ region: CGRect?, frameSize: CGSize) {
        guard !goalLocked else { return }
        
        if let region = region, region != .zero, validateGoalRegion(region, frameSize: frameSize) {
            validGoalRegionCounter += 1
            if validGoalRegionCounter >= requiredValidFrames {
                lockedGoalRegion = region
                goalLocked = true
            }
        } else {
            validGoalRegionCounter = 0
        }
    }
    
    func processTargetDetection(_ newTargets: [[AnyHashable: Any]]) {
        guard goalLocked else { return }
        
        // Filter out targets that are already locked
        let unlockedTargets = newTargets.filter { newTarget in
            guard let newTargetId = newTarget["targetNumber"] as? Int else { return false }
            return !lockedTargets.contains { lockedTarget in
                guard let lockedTargetId = lockedTarget["targetNumber"] as? Int else { return false }
                return lockedTargetId == newTargetId
            }
        }
        
        // Store current detected targets for manual locking
        currentDetectedTargets = unlockedTargets
        
        // Show lock button if we have targets and goal is locked
        showLockTargetsButton = !unlockedTargets.isEmpty
    }
    
    func lockCurrentTargets() {
        for target in currentDetectedTargets {
            if let id = target["targetNumber"] as? Int,
               !lockedTargets.contains(where: { ($0["targetNumber"] as? Int) == id }) {
                lockedTargets.append(target)
            }
        }
        showLockTargetsButton = false
    }
    
    func reset() {
        goalLocked = false
        targetsLocked = false
        lockedGoalRegion = nil
        lockedTargets.removeAll()
        currentDetectedTargets.removeAll()
        validGoalRegionCounter = 0
        showLockTargetsButton = false
    }
} 