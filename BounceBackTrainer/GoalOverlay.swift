import SwiftUI

struct GoalOverlay: View {
    @Binding var goalRegion: CGRect
    let frameSize: CGSize
    
    @State private var isDragging = false
    @State private var isResizing = false
    @State private var dragOffset = CGSize.zero
    @State private var resizeOffset = CGSize.zero
    
    private let minSize: CGFloat = 100
    private let handleSize: CGFloat = 30
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent goal overlay
                Rectangle()
                    .fill(Color.green.opacity(0.3))
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: goalRegion.width, height: goalRegion.height)
                    .position(x: goalRegion.midX, y: goalRegion.midY)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isResizing {
                                    isDragging = true
                                    dragOffset = value.translation
                                    
                                    let newX = goalRegion.midX + value.translation.width
                                    let newY = goalRegion.midY + value.translation.height
                                    
                                    // Constrain to frame bounds
                                    let constrainedX = max(goalRegion.width/2, min(frameSize.width - goalRegion.width/2, newX))
                                    let constrainedY = max(goalRegion.height/2, min(frameSize.height - goalRegion.height/2, newY))
                                    
                                    goalRegion.origin.x = constrainedX - goalRegion.width/2
                                    goalRegion.origin.y = constrainedY - goalRegion.height/2
                                }
                            }
                            .onEnded { _ in
                                isDragging = false
                                dragOffset = .zero
                            }
                    )
                
                // Corner resize handles
                ForEach(0..<4) { corner in
                    Circle()
                        .fill(Color.white)
                        .stroke(Color.green, lineWidth: 2)
                        .frame(width: handleSize, height: handleSize)
                        .position(cornerPosition(for: corner))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isResizing = true
                                    resizeCorner(corner, with: value.translation)
                                }
                                .onEnded { _ in
                                    isResizing = false
                                    resizeOffset = .zero
                                }
                        )
                }
                
                // Goal text overlay
                Text("GOAL")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 2)
                    .position(x: goalRegion.midX, y: goalRegion.midY)
            }
        }
    }
    
    private func cornerPosition(for corner: Int) -> CGPoint {
        switch corner {
        case 0: // Top-left
            return CGPoint(x: goalRegion.minX, y: goalRegion.minY)
        case 1: // Top-right
            return CGPoint(x: goalRegion.maxX, y: goalRegion.minY)
        case 2: // Bottom-left
            return CGPoint(x: goalRegion.minX, y: goalRegion.maxY)
        case 3: // Bottom-right
            return CGPoint(x: goalRegion.maxX, y: goalRegion.maxY)
        default:
            return .zero
        }
    }
    
    private func resizeCorner(_ corner: Int, with translation: CGSize) {
        var newRegion = goalRegion
        
        switch corner {
        case 0: // Top-left
            newRegion.origin.x += translation.width
            newRegion.origin.y += translation.height
            newRegion.size.width -= translation.width
            newRegion.size.height -= translation.height
        case 1: // Top-right
            newRegion.origin.y += translation.height
            newRegion.size.width += translation.width
            newRegion.size.height -= translation.height
        case 2: // Bottom-left
            newRegion.origin.x += translation.width
            newRegion.size.width -= translation.width
            newRegion.size.height += translation.height
        case 3: // Bottom-right
            newRegion.size.width += translation.width
            newRegion.size.height += translation.height
        default:
            break
        }
        
        // Constrain minimum size and bounds
        if newRegion.width >= minSize && newRegion.height >= minSize &&
           newRegion.minX >= 0 && newRegion.maxX <= frameSize.width &&
           newRegion.minY >= 0 && newRegion.maxY <= frameSize.height {
            goalRegion = newRegion
        }
    }
}

struct GoalOverlay_Previews: PreviewProvider {
    static var previews: some View {
        GoalOverlay(
            goalRegion: .constant(CGRect(x: 100, y: 100, width: 200, height: 150)),
            frameSize: CGSize(width: 400, height: 600)
        )
        .background(Color.black)
    }
} 