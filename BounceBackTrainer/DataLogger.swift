import Foundation
import UIKit

struct FrameData {
    let timestamp: Date
    let frameNumber: Int
    let ballPosition: CGPoint?
    let ballVelocity: CGPoint?
    let targets: [TargetData]
    let impactDetected: Bool
    let impactPosition: CGPoint?
}

struct TargetData {
    let centerX: Int
    let centerY: Int
    let radius: Double
    let targetNumber: Int
    let isCircular: Bool
    let quadrant: Int
}

struct ImpactEvent {
    let timestamp: Date
    let frameNumber: Int
    let position: CGPoint
    let targetHit: Int?
    let ballVelocity: CGPoint?
}

class DataLogger: ObservableObject {
    @Published var frameData: [FrameData] = []
    @Published var impactEvents: [ImpactEvent] = []
    
    private let maxFrameData = 300 // Keep last 300 frames (10 seconds at 30fps)
    private let dateFormatter: DateFormatter
    
    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    }
    
    func logFrame(frameNumber: Int, ball: NSDictionary?, targets: [NSDictionary], impactDetected: Bool) {
        let ballPosition: CGPoint?
        let ballVelocity: CGPoint?
        
        if let ball = ball,
           let ballX = ball["x"] as? NSNumber,
           let ballY = ball["y"] as? NSNumber {
            ballPosition = CGPoint(x: CGFloat(ballX.intValue), y: CGFloat(ballY.intValue))
            
            if let velX = ball["velocityX"] as? NSNumber,
               let velY = ball["velocityY"] as? NSNumber {
                ballVelocity = CGPoint(x: CGFloat(velX.doubleValue), y: CGFloat(velY.doubleValue))
            } else {
                ballVelocity = nil
            }
        } else {
            ballPosition = nil
            ballVelocity = nil
        }
        
        // Convert NSDictionary targets to TargetData
        let targetData = targets.compactMap { dict -> TargetData? in
            guard let centerX = dict["centerX"] as? NSNumber,
                  let centerY = dict["centerY"] as? NSNumber,
                  let radius = dict["radius"] as? NSNumber,
                  let targetNumber = dict["targetNumber"] as? NSNumber,
                  let isCircular = dict["isCircular"] as? Bool,
                  let quadrant = dict["quadrant"] as? NSNumber else {
                return nil
            }
            
            return TargetData(
                centerX: centerX.intValue,
                centerY: centerY.intValue,
                radius: radius.doubleValue,
                targetNumber: targetNumber.intValue,
                isCircular: isCircular,
                quadrant: quadrant.intValue
            )
        }
        
        let data = FrameData(
            timestamp: Date(),
            frameNumber: frameNumber,
            ballPosition: ballPosition,
            ballVelocity: ballVelocity,
            targets: targetData,
            impactDetected: impactDetected,
            impactPosition: impactDetected ? ballPosition : nil
        )
        
        frameData.append(data)
        
        // Keep only recent frame data
        if frameData.count > maxFrameData {
            frameData.removeFirst(frameData.count - maxFrameData)
        }
        
        // Log impact event if detected
        if impactDetected, let position = ballPosition {
            let impactEvent = ImpactEvent(
                timestamp: Date(),
                frameNumber: frameNumber,
                position: position,
                targetHit: findClosestTarget(to: position, targets: targets),
                ballVelocity: ballVelocity
            )
            impactEvents.append(impactEvent)
        }
    }
    
    private func findClosestTarget(to position: CGPoint, targets: [NSDictionary]) -> Int? {
        var closestTarget: Int?
        var minDistance: CGFloat = CGFloat.greatestFiniteMagnitude
        
        for target in targets {
            guard let centerX = target["centerX"] as? NSNumber,
                  let centerY = target["centerY"] as? NSNumber,
                  let targetNumber = target["targetNumber"] as? NSNumber else { continue }
            
            let targetCenter = CGPoint(x: CGFloat(centerX.intValue), y: CGFloat(centerY.intValue))
            let distance = hypot(position.x - targetCenter.x, position.y - targetCenter.y)
            
            if distance < minDistance {
                minDistance = distance
                closestTarget = targetNumber.intValue
            }
        }
        
        return closestTarget
    }
    
    func exportData() -> URL? {
        let timestamp = dateFormatter.string(from: Date())
        let filename = "bounce_back_data_\(timestamp).json"
        
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = documentsPath.appendingPathComponent(filename)
        
        let exportData = ExportData(
            timestamp: Date(),
            frameData: frameData,
            impactEvents: impactEvents,
            summary: generateSummary()
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let jsonData = try encoder.encode(exportData)
            try jsonData.write(to: fileURL)
            
            return fileURL
        } catch {
            print("Error exporting data: \(error)")
            return nil
        }
    }
    
    func exportCSV() -> URL? {
        let timestamp = dateFormatter.string(from: Date())
        let filename = "bounce_back_data_\(timestamp).csv"
        
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = documentsPath.appendingPathComponent(filename)
        
        var csvString = "Timestamp,FrameNumber,BallX,BallY,VelocityX,VelocityY,TargetsCount,ImpactDetected,ImpactX,ImpactY\n"
        
        for data in frameData {
            let ballX = data.ballPosition?.x ?? 0
            let ballY = data.ballPosition?.y ?? 0
            let velX = data.ballVelocity?.x ?? 0
            let velY = data.ballVelocity?.y ?? 0
            let impactX = data.impactPosition?.x ?? 0
            let impactY = data.impactPosition?.y ?? 0
            
            csvString += "\(data.timestamp),\(data.frameNumber),\(ballX),\(ballY),\(velX),\(velY),\(data.targets.count),\(data.impactDetected),\(impactX),\(impactY)\n"
        }
        
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Error exporting CSV: \(error)")
            return nil
        }
    }
    
    private func generateSummary() -> Summary {
        let totalFrames = frameData.count
        let totalImpacts = impactEvents.count
        let framesWithBall = frameData.filter { $0.ballPosition != nil }.count
        let averageTargets = frameData.isEmpty ? 0 : frameData.map { $0.targets.count }.reduce(0, +) / frameData.count
        
        return Summary(
            totalFrames: totalFrames,
            totalImpacts: totalImpacts,
            framesWithBall: framesWithBall,
            averageTargets: averageTargets,
            sessionDuration: totalFrames > 0 ? Double(totalFrames) / 30.0 : 0 // Assuming 30fps
        )
    }
    
    func clearData() {
        frameData.removeAll()
        impactEvents.removeAll()
    }
}

// Data structures for export
struct ExportData: Codable {
    let timestamp: Date
    let frameData: [FrameData]
    let impactEvents: [ImpactEvent]
    let summary: Summary
}

struct Summary: Codable {
    let totalFrames: Int
    let totalImpacts: Int
    let framesWithBall: Int
    let averageTargets: Int
    let sessionDuration: Double
}

// Make TargetData Codable
extension TargetData: Codable {}

// Make FrameData and ImpactEvent Codable
extension FrameData: Codable {
    enum CodingKeys: String, CodingKey {
        case timestamp, frameNumber, targets, impactDetected
        case ballPositionX, ballPositionY, ballVelocityX, ballVelocityY
        case impactPositionX, impactPositionY
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(frameNumber, forKey: .frameNumber)
        try container.encode(targets, forKey: .targets)
        try container.encode(impactDetected, forKey: .impactDetected)
        try container.encode(ballPosition?.x, forKey: .ballPositionX)
        try container.encode(ballPosition?.y, forKey: .ballPositionY)
        try container.encode(ballVelocity?.x, forKey: .ballVelocityX)
        try container.encode(ballVelocity?.y, forKey: .ballVelocityY)
        try container.encode(impactPosition?.x, forKey: .impactPositionX)
        try container.encode(impactPosition?.y, forKey: .impactPositionY)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        frameNumber = try container.decode(Int.self, forKey: .frameNumber)
        
        targets = try container.decode([TargetData].self, forKey: .targets)
        impactDetected = try container.decode(Bool.self, forKey: .impactDetected)
        
        let ballX = try container.decodeIfPresent(CGFloat.self, forKey: .ballPositionX)
        let ballY = try container.decodeIfPresent(CGFloat.self, forKey: .ballPositionY)
        ballPosition = (ballX != nil && ballY != nil) ? CGPoint(x: ballX!, y: ballY!) : nil
        
        let velX = try container.decodeIfPresent(CGFloat.self, forKey: .ballVelocityX)
        let velY = try container.decodeIfPresent(CGFloat.self, forKey: .ballVelocityY)
        ballVelocity = (velX != nil && velY != nil) ? CGPoint(x: velX!, y: velY!) : nil
        
        let impactX = try container.decodeIfPresent(CGFloat.self, forKey: .impactPositionX)
        let impactY = try container.decodeIfPresent(CGFloat.self, forKey: .impactPositionY)
        impactPosition = (impactX != nil && impactY != nil) ? CGPoint(x: impactX!, y: impactY!) : nil
    }
}

extension ImpactEvent: Codable {
    enum CodingKeys: String, CodingKey {
        case timestamp, frameNumber, targetHit
        case positionX, positionY
        case ballVelocityX, ballVelocityY
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(frameNumber, forKey: .frameNumber)
        try container.encode(targetHit, forKey: .targetHit)
        try container.encode(position.x, forKey: .positionX)
        try container.encode(position.y, forKey: .positionY)
        try container.encode(ballVelocity?.x, forKey: .ballVelocityX)
        try container.encode(ballVelocity?.y, forKey: .ballVelocityY)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        frameNumber = try container.decode(Int.self, forKey: .frameNumber)
        
        let posX = try container.decode(CGFloat.self, forKey: .positionX)
        let posY = try container.decode(CGFloat.self, forKey: .positionY)
        position = CGPoint(x: posX, y: posY)
        
        targetHit = try container.decodeIfPresent(Int.self, forKey: .targetHit)
        
        let velX = try container.decodeIfPresent(CGFloat.self, forKey: .ballVelocityX)
        let velY = try container.decodeIfPresent(CGFloat.self, forKey: .ballVelocityY)
        ballVelocity = (velX != nil && velY != nil) ? CGPoint(x: velX!, y: velY!) : nil
    }
} 